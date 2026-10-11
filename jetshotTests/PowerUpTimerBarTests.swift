//
//  PowerUpTimerBarTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The power-up countdown bars against the two things that used to make them lie: the
/// hit-stop clock, which slowed the expiries but not the bars, and a boss, which threw
/// the bars of still-running power-ups away or let new ones land on its health bar.
///
/// See `GameplayHarness` for how the scene is brought up.
@MainActor
final class PowerUpTimerBarTests: XCTestCase {

    private func timerLayer(_ harness: GameplayHarness) throws -> SKNode {
        return try XCTUnwrap(harness.node(named: "powerUpTimerLayer"), "no power-up bar layer in the HUD")
    }

    private func wait(_ harness: GameplayHarness, upTo timeout: TimeInterval,
                      until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            harness.spin(0.05)
        }
        return condition()
    }

    // MARK: - Clock

    /// The expiries run on `gameContentNode`, whose speed is the hit-stop scale; the bars
    /// have to run at the same rate or they empty before the power-up ends.
    func testTheBarsKeepTheHitStopsTime() throws {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugActivatePowerUp(.magnet)
        let layer = try timerLayer(harness)
        XCTAssertEqual(layer.children.count, 1, "the magnet raised no bar")

        // The Overdrive's opening beat is a hit-stop.
        harness.scene.debugTriggerOverdrive()
        XCTAssertLessThan(harness.gameContent.speed, 1, "no hit-stop ran, so this proves nothing")
        XCTAssertEqual(layer.speed, harness.gameContent.speed, accuracy: 1e-6,
                       "the bars kept running at full speed through the hit-stop")

        harness.spin(0.8)
        XCTAssertEqual(harness.gameContent.speed, 1, accuracy: 1e-6, "the hit-stop never ended")
        XCTAssertEqual(layer.speed, 1, accuracy: 1e-6, "the bars stayed slowed after the hit-stop")
    }

    /// Following the time scale must not cost the pause: the bars still freeze with it.
    func testAPauseDuringAHitStopStillFreezesTheBars() throws {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugActivatePowerUp(.magnet)
        let layer = try timerLayer(harness)
        harness.scene.debugTriggerOverdrive()

        let pause = try XCTUnwrap(harness.node(named: "pauseButton"))
        harness.touchDown(at: harness.scenePosition(of: pause))
        harness.spin(0.2)

        XCTAssertTrue(harness.gameContent.isPaused, "the pause never took, so this proves nothing")
        XCTAssertTrue(layer.isPaused, "the bars kept draining behind the pause menu")
    }

    // MARK: - Bosses

    /// A bar is hidden, not deleted, for the boss — from its warning, through its
    /// entrance, to its death — and comes back afterwards. A power-up picked up meanwhile
    /// gets a bar too, held back until the corner is free.
    func testBarsSitOutAnEndlessBossAndComeBackAfterIt() throws {
        let harness = GameplayHarness()
        harness.startPlayingWithControl(endless: true)
        defer { harness.teardown() }
        harness.scene.debugSetInvulnerable(true)

        // 12 s: outlasts the warning and the entrance with room to spare.
        harness.scene.debugActivatePowerUp(.scoreMultiplier)
        let layer = try timerLayer(harness)
        XCTAssertEqual(layer.children.count, 1)
        XCTAssertFalse(layer.isHidden)

        harness.scene.debugSetEndlessRound(5)
        harness.spin(0.4)
        XCTAssertTrue(layer.isHidden, "the bars stayed up over the boss warning")
        XCTAssertEqual(layer.children.count, 1, "the boss round threw a running power-up's bar away")

        // The entrance: the boss is on screen with its health bar, but not yet fightable.
        XCTAssertTrue(wait(harness, upTo: 4) { harness.scene.bossManager.getBoss() != nil },
                      "the boss never arrived")
        XCTAssertFalse(harness.scene.bossManager.isBossActive(), "missed the entrance, so this proves nothing")
        harness.spin(0.05)
        XCTAssertTrue(layer.isHidden, "the bars showed through the boss's entrance")

        harness.scene.debugActivatePowerUp(.magnet)
        XCTAssertEqual(layer.children.count, 2, "a power-up picked up during the boss got no bar")
        XCTAssertTrue(layer.isHidden)

        XCTAssertTrue(wait(harness, upTo: 4) { harness.scene.bossManager.isBossActive() },
                      "the boss never became fightable")
        XCTAssertTrue(layer.isHidden)

        let boss = try XCTUnwrap(harness.scene.bossManager.getBoss())
        _ = harness.scene.bossManager.bossTakeDamage(amount: boss.maxHealthPoints)
        XCTAssertFalse(harness.scene.bossManager.isBossActive(), "the boss survived, so this proves nothing")
        harness.spin(0.1)

        XCTAssertFalse(layer.isHidden, "the corner is free but the bars stayed hidden")
        XCTAssertEqual(layer.children.count, 2, "a bar was lost over the boss round")
    }
}
