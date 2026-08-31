import Darwin
import Foundation

// Wire format between the app and the `slate` command line tool. One JSON
// object per line, both directions.

struct AgentRequest: Codable {
    var command: String
    var name: String?
    var detail: String?
    var value: String?
    var kind: String?
    var newName: String?
    var account: String?
}

struct AgentResponse: Codable {
    var ok: Bool
    var error: String?
    var value: String?
    var username: String?
    var items: [Entry]?

    struct Entry: Codable {
        var name: String
        var username: String
        var kind: String
    }

    static func failure(_ message: String) -> AgentResponse {
        AgentResponse(ok: false, error: message)
    }
}

enum AgentProtocol {
    static var socketPath: String {
        Paths.supportDirectory.appendingPathComponent("agent.sock").path
    }

    /// Set by the app so the socket can reach the store on the main actor.
    /// Same idea for bulk import: the command line hands over a file path and
    /// the app does the work with the vault it already has open.
    nonisolated(unsafe) static var importHandler: ((String) -> String)?

    /// Removing an entry outright, for tidying up after an import.
    nonisolated(unsafe) static var deleteHandler: ((String) -> Bool)?

    /// Everything that writes: add, set, rename, kind, id. One handler, so
    /// the app decides in a single place what a command line may change.
    nonisolated(unsafe) static var mutateHandler: ((AgentRequest) -> AgentResponse)?

    static func handle(_ request: AgentRequest, snapshot: SecretSnapshot) -> AgentResponse {
        guard snapshot.isUnlocked else { return .failure("locked") }

        switch request.command {
        case "ping":
            return AgentResponse(ok: true)
        case "list":
            let entries = snapshot.all().map {
                AgentResponse.Entry(
                    name: $0.displayName,
                    username: $0.username,
                    kind: $0.kind.rawValue
                )
            }
            return AgentResponse(ok: true, items: entries)
        case "get":
            guard let name = request.name else { return .failure("missing name") }
            guard let item = snapshot.find(name) else { return .failure("not found: \(name)") }
            return AgentResponse(ok: true, value: item.secret, username: item.username)
        case "delete":
            guard let name = request.name else { return .failure("missing name") }
            guard let item = snapshot.find(name) else { return .failure("not found: \(name)") }
            guard let deleteHandler else { return .failure("delete unavailable") }
            return deleteHandler(item.displayName)
                ? AgentResponse(ok: true, value: item.displayName)
                : .failure("delete failed")
        case "add", "set", "rename", "kind", "id":
            guard let mutateHandler else { return .failure("write unavailable") }
            return mutateHandler(request)
        case "import":
            guard let path = request.detail else { return .failure("missing path") }
            guard let importHandler else { return .failure("import unavailable") }
            return AgentResponse(ok: true, value: importHandler(path))
        default:
            return .failure("unknown command: \(request.command)")
        }
    }
}

/// Unix domain socket in the app's own directory, mode 0600. Anything running
/// as another user cannot reach it; anything running as this user can, exactly
/// like ssh-agent.
final class AgentServer {
    private let queue = DispatchQueue(label: "com.avalonlotus.slate.agent")
    private var listener: DispatchSourceRead?
    private var descriptor: Int32 = -1

    func start() {
        queue.async { [weak self] in self?.openSocket() }
    }

    func stop() {
        queue.async { [weak self] in self?.closeSocket() }
    }

    private func openSocket() {
        closeSocket()
        try? Paths.ensureSupportDirectory()
        let path = AgentProtocol.socketPath
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), source, 104)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            return
        }
        chmod(path, 0o600)
        descriptor = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        listener = source
    }

    private func accept() {
        let client = Darwin.accept(descriptor, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let read = Darwin.read(client, &buffer, buffer.count)
        guard read > 0 else { return }

        let data = Data(buffer[0..<read])
        let request = (try? JSONDecoder().decode(AgentRequest.self, from: data))
            ?? AgentRequest(command: "unknown")
        let response = AgentProtocol.handle(request, snapshot: SecretSnapshot.shared)
        guard var payload = try? JSONEncoder().encode(response) else { return }
        payload.append(0x0A)
        payload.withUnsafeBytes { bytes in
            _ = Darwin.write(client, bytes.baseAddress, bytes.count)
        }
    }

    private func closeSocket() {
        listener?.cancel()
        listener = nil
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
        unlink(AgentProtocol.socketPath)
    }
}
