#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import CryptoKit
import Foundation
import UniformTypeIdentifiers
import SwiftUI

enum ItemKind: String, Codable, CaseIterable {
    case apiKey
    case token
    case identifier
    case login

    var label: String {
        switch self {
        case .apiKey: return "API Key"
        case .token: return "授權碼"
        case .identifier: return "ID"
        case .login: return "帳號密碼"
        }
    }

    var symbol: String {
        switch self {
        case .apiKey: return "key.fill"
        case .token: return "checkmark.seal.fill"
        case .identifier: return "number"
        case .login: return "person.crop.circle.fill"
        }
    }

    /// IDs are not secrets, so they are shown rather than masked.
    var isSecret: Bool { self != .identifier }

    var valueLabel: String {
        switch self {
        case .apiKey: return "API KEY"
        case .token: return "授權碼"
        case .identifier: return "ID"
        case .login: return "密碼"
        }
    }

    var valuePlaceholder: String {
        switch self {
        case .apiKey: return "sk-…"
        case .token: return "存取權杖 / refresh token"
        case .identifier: return "App ID、Client ID、頻道 ID"
        case .login: return "密碼"
        }
    }

    var namePlaceholder: String {
        switch self {
        case .apiKey: return "例如：正式環境"
        case .token: return "例如：粉專發文權杖"
        case .identifier: return "例如：App ID"
        case .login: return "例如：公司信箱"
        }
    }

    /// A token belongs to an app or a page, so it carries that id next to the
    /// value. An API key has no such counterpart.
    var showsAccountField: Bool { self == .login || self == .token }

    var accountLabel: String { self == .token ? "應用 / 頻道 ID" : "帳號" }

    var accountPlaceholder: String {
        self == .token ? "例如：Meta App ID、粉專 ID" : "email 或使用者名稱"
    }

    var newTitle: String {
        switch self {
        case .apiKey: return "新增金鑰"
        case .token: return "新增授權碼"
        case .identifier: return "新增 ID"
        case .login: return "新增帳號"
        }
    }
}

