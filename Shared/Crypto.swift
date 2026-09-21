import CommonCrypto
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif
import Foundation
import LocalAuthentication
import Security

enum VaultError: LocalizedError {
    case biometryUnavailable
    case accessControlFailed
    case enclaveMissing
    case authenticationFailed(String)
    case corruptedVault
    case wrongPassphrase
    case noPassphraseSet
    case deviceNotEnrolled

    var errorDescription: String? {
        switch self {
        case .biometryUnavailable:
            #if os(macOS)
            return "這台 Mac 無法驗證使用者身分，請先設定登入密碼或 Touch ID"
            #else
            return "這台裝置無法驗證使用者身分"
            #endif
        case .accessControlFailed:
            return "無法建立安全區存取條件"
        case .enclaveMissing:
            return "找不到安全區金鑰"
        case .authenticationFailed(let reason):
            return reason
        case .corruptedVault:
            return "保險庫檔案已損毀或無法解密"
        case .wrongPassphrase:
            return "備份密碼不正確"
        case .noPassphraseSet:
            return "這個保險庫還沒有設定備份密碼"
        case .deviceNotEnrolled:
            return "這台 Mac 還沒有加入這個保險庫，請用備份密碼開啟"
        }
    }
}

/// Wraps the vault's symmetric key in a Secure Enclave P256 key whose private
/// operations are gated by `.userPresence`, so every unlock costs one Touch ID
/// — or the login password on a Mac without it.
enum EnclaveKey {
    private static let salt = Data("com.avalonlotus.keyvault.hkdf.v1".utf8)

    /// True when this Mac can actually take a fingerprint, which decides how
    /// the unlock is described rather than whether it is possible at all.
    static var hasBiometrics: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        var error: NSError?
        return LAContext().canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error
        )
        #endif
    }

    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        guard SecureEnclave.isAvailable else { return false }
        var error: NSError?
        // Not the biometrics-only policy: a Mac mini has a Secure Enclave but
        // no Touch ID, and .userPresence falls back to the login password
        // there. Demanding biometrics would lock those machines out entirely.
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        #endif
    }

    /// 蓋過格式標記就用 v2 的那組檔案，否則還是 v1。
    static var keyURL: URL { EnclaveFormat.stored >= 2 ? Paths.enclaveKey2 : Paths.enclaveKey }
    static var peerURL: URL {
        EnclaveFormat.stored >= 2 ? Paths.peerPublicKey2 : Paths.peerPublicKey
    }

    static var exists: Bool {
        Paths.migrateLegacyDirectoryIfNeeded()
        #if targetEnvironment(simulator)
        return FileManager.default.fileExists(atPath: Paths.simulatorKey.path)
        #else
        return FileManager.default.fileExists(atPath: keyURL.path)
            && FileManager.default.fileExists(atPath: peerURL.path)
        #endif
    }

    /// 第一次建庫：直接生在 v2 的檔名底下。
    static func provision() throws {
        try provision(keyURL: Paths.enclaveKey2, peerURL: Paths.peerPublicKey2)
        EnclaveFormat.stamp()
    }

    /// 寫到指定路徑。遷移用這個把新金鑰生在旁邊，舊的一個字都不動。
    static func provision(keyURL: URL, peerURL: URL) throws {
        #if targetEnvironment(simulator)
        // The simulator has no Secure Enclave, so a plain random key stands in
        // and the rest of the app behaves identically. Compiled out on device.
        try Paths.ensureSupportDirectory()
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        try Data(bytes).write(to: Paths.simulatorKey, options: .atomic)
        Paths.restrictToOwner(Paths.simulatorKey)
        #else
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            // 不帶 .userPresence：程式要讀的東西不該卡在有沒有人在場。
            // 人要在畫面上看內容時才驗證，那道門在 PersonCheck。
            [.privateKeyUsage],
            &error
        ) else { throw VaultError.accessControlFailed }

        let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        let peer = P256.KeyAgreement.PrivateKey()
        try Paths.ensureSupportDirectory()
        try enclave.dataRepresentation.write(to: keyURL, options: .completeFileProtection)
        try peer.publicKey.rawRepresentation.write(to: peerURL, options: .completeFileProtection)
        Paths.restrictToOwner(keyURL)
        Paths.restrictToOwner(peerURL)
        #endif
    }

    /// Blocks on the Touch ID sheet, so never call this from the main thread.
    static func deriveKey(
        reason: String,
        reuseDuration: TimeInterval = 0,
        keyURL: URL? = nil,
        peerURL: URL? = nil
    ) throws -> SymmetricKey {
        let keyURL = keyURL ?? EnclaveKey.keyURL
        let peerURL = peerURL ?? EnclaveKey.peerURL
        let manager = FileManager.default
        guard manager.fileExists(atPath: keyURL.path),
              manager.fileExists(atPath: peerURL.path)
        else { throw VaultError.enclaveMissing }
        let context = LAContext()
        context.localizedReason = reason
        context.localizedCancelTitle = "取消"
        context.touchIDAuthenticationAllowableReuseDuration = reuseDuration

        #if targetEnvironment(simulator)
        return SymmetricKey(data: try Data(contentsOf: Paths.simulatorKey))
        #else
        let blob = try Data(contentsOf: keyURL)
        let peerData = try Data(contentsOf: peerURL)
        do {
            let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: blob,
                authenticationContext: context
            )
            let peer = try P256.KeyAgreement.PublicKey(rawRepresentation: peerData)
            let shared = try enclave.sharedSecretFromKeyAgreement(with: peer)
            return shared.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: salt,
                sharedInfo: Data(),
                outputByteCount: 32
            )
        } catch {
            throw VaultError.authenticationFailed(readableMessage(for: error))
        }
        #endif
    }

    static func readableMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == LAError.errorDomain, let code = LAError.Code(rawValue: nsError.code) {
            switch code {
            case .userCancel, .appCancel, .systemCancel:
                return "已取消驗證"
            case .userFallback:
                return "已改用密碼但未完成驗證"
            case .biometryLockout:
                #if os(macOS)
                return "Touch ID 已鎖定，請用 Mac 密碼登入一次再試"
                #else
                return "生物辨識已鎖定，請用裝置密碼解鎖一次再試"
                #endif
            case .biometryNotEnrolled:
                return "尚未在系統設定中登錄生物辨識"
            case .authenticationFailed:
                return "指紋不符，請再試一次"
            default:
                break
            }
        }
        if nsError.code == errSecUserCanceled || nsError.code == -128 { return "已取消驗證" }
        return "驗證失敗（\(nsError.code)）"
    }
}

