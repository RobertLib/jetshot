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
/// first. The rest goes through the production manager with isolated memory stores.
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

    private var cloud: MemoryProgressStore {
        CloudStorageManager.shared.testStores!.cloud
    }

    private func cloudEpoch() -> Int {
        (cloud.object(forKey: Keys.progressEpoch) as? NSNumber)?.intValue ?? 0
    }

    // MARK: - Through isolated stores

    func testResettingOpensANewEpochInBothStores() {
        withCleanProgress {
            let before = CloudStorageManager.shared.currentEpoch

            LevelManager.shared.resetProgress()

            XCTAssertEqual(CloudStorageManager.shared.currentEpoch, before + 1)
            XCTAssertEqual(
                cloudEpoch(), before + 1,
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
            for key in Keys.progress {
                cloud.removeObject(forKey: key)
            }
            let resetEpoch = CloudStorageManager.shared.currentEpoch + 1
            cloud.set(Int64(resetEpoch), forKey: Keys.progressEpoch)

            LevelManager.shared.completeLevel(5, score: 300)

            XCTAssertEqual(storedCompletedLevels(), [5], "the stale save survived the reset")
            XCTAssertNil(LevelManager.shared.getLevelScore(level: 1), "a pre-reset score survived the reset")
            XCTAssertEqual(
                cloud.object(forKey: Keys.completedLevels) as? [Int], [5],
                "the stale device pushed its old save back up to iCloud"
            )
            XCTAssertEqual(CloudStorageManager.shared.currentEpoch, resetEpoch)
        }
    }

    /// Within one epoch nothing changes: a save on top of another device's progress
    /// still adds to it.
    func testASaveInTheSameEpochStillAddsToTheCloudsProgress() {
        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 100)

            LevelManager.shared.completeLevel(2, score: 200)

            XCTAssertEqual(storedCompletedLevels(), [1, 2])
            XCTAssertEqual(cloud.object(forKey: Keys.completedLevels) as? [Int], [1, 2])
            XCTAssertEqual(
                cloudEpoch(), CloudStorageManager.shared.currentEpoch,
                "an ordinary save moved the two stores into different epochs"
            )
        }
    }

    /// Incoming progress is available, but its notification merge has not run yet.
    func testASavePreservesUnmergedRemoteProgressInTheSameEpoch() {
        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 100, stars: 1, bulletCount: 2, sideMissileCount: 0)
            LevelManager.shared.recordMedals([.untouched], level: 1)
            cloud.set([1, 2], forKey: Keys.completedLevels)
            cloud.set(["1": 1000, "2": 2000], forKey: Keys.levelScores)
            cloud.set(["1": 3, "2": 2], forKey: Keys.levelStars)
            cloud.set(["1": MedalSet.hunter.rawValue], forKey: Keys.levelMedals)
            cloud.set(["1": ["bulletCount": 4, "sideMissileCount": 2]], forKey: Keys.levelWeapons)

            LevelManager.shared.completeLevel(3, score: 300)
            LevelManager.shared.recordMedals([.chain], level: 1)

            XCTAssertEqual(storedCompletedLevels(), [1, 2, 3])
            XCTAssertEqual(cloud.object(forKey: Keys.completedLevels) as? [Int], [1, 2, 3])
            XCTAssertEqual(cloud.object(forKey: Keys.levelScores) as? [String: Int], ["1": 1000, "2": 2000, "3": 300])
            XCTAssertEqual(LevelManager.shared.getLevelStars(level: 1), 3)
            XCTAssertEqual(LevelManager.shared.getLevelMedals(level: 1), .all)
            XCTAssertEqual(LevelManager.shared.getLevelWeapons(level: 1).bulletCount, 4)
            XCTAssertEqual(LevelManager.shared.getLevelWeapons(level: 1).sideMissileCount, 2)
        }
    }

    func testSavingAnEndlessRecordKeepsTheUnmergedRemoteBest() {
        withCleanProgress {
            LevelManager.shared.recordEndlessRun(score: 100, round: 2)
            cloud.set(["bestScore": 1000, "bestRound": 10], forKey: Keys.endlessRecords)

            LevelManager.shared.recordEndlessRun(score: 300, round: 4)

            XCTAssertEqual(LevelManager.shared.getEndlessRecords().bestScore, 1000)
            XCTAssertEqual(LevelManager.shared.getEndlessRecords().bestRound, 10)
            XCTAssertEqual(cloud.object(forKey: Keys.endlessRecords) as? [String: Int], ["bestScore": 1000, "bestRound": 10])
        }
    }

    func testCleanProgressRestoresBothStoresTheirEpochsAndTheStoryPreference() {
        withCleanProgress {
            let storage = CloudStorageManager.shared
            let stores = storage.testStores!
            stores.local.set([1], forKey: Keys.completedLevels)
            stores.local.set(7, forKey: Keys.progressEpoch)
            stores.cloud.set([1, 2], forKey: Keys.completedLevels)
            stores.cloud.set(8, forKey: Keys.progressEpoch)
            LevelManager.shared.hasSeenOpeningStory = true

            withCleanProgress {
                XCTAssertTrue(storedCompletedLevels().isEmpty)
                XCTAssertNil(cloud.object(forKey: Keys.completedLevels))
                XCTAssertFalse(LevelManager.shared.hasSeenOpeningStory)
                LevelManager.shared.completeLevel(3, score: 300)
                LevelManager.shared.resetProgress()
            }

            XCTAssertEqual(storedCompletedLevels(), [1])
            XCTAssertEqual(storage.currentEpoch, 7)
            XCTAssertEqual(cloud.object(forKey: Keys.completedLevels) as? [Int], [1, 2])
            XCTAssertEqual(cloudEpoch(), 8)
            XCTAssertTrue(LevelManager.shared.hasSeenOpeningStory)
        }
    }
}
