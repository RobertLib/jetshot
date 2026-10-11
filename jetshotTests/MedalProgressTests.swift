//
//  MedalProgressTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Medals are progress, so they get the same "never take anything away" guarantees as
/// scores and stars — with a set union where those use a maximum. See
/// `LevelManager.recordMedals(_:level:)`.
@MainActor
final class MedalProgressTests: XCTestCase {

    func testAFreshLevelHoldsNoMedals() {
        withCleanProgress {
            XCTAssertEqual(LevelManager.shared.getLevelMedals(level: 4), [])
            XCTAssertEqual(LevelManager.shared.getTotalMedalCount(), 0)
        }
    }

    func testMedalsAccumulateAcrossRuns() {
        withCleanProgress {
            LevelManager.shared.recordMedals([.untouched], level: 4)
            LevelManager.shared.recordMedals([.hunter], level: 4)

            XCTAssertEqual(
                LevelManager.shared.getLevelMedals(level: 4), [.untouched, .hunter],
                "a later run's medals replaced an earlier run's instead of joining them"
            )
        }
    }

    func testAWorseRunTakesNothingAway() {
        withCleanProgress {
            LevelManager.shared.recordMedals(.all, level: 7)
            LevelManager.shared.recordMedals([], level: 7)
            XCTAssertEqual(LevelManager.shared.getLevelMedals(level: 7), .all)
        }
    }

    func testOnlyNewMedalsAreReportedAsNew() {
        withCleanProgress {
            XCTAssertEqual(LevelManager.shared.recordMedals([.chain], level: 2), [.chain])
            XCTAssertEqual(LevelManager.shared.recordMedals([.chain, .hunter], level: 2), [.hunter],
                           "a medal the level already held was announced again")
            XCTAssertEqual(LevelManager.shared.recordMedals([.chain], level: 2), [])
        }
    }

    func testTheTallyCountsEveryLevel() {
        withCleanProgress {
            LevelManager.shared.recordMedals(.all, level: 1)
            LevelManager.shared.recordMedals([.chain], level: 9)
            XCTAssertEqual(LevelManager.shared.getTotalMedalCount(), 4)
        }
    }

    func testResettingProgressClearsMedals() {
        withCleanProgress {
            LevelManager.shared.recordMedals(.all, level: 3)
            LevelManager.shared.resetProgress()
            XCTAssertEqual(LevelManager.shared.getLevelMedals(level: 3), [])
        }
    }

    /// End to end: the results screen is where a finished run's medals are written.
    func testTheResultsScreenRecordsTheRunsMedals() {
        withCleanProgress {
            let harness = GameplayHarness()
            defer { harness.teardown() }

            harness.present(LevelCompleteScene(size: harness.view.bounds.size, level: 6, score: 900,
                                               medals: [.untouched, .hunter]))

            XCTAssertEqual(LevelManager.shared.getLevelMedals(level: 6), [.untouched, .hunter])
        }
    }

    // MARK: - In play

    /// A hit costs the untouched medal for the rest of the level.
    func testAHitLosesTheUntouchedMedal() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        XCTAssertTrue(harness.scene.medalsEarnedSoFar.contains(.untouched))
        harness.addEnemyBullet(at: harness.player.position)
        harness.spin(0.5)
        XCTAssertFalse(harness.scene.medalsEarnedSoFar.contains(.untouched), "a hit left the untouched medal standing")
    }

    /// A hit the Overdrive absorbed was still a hit.
    func testAnAbsorbedHitStillCostsTheUntouchedMedal() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugFillOverdrive()
        harness.addEnemyBullet(at: harness.player.position)
        harness.spin(0.5)

        XCTAssertTrue(harness.scene.isOverdriveActive, "the meter did not absorb the hit, so this proves nothing")
        XCTAssertFalse(harness.scene.medalsEarnedSoFar.contains(.untouched))
    }

    /// Enemies that get away count against the hunter medal; enemies shot down count
    /// for it.
    func testTheHunterMedalFollowsTheKillRate() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        var enemies: [Enemy] = []
        for i in 0..<4 {
            enemies.append(harness.addEnemy(.fast, at: CGPoint(x: 80 + CGFloat(i) * 70, y: 600)))
        }
        harness.player.position = CGPoint(x: 200, y: 200)
        for enemy in enemies.prefix(3) {
            harness.fireBullets(onto: enemy.position)
        }
        harness.spin(0.4)
        XCTAssertFalse(harness.scene.medalsEarnedSoFar.contains(.hunter), "three kills in four met an 85% bar")

        harness.fireBullets(onto: enemies[3].position)
        harness.spin(0.4)
        XCTAssertTrue(harness.scene.medalsEarnedSoFar.contains(.hunter), "a clean sweep did not earn the hunter medal")
    }
}
