import Foundation

/// A copy of the unlocked contents that background threads may read. The store
/// pushes into it; the agent socket reads from it. Cleared on lock.
final class SecretSnapshot: @unchecked Sendable {
    static let shared = SecretSnapshot()

    private let lock = NSLock()
    private var items: [KeyItem] = []

    var isUnlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !items.isEmpty || unlocked
    }

    private var unlocked = false

    func update(_ items: [KeyItem]) {
        lock.lock()
        self.items = items.filter { !$0.isDeleted }
        unlocked = true
        lock.unlock()
    }

    func clear() {
        lock.lock()
        items = []
        unlocked = false
        lock.unlock()
    }

    func all() -> [KeyItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    /// Exact name first, then a case-insensitive contains match on name,
    /// name or username.
    func find(_ needle: String) -> KeyItem? {
        let items = all()
        if let exact = items.first(where: { $0.name == needle }) { return exact }
        let lowered = needle.lowercased()
        return items.first {
            $0.name.lowercased() == lowered
                || $0.name.lowercased().contains(lowered)
                || $0.username.lowercased().contains(lowered)
        }
    }
}
