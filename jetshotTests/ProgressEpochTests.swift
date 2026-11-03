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
/// are only unioned while they share one; across epochs the newer store wins whole —
/// unless this device's progress is known to have been made after the newer reset.
///
/// The decision itself is the pure `CloudStorageManager.reconcile(local:cloud:)`, covered
/// first. The rest goes through the production manager with isolated memory stores;
/// `CloudSyncTests` drives the merge itself.
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
    /// another device has reset since. With no start time — every 1.0.8 install — the
    /// local progress is of unknown age, and unknown has to count as older than the reset.
    func testANewerResetInTheCloudWinsOverLocalProgressOfUnknownAge() {
        let local = Store.Snapshot(values: [
            Keys.completedLevels: Array(1...20),
            Keys.levelScores: ["1": 9000],
            Keys.endlessRecords: ["bestScore": 80000, "bestRound": 31]
        ], epoch: 0)
        let cloud = Store.Snapshot(values: [Keys.completedLevels: [1]], epoch: 1, resetAt: 5_000)

        let merged = Store.reconcile(local: local, cloud: cloud)

        XCTAssertEqual(merged.epoch, 1)
        XCTAssertEqual(merged.values[Keys.completedLevels] as? [Int], [1], "the old save was merged back into the reset one")
        XCTAssertNil(merged.values[Keys.levelScores], "a score from before the reset survived it")
        XCTAssertNil(merged.values[Keys.endlessRecords], "an endless record from before the reset survived it")
        XCTAssertEqual(merged.resetAt, 5_000)
        XCTAssertEqual(merged.startedAt, 5_000, "adopted progress was all made after the cloud's reset")
    }

    /// A start time is only an exemption when it is *after* the reset; and a reset made
    /// by 1.0.8 carries no time to compare it with.
    func testProgressStartedBeforeTheResetOrAgainstAnUndatedResetStillLoses() {
        let local = Store.Snapshot(values: [Keys.completedLevels: [1, 2, 3]], epoch: 0, startedAt: 4_000)
        let cases: [(label: String, cloud: Store.Snapshot)] = [
            ("started before the reset", Store.Snapshot(values: [:], epoch: 1, resetAt: 5_000)),
            ("reset made by 1.0.8", Store.Snapshot(values: [:], epoch: 1))
        ]

        for (label, cloud) in cases {
            let merged = Store.reconcile(local: local, cloud: cloud)

            XCTAssertEqual(merged.epoch, 1, label)
            XCTAssertTrue(merged.values.isEmpty, "\(label): pre-reset progress survived the reset")
        }
    }

    /// The new iPad: the account was reset long ago, this device was played offline
    /// since, and it is behind on the epoch only because it had not synced yet.
    func testADeviceThatStartedAfterTheCloudsResetIsUnionedIntoIt() {
        let local = Store.Snapshot(values: [
            Keys.completedLevels: Array(1...20),
            Keys.levelScores: ["1": 900, "20": 4000]
        ], epoch: 0, startedAt: 9_000)
        let cloud = Store.Snapshot(values: [
            Keys.completedLevels: [1, 2],
            Keys.levelScores: ["1": 1500]
        ], epoch: 3, resetAt: 5_000)

        let merged = Store.reconcile(local: local, cloud: cloud)

        XCTAssertEqual(merged.epoch, 3, "the union has to move this device onto the cloud's epoch")
        XCTAssertEqual(merged.resetAt, 5_000)
        XCTAssertEqual(merged.values[Keys.completedLevels] as? [Int], Array(1...20), "post-reset progress was wiped")
        XCTAssertEqual(merged.values[Keys.levelScores] as? [String: Int], ["1": 1500, "20": 4000])
        XCTAssertEqual(merged.startedAt, 5_000, "the cloud's half dates from its reset, so the union does too")
    }

    /// The start time has to stay a lower bound on *all* of a device's progress.
    func testASameEpochUnionDatesTheResultFromTheEarlierOfBothSides() {
        let local = Store.Snapshot(values: [Keys.completedLevels: [4]], epoch: 2, resetAt: 5_000, startedAt: 9_000)

        let addedTo = Store.reconcile(local: local, cloud: Store.Snapshot(
            values: [Keys.completedLevels: [1]], epoch: 2, resetAt: 5_000))
        XCTAssertEqual(addedTo.startedAt, 5_000, "remote progress came in, but the start time stayed later than it")

        let unchanged = Store.reconcile(local: local, cloud: Store.Snapshot(
            values: [Keys.completedLevels: [4]], epoch: 2, resetAt: 5_000))
        XCTAssertEqual(unchanged.startedAt, 9_000, "nothing came in, yet the start time moved")

        let epochZero = Store.reconcile(
            local: Store.Snapshot(values: [Keys.completedLevels: [4]], epoch: 0, startedAt: 9_000),
            cloud: Store.Snapshot(values: [Keys.completedLevels: [1]], epoch: 0))
        XCTAssertNil(epochZero.startedAt, "epoch 0 has no reset time, so progress from it is of unknown age")
    }

    /// iCloud resolves conflicts per key, so a device that had not seen a reset can land
    /// its old collection after it. The epoch tag gives such a write away.
    func testACloudKeyTaggedWithAnOlderEpochReadsAsAbsent() {
        let values: [String: Any] = [
            Keys.completedLevels: [1, 2, 3],
            Keys.levelScores: ["1": 900],
            Keys.levelStars: ["1": 3]
        ]
        let tags = [Keys.completedLevels: 1, Keys.levelScores: 2]

        let current = Store.currentCloudValues(values, tags: tags, epoch: 2)

        XCTAssertNil(current[Keys.completedLevels], "a write made under an older epoch was read as current")
        XCTAssertEqual(current[Keys.levelScores] as? [String: Int], ["1": 900])
        XCTAssertEqual(current[Keys.levelStars] as? [String: Int], ["1": 3], "an untagged 1.0.8 write was rejected")
    }

    /// Another Apple ID's epochs are not this device's timeline: nothing is wiped, and a
    /// higher local epoch is not pushed into the new account.
    func testAnAccountChangeUnionsIntoTheNewAccountAndAdoptsItsEpoch() {
        let local = Store.Snapshot(values: [
            Keys.completedLevels: [1, 2, 3],
            Keys.levelScores: ["1": 100]
        ], epoch: 2, resetAt: 5_000, startedAt: 9_000)
        let cloud = Store.Snapshot(values: [
            Keys.completedLevels: [7],
            Keys.levelScores: ["7": 700]
        ], epoch: 0)

        let merged = Store.reconcileAfterAccountChange(local: local, cloud: cloud)

        XCTAssertEqual(merged.epoch, 0, "the previous account's epoch was pushed into the new one")
        XCTAssertNil(merged.resetAt)
        XCTAssertEqual(merged.values[Keys.completedLevels] as? [Int], [1, 2, 3, 7])
        XCTAssertEqual(merged.values[Keys.levelScores] as? [String: Int], ["1": 100, "7": 700])
        XCTAssertNil(merged.startedAt, "two accounts' histories mixed, so the start time is unknown")
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
