import Foundation

// Round-trips the real vault file through the real Secure Enclave key, then
// restores whatever was there before. One Touch ID prompt.
do {
    guard EnclaveKey.exists else {
        print("FAIL: enclave key not provisioned; open the app once first")
        exit(1)
    }
    let enclaveKey = try EnclaveKey.deriveKey(reason: "執行 Slate 自我測試")
    let (derived, original) = try VaultFile.openOrCreate(enclaveKey: enclaveKey)
    print("loaded existing items: \(original.count)")

    let sample = KeyItem(kind: .login, name: "自我測試", provider: "OpenAI", username: "tester@example.com", secret: "sk-test-0123456789", note: "round trip")
    try VaultFile.save(original + [sample], key: derived)

    let reloaded = try VaultFile.load(key: derived)
    guard reloaded.count == original.count + 1,
          let stored = reloaded.first(where: { $0.id == sample.id }),
          stored.secret == sample.secret,
          stored.name == sample.name,
          stored.username == sample.username,
          stored.kind == .login else {
        print("FAIL: round trip mismatch")
        exit(1)
    }

    let raw = try Data(contentsOf: Paths.vault)
    if raw.range(of: Data("sk-test-0123456789".utf8)) != nil {
        print("FAIL: plaintext secret found in vault.dat")
        exit(1)
    }
    let mode = (try FileManager.default.attributesOfItem(atPath: Paths.vault.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
    print("vault.dat bytes: \(raw.count), mode: \(String(mode, radix: 8))")

    if original.isEmpty {
        try FileManager.default.removeItem(at: Paths.vault)
        print("restored: removed vault.dat")
    } else {
        try VaultFile.save(original, key: derived)
        print("restored: \(original.count) items")
    }
    print("PASS")
} catch {
    print("FAIL: \(error)")
    exit(1)
}