struct KeyItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: ItemKind = .apiKey
    var name: String = ""
    var username: String = ""
    var secret: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }

    var displayName: String { name.isEmpty ? "未命名" : name }

    var subtitle: String {
        switch kind {
        case .token, .login:
            return username.isEmpty ? kind.label : username
        case .apiKey, .identifier:
            return kind.label
        }
    }

    init(
        id: UUID = UUID(),
        kind: ItemKind = .apiKey,
        name: String = "",
        username: String = "",
        secret: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.username = username
        self.secret = secret
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    // Vaults written before accounts existed have neither kind nor username.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        // Decoded through its raw value: an unfamiliar kind falls back rather
        // than throwing and taking the rest of the vault with it.
        kind = (try container.decodeIfPresent(String.self, forKey: .kind))
            .flatMap(ItemKind.init(rawValue:)) ?? .apiKey
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        secret = try container.decodeIfPresent(String.self, forKey: .secret) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

@MainActor
final class VaultStore: ObservableObject {
    enum Phase: Equatable {
        case locked
        case unlocking
        case unlocked
    }

    @Published private(set) var phase: Phase = .locked
    @Published private(set) var items: [KeyItem] = [] {
        didSet { SecretSnapshot.shared.update(items) }
    }
    @Published private(set) var events: [AuditEvent] = []
    @Published private(set) var hasPassphrase = VaultKeyStore.load()?.hasPassphrase ?? false
    /// Names of the vaults the shared passphrase has not been applied to yet.
    @Published private(set) var vaultsMissingPassphrase: [String] = []
    /// True when some other vault already carries a passphrase wrap, so typing
    /// the same phrase here is a re-alignment rather than a first setup.
    @Published private(set) var passphraseExistsElsewhere = false
    @Published private(set) var vaults: [VaultDescriptor] = VaultCatalogue.all
    @Published private(set) var currentVaultID: String = Paths.currentVaultID
    @Published var message: String?
    @Published var search: String = ""

    private var key: SymmetricKey?
    private var clipboardToken: Int = 0
    /// The file an import came from. It holds the whole vault behind nothing
    /// but the passphrase, so it is removed the moment the vault opens here.
    private var importedBundleURL: URL?

    init() {
        Paths.migrateLegacyDirectoryIfNeeded()
        vaults = VaultCatalogue.all
        currentVaultID = Paths.currentVaultID
        refreshPassphraseScope()
    }

    /// There is one backup passphrase per Mac, so it counts as set only when
    /// every vault carries a wrap for it.
    private func refreshPassphraseScope() {
        hasPassphrase = VaultKeyStore.load()?.hasPassphrase ?? false
        let catalogue = VaultCatalogue.all
        vaultsMissingPassphrase = catalogue
            .filter { VaultKeyStore.load(vaultID: $0.id)?.hasPassphrase != true }
            .map(\.name)
        passphraseExistsElsewhere = catalogue.contains {
            $0.id != currentVaultID && VaultKeyStore.load(vaultID: $0.id)?.hasPassphrase == true
        }
    }

    var currentVaultName: String {
        VaultCatalogue.descriptor(for: currentVaultID)?.name ?? Brand.name
    }

    init(previewPhase: Phase, previewItems: [KeyItem], previewHasPassphrase: Bool = false) {
        phase = previewPhase
        items = previewItems
        hasPassphrase = previewHasPassphrase
    }

    var isFirstRun: Bool { !EnclaveKey.exists }

    /// True when a passphrase wrap exists, meaning the vault can be opened
    /// without this Mac's enclave.
    var restoreAvailable: Bool {
        VaultKeyStore.load()?.codeWrap != nil
    }

    /// An imported vault carries no wrap for this machine, so the backup
    /// passphrase is the only way in and should be what the lock screen asks
    /// for — not a grey link under everything else.
    var needsAdoption: Bool {
        guard let envelope = VaultKeyStore.load() else { return false }
        return envelope.codeWrap != nil && envelope.deviceWrap(id: DeviceIdentity.id) == nil
    }

    var visibleItems: [KeyItem] { items.filter { !$0.isDeleted } }

    var filtered: [KeyItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Alphabetical, case and locale aware, so a name always sits where the
        // reader expects rather than wherever it was last touched.
        let sorted = visibleItems.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.lowercased().contains(query)
                || $0.username.lowercased().contains(query)
        }
    }

    func unlock() {
        guard phase == .locked else { return }
        guard EnclaveKey.isSupported else {
            message = VaultError.biometryUnavailable.errorDescription
            return
        }
        phase = .unlocking
        message = nil

        Task.detached(priority: .userInitiated) {
            do {
                let enclaveKey = try DeviceKey.current(reason: "讀取你儲存的 API Key")
                let (vaultKey, items) = try VaultFile.openOrCreate(enclaveKey: enclaveKey)
                let events = VaultFile.loadEvents(key: vaultKey)
                await MainActor.run { self.finishUnlock(key: vaultKey, items: items, events: events) }
            } catch {
                await MainActor.run { self.failUnlock(error) }
            }
        }
    }

    /// Called once the vault is open on this machine, which is the point the
    /// transfer file has done its job and should stop existing.
    private func discardImportSource() {
        guard let url = importedBundleURL else { return }
        importedBundleURL = nil
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
        message = "已匯入，來源檔已刪除"
    }

    private func finishUnlock(key: SymmetricKey, items: [KeyItem], events: [AuditEvent] = []) {
        self.key = key
        self.items = items
        self.events = events
        refreshPassphraseScope()
        discardImportSource()
        withAnimation(Motion.snappy) { phase = .unlocked }
    }

    private func failUnlock(_ error: Error) {
        key = nil
        items = []
        message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        withAnimation(Motion.snappy) { phase = .locked }
    }

    /// Switching companies always locks first: the previous vault's contents
    /// must never survive into the next one.
    func switchVault(to id: String) {
        guard id != currentVaultID else { return }
        lock()
        VaultCatalogue.select(id)
        currentVaultID = id
        refreshPassphraseScope()
        // A vault this machine has never been bound to is opened by its code,
        // not by the enclave, so do not start an unlock that can only fail.
        guard !needsAdoption else { return }
        unlock()
    }

    @discardableResult
    func createVault(named name: String) -> VaultDescriptor {
        let descriptor = VaultCatalogue.create(name: name)
        vaults = VaultCatalogue.all
        refreshPassphraseScope()
        switchVault(to: descriptor.id)
        return descriptor
    }

    func renameVault(_ id: String, to name: String) {
        VaultCatalogue.rename(id, to: name)
        vaults = VaultCatalogue.all
    }

    func deleteVault(_ id: String) {
        guard vaults.count > 1 else {
            message = "至少要保留一個保險庫"
            return
        }
        let wasCurrent = id == currentVaultID
        if wasCurrent { lock() }
        VaultCatalogue.delete(id)
        vaults = VaultCatalogue.all
        refreshPassphraseScope()
        if wasCurrent {
            currentVaultID = VaultCatalogue.selectedID
            Paths.currentVaultID = currentVaultID
            unlock()
        }
    }

    /// Clears the open vault but leaves the unlock window running, so hiding
    /// the panel or switching companies does not cost another scan.
    func lock() {
        key = nil
        SecretSnapshot.shared.clear()
        items = []
        events = []
        search = ""
        message = nil
        phase = .locked
    }

    /// What the lock button means: the unlock window closes with the vault, so
    /// the next open needs Touch ID.
    func lockNow() {
        DeviceKey.forget()
        lock()
    }

    @discardableResult
    func save(_ item: KeyItem) -> KeyItem {
        var updated = item
        updated.updatedAt = Date()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updated
        } else {
            items.append(updated)
        }
        persist()
        return updated
    }

    func delete(_ item: KeyItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        // A tombstone, so the deletion survives a merge with another device.
        var tombstone = KeyItem(id: item.id, createdAt: item.createdAt)
        tombstone.updatedAt = Date()
        tombstone.deletedAt = tombstone.updatedAt
        items[index] = tombstone
        persist()
    }

    /// Writes a new value onto an existing row, so history stays attached to
    /// it rather than starting over on a fresh entry.
    func replaceSecret(of item: KeyItem, with secret: String, detail: String = "") {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        updated.secret = secret
        updated.updatedAt = Date()
        items[index] = updated
        events.append(AuditEvent(
            kind: .replaced, itemID: item.id, itemName: item.displayName, detail: detail
        ))
        persist()
    }

    private func clearPasteboardIfHolding(_ secret: String) {
        #if canImport(AppKit)
        guard !secret.isEmpty,
              NSPasteboard.general.string(forType: .string) == secret else { return }
        NSPasteboard.general.clearContents()
        #endif
    }

    private func persist() {
        guard let key else { return }
        do {
            try VaultFile.save(items, key: key, events: events)
        } catch {
            message = "儲存失敗：\(error.localizedDescription)"
        }
    }

    // MARK: - Moving a vault between machines

    /// The receiving Mac can only open the bundle with the master passphrase,
    /// so exporting without one would produce a file nobody can use.
    func exportBundle(to url: URL) {
        guard let vaultKey = key else {
            message = "先解鎖再匯出"
            return
        }
        do {
            let bundle = try VaultBundle.make(name: currentVaultName, vaultKey: vaultKey)
            try JSONEncoder().encode(bundle).write(to: url, options: .atomic)
            Paths.restrictToOwner(url)
            message = "已匯出。這個檔案可以直接開啟，匯入後請刪除"
        } catch {
            message = "匯出失敗：\(error.localizedDescription)"
        }
    }

    /// Brings in a file exported from another password manager. A row whose
    /// name already exists is updated in place, so importing the same file
    /// twice corrects the entries rather than doubling them.
    func importFile(at url: URL) {
        guard phase == .unlocked else {
            message = "先解鎖再匯入"
            return
        }
        do {
            let result = url.pathExtension.lowercased() == "txt"
                ? try TextImporter.read(url)
                : try CSVImporter.read(url)
            guard !result.items.isEmpty else {
                message = "這個檔案裡沒有可匯入的項目"
                return
            }
            var added = 0
            var updated = 0
            for incoming in result.items {
                let target = incoming.displayName.lowercased()
                if let index = items.firstIndex(where: {
                    $0.deletedAt == nil && $0.displayName.lowercased() == target
                }) {
                    items[index].kind = incoming.kind
                    items[index].secret = incoming.secret
                    if !incoming.username.isEmpty { items[index].username = incoming.username }
                    items[index].updatedAt = Date()
                    updated += 1
                } else {
                    items.append(incoming)
                    added += 1
                }
            }
            persist()
            var summary = "已匯入 \(added) 筆"
            if updated > 0 { summary += "，更新 \(updated) 筆" }
            if result.skipped > 0 { summary += "，略過 \(result.skipped) 筆空白列" }
            message = summary
        } catch {
            message = "匯入失敗：檔案讀不開或不是 CSV"
        }
    }

    func importBundle(from url: URL) {
        do {
            let bundle = try JSONDecoder().decode(VaultBundle.self, from: try Data(contentsOf: url))
            let descriptor = try bundle.install()
            vaults = VaultCatalogue.all
            lock()
            VaultCatalogue.select(descriptor.id)
            currentVaultID = descriptor.id
            refreshPassphraseScope()
            importedBundleURL = url
            unlock()
        } catch {
            message = "匯入失敗：檔案損壞或不是 Slate 匯出檔"
        }
    }

    // MARK: - Master passphrase

    /// One phrase for the whole Mac: every vault keeps its own key, but each of
    /// them is wrapped with the same passphrase, so a restore never depends on
    /// remembering which company a file came from.
    func setPassphrase(_ passphrase: String) {
        guard phase == .unlocked else { return }
        let catalogue = VaultCatalogue.all
        let openVaultID = currentVaultID
        let openVaultKey = key
        Task.detached(priority: .userInitiated) {
            do {
                let enclaveKey = try DeviceKey.current(reason: "為所有保險庫設定備份密碼")
                var skipped: [String] = []
                for vault in catalogue {
                    guard var envelope = VaultKeyStore.load(vaultID: vault.id) else { continue }
                    guard let vaultKey = Self.vaultKey(
                        in: envelope,
                        enclaveKey: enclaveKey,
                        preferring: vault.id == openVaultID ? openVaultKey : nil
                    ) else {
                        skipped.append(vault.name)
                        continue
                    }
                    let salt = VaultKeyStore.randomSalt()
                    let derived = VaultKeyStore.passphraseKey(
                        passphrase, salt: salt, rounds: VaultKeyStore.defaultRounds
                    )
                    envelope.kdf = KDFParameters(rounds: VaultKeyStore.defaultRounds, salt: salt)
                    envelope.replace(KeyWrap(
                        type: .passphrase,
                        blob: try VaultKeyStore.wrap(vaultKey, with: derived)
                    ))
                    try VaultKeyStore.save(envelope, vaultID: vault.id)
                }
                let missed = skipped
                await MainActor.run { self.finishPassphrase(skipped: missed) }
            } catch {
                await MainActor.run {
                    self.message = "設定備份密碼失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    /// The open vault's key is already in memory; the others have to come out
    /// of a device wrap, and a vault this Mac has not joined has none that fit.
    private nonisolated static func vaultKey(
        in envelope: KeyEnvelope,
        enclaveKey: SymmetricKey,
        preferring known: SymmetricKey?
    ) -> SymmetricKey? {
        if let known { return known }
        for wrap in envelope.wraps where wrap.type == .device {
            if let opened = try? VaultKeyStore.unwrap(wrap.blob, with: enclaveKey) { return opened }
        }
        return nil
    }

    private func finishPassphrase(skipped: [String]) {
        refreshPassphraseScope()
        if skipped.isEmpty {
            message = "備份密碼已設定，所有保險庫共用這一組"
        } else {
            message = "備份密碼已設定；\(skipped.joined(separator: "、")) 還沒加入這台 Mac，未套用"
        }
    }

    /// Removing it removes it everywhere, for the same reason setting it sets
    /// it everywhere: there is only ever one backup passphrase.
    func removePassphrase() {
        for vault in VaultCatalogue.all {
            guard var envelope = VaultKeyStore.load(vaultID: vault.id) else { continue }
            envelope.removePassphrase()
            try? VaultKeyStore.save(envelope, vaultID: vault.id)
        }
        refreshPassphraseScope()
    }

    /// Takes a vault copied from another Mac and re-wraps its key for this one.
    func adopt(withPassphrase passphrase: String) {
        guard phase != .unlocking else { return }
        phase = .unlocking
        message = nil
        Task.detached(priority: .userInitiated) {
            do {
                guard var envelope = VaultKeyStore.load() else { throw VaultError.enclaveMissing }
                guard let wrapped = envelope.codeWrap?.blob else { throw VaultError.noPassphraseSet }
                let derived = VaultKeyStore.passphraseKey(
                    passphrase, salt: envelope.kdf.salt, rounds: envelope.kdf.rounds
                )
                guard let vaultKey = try? VaultKeyStore.unwrap(wrapped, with: derived) else {
                    throw VaultError.wrongPassphrase
                }
                // The passphrase has already produced the vault key, so the
                // vault opens either way. Binding this Mac to it is a
                // convenience for next time — if the system prompt is
                // dismissed or fails, say so instead of refusing entry and
                // leaving the reader to think the passphrase was wrong.
                var bound = true
                do {
                    let enclaveKey = try DeviceKey.current(reason: "把這個保險庫綁到這台 Mac")
                    envelope.replace(try VaultKeyStore.deviceWrap(for: vaultKey, enclaveKey: enclaveKey))
                    // The code was for one journey. Once this Mac can open the
                    // vault itself, the code stops being a key to it.
                    envelope.removeTransfer()
                    try VaultKeyStore.save(envelope)
                } catch {
                    bound = false
                }
                let items = try VaultFile.load(key: vaultKey)
                await MainActor.run {
                    self.finishUnlock(key: vaultKey, items: items)
                    if !bound {
                        self.message = "已開啟，但這台 Mac 還沒綁定，下次仍需備份密碼"
                    }
                }
            } catch {
                await MainActor.run { self.failUnlock(error) }
            }
        }
    }

    /// Copies a secret and wipes it from the pasteboard after a short window.
    func copy(_ item: KeyItem) {
        copy(item.secret)
    }

    func copy(_ text: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Clipboard managers honour this type by not recording the value.
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let token = pasteboard.changeCount
        clipboardToken = token

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard let self, self.clipboardToken == token else { return }
            if NSPasteboard.general.changeCount == token {
                NSPasteboard.general.clearContents()
            }
        }
        #else
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: text]],
            options: [.expirationDate: Date().addingTimeInterval(45)]
        )
        #endif
    }
}

