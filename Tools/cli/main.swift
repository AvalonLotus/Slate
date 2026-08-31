import CryptoKit
import Darwin
import Foundation
import LocalAuthentication

// slate — reads the vault from scripts. Talks to the running app when it is
// unlocked; falls back to Touch ID when it is not.

let usage = """
用法：
  slate get <名稱>     印出該筆的密碼或 API Key
  slate user <名稱>    印出該筆的帳號
  slate list           列出所有條目名稱
  slate json           以 JSON 列出所有條目（不含密碼）
  slate check          逐一詢問各服務，該金鑰是否仍能通過驗證

寫入（需要 Slate 開著且已解鎖）：
  slate add <名稱> [型別]     新增一筆，值從標準輸入讀
  slate set <名稱>            換掉該筆的值，值從標準輸入讀
  slate rename <舊名> <新名>  改名
  slate kind <名稱> <型別>    改型別
  slate id <名稱> <ID>        設定應用 / 頻道 ID
  slate delete <名稱>         刪除該筆
  slate import <檔案>         匯入 csv 或 txt

型別：apiKey、token、identifier、login

值一律從標準輸入讀，不放在指令參數裡，免得留在 shell 紀錄或行程清單。

Slate 開著且已解鎖時直接取值，否則彈一次 Touch ID，
同一批操作五分鐘內只需驗證一次。
"""

/// Secrets arrive on stdin so they never appear in `ps` or shell history.
func readValue() -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: - Agent

func askAgent(_ request: AgentRequest) -> AgentResponse? {
    let path = AgentProtocol.socketPath
    guard FileManager.default.fileExists(atPath: path) else { return nil }

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        path.withCString { source in
            strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), source, 104)
        }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
    }
    guard connected == 0, let payload = try? JSONEncoder().encode(request) else { return nil }

    let sent = payload.withUnsafeBytes { bytes in
        write(fd, bytes.baseAddress, bytes.count)
    }
    guard sent > 0 else { return nil }

    var buffer = [UInt8](repeating: 0, count: 65536)
    let received = read(fd, &buffer, buffer.count)
    guard received > 0 else { return nil }
    return try? JSONDecoder().decode(AgentResponse.self, from: Data(buffer[0..<received]))
}

// MARK: - Direct unlock

func openLocally() -> [KeyItem] {
    guard EnclaveKey.exists else { fail("保險庫還沒建立，先開一次 Slate") }
    do {
        let enclaveKey = try EnclaveKey.deriveKey(
            reason: "讓終端機讀取保險庫",
            reuseDuration: LATouchIDAuthenticationMaximumAllowableReuseDuration
        )
        let (_, items) = try VaultFile.openOrCreate(enclaveKey: enclaveKey)
        return items.filter { !$0.isDeleted }
    } catch {
        fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }
}

func lookup(_ name: String) -> KeyItem {
    let snapshot = SecretSnapshot()
    snapshot.update(openLocally())
    guard let item = snapshot.find(name) else { fail("找不到：\(name)") }
    return item
}

// MARK: - Commands

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { print(usage); exit(0) }

switch command {
case "get", "user":
    guard arguments.count > 1 else { fail("要給名稱") }
    let name = arguments[1]
    if let response = askAgent(AgentRequest(command: "get", name: name)), response.ok {
        let value = command == "get" ? response.value : response.username
        print(value ?? "")
    } else {
        let item = lookup(name)
        print(command == "get" ? item.secret : item.username)
    }

case "list":
    if let response = askAgent(AgentRequest(command: "list")), response.ok, let items = response.items {
        for item in items {
            let detail = item.username
            print(detail.isEmpty ? item.name : "\(item.name)\t\(detail)")
        }
    } else {
        for item in openLocally() {
            let detail = item.username
            print(detail.isEmpty ? item.displayName : "\(item.displayName)\t\(detail)")
        }
    }

case "json":
    let entries: [[String: String]]
    if let response = askAgent(AgentRequest(command: "list")), response.ok, let items = response.items {
        entries = items.map { ["name": $0.name, "username": $0.username, "kind": $0.kind] }
    } else {
        entries = openLocally().map {
            ["name": $0.displayName, "username": $0.username, "kind": $0.kind.rawValue]
        }
    }
    let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8) ?? "[]")

