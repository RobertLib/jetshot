//
//  CloudSyncTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// The iCloud merge as it actually runs: both stores, the epoch bookkeeping beside them,
/// and the change reason that triggered it.
///
/// Under XCTest the manager never registers for iCloud's change notification and never
/// runs its startup merge, so these drive both through `mergeForTesting(changeReason:)`
/// against the isolated memory stores. The pure decisions underneath are covered in
/// `ProgressEpochTests`.
@MainActor
final class CloudSyncTests: XCTestCase {

    private typealias Keys = CloudStorageManager.Keys

    private var storage: CloudStorageManager { CloudStorageManager.shared }
    private var local: MemoryProgressStore { storage.testStores!.local }
    private var cloud: MemoryProgressStore { storage.testStores!.cloud }

    private func number(_ object: Any?) -> NSNumber? { object as? NSNumber }

    private func cloudTag(_ key: String) -> Int? {
        number(cloud.object(forKey: Keys.epochTag(for: key)))?.intValue
    }

    /// Lets every `.progressDidChange` an earlier test queued on the main queue go out,
    /// so an inverted expectation only hears this test's.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    // MARK: - Resets and start times

    /// The scenario that cost a player their progress: the account was reset once, long
    /// ago; a new iPad is played offline; then its first sync lands with the reset's
    /// epoch. Everything the iPad did postdates the reset, so it must be kept.
    func testAnOfflineDeviceKeepsItsProgressWhenItsFirstSyncBringsAnOlderReset() {
        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 100)
            LevelManager.shared.completeLevel(2, score: 200)
            let startedAt = number(local.object(forKey: Keys.progressStartedAt))?.doubleValue
            XCTAssertNotNil(startedAt, "the first save on an empty device did not record when it started")

            // The initial sync replaces the cloud store with the server's copy: reset an
            // hour before this device was first played, with progress made since.
            let resetAt = (startedAt ?? 0) - 3600
            storage.restoreTestStores(local: local.snapshot(), cloud: [
                Keys.progressEpoch: Int64(1),
                Keys.progressResetAt: resetAt,
                Keys.epochTag(for: Keys.progressResetAt): Int64(1),
                Keys.completedLevels: [1, 3],
                Keys.epochTag(for: Keys.completedLevels): Int64(1)
            ])
            let announced = expectation(forNotification: .progressDidChange, object: nil)

            storage.mergeForTesting(changeReason: NSUbiquitousKeyValueStoreInitialSyncChange)