/// 安全區金鑰的格式。v1 的金鑰帶 `.userPresence`，每次使用都要有人在場，
/// 連 App 自己開保險庫都要；v2 不帶，程式自己開得了，人只在要看內容時驗證。
enum EnclaveFormat {
    static let current = 2

    private static var marker: URL {
        Paths.supportDirectory.appendingPathComponent("enclave.format")
    }

    /// 沒有這個檔就是 v1：v2 是從寫下這個檔開始的。
    static var stored: Int {
        guard let text = try? String(contentsOf: marker, encoding: .utf8),
              let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return 1 }
        return value
    }

    static func stamp() {
        try? FileManager.default.createDirectory(
            at: Paths.supportDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? "\(current)".write(to: marker, atomically: true, encoding: .utf8)
    }

    /// v1 的金鑰檔還在，而且還沒換過去。
    static var needsMigration: Bool {
        let manager = FileManager.default
        return stored < current
            && manager.fileExists(atPath: Paths.enclaveKey.path)
            && manager.fileExists(atPath: Paths.peerPublicKey.path)
    }
}

/// 把 v1 的保險庫換到 v2 的金鑰底下。
enum EnclaveMigration {
    /// 驗證一次，然後就不必再驗。會擋在驗證面板上，不要從主執行緒呼叫。
    ///
    /// 全程只增不減：新金鑰生在自己的檔名底下，每個信封「加」一份新的 wrap，
    /// 舊金鑰與舊 wrap 一個字都不動。停在任何一點，這台都還是照 v1 開得了，
    /// 下次啟動從頭再跑一次。最後一步才蓋格式標記，蓋下去才算換過去。
    static func run() throws {
        let manager = FileManager.default
        let old = try EnclaveKey.deriveKey(
            reason: "把保險庫改成不必每次驗證",
            keyURL: Paths.enclaveKey,
            peerURL: Paths.peerPublicKey
        )

        var opened: [(id: String, key: SymmetricKey)] = []
        for descriptor in VaultCatalogue.all {
            let envelopeURL = Paths.keyEnvelope(for: descriptor.id)
            // 還沒開過的保險庫沒有信封，本來就沒東西要搬。
            guard manager.fileExists(atPath: envelopeURL.path) else { continue }
            // 檔案在卻讀不出來：停手。這種時候繼續走，等於在還沒確認能不能開的
            // 情況下把這台改成只認新金鑰。
            guard let envelope = VaultKeyStore.load(vaultID: descriptor.id) else {
                throw VaultError.corruptedVault
            }
            guard envelope.wraps.contains(where: { $0.type == .device }) else { continue }

            // 別台機器的 wrap 用這把開不了，開得了的那個就是這台的。
            var found: SymmetricKey?
            for wrap in envelope.wraps where wrap.type == .device {
                if let key = try? VaultKeyStore.unwrap(wrap.blob, with: old) {
                    found = key
                    break
                }
            }
            guard let found else {
                throw VaultError.authenticationFailed(
                    "「\(descriptor.name)」用現在的金鑰打不開，沒有動任何東西"
                )
            }
            opened.append((descriptor.id, found))
        }

        try EnclaveKey.provision(keyURL: Paths.enclaveKey2, peerURL: Paths.peerPublicKey2)
        let fresh = try EnclaveKey.deriveKey(
            reason: "", keyURL: Paths.enclaveKey2, peerURL: Paths.peerPublicKey2
        )

        let label = "\(DeviceIdentity.id).v2"
        for entry in opened {
            guard var envelope = VaultKeyStore.load(vaultID: entry.id) else {
                throw VaultError.corruptedVault
            }
            envelope.replace(KeyWrap(
                type: .device,
                id: label,
                label: DeviceIdentity.label,
                platform: DeviceIdentity.platform,
                blob: try VaultKeyStore.wrap(entry.key, with: fresh)
            ))
            try VaultKeyStore.save(envelope, vaultID: entry.id)
        }

        // 蓋標記等於把這台切到 v2，切之前先確認每個保險庫都真的打得開。
        for entry in opened {
            guard let envelope = VaultKeyStore.load(vaultID: entry.id),
                  let wrap = envelope.deviceWrap(id: label),
                  (try? VaultKeyStore.unwrap(wrap.blob, with: fresh)) != nil
            else { throw VaultError.corruptedVault }
        }

        // 快取裡還是剛才那把 v1 的。
        DeviceKey.forget()
        EnclaveFormat.stamp()
    }
}

