import Foundation

/// Reads the CSV that password managers export. Dashlane, 1Password and
/// Bitwarden all differ in column names but agree on the shape, so the header
/// decides how each row is read.

/// The importer has to guess the type, because the file it reads is just
/// names and values. Names win over values: an app password and a recovery
/// key look like random strings too, but neither is revoked upstream.
enum KindGuess {
    private static let passwordWords = [
        "password", "passphrase", "recovery", "file vault", "filevault",
        "帳號", "密碼", "登入", "信箱"
    ]
    private static let identifierWords = [
        "app id", "client id", "channel id", "page id", "user id", "account id",
        "project id", "tenant id", "編號", "識別"
    ]
    private static let tokenWords = [
        "token", "oauth", "授權", "權杖", "bearer", "refresh", "access"
    ]
    private static let keyWords = [
        "api", "key", "secret", "developer", "client"
    ]
    /// Prefixes that identify an access token no matter what the row is called.
    private static let tokenPrefixes = ["eaa", "ya29.", "bearer ", "ghu_", "ghs_"]

    static func kind(name: String, value: String) -> ItemKind {
        let haystack = name.lowercased()
        let compact = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = compact.lowercased()

        if passwordWords.contains(where: haystack.contains) { return .login }
        if identifierWords.contains(where: haystack.contains) { return .identifier }
        if tokenWords.contains(where: haystack.contains) { return .token }
        // A row can hold more than one line (an app id and its token, say),
        // so every line gets checked, not just the first.
        let lines = head.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if lines.contains(where: { line in tokenPrefixes.contains(where: line.hasPrefix) }) {
            return .token
        }
        // A bare run of digits is an ID, not a credential.
        if compact.count <= 24, compact.allSatisfy(\.isNumber) { return .identifier }
        if keyWords.contains(where: haystack.contains) { return .apiKey }
        return compact.count >= 24 && !compact.contains(" ") ? .apiKey : .login
    }
}

/// The paste-friendly format: one entry per block, first line the name, the
/// rest the value, blocks separated by a blank line. Lines starting with #
/// are notes to the reader and ignored.
enum TextImporter {
    static func read(_ url: URL) throws -> CSVImporter.Result {
        let text = try String(contentsOf: url, encoding: .utf8)
        var items: [KeyItem] = []

        for block in text.components(separatedBy: "\n\n") {
            let lines = block
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            guard lines.count >= 2 else { continue }

            let name = lines[0]
                .replacingOccurrences(of: "名稱:", with: "")
                .replacingOccurrences(of: "名稱：", with: "")
                .trimmingCharacters(in: .whitespaces)
            let value = lines.dropFirst().joined(separator: "\n")
            guard !name.isEmpty, !value.isEmpty else { continue }

            let kind = KindGuess.kind(name: name, value: value)
            var account = ""
            var secret = value
            if kind == .token {
                // Pasted token blocks usually lead with the app or page id.
                var rest = value.components(separatedBy: .newlines)
                if let first = rest.first?.trimmingCharacters(in: .whitespaces),
                   first.count <= 24, !first.isEmpty, first.allSatisfy(\.isNumber) {
                    account = first
                    rest.removeFirst()
                    secret = rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            items.append(KeyItem(kind: kind, name: name, username: account, secret: secret))
        }

        return CSVImporter.Result(items: items, skipped: 0)
    }
}

enum CSVImporter {
    struct Result {
        var items: [KeyItem]
        var skipped: Int
    }

    static func read(_ url: URL) throws -> Result {
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = parse(text)
        guard let header = rows.first, rows.count > 1 else {
            return Result(items: [], skipped: 0)
        }

        let columns = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func index(_ names: [String]) -> Int? {
            for name in names {
                if let found = columns.firstIndex(of: name) { return found }
            }
            return nil
        }

        let titleAt = index(["title", "name", "item name"])
        let usernameAt = index(["username", "login_username", "login", "email"])
        let passwordAt = index(["password", "login_password"])
        let noteAt = index(["note", "notes", "secure note"])

        var items: [KeyItem] = []
        var skipped = 0

        for row in rows.dropFirst() {
            func value(_ position: Int?) -> String {
                guard let position, position < row.count else { return "" }
                return row[position].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let title = value(titleAt)
            let username = value(usernameAt)
            let password = value(passwordAt)
            let note = value(noteAt)

            // A row with a password is an account; one with only a note is
            // where API keys live in most exports.
            if !password.isEmpty {
                items.append(KeyItem(
                    kind: .login,
                    name: title.isEmpty ? username : title,
                    username: username,
                    secret: password
                ))
            } else if !note.isEmpty {
                let name = title.isEmpty ? "未命名" : title
                items.append(KeyItem(
                    kind: KindGuess.kind(name: name, value: note),
                    name: name,
                    secret: note
                ))
            } else {
                skipped += 1
            }
        }

        return Result(items: items, skipped: skipped)
    }

    /// Minimal RFC 4180 reader: quoted fields may hold commas, newlines and
    /// doubled quotes, all of which show up in exported notes.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.startIndex

        while iterator < text.endIndex {
            let character = text[iterator]
            if quoted {
                if character == "\"" {
                    let next = text.index(after: iterator)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        iterator = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    quoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n", "\r\n", "\r":
                    row.append(field)
                    field = ""
                    if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                    row = []
                default:
                    field.append(character)
                }
            }
            iterator = text.index(after: iterator)
        }

        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