/// An append-only record of what happened to the vault. It holds no secret
/// values, only what was done and when, so an audit can be read without
/// exposing anything.
struct AuditEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case replaced
        case deleted
        case other

        /// A vault written by an older build can name a kind this one no
        /// longer has. Anything unrecognised reads as `other` so one retired
        /// event never makes the whole document undecodable.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .other
        }

        var label: String {
            switch self {
            case .replaced: return "換新"
            case .deleted: return "刪除"
            case .other: return "其他"
            }
        }
    }

    var id = UUID()
    var at = Date()
    var kind: Kind
    var itemID: UUID
    var itemName: String
    var detail: String = ""
}

/// What actually gets sealed into vault.dat.
struct VaultDocument: Codable {
    var formatVersion = 3
    var updatedAt = Date()
    var items: [KeyItem] = []
    var events: [AuditEvent] = []
}


/// One file that carries a whole vault to another machine. It is nothing but
/// the two sealed files side by side, so it is as unreadable in transit as
/// they are at rest: without the master passphrase it opens nothing.
struct VaultBundle: Codable {
    // slatevault was the original spelling; the type still claims it so files
    // exported before the rename stay openable.
    static let fileExtension = "slate"
    static let contentType = UTType(exportedAs: "com.avalonlotus.slate.vault")