/// 人的那道門。只確認操作的是誰，不碰任何金鑰——保險庫早就開著了，
/// 這裡擋的是畫面。
enum PersonCheck {
    /// 擋在驗證面板上，不要從主執行緒呼叫。
    static func confirm(reason: String) throws {
        let context = LAContext()
        context.localizedCancelTitle = "取消"

        var inspection: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &inspection) else {
            throw VaultError.biometryUnavailable
        }

        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, error in
            if !ok { failure = error ?? VaultError.authenticationFailed("驗證未完成") }
            done.signal()
        }
        done.wait()

        if let failure {
            throw VaultError.authenticationFailed(EnclaveKey.readableMessage(for: failure))
        }
    }
}

/// The device key, held for as long as this copy of the app is running.
/// Without it every vault switch costs its own Touch ID, because each vault's
/// envelope has to be unwrapped with the hardware key again.
enum DeviceKey {
    private static let mutex = NSLock()
    nonisolated(unsafe) private static var cached: SymmetricKey?

    /// Blocks on the Touch ID sheet the first time it is asked, so never call
    /// this from the main thread.
    static func current(reason: String) throws -> SymmetricKey {
        if let key = held() { return key }
        if !EnclaveKey.exists { try EnclaveKey.provision() }
        let key = try EnclaveKey.deriveKey(reason: reason)
        mutex.lock()
        cached = key
        mutex.unlock()
        return key
    }

    /// True while the key is in hand, which is the same as saying the next
    /// unlock costs no sheet. Lets the caller decide whether it has to drag
    /// the app in front of the person first.
    static var isWarm: Bool { held() != nil }

    /// Hands it back: the next unlock scans again. The lock button, sleep and
    /// screen lock are the only things that do this.
    static func forget() {
        mutex.lock()
        cached = nil
        mutex.unlock()
    }

