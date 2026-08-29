//
//  EndlessRunTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Endless run end to end, in a real running `GameScene`.
///
/// `EndlessRulesTests` covers the arithmetic; this covers the part that can actually
/// strand a player. An endless run has no authored wave list and no completion condition,
/// so if the round advance or the queue top-up ever fails the result is not a crash or a
/// wrong number — it is a silent, permanently empty playfield with the player flying
/// around an empty screen forever, which no unit test over pure functions would notice.
///
/// See `GameplayHarness` for why these build their scene per test and why the intro is
/// unpaused from the outside.
@MainActor
final class EndlessRunTests: XCTestCase {

    /// Spins until the playfield has enemies on it, and reports whether it ever did.
    private func waitForEnemies(_ harness: GameplayHarness, timeout: TimeInterval = 8.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            harness.spin(0.2)
            if harness.scene.activeEnemyCount > 0 { return true }
        }
        return false
    }

    /// Plays a round the way a player does — shooting enemies down as they arrive — until
    /// the run moves on. Reports whether it did.
    ///
    /// Clearing the screen once is not enough and should not be: a round only ends when
    /// its whole wave has *spawned* and then been cleared, so a single sweep two seconds
    /// in just deletes the two enemies that have arrived so far while the other five are
    /// still queued. Killing continuously is the real condition, and it takes about as
    /// long as the round's spawn cadence — hence the generous timeout.
    private func playOutRound(_ harness: GameplayHarness, timeout: TimeInterval = 25.0) -> Bool {
        let startingRound = harness.scene.endlessRound
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            harness.clearEnemies()
            harness.spin(0.25)
            if harness.scene.endlessRound > startingRound { return true }
        }
        return false
    }

    func testAnEndlessRunStartsSpawningWithoutAnAuthoredLevel() {
        let harness = GameplayHarness()
        harness.startPlaying(suspendLevelProgression: false, endless: true)
        defer { harness.teardown() }

        XCTAssertTrue(harness.scene.isEndless)
        XCTAssertTrue(
            waitForEnemies(harness),
            "an endless run never spawned anything, so the player is stranded on an empty screen"
        )
    }

    func testClearingARoundAdvancesTheRunAndQueuesAnother() {
        let harness = GameplayHarness()
        harness.startPlaying(suspendLevelProgression: false, endless: true)
        defer { harness.teardown() }

        XCTAssertTrue(waitForEnemies(harness), "round one never spawned")

        XCTAssertTrue(playOutRound(harness), "clearing round one did not advance the run")
        XCTAssertTrue(
            waitForEnemies(harness),
            "the next round was never queued — `appendWaves` did not restart the spawner"
        )
    }

    func testTheRunKeepsGoingAcrossSeveralRounds() {
        // The top-up is a read-modify-write on a queue that has already drained, and its
        // `waveStartTime` repair only fires on the transition. Doing it once proves less
        // than doing it repeatedly.
        let harness = GameplayHarness()
        harness.startPlaying(suspendLevelProgression: false, endless: true)
        defer { harness.teardown() }

        XCTAssertTrue(waitForEnemies(harness), "round one never spawned")

        for round in 1...2 {
            XCTAssertTrue(playOutRound(harness), "the run stalled while clearing round \(round)")
            XCTAssertTrue(
                waitForEnemies(harness),
                "the run went quiet after clearing round \(round)"
            )
        }

        XCTAssertGreaterThanOrEqual(
            harness.scene.endlessRound, 3,
            "two cleared rounds did not advance the counter"
        )
    }

    func testACampaignLevelIsNotTreatedAsEndless() {
        // The flag gates the update loop's whole completion branch, so a campaign level
        // that came up endless would never spawn its boss and could never be finished.
        let harness = GameplayHarness()
        harness.startPlaying(level: 2)
        defer { harness.teardown() }

        XCTAssertFalse(harness.scene.isEndless)
        XCTAssertEqual(harness.scene.endlessRound, 0, "a campaign level is counting endless rounds")
    }
}