            wait(for: [announced], timeout: 2)
            XCTAssertEqual(storedCompletedLevels(), [1, 2, 3], "the offline progress was wiped by a reset it postdates")
            XCTAssertEqual(LevelManager.shared.getLevelScore(level: 2), 200)
            XCTAssertEqual(storage.currentEpoch, 1)
            XCTAssertEqual(cloud.object(forKey: Keys.completedLevels) as? [Int], [1, 2, 3])
            XCTAssertEqual(cloudTag(Keys.completedLevels), 1)
            XCTAssertEqual(cloud.object(forKey: Keys.levelScores) as? [String: Int], ["1": 100, "2": 200])
            XCTAssertEqual(cloudTag(Keys.levelScores), 1, "the union went up without the epoch it belongs to")
            XCTAssertEqual(number(local.object(forKey: Keys.progressResetAt))?.doubleValue, resetAt)
            XCTAssertEqual(
                number(local.object(forKey: Keys.progressStartedAt))?.doubleValue, resetAt,
                "the cloud's half of the union dates from its reset, so the start time has to as well"
            )
        }
    }

    /// The other side of the same rule: a device whose progress was made before the
    /// reset loses it, start time or not.
    func testADeviceWhoseProgressPredatesADatedResetStillAdoptsIt() {
        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 100)
            LevelManager.shared.completeLevel(2, score: 200)
            let startedAt = number(local.object(forKey: Keys.progressStartedAt))?.doubleValue ?? 0

            // Another device resets after this one started playing.
            for key in Keys.progress {
                cloud.removeObject(forKey: key)
                cloud.removeObject(forKey: Keys.epochTag(for: key))
            }
            cloud.set(Int64(1), forKey: Keys.progressEpoch)
            cloud.set(startedAt + 60, forKey: Keys.progressResetAt)
            cloud.set(Int64(1), forKey: Keys.epochTag(for: Keys.progressResetAt))

            storage.mergeForTesting(changeReason: NSUbiquitousKeyValueStoreServerChange)
            drainMainQueue()

            XCTAssertTrue(storedCompletedLevels().isEmpty, "progress from before the reset survived it")
            XCTAssertNil(LevelManager.shared.getLevelScore(level: 1))
            XCTAssertEqual(storage.currentEpoch, 1)
            XCTAssertNil(cloud.object(forKey: Keys.completedLevels), "the stale device pushed its old save back up")
        }
    }

    /// A reset made by 1.0.8 moves the epoch on but leaves the previous reset's time in
    /// iCloud. Read as the new epoch's, it would date that reset too early and let this
    /// device's progress — made between the two resets — union back into the newer one.
    func testAResetTimeLeftBehindByAnOlderResetDoesNotDateANewerOne() {
        withCleanProgress {
            let firstReset = Date().timeIntervalSince1970 - 7200
            storage.restoreTestStores(local: [
                Keys.progressEpoch: 1,
                Keys.progressResetAt: firstReset,
                Keys.progressStartedAt: firstReset + 60,
                Keys.completedLevels: [1, 2]
            ], cloud: [
                Keys.progressEpoch: Int64(2),
                Keys.progressResetAt: firstReset,
                Keys.epochTag(for: Keys.progressResetAt): Int64(1)
            ])

            storage.mergeForTesting(changeReason: NSUbiquitousKeyValueStoreServerChange)
            drainMainQueue()

            XCTAssertTrue(storedCompletedLevels().isEmpty, "progress of unknown age relative to the newer reset survived it")
            XCTAssertEqual(storage.currentEpoch, 2)
            XCTAssertNil(local.object(forKey: Keys.progressResetAt), "the older reset's time was adopted as the newer one's")
        }
    }

    func testAResetRecordsItsTimeAndClearsTheStartTimeAndTags() {
        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 100)
            XCTAssertEqual(cloudTag(Keys.completedLevels), storage.currentEpoch, "a save did not tag its key")
            let before = Date().timeIntervalSince1970

            LevelManager.shared.resetProgress()

            let resetAt = number(local.object(forKey: Keys.progressResetAt))?.doubleValue
            XCTAssertNotNil(resetAt)
            XCTAssertGreaterThanOrEqual(resetAt ?? 0, before)
            XCTAssertEqual(number(cloud.object(forKey: Keys.progressResetAt))?.doubleValue, resetAt)
            XCTAssertEqual(cloudTag(Keys.progressResetAt), storage.currentEpoch, "the reset time went up without its epoch")
            XCTAssertNil(local.object(forKey: Keys.progressStartedAt), "the start time outlived the progress it dated")
            for key in Keys.progress {
                XCTAssertNil(cloud.object(forKey: Keys.epochTag(for: key)), "\(key)'s epoch tag outlived the reset")
            }

            LevelManager.shared.completeLevel(1, score: 50)
            XCTAssertGreaterThanOrEqual(number(local.object(forKey: Keys.progressStartedAt))?.doubleValue ?? 0, resetAt ?? 0)
            XCTAssertEqual(cloudTag(Keys.completedLevels), storage.currentEpoch)
        }
    }

    // MARK: - Stale writes

    /// Device B had not received A's reset and saved anyway. iCloud keeps the newest
    /// write per key, so the server ends up with A's new epoch *and* B's old collection.
    /// B's tag gives it away: it is ignored, and the merge cleans it off the server.
    func testAStaleWriteThatLandedAfterAResetIsIgnoredAndCleanedUp() {
        withCleanProgress {
            // Device B, never told about the reset, finishes level 3 on its old save.
            LevelManager.shared.completeLevel(1, score: 100)
            LevelManager.shared.completeLevel(2, score: 200)
            LevelManager.shared.completeLevel(3, score: 300)
            var server = cloud.snapshot()
            XCTAssertEqual(server[Keys.epochTag(for: Keys.completedLevels)] as? Int64, 0)

            // A's reset won the epoch keys and a write of its own in the new epoch; B's
            // writes to the progress keys came later and won those. An untagged 1.0.8
            // write is mixed in for contrast.
            let resetAt = Date().timeIntervalSince1970 - 60
            server[Keys.progressEpoch] = Int64(1)
            server[Keys.progressResetAt] = resetAt
            server[Keys.epochTag(for: Keys.progressResetAt)] = Int64(1)
            server[Keys.levelMedals] = ["5": MedalSet.hunter.rawValue]
            server[Keys.epochTag(for: Keys.levelMedals)] = Int64(1)
            server[Keys.endlessRecords] = ["bestScore": 500, "bestRound": 3]
            server.removeValue(forKey: Keys.epochTag(for: Keys.endlessRecords))

            // Device A after its reset: epoch 1, one level played since.
            storage.restoreTestStores(local: [
                Keys.progressEpoch: 1,
                Keys.progressResetAt: resetAt,
                Keys.progressStartedAt: resetAt + 1,
                Keys.levelMedals: ["5": MedalSet.hunter.rawValue]
            ], cloud: server)

            storage.mergeForTesting(changeReason: NSUbiquitousKeyValueStoreServerChange)
            drainMainQueue()

            XCTAssertTrue(storedCompletedLevels().isEmpty, "a write made before the reset was merged into it")
            XCTAssertNil(LevelManager.shared.getLevelScore(level: 3))
            XCTAssertEqual(LevelManager.shared.getLevelMedals(level: 5), .hunter)
            XCTAssertEqual(LevelManager.shared.getEndlessRecords().bestScore, 500, "an untagged 1.0.8 write was rejected")
            for key in [Keys.completedLevels, Keys.levelScores, Keys.levelStars] {
                XCTAssertNil(cloud.object(forKey: key), "the stale \(key) was left on the server")
                XCTAssertNil(cloud.object(forKey: Keys.epochTag(for: key)), "the stale \(key)'s tag was left on the server")
            }
            XCTAssertEqual(storage.currentEpoch, 1)
        }
    }

    // MARK: - Account changes

    /// Signed into account B (epoch 2) and back into A (never reset). An ordinary merge
    /// let B's higher epoch win whole and overwrite A's progress on every device.
    func testAnAccountChangeUnionsIntoTheNewAccountWithoutPushingTheOldEpoch() {
        withCleanProgress {
            storage.restoreTestStores(local: [
                Keys.progressEpoch: 2,
                Keys.progressResetAt: 5_000.0,
                Keys.progressStartedAt: 9_000.0,
                Keys.completedLevels: [1, 2, 3],
                Keys.levelScores: ["1": 100]
            ], cloud: [
                Keys.completedLevels: [7],
                Keys.levelScores: ["7": 700]
            ])
            let announced = expectation(forNotification: .progressDidChange, object: nil)

            storage.mergeForTesting(changeReason: NSUbiquitousKeyValueStoreAccountChange)

            wait(for: [announced], timeout: 2)
            XCTAssertEqual(storedCompletedLevels(), [1, 2, 3, 7])
            XCTAssertEqual(LevelManager.shared.getLevelScore(level: 7), 700, "the new account's progress was lost")
            XCTAssertEqual(storage.currentEpoch, 0, "this device kept the previous account's epoch")
            XCTAssertEqual(number(cloud.object(forKey: Keys.progressEpoch))?.intValue ?? 0, 0,
                           "the previous account's epoch was pushed into the new one")
            XCTAssertEqual(cloud.object(forKey: Keys.completedLevels) as? [Int], [1, 2, 3, 7])
            XCTAssertEqual(cloud.object(forKey: Keys.levelScores) as? [String: Int], ["1": 100, "7": 700])
            XCTAssertNil(local.object(forKey: Keys.progressResetAt), "the previous account's reset time was kept")
            XCTAssertNil(local.object(forKey: Keys.progressStartedAt), "a mixed history kept a start time")
        }
    }

    // MARK: - Saves

    /// A save that improves nothing must not touch either store: rewriting the same
    /// value would be a newer write in iCloud's eyes, able to replace another device's.
    func testASaveThatChangesNothingWritesNothing() {
        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 500, stars: 3, bulletCount: 2, sideMissileCount: 1)
            LevelManager.shared.completeLevel(2, score: 500, stars: 2)
            LevelManager.shared.recordEndlessRun(score: 1000, round: 5)
            let cloudWrites = cloud.writeCount
            let localWrites = local.writeCount

            LevelManager.shared.completeLevel(1, score: 100, stars: 1, bulletCount: 1, sideMissileCount: 0)
            LevelManager.shared.completeLevel(2, score: 500, stars: 2)
            LevelManager.shared.recordEndlessRun(score: 10, round: 1)

            XCTAssertEqual(cloud.writeCount, cloudWrites, "an unchanged save was rewritten to iCloud")
            XCTAssertEqual(local.writeCount, localWrites, "an unchanged save was rewritten locally")
        }
    }

    /// The notification is for merges. A device's own save is not news to it.
    func testAnOwnSaveDoesNotAnnounceAProgressChange() {
        withCleanProgress {
            drainMainQueue()
            let announced = expectation(forNotification: .progressDidChange, object: nil)
            announced.isInverted = true

            LevelManager.shared.completeLevel(1, score: 100)
            storage.mergeForTesting(changeReason: NSUbiquitousKeyValueStoreServerChange)

            wait(for: [announced], timeout: 0.3)
        }
    }
}
