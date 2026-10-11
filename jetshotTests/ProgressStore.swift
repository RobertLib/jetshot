import XCTest
@testable import jetshot

/// Runs against fresh memory stores, then restores both copies including their epochs
/// and local-only story preference. Refuse to reset anything if isolation is absent.
@MainActor
func withCleanProgress(_ body: () -> Void) {
    let storage = CloudStorageManager.shared
    guard let stores = storage.testStores else {
        return XCTFail("Progress tests require isolated stores; refusing to reset real progress")
    }
    let local = stores.local.snapshot()
    let cloud = stores.cloud.snapshot()
    storage.restoreTestStores(local: [:], cloud: [:])
    defer { storage.restoreTestStores(local: local, cloud: cloud) }
    body()
}

/// The raw completed-levels array, for assertions that care about duplicates rather than
/// membership — which `isLevelCompleted` cannot distinguish.
@MainActor
func storedCompletedLevels() -> [Int] {
    CloudStorageManager.shared.loadArray(forKey: CloudStorageManager.Keys.completedLevels) as? [Int] ?? []
}