    var formatVersion = 3
    var name: String
    var exportedAt = Date()
    /// Empty in files written from this version on; older files carry the
    /// sending machine's envelope here.
    var envelope: Data
    var payload: Data
    /// The vault key in the clear, which is what lets the receiving machine
    /// open the file without being told anything.
    var vaultKey: Data?

    /// Builds a file that opens by itself. The vault key travels with it, so
    /// the machine receiving it needs nothing from the machine that sent it —
    /// no code, no passphrase. The file is therefore readable by whoever
    /// holds it, and is deleted as soon as it has been used.
    static func make(name: String, vaultKey: SymmetricKey) throws -> VaultBundle {
        let payload = (try? Data(contentsOf: Paths.vault)) ?? Data()
        let key = vaultKey.withUnsafeBytes { Data($0) }
        return VaultBundle(name: name, envelope: Data(), payload: payload, vaultKey: key)
    }

    /// Writes the bundle into a fresh vault on this machine and binds it to
    /// this machine's own Secure Enclave, so from here on it unlocks the way
    /// every other vault on this Mac does.
    @discardableResult
    func install() throws -> VaultDescriptor {
        let descriptor = VaultCatalogue.create(name: name)
        let directory = Paths.directory(for: descriptor.id)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !payload.isEmpty {
            try payload.write(to: directory.appendingPathComponent("vault.dat"), options: .atomic)
        }

        if let raw = vaultKey {
            let enclaveKey = try DeviceKey.current(reason: "把這個保險庫綁到這台 Mac")
            let envelope = KeyEnvelope(
                kdf: KDFParameters(rounds: VaultKeyStore.defaultRounds, salt: VaultKeyStore.randomSalt()),
                wraps: [try VaultKeyStore.deviceWrap(
                    for: SymmetricKey(data: raw), enclaveKey: enclaveKey
                )]
            )
            try VaultKeyStore.save(envelope, vaultID: descriptor.id)
        } else {
            // A file from before the key travelled with it.
            try envelope.write(to: directory.appendingPathComponent("keys.json"), options: .atomic)
        }
        return descriptor
    }
}

