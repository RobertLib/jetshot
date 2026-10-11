//
//  BossSlowMotionTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// SLOW MO against a boss.
///
/// It used to do nothing there: the scene halved `speed` on enemies, asteroids and
/// rounds, but a boss is not an enemy in that sense — its cadence, flight and volleys
/// ran on at full pace — and its rounds fly on physics velocity, which `speed` does not
/// scale. `BossManager.setTimeScale(_:)` slows the whole fight, keeping every pattern's
/// shape by scaling velocity and action time together.
@MainActor
final class BossSlowMotionTests: XCTestCase {

    private func boss(in harness: GameplayHarness) -> Boss? {
        harness.gameContent.children.compactMap { $0 as? Boss }.first
    }

    /// The rounds `body` puts on the playfield, told apart from any already there.
    private func newRounds(_ harness: GameplayHarness, _ body: () -> Void) -> [SKNode] {
        let before = Set(harness.gameContent.children.filter { $0.name == "enemyBullet" }.map(ObjectIdentifier.init))
        body()
        return harness.gameContent.children.filter {
            $0.name == "enemyBullet" && !before.contains(ObjectIdentifier($0))
        }
    }

    func testSlowingTheFightHalvesItsRoundsAndRestoresThem() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlaying(level: 1)
        let manager = harness.scene.bossManager!
        manager.spawnBoss(level: 1) {}
        harness.spin(2.4)
        guard let boss = boss(in: harness), manager.isBossActive() else {
            return XCTFail("the boss never became fightable")
        }

        let fired = newRounds(harness) { _ = manager.performAttack(.straightShot) }
        guard let early = fired.first, let full = early.physicsBody?.velocity else {
            return XCTFail("a straight shot put no round on the playfield")
        }
        XCTAssertLessThan(full.dy, -100, "the round is not flying down the screen")

        manager.setTimeScale(0.5)
        XCTAssertEqual(boss.speed, 0.5, "the boss itself was not slowed")
        XCTAssertEqual(early.speed, 0.5, "a round in flight kept its full clock")
        XCTAssertEqual(early.physicsBody?.velocity.dy ?? 0, full.dy * 0.5, accuracy: 0.01,
                       "a round in flight kept its full velocity")

        let slowed = newRounds(harness) { _ = manager.performAttack(.straightShot) }
        guard let late = slowed.first else { return XCTFail("a straight shot put no round on the playfield") }
        XCTAssertEqual(late.speed, 0.5, "a round fired under SLOW MO left at full clock")
        XCTAssertEqual(late.physicsBody?.velocity.dy ?? 0, full.dy * 0.5, accuracy: 0.01,
                       "a round fired under SLOW MO left at full speed")

        // Asking again for the same scale changes nothing: the scene does every tick.
        manager.setTimeScale(0.5)
        XCTAssertEqual(early.physicsBody?.velocity.dy ?? 0, full.dy * 0.5, accuracy: 0.01,
                       "a repeated call slowed the rounds again")

        manager.setTimeScale(1)
        XCTAssertEqual(boss.speed, 1)
        for round in [early, late] {
            XCTAssertEqual(round.speed, 1, "a round stayed slowed after SLOW MO ended")
            XCTAssertEqual(round.physicsBody?.velocity.dy ?? 0, full.dy, accuracy: 0.01,
                           "a round stayed slowed after SLOW MO ended")
        }
    }

    /// The power-up itself reaches the boss — one that was already there, and one that
    /// arrives while it runs.
    func testTheSlowMotionPowerUpSlowsTheBoss() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlayingWithControl(level: 2)
        harness.scene.debugSetInvulnerable(true)
        let manager = harness.scene.bossManager!

        harness.scene.debugActivatePowerUp(.slowMotion)
        harness.spin(0.3)
        XCTAssertEqual(manager.timeScale, 0.5, "SLOW MO never reached the boss manager")

        manager.spawnBoss(level: 2) {}
        XCTAssertEqual(boss(in: harness)?.speed, 0.5, "a boss arriving under SLOW MO arrived at full pace")
        harness.spin(0.3)
        XCTAssertEqual(boss(in: harness)?.speed, 0.5, "the boss was not kept slowed")
    }

    func testTheScenesSlowMotionSweepScalesBossRoundVelocityOnlyOnce() throws {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        let scene = harness.startPlayingWithControl(level: 1)
        scene.debugSetInvulnerable(true)
        let manager = scene.bossManager!
        manager.spawnBoss(level: 1) {}
        harness.spin(2.4)
        XCTAssertTrue(manager.isBossActive())

        let round = try XCTUnwrap(newRounds(harness) {
            _ = manager.performAttack(.straightShot)
        }.first)
        let body = try XCTUnwrap(round.physicsBody)
        let fullSpeed = hypot(body.velocity.dx, body.velocity.dy)
        XCTAssertGreaterThan(fullSpeed, 100)
        XCTAssertTrue(manager.ownsRound(round))

        scene.debugActivatePowerUp(.slowMotion)
        harness.spin(0.25)
        XCTAssertEqual(hypot(body.velocity.dx, body.velocity.dy), fullSpeed * 0.5, accuracy: 0.01,
                       "the scene and boss manager both scaled the same round")
        harness.spin(0.25)
        XCTAssertEqual(hypot(body.velocity.dx, body.velocity.dy), fullSpeed * 0.5, accuracy: 0.01,
                       "a later scene sweep scaled the boss round again")
    }

    /// A dying boss keeps its own pace: `GameScene` waits a fixed 2.2 s for the
    /// explosions before it moves on, slowed or not.
    func testADyingBossIsNotSlowed() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlaying(level: 1)
        let manager = harness.scene.bossManager!
        manager.spawnBoss(level: 1) {}
        harness.spin(2.4)
        guard let boss = boss(in: harness) else { return XCTFail("no boss") }

        manager.setTimeScale(0.5)
        while manager.isBossActive() { _ = manager.bossTakeDamage() }
        XCTAssertEqual(boss.speed, 1, "the kill left the explosions slowed")
        manager.setTimeScale(0.5)
        XCTAssertEqual(boss.speed, 1, "SLOW MO slowed the explosions")
    }
}
