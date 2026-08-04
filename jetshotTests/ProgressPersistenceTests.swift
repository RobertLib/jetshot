//
//  ProgressPersistenceTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Progress is the only state in the game that outlives a launch, and the rules that
/// guard it are all "keep the better of the two": a replay must never lower a score, a
/// star rating or an unlocked arsenal. Each of those has a matching `max()` on the iCloud
/// merge side, and a disagreement between the two used to make values flip-flop between
/// devices on every sync.
///
/// `LevelManager` itself was already well covered; what was not covered at all is the
/// scene that *calls* it. `LevelCompleteScene.didMove(to:)` is the only place a finished
/// run is written, so until it is presented nothing here is exercised end to end.
///
/// Every test runs inside `withCleanProgress`, which wipes the store and restores it
/// afterwards, so the suite is neither order-dependent nor destructive to a developer's
/// simulator progress.
@MainActor
final class ProgressPersistenceTests: XCTestCase {

    // MARK: - Unlocking

    func testAFreshInstallHasOnlyTheFirstLevel() {
        withCleanProgress {
            XCTAssertTrue(LevelManager.shared.isLevelUnlocked(1), "level 1 must always be playable")
            XCTAssertFalse(
                LevelManager.shared.isLevelUnlocked(2),
                "level 2 was unlocked before level 1 was cleared"
            )
        }
    }

    func testFinishingALevelUnlocksTheNextOneOnly() {
        withCleanProgress {
            LevelManager.shared.completeLevel(3, score: 1000, stars: 2, bulletCount: 2, sideMissileCount: 1)

            XCTAssertTrue(LevelManager.shared.isLevelCompleted(3))
            XCTAssertTrue(LevelManager.shared.isLevelUnlocked(4), "clearing level 3 did not unlock level 4")
            XCTAssertFalse(LevelManager.shared.isLevelUnlocked(5), "clearing level 3 unlocked level 5 as well")
        }
    }

    // MARK: - "Keep the better run" rules

    func testAWorseReplayNeverLowersTheStoredScore() {
        withCleanProgress {
            LevelManager.shared.completeLevel(2, score: 5000)
            LevelManager.shared.completeLevel(2, score: 100)

            XCTAssertEqual(
                LevelManager.shared.getLevelScore(level: 2), 5000,
                "a worse replay overwrote the personal best"
            )
        }
    }

    func testAWorseReplayNeverLowersTheStarRating() {
        withCleanProgress {
            LevelManager.shared.completeLevel(2, score: 500, stars: 3)
            LevelManager.shared.completeLevel(2, score: 500, stars: 1)

            XCTAssertEqual(
                LevelManager.shared.getLevelStars(level: 2), 3,
                "a worse replay took away earned stars"
            )
        }
    }

    /// The two arsenal slots are kept independently, so a run that improved only the side
    /// missiles must not roll the bullet count back.
    func testEachWeaponSlotKeepsItsOwnBest() {
        withCleanProgress {
            LevelManager.shared.completeLevel(2, score: 100, bulletCount: 4, sideMissileCount: 0)
            LevelManager.shared.completeLevel(2, score: 100, bulletCount: 1, sideMissileCount: 3)

            let weapons = LevelManager.shared.getLevelWeapons(level: 2)
            XCTAssertEqual(weapons.bulletCount, 4, "the better bullet count was lost")
            XCTAssertEqual(weapons.sideMissileCount, 3, "the better missile count was lost")
        }
    }

    /// `completeLevel` guards on `levels.contains(level)`, so a replay must not push the
    /// same level into the completed list twice — which would double it in every count the
    /// level select derives from that array.
    func testReplayingALevelDoesNotRecordItTwice() {
        withCleanProgress {
            LevelManager.shared.completeLevel(4, score: 100)
            LevelManager.shared.completeLevel(4, score: 200)

            let completed = storedCompletedLevels()
            XCTAssertEqual(
                completed.filter { $0 == 4 }.count, 1,
                "level 4 appears more than once in \(completed)"
            )
        }
    }

    func testTotalScoreAddsUpEveryLevelsBest() {
        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 1000)
            LevelManager.shared.completeLevel(2, score: 2500)
            LevelManager.shared.completeLevel(2, score: 10) // worse replay, must be ignored

