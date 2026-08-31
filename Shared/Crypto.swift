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

    static var exists: Bool {
        Paths.migrateLegacyDirectoryIfNeeded()
        #if targetEnvironment(simulator)
        return FileManager.default.fileExists(atPath: Paths.simulatorKey.path)
        #else
        return FileManager.default.fileExists(atPath: Paths.enclaveKey.path)
            && FileManager.default.fileExists(atPath: Paths.peerPublicKey.path)
        #endif
    }

    static func provision() throws {
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
            [.privateKeyUsage, .userPresence],
            &error
        ) else { throw VaultError.accessControlFailed }

        let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        let peer = P256.KeyAgreement.PrivateKey()
        try Paths.ensureSupportDirectory()
        try enclave.dataRepresentation.write(to: Paths.enclaveKey, options: .completeFileProtection)
        try peer.publicKey.rawRepresentation.write(to: Paths.peerPublicKey, options: .completeFileProtection)
        Paths.restrictToOwner(Paths.enclaveKey)
        Paths.restrictToOwner(Paths.peerPublicKey)
        #endif
    }

    /// Blocks on the Touch ID sheet, so never call this from the main thread.
    static func deriveKey(reason: String, reuseDuration: TimeInterval = 0) throws -> SymmetricKey {
        guard exists else { throw VaultError.enclaveMissing }
        let context = LAContext()
        context.localizedReason = reason
        context.localizedCancelTitle = "取消"
        context.touchIDAuthenticationAllowableReuseDuration = reuseDuration

        #if targetEnvironment(simulator)
        return SymmetricKey(data: try Data(contentsOf: Paths.simulatorKey))
        #else
        let blob = try Data(contentsOf: Paths.enclaveKey)
        let peerData = try Data(contentsOf: Paths.peerPublicKey)
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

    private static func readableMessage(for error: Error) -> String {
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

/// How long one Touch ID scan stays good for. Inside the window the app can
/// open another company's vault, or reopen after locking, without asking again.
enum UnlockWindow {
    static let choices = [5, 10, 15]
    private static let defaultsKey = "UnlockWindowMinutes"

    static var minutes: Int {
        let stored = UserDefaults.standard.integer(forKey: defaultsKey)
        return choices.contains(stored) ? stored : choices[0]
    }

    static var seconds: TimeInterval { TimeInterval(minutes * 60) }
}

/// The device key, held in memory for the length of the unlock window. Without
/// it every vault switch costs its own Touch ID, because each vault's envelope
/// has to be unwrapped with the hardware key again.
enum DeviceKey {
    private static let mutex = NSLock()
    nonisolated(unsafe) private static var cached: (key: SymmetricKey, until: Date)?

    /// Blocks on the Touch ID sheet whenever the window has run out, so never
    /// call this from the main thread.
    static func current(reason: String) throws -> SymmetricKey {
        if let key = unexpired() { return key }
        if !EnclaveKey.exists { try EnclaveKey.provision() }
        let key = try EnclaveKey.deriveKey(reason: reason)
        mutex.lock()
        cached = (key, Date().addingTimeInterval(UnlockWindow.seconds))
        mutex.unlock()
        return key
    }

    /// Closes the window early: the next unlock scans again.
    static func forget() {
        mutex.lock()
        cached = nil
        mutex.unlock()
    }

    private static func unexpired() -> SymmetricKey? {
        mutex.lock()
        defer { mutex.unlock() }
        guard let entry = cached else { return nil }
        guard entry.until > Date() else {
            cached = nil
            return nil
        }
        return entry.key
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