case "check":
    // One local open covers every entry, so a locked app costs a single
    // prompt rather than one per key.
    let subjects: [(name: String, kind: String, secret: String)]
    if let listing = askAgent(AgentRequest(command: "list")), listing.ok, let entries = listing.items {
        subjects = entries.compactMap { entry in
            guard let reply = askAgent(AgentRequest(command: "get", name: entry.name)),
                  reply.ok, let secret = reply.value, !secret.isEmpty else { return nil }
            return (entry.name, entry.kind, secret)
        }
    } else {
        subjects = openLocally()
            .filter { !$0.secret.isEmpty }
            .map { ($0.displayName, $0.kind.rawValue, $0.secret) }
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var results: [(name: String, verdict: KeyProbe.Verdict)] = []

    for subject in subjects {
        group.enter()
        Task {
            let verdict = await KeyProbe.check(
                name: subject.name, kind: subject.kind, secret: subject.secret
            )
            lock.lock()
            results.append((subject.name, verdict))
            lock.unlock()
            group.leave()
        }
    }
    group.wait()

    let width = results.map(\.name.count).max() ?? 0
    for row in results.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
        let padding = String(repeating: " ", count: max(0, width - row.name.count))
        print("\(row.name)\(padding)  \(row.verdict.label)")
    }
    let broken = results.filter { $0.verdict == .invalid }
    print("")
    print(broken.isEmpty
        ? "沒有失效的金鑰。"
        : "有 \(broken.count) 把失效：\(broken.map(\.name).joined(separator: "、"))")

case "add":
    guard arguments.count > 1 else { fail("要給名稱") }
    let value = readValue()
    guard !value.isEmpty else { fail("值是空的，請用管線把值送進來") }
    guard let response = askAgent(AgentRequest(
        command: "add", name: arguments[1], value: value,
        kind: arguments.count > 2 ? arguments[2] : nil
    )) else { fail("Slate 沒有在執行，寫入需要 App 開著且已解鎖") }
    guard response.ok else { fail(response.error ?? "新增失敗") }
    print("已新增：\(response.value ?? arguments[1])")

case "set":
    guard arguments.count > 1 else { fail("要給名稱") }
    let value = readValue()
    guard !value.isEmpty else { fail("值是空的，請用管線把值送進來") }
    guard let response = askAgent(AgentRequest(command: "set", name: arguments[1], value: value)) else {
        fail("Slate 沒有在執行，寫入需要 App 開著且已解鎖")
    }
    guard response.ok else { fail(response.error ?? "更新失敗") }
    print("已更新：\(response.value ?? arguments[1])")

case "rename":
    guard arguments.count > 2 else { fail("要給舊名和新名") }
    guard let response = askAgent(AgentRequest(
        command: "rename", name: arguments[1], newName: arguments[2]
    )) else { fail("Slate 沒有在執行，寫入需要 App 開著且已解鎖") }
    guard response.ok else { fail(response.error ?? "改名失敗") }
    print("已改名：\(response.value ?? arguments[2])")

case "kind":
    guard arguments.count > 2 else { fail("要給名稱和型別") }
    guard let response = askAgent(AgentRequest(
        command: "kind", name: arguments[1], kind: arguments[2]
    )) else { fail("Slate 沒有在執行，寫入需要 App 開著且已解鎖") }
    guard response.ok else { fail(response.error ?? "改型別失敗") }
    print("已改為：\(response.value ?? arguments[2])")

case "id":
    guard arguments.count > 2 else { fail("要給名稱和 ID") }
    guard let response = askAgent(AgentRequest(
        command: "id", name: arguments[1], account: arguments[2]
    )) else { fail("Slate 沒有在執行，寫入需要 App 開著且已解鎖") }
    guard response.ok else { fail(response.error ?? "設定失敗") }
    print("已設定 ID：\(response.value ?? arguments[2])")

case "-h", "--help", "help":
    print(usage)

default:
    fail("不認識的指令：\(command)\n\n" + usage)
}
