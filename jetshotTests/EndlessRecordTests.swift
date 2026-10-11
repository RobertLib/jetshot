//
//  EndlessRecordTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// An endless run has no results screen, so its records used to be written in exactly
/// one place — game over. Every other way out lost the run: the pause menu's RETRY,
/// LEVELS and MENU, and the app being closed from the pause menu.
///
/// Recording more than once per run is safe by construction: the store keeps the best
/// score and the deepest round, and counts nothing.
@MainActor
final class EndlessRecordTests: XCTestCase {

    private func startEndlessRun(_ harness: GameplayHarness, scoring points: Int) -> Int {
        harness.startPlayingWithControl(endless: true)
        _ = harness.scene.addScore(points, chainsCombo: false)
        return harness.scene.currentScore
    }

    func testQuittingFromThePauseMenuRecordsTheRun() {
        withCleanProgress {
            let harness = GameplayHarness()
            defer { harness.teardown() }
            let score = startEndlessRun(harness, scoring: 1234)

            guard let pauseButton = harness.node(named: "pauseButton") else {
                return XCTFail("no pause button in the HUD")
            }
            harness.touchDown(at: harness.scenePosition(of: pauseButton))
            harness.spin(0.9)
            guard let menuButton = harness.node(named: "pauseMenuButton") else {
                return XCTFail("the pause menu has no MENU button")
            }
            harness.touchDown(at: harness.scenePosition(of: menuButton))
            harness.spin(0.4)

            let records = LevelManager.shared.getEndlessRecords()
            XCTAssertEqual(records.bestScore, score, "quitting to the menu threw the run's score away")
            XCTAssertGreaterThanOrEqual(records.bestRound, 1, "quitting to the menu threw the run's depth away")
        }
    }

    /// The app leaving the foreground is the last moment the game is sure to run: from
    /// the paused menu the player can swipe it away, and the system can end it.
    func testLeavingTheForegroundRecordsTheRun() {
        withCleanProgress {
            let harness = GameplayHarness()
            defer { harness.teardown() }
            let score = startEndlessRun(harness, scoring: 4321)

            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

            XCTAssertTrue(harness.gameContent.isPaused, "the run kept going behind the app switcher")
            XCTAssertEqual(LevelManager.shared.getEndlessRecords().bestScore, score)
        }
    }

    /// A run banked on the way into the background is banked again when it ends. The
    /// second write of the same result must change nothing, and a lower one must not
    /// lower anything.
    func testRecordingTheSameRunAgainChangesNothing() {
        withCleanProgress {
            let harness = GameplayHarness()
            defer { harness.teardown() }
            let score = startEndlessRun(harness, scoring: 500)

            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            let banked = LevelManager.shared.getEndlessRecords()
            XCTAssertEqual(banked.bestScore, score)

            LevelManager.shared.recordEndlessRun(score: score, round: banked.bestRound)
            LevelManager.shared.recordEndlessRun(score: 10, round: 1)

            let records = LevelManager.shared.getEndlessRecords()
            XCTAssertEqual(records.bestScore, banked.bestScore)
            XCTAssertEqual(records.bestRound, banked.bestRound)
        }
    }

    func testACampaignLevelRecordsNothing() {
        withCleanProgress {
            let harness = GameplayHarness()
            defer { harness.teardown() }
            harness.startPlayingWithControl()
            _ = harness.scene.addScore(999, chainsCombo: false)

            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

            let records = LevelManager.shared.getEndlessRecords()
            XCTAssertEqual(records.bestScore, 0)
            XCTAssertEqual(records.bestRound, 0)
        }
    }
}
