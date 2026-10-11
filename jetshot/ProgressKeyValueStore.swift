import Foundation

/// The property-list operations shared by local defaults and iCloud progress.
nonisolated protocol ProgressKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension UserDefaults: ProgressKeyValueStore {}
extension NSUbiquitousKeyValueStore: ProgressKeyValueStore {}

#if DEBUG
/// XCTest uses two independent memory stores, never the player's defaults or iCloud.
/// Reads can bypass CloudStorageManager's queue, so the store protects its own values.
nonisolated final class MemoryProgressStore: ProgressKeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: Any?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func removeObject(forKey key: String) {
        set(nil, forKey: key)
    }

    @discardableResult func synchronize() -> Bool { true }

    func snapshot() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func restore(_ snapshot: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        values = snapshot
    }
}
#endif