enum VaultFile {
    /// Returns the vault key plus its contents, creating the key envelope on a
    /// first run and upgrading vaults that were sealed with the enclave key直接.
    static func openOrCreate(enclaveKey: SymmetricKey) throws -> (SymmetricKey, [KeyItem]) {
        if var envelope = VaultKeyStore.load() {
            // The id is only a label; the lock is the device key itself. If the
            // label does not match, try every device wrap before giving up, and
            // relabel the one that opens so it matches next time.
            var opened: SymmetricKey?
            if let wrap = envelope.deviceWrap(id: DeviceIdentity.id) {
                opened = try? VaultKeyStore.unwrap(wrap.blob, with: enclaveKey)
            }
            if opened == nil {
                for candidate in envelope.wraps where candidate.type == .device {
                    guard let key = try? VaultKeyStore.unwrap(candidate.blob, with: enclaveKey) else {
                        continue
                    }
                    opened = key
                    envelope.wraps.removeAll { $0.type == .device && $0.id == candidate.id }
                    envelope.replace(try VaultKeyStore.deviceWrap(for: key, enclaveKey: enclaveKey))
                    try? VaultKeyStore.save(envelope)
                    break
                }
            }
            guard let vaultKey = opened else { throw VaultError.deviceNotEnrolled }
            return (vaultKey, try load(key: vaultKey))
        }

        let legacyItems = (try? load(key: enclaveKey)) ?? []
        let vaultKey = SymmetricKey(size: .bits256)
        let envelope = KeyEnvelope(
            kdf: KDFParameters(rounds: VaultKeyStore.defaultRounds, salt: VaultKeyStore.randomSalt()),
            wraps: [try VaultKeyStore.deviceWrap(for: vaultKey, enclaveKey: enclaveKey)]
        )
        try VaultKeyStore.save(envelope)
        try save(legacyItems, key: vaultKey)
        return (vaultKey, legacyItems)
    }

