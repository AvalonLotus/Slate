import AppKit
import CryptoKit
import Foundation

/// Slate ships outside the App Store, so it asks a small manifest on the site
/// whether a newer build exists. Nothing is downloaded or installed here: the
/// answer is a version and a link, and the user decides.
struct UpdateManifest: Codable, Equatable {
    var version: String
    /// The disk image, for someone installing Slate for the first time.
    var url: String
    /// A zipped .app plus its digest, which is what the in-app update uses:
    /// no volume to mount, and the bytes are checked before anything is run.
    var zip: String?
    var sha256: String?
    var notes: String?
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, manifest: UpdateManifest)
        case installing
        case failed(String)
    }

    static let feed = URL(string: "https://avalonlotus.com/slate/latest.json")!

    @Published private(set) var state: State = .idle

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    func check() {
        guard state != .checking else { return }
        state = .checking

        var request = URLRequest(url: Self.feed)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8

        Task { [currentVersion] in
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    state = .failed("無法連線至更新伺服器")
                    return
                }
                let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
                guard Self.isNewer(manifest.version, than: currentVersion) else {
                    state = .upToDate
                    return
                }
                state = .available(version: manifest.version, manifest: manifest)
            } catch {
                state = .failed("無法連線至更新伺服器")
            }
        }
    }

    /// Downloads the zipped app, checks the digest the manifest promised, and
    /// swaps it in. A mismatch stops before anything is written, so a truncated
    /// or tampered download never reaches /Applications.
    func install() {
        guard case .available(_, let manifest) = state,
              let zip = manifest.zip.flatMap(URL.init(string:)),
              let expected = manifest.sha256?.lowercased()
        else {
            state = .failed("這個版本沒有提供自動更新")
            return
        }
        state = .installing

        Task {
            do {
                let (file, response) = try await URLSession.shared.download(from: zip)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateError.message("下載失敗")
                }
                let digest = try Self.sha256(of: file)
                guard digest == expected else {
                    throw UpdateError.message("檔案校驗不符，已中止")
                }
                let replacement = try Self.unpack(file)
                try Self.swapIn(replacement)
                Self.relaunch()
            } catch let UpdateError.message(text) {
                state = .failed(text)
            } catch {
                state = .failed("更新失敗")
            }
        }
    }

    enum UpdateError: Error {
        case message(String)
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// ditto, not unzip: it is the only extractor that keeps the signature and
    /// resource forks of a signed bundle intact.
    private static func unpack(_ archive: URL) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("slate-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.message("更新檔內容不正確")
        }
        // A bundle whose seal is broken is not worth installing.
        try run("/usr/bin/codesign", ["--verify", "--deep", app.path])
        return app
    }

    private static func swapIn(_ replacement: URL) throws {
        let destination = Bundle.main.bundleURL
        let manager = FileManager.default
        let backup = destination.appendingPathExtension("previous")

        try? manager.removeItem(at: backup)
        if manager.fileExists(atPath: destination.path) {
            try manager.moveItem(at: destination, to: backup)
        }
        do {
            try run("/usr/bin/ditto", [replacement.path, destination.path])
        } catch {
            // Put the old one back rather than leave nothing installed.
            try? manager.removeItem(at: destination)
            try? manager.moveItem(at: backup, to: destination)
            throw UpdateError.message("無法寫入應用程式資料夾")
        }
        try? manager.removeItem(at: backup)
    }

    private static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"$0\"", path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw UpdateError.message("更新失敗（\(URL(fileURLWithPath: tool).lastPathComponent)）")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Compares dotted versions numerically, so 1.10 sorts above 1.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
