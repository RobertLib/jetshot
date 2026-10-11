//
//  ProgressEpochTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// "Reset progress" has to stay reset on every device.
///
/// The iCloud merge only ever adds — a union of completed levels, the best of every
/// score — which is right for two devices playing one save and wrong for a reset: the
/// other device still held the old progress, pushed it back up on its next merge, and
/// the reset came undone everywhere. Each reset now opens a new epoch, and two stores
/// are only unioned while they share one; across epochs the newer store wins whole.
///
/// The decision itself is the pure `CloudStorageManager.reconcile(local:cloud:)`, covered
/// first. The rest goes through the real stores inside `withCleanProgress`.
@MainActor
final class ProgressEpochTests: XCTestCase {

    private typealias Store = CloudStorageManager
    private typealias Keys = CloudStorageManager.Keys

    // MARK: - Reconcile

    func testStoresInTheSameEpochAreUnioned() {
        let local = Store.Snapshot(values: [
            Keys.completedLevels: [1, 2],
            Keys.levelScores: ["1": 500, "2": 900],
            Keys.levelMedals: ["1": 0b001],
            Keys.levelWeapons: ["2": ["bulletCount": 4, "sideMissileCount": 0]]
        ], epoch: 2)
        let cloud = Store.Snapshot(values: [
            Keys.completedLevels: [2, 3],
            Keys.levelScores: ["2": 1200],
            Keys.levelMedals: ["1": 0b010],
            Keys.levelWeapons: ["2": ["bulletCount": 1, "sideMissileCount": 2]]
        ], epoch: 2)

        let merged = Store.reconcile(local: local, cloud: cloud)

        XCTAssertEqual(merged.epoch, 2)
        XCTAssertEqual(merged.values[Keys.completedLevels] as? [Int], [1, 2, 3])
        XCTAssertEqual(merged.values[Keys.levelScores] as? [String: Int], ["1": 500, "2": 1200])
        XCTAssertEqual(merged.values[Keys.levelMedals] as? [String: Int], ["1": 0b011])
        XCTAssertEqual(
            merged.values[Keys.levelWeapons] as? [String: [String: Int]],
            ["2": ["bulletCount": 4, "sideMissileCount": 2]]
        )
        XCTAssertNil(merged.values[Keys.levelStars], "a key neither side holds must stay absent")
    }

    /// The case that used to undo a reset: this device still holds the old save, and
    /// another device has reset since.
    func testANewerResetInTheCloudWinsOverOlderLocalProgress() {
        let local = Store.Snapshot(values: [
            Keys.completedLevels: Array(1...20),
            Keys.levelScores: ["1": 9000],
            Keys.endlessRecords: ["bestScore": 80000, "bestRound": 31]
        ], epoch: 0)
        let cloud = Store.Snapshot(values: [Keys.completedLevels: [1]], epoch: 1)

        let merged = Store.reconcile(local: local, cloud: cloud)

        XCTAssertEqual(merged.epoch, 1)
        XCTAssertEqual(merged.values[Keys.completedLevels] as? [Int], [1], "the old save was merged back into the reset one")
        XCTAssertNil(merged.values[Keys.levelScores], "a score from before the reset survived it")
        XCTAssertNil(merged.values[Keys.endlessRecords], "an endless record from before the reset survived it")
    }

    func testANewerResetOnThisDeviceWinsOverOlderCloudProgress() {
        let local = Store.Snapshot(values: [:], epoch: 3)
        let cloud = Store.Snapshot(values: [
            Keys.completedLevels: [1, 2, 3],
            Keys.levelStars: ["1": 3]
        ], epoch: 2)

        let merged = Store.reconcile(local: local, cloud: cloud)

        XCTAssertEqual(merged.epoch, 3)
        XCTAssertTrue(merged.values.isEmpty, "the cloud's pre-reset save leaked into this device's reset")
    }

    // MARK: - Through the real stores

    func testResettingOpensANewEpochInBothStores() {
        withCleanProgress {
            let before = CloudStorageManager.shared.currentEpoch

            LevelManager.shared.resetProgress()

            XCTAssertEqual(CloudStorageManager.shared.currentEpoch, before + 1)
            XCTAssertEqual(
                NSUbiquitousKeyValueStore.default.longLong(forKey: Keys.progressEpoch), Int64(before + 1),
                "the reset never told iCloud, so other devices would merge their old save back"
            )
        }
    }

    /// A device that has not yet merged another device's reset finishes a level. Its
    /// save must land on the reset, not carry its whole old collection up with it.
    func testAStaleDeviceAdoptsAResetBeforeSavingOverIt() {
        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 100)
            LevelManager.shared.completeLevel(2, score: 200)

            // Another device resets: iCloud is cleared and moves to the next epoch.
            let cloud = NSUbiquitousKeyValueStore.default
            for key in Keys.progress {
                cloud.removeObject(forKey: key)
            }
            let resetEpoch = CloudStorageManager.shared.currentEpoch + 1
            cloud.set(Int64(resetEpoch), forKey: Keys.progressEpoch)

            LevelManager.shared.completeLevel(5, score: 300)

            XCTAssertEqual(storedCompletedLevels(), [5], "the stale save survived the reset")
            XCTAssertNil(LevelManager.shared.getLevelScore(level: 1), "a pre-reset score survived the reset")
            XCTAssertEqual(
                cloud.array(forKey: Keys.completedLevels) as? [Int], [5],
                "the stale device pushed its old save back up to iCloud"
            )
            XCTAssertEqual(CloudStorageManager.shared.currentEpoch, resetEpoch)
        }
    }

    /// Within one epoch nothing changes: a save on top of another device's progress
    /// still adds to it.
    func testASaveInTheSameEpochStillAddsToTheCloudsProgress() {
        withCleanProgress {
            let cloud = NSUbiquitousKeyValueStore.default
            LevelManager.shared.completeLevel(1, score: 100)

            LevelManager.shared.completeLevel(2, score: 200)

            XCTAssertEqual(storedCompletedLevels(), [1, 2])
            XCTAssertEqual(cloud.array(forKey: Keys.completedLevels) as? [Int], [1, 2])
            XCTAssertEqual(
                Int(cloud.longLong(forKey: Keys.progressEpoch)), CloudStorageManager.shared.currentEpoch,
                "an ordinary save moved the two stores into different epochs"
            )
        }
    }
}