            XCTAssertEqual(LevelManager.shared.getTotalScore(), 3500)
        }
    }

    func testResetProgressClearsEverything() {
        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 1000, stars: 3, bulletCount: 4, sideMissileCount: 2)
            LevelManager.shared.hasSeenOpeningStory = true

            LevelManager.shared.resetProgress()

            XCTAssertFalse(LevelManager.shared.isLevelCompleted(1))
            XCTAssertEqual(LevelManager.shared.getTotalScore(), 0)
            XCTAssertEqual(LevelManager.shared.getLevelStars(level: 1), 0)
            XCTAssertEqual(LevelManager.shared.getLevelWeapons(level: 1).bulletCount, 1)
            XCTAssertFalse(
                LevelManager.shared.hasSeenOpeningStory,
                "a full reset should replay the intro, like a fresh install"
            )
        }
    }

    // MARK: - LevelCompleteScene

    /// The scene is the only writer of a finished run in the whole app, and it was not
    /// covered by a single test.
    func testLevelCompleteScenePersistsTheRun() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            harness.present(LevelCompleteScene(
                size: harness.view.bounds.size,
                level: 6,
                score: 4200,
                coinsCollected: 10,
                totalCoins: 10,
                bulletCount: 3,
                sideMissileCount: 2
            ))

            XCTAssertTrue(LevelManager.shared.isLevelCompleted(6), "finishing level 6 was never recorded")
            XCTAssertEqual(LevelManager.shared.getLevelScore(level: 6), 4200)
            XCTAssertTrue(LevelManager.shared.isLevelUnlocked(7), "level 7 stayed locked after clearing level 6")

            let weapons = LevelManager.shared.getLevelWeapons(level: 6)
            XCTAssertEqual(weapons.bulletCount, 3)
            XCTAssertEqual(weapons.sideMissileCount, 2)
        }
    }

    /// The rating the scene stores has to be the one `StarRating` computes from the coin
    /// rate — the scene used to derive it twice, and this pins the persisted value to the
    /// pure rule that `StarRatingTests` covers.
    func testLevelCompleteScenePersistsTheRatingItsCoinRateEarns() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let cases: [(collected: Int, total: Int, expected: Int)] = [
            (10, 10, 3),   // perfect
            (7, 10, 3),    // exactly the three-star threshold
            (5, 10, 2),    // mid
            (1, 10, 1),    // scraped through
            (0, 0, 3)      // a level with no coins rates three
        ]

        withCleanProgress {
            for (index, testCase) in cases.enumerated() {
                // A distinct level per case, so the "keep the best rating" rule cannot
                // mask a wrong value with a previous case's higher one.
                let level = 10 + index

                harness.present(LevelCompleteScene(
                    size: harness.view.bounds.size,
                    level: level,
                    score: 100,
                    coinsCollected: testCase.collected,
                    totalCoins: testCase.total,
                    bulletCount: 1,
                    sideMissileCount: 0
                ))

                XCTAssertEqual(
                    LevelManager.shared.getLevelStars(level: level),
                    testCase.expected,
                    "\(testCase.collected)/\(testCase.total) coins persisted "
                    + "\(LevelManager.shared.getLevelStars(level: level)) stars, expected \(testCase.expected)"
                )
                XCTAssertEqual(
                    StarRating.stars(coinsCollected: testCase.collected, totalCoins: testCase.total),
                    testCase.expected,
                    "the pure rule and the scene disagree for \(testCase.collected)/\(testCase.total)"
                )
            }
        }
    }

    // MARK: - GameOverScene

    /// Dying must not bank the level. `GameOverScene` had no coverage at all, and it sits
    /// one method away from the code that writes progress.
    func testGameOverSceneDoesNotBankTheLevel() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            harness.present(GameOverScene(size: harness.view.bounds.size, score: 9999, level: 8))

            XCTAssertFalse(LevelManager.shared.isLevelCompleted(8), "losing level 8 marked it completed")
            XCTAssertFalse(LevelManager.shared.isLevelUnlocked(9), "losing level 8 unlocked level 9")
            XCTAssertEqual(LevelManager.shared.getTotalScore(), 0, "a losing run banked its score")
        }
    }
}