    private static func held() -> SymmetricKey? {
        mutex.lock()
        defer { mutex.unlock() }
        return cached
    }
}

enum Paths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Brand.name, isDirectory: true)
    }

    // The enclave key belongs to the device, not to any one vault: every
    // vault's envelope is wrapped with the same hardware key.
    static var enclaveKey: URL { supportDirectory.appendingPathComponent("enclave.key") }
    /// v2 的安全區金鑰，另外兩個檔名。v1 的那兩個留在原地，換過去之後只是舊備份，
    /// 遷移全程不寫、不搬、不刪它們——中途停在哪裡都還原得回去。
    static var enclaveKey2: URL { supportDirectory.appendingPathComponent("enclave2.key") }
    static var peerPublicKey2: URL { supportDirectory.appendingPathComponent("peer2.pub") }
    /// Simulator stand-in for the Secure Enclave key. Never written on device.
    static var simulatorKey: URL { supportDirectory.appendingPathComponent("simulator.key") }
    static var peerPublicKey: URL { supportDirectory.appendingPathComponent("peer.pub") }
    static var catalogue: URL { supportDirectory.appendingPathComponent("vaults.json") }
    // These two live in files rather than UserDefaults so the app, the CLI and
    // the self test all agree on which device and which vault they are.
    static var deviceIdentity: URL { supportDirectory.appendingPathComponent("device.id") }
    static var selectedVault: URL { supportDirectory.appendingPathComponent("selected.vault") }

    static var vaultsDirectory: URL {
        supportDirectory.appendingPathComponent("Vaults", isDirectory: true)
    }

    /// Which vault the app is currently working with. Everything vault-scoped
    /// hangs off this, so switching companies is a one-line change.
    nonisolated(unsafe) static var currentVaultID: String = VaultCatalogue.selectedID

    static func directory(for vaultID: String) -> URL {
        vaultsDirectory.appendingPathComponent(vaultID, isDirectory: true)
    }

    static var vaultDirectory: URL { directory(for: currentVaultID) }
    static var vault: URL { vaultDirectory.appendingPathComponent("vault.dat") }
    static var keyEnvelope: URL { keyEnvelope(for: currentVaultID) }

    static func keyEnvelope(for vaultID: String) -> URL {
        directory(for: vaultID).appendingPathComponent("keys.json")
    }

    static func restrictToOwner(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Carries a vault created under the app's previous name across a rename.
    static func migrateLegacyDirectoryIfNeeded() {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = base.appendingPathComponent("Key Vault", isDirectory: true)
        if manager.fileExists(atPath: legacy.path), !manager.fileExists(atPath: supportDirectory.path) {
            try? manager.moveItem(at: legacy, to: supportDirectory)
        }
        VaultCatalogue.adoptSingleVaultLayoutIfNeeded()
    }

    static func ensureSupportDirectory() throws {
        try ensureDirectory(for: currentVaultID)
    }

    static func ensureDirectory(for vaultID: String) throws {
        try FileManager.default.createDirectory(
            at: directory(for: vaultID),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}

struct VaultDescriptor: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var createdAt: Date
}

/// The list of vaults, one per company. Each has its own key envelope and its
/// own sync destination; they share the device key and the backup passphrase,
/// which is set once and applied to every vault.
enum VaultCatalogue {
    nonisolated(unsafe) private static var cache: [VaultDescriptor]?

    static var all: [VaultDescriptor] {
        if let cache { return cache }
        let loaded = ((try? Data(contentsOf: Paths.catalogue))
            .flatMap { try? JSONDecoder().decode([VaultDescriptor].self, from: $0) } ?? [])
            // Alphabetical, not creation order: the picker is a list to read.
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        cache = loaded
        return loaded
    }

    static var selectedID: String {
        if let stored = try? String(contentsOf: Paths.selectedVault, encoding: .utf8) {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if all.contains(where: { $0.id == trimmed }) { return trimmed }
        }
        return all.first?.id ?? "default"
    }

    static func select(_ id: String) {
        try? id.write(to: Paths.selectedVault, atomically: true, encoding: .utf8)
        Paths.currentVaultID = id
    }

    static func descriptor(for id: String) -> VaultDescriptor? {
        all.first { $0.id == id }
    }

    @discardableResult
    static func create(name: String) -> VaultDescriptor {
        let descriptor = VaultDescriptor(id: UUID().uuidString, name: name, createdAt: Date())
        var list = all
        list.append(descriptor)
        save(list)
        try? FileManager.default.createDirectory(
            at: Paths.directory(for: descriptor.id),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return descriptor
    }

    static func rename(_ id: String, to name: String) {
        var list = all
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].name = name
        save(list)
    }

    /// Removes the vault and everything sealed inside it. Irreversible.
    static func delete(_ id: String) {
        var list = all
        list.removeAll { $0.id == id }
        save(list)
        try? FileManager.default.removeItem(at: Paths.directory(for: id))
        if selectedID == id, let first = list.first { select(first.id) }
    }

    private static func save(_ list: [VaultDescriptor]) {
        cache = list
        try? FileManager.default.createDirectory(
            at: Paths.supportDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? JSONEncoder().encode(list).write(to: Paths.catalogue, options: .atomic)
        Paths.restrictToOwner(Paths.catalogue)
    }

    /// Vaults written before multiple companies existed sat loose in the
    /// support directory; move them into the first catalogue entry.
    static func adoptSingleVaultLayoutIfNeeded() {
        let manager = FileManager.default
        if all.isEmpty {
            let descriptor = create(name: "個人")
            select(descriptor.id)
            let root = Paths.supportDirectory
            for name in ["vault.dat", "keys.json"] {
                let legacy = root.appendingPathComponent(name)
                guard manager.fileExists(atPath: legacy.path) else { continue }
                try? manager.moveItem(
                    at: legacy,
                    to: Paths.directory(for: descriptor.id).appendingPathComponent(name)
                )
            }
        }
        Paths.currentVaultID = selectedID
    }
}


/// The vault key is stored wrapped, never bare: once per device by that
/// device's hardware key, and once by the master passphrase, which is the only
/// wrap that can travel. Layout is fixed by docs/vault-format.md.
struct KDFParameters: Codable {
    var algorithm = "PBKDF2-HMAC-SHA256"
    var rounds: Int
    var salt: Data
}

struct KeyWrap: Codable, Equatable {
    enum Kind: String, Codable {
        case device
        case passphrase
        /// Holds the vault key under a one-time code printed at export. It
        /// exists only inside a transfer file and is removed once the machine
        /// that received it has its own device wrap.
        case transfer

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .passphrase
        }
    }

    var type: Kind
    var id: String?
    var label: String?
    var platform: String?
    var blob: Data
}

struct KeyEnvelope: Codable {
    var formatVersion = 3
    var kdf: KDFParameters
    var wraps: [KeyWrap]

    var hasPassphrase: Bool { wraps.contains { $0.type == .passphrase } }
    var passphraseWrap: KeyWrap? { wraps.first { $0.type == .passphrase } }
    var transferWrap: KeyWrap? { wraps.first { $0.type == .transfer } }

    /// Either wrap a typed code can open, transfer first since it is the one
    /// a freshly imported vault carries.
    var codeWrap: KeyWrap? { transferWrap ?? passphraseWrap }

    mutating func removeTransfer() {
        wraps.removeAll { $0.type == .transfer }
    }

    func deviceWrap(id: String) -> KeyWrap? {
        wraps.first { $0.type == .device && $0.id == id }
    }

    mutating func replace(_ wrap: KeyWrap) {
        wraps.removeAll { $0.type == wrap.type && $0.id == wrap.id }
        wraps.append(wrap)
    }

    mutating func removePassphrase() {
        wraps.removeAll { $0.type == .passphrase }
    }

    /// Folder sync can bring back an envelope another device extended; keep
    /// every wrap either side knows about.
    static func merged(_ local: KeyEnvelope, _ remote: KeyEnvelope) -> KeyEnvelope {
        var result = local
        result.kdf = local.kdf.rounds >= remote.kdf.rounds ? local.kdf : remote.kdf
        for wrap in remote.wraps where !result.wraps.contains(where: {
            $0.type == wrap.type && $0.id == wrap.id
        }) {
            result.wraps.append(wrap)
        }
        return result
    }
}

/// The shape written before wraps became a list. Read once, then upgraded.
private struct LegacyEnvelope: Codable {
    var version: Int
    var enclaveWrapped: Data
    var passphraseWrapped: Data?
    var salt: Data
    var rounds: Int
}

enum DeviceIdentity {
    nonisolated(unsafe) static var id: String = {
        if let stored = try? String(contentsOf: Paths.deviceIdentity, encoding: .utf8),
           !stored.isEmpty {
            return stored.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fresh = UUID().uuidString
        try? FileManager.default.createDirectory(
            at: Paths.supportDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fresh.write(to: Paths.deviceIdentity, atomically: true, encoding: .utf8)
        return fresh
    }()

    #if os(macOS)
    static var label: String { Host.current().localizedName ?? "Mac" }
    static let platform = "macos"
    #else
    static var label: String { UIDevice.current.name }
    static let platform = "ios"
    #endif
}

enum VaultKeyStore {
    static let defaultRounds = 600_000

    static func load(vaultID: String = Paths.currentVaultID) -> KeyEnvelope? {
        guard let data = try? Data(contentsOf: Paths.keyEnvelope(for: vaultID)) else { return nil }
        if let envelope = try? JSONDecoder().decode(KeyEnvelope.self, from: data) { return envelope }
        guard let legacy = try? JSONDecoder().decode(LegacyEnvelope.self, from: data) else { return nil }
        var wraps = [KeyWrap(
            type: .device,
            id: DeviceIdentity.id,
            label: DeviceIdentity.label,
            platform: DeviceIdentity.platform,
            blob: legacy.enclaveWrapped
        )]
        if let passphrase = legacy.passphraseWrapped {
            wraps.append(KeyWrap(type: .passphrase, blob: passphrase))
        }
        let upgraded = KeyEnvelope(
            kdf: KDFParameters(rounds: legacy.rounds, salt: legacy.salt),
            wraps: wraps
        )
        try? save(upgraded, vaultID: vaultID)
        return upgraded
    }

    static func save(_ envelope: KeyEnvelope, vaultID: String = Paths.currentVaultID) throws {
        try Paths.ensureDirectory(for: vaultID)
        let url = Paths.keyEnvelope(for: vaultID)
        try JSONEncoder().encode(envelope).write(to: url, options: [.atomic])
        Paths.restrictToOwner(url)
    }

    /// Eight digits, typed once on the receiving machine. The file it opens
    /// is deleted the moment that machine binds itself, so the code never
    /// stands guard over anything for long.
    static func transferCode() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(Int($0) % 10) }.joined()
    }

    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func wrap(_ vaultKey: SymmetricKey, with key: SymmetricKey) throws -> Data {
        let raw = vaultKey.withUnsafeBytes { Data($0) }
        return try AES.GCM.seal(raw, using: key).combined!
    }

    static func unwrap(_ blob: Data, with key: SymmetricKey) throws -> SymmetricKey {
        let box = try AES.GCM.SealedBox(combined: blob)
        return SymmetricKey(data: try AES.GCM.open(box, using: key))
    }

    static func deviceWrap(for vaultKey: SymmetricKey, enclaveKey: SymmetricKey) throws -> KeyWrap {
        KeyWrap(
            type: .device,
            id: DeviceIdentity.id,
            label: DeviceIdentity.label,
            platform: DeviceIdentity.platform,
            blob: try wrap(vaultKey, with: enclaveKey)
        )
    }

    /// PBKDF2-HMAC-SHA256; CryptoKit has no password-based derivation of its own.
    /// The passphrase is normalised first so the same characters typed on a
    /// different keyboard still derive the same key.
    static func passphraseKey(_ passphrase: String, salt: Data, rounds: Int) -> SymmetricKey {
        SymmetricKey(data: pbkdf2(
            password: Data(passphrase.precomposedStringWithCanonicalMapping.utf8),
            salt: salt,
            rounds: rounds
        ))
    }

    static func pbkdf2(password: Data, salt: Data, rounds: Int, length: Int = 32) -> Data {
        var derived = [UInt8](repeating: 0, count: length)
        let password = [UInt8](password)
        salt.withUnsafeBytes { saltBytes in
            _ = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password.withUnsafeBufferPointer { $0.baseAddress?.withMemoryRebound(to: CChar.self, capacity: password.count) { $0 } },
                password.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(rounds),
                &derived,
                derived.count
            )
        }
        return Data(derived)
    }
}