    static func load(key: SymmetricKey) throws -> [KeyItem] {
        guard FileManager.default.fileExists(atPath: Paths.vault.path) else { return [] }
        return try decode(try Data(contentsOf: Paths.vault), key: key)
    }

    static func loadEvents(key: SymmetricKey) -> [AuditEvent] {
        guard FileManager.default.fileExists(atPath: Paths.vault.path),
              let blob = try? Data(contentsOf: Paths.vault),
              let document = try? decodeDocument(blob, key: key) else { return [] }
        return document.events
    }

    static func decodeDocument(_ blob: Data, key: SymmetricKey) throws -> VaultDocument {
        guard let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: key) else {
            throw VaultError.corruptedVault
        }
        if let document = try? decoder.decode(VaultDocument.self, from: plain) { return document }
        let items = (try? legacyDecoder.decode([KeyItem].self, from: plain)) ?? []
        return VaultDocument(items: items)
    }

    static func decode(_ blob: Data, key: SymmetricKey) throws -> [KeyItem] {
        guard let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: key) else {
            throw VaultError.corruptedVault
        }
        if let document = try? decoder.decode(VaultDocument.self, from: plain) {
            return document.items
        }
        // Vaults written before the document wrapper existed are a bare array.
        return (try? legacyDecoder.decode([KeyItem].self, from: plain)) ?? []
    }

    static func save(_ items: [KeyItem], key: SymmetricKey, events: [AuditEvent] = []) throws {
        let document = VaultDocument(updatedAt: Date(), items: items, events: events)
        let plain = try encoder.encode(document)
        let sealed = try AES.GCM.seal(plain, using: key)
        try Paths.ensureSupportDirectory()
        try sealed.combined!.write(to: Paths.vault, options: [.atomic, .completeFileProtection])
        Paths.restrictToOwner(Paths.vault)
    }

    // Dates are ISO 8601 so the bytes match on every platform.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let legacyDecoder = JSONDecoder()
}
