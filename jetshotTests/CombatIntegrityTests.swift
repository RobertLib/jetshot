//
//  CombatIntegrityTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The contact handlers' bookkeeping: that a kill pays once, that a hit lands once, and
/// that the ship is hurt exactly when it should be — not during its own death, not after
/// the boss is dead, and not through protection it was promised.
///
/// SpriteKit delivers *every* contact of a physics step, including ones whose node an
/// earlier contact in the same step already used up. Rounds parked on a target with
/// `GameplayHarness.fireBullets(onto:)` all touch it in the same step, which is exactly
/// the case that used to pay out several times.
@MainActor
final class CombatIntegrityTests: XCTestCase {

    /// Polls `condition`, letting the scene run, for up to `timeout` seconds.
    @discardableResult
    private func spin(_ harness: GameplayHarness, until condition: () -> Bool,
                      timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            harness.spin(0.02)
        }
        return condition()
    }

    // MARK: - One kill, one payout

    func testRoundsLandingTogetherPayTheKillOnce() {
        let harness = GameplayHarness()
        harness.startPlaying(bulletCount: 3)
        defer { harness.teardown() }

        let enemy = harness.addEnemy(.fast, at: CGPoint(x: 200, y: 600))
        enemy.health = 1
        harness.player.position = CGPoint(x: 200, y: 200)
        let before = harness.scene.currentScore

        let rounds = harness.fireBullets(onto: enemy.position)
        XCTAssertEqual(rounds.count, 3, "this test needs several rounds on the target at once")
        harness.spin(0.15)

        XCTAssertNil(enemy.parent, "the enemy survived, so this test proves nothing")
        XCTAssertEqual(
            harness.scene.currentScore - before, EnemyType.fast.points,
            "three rounds arriving together paid one kill \(harness.scene.currentScore - before) points"
        )
        XCTAssertTrue(rounds.allSatisfy { $0.parent == nil }, "a round that reached the hull was not spent")
    }

    func testASplitterSplitsOnceHoweverManyRoundsKillIt() {
        let harness = GameplayHarness()
        harness.startPlaying(bulletCount: 3)
        defer { harness.teardown() }

        let splitter = harness.addEnemy(.splitter, at: CGPoint(x: 200, y: 600))
        splitter.health = 1
        harness.player.position = CGPoint(x: 200, y: 200)

        harness.fireBullets(onto: splitter.position)
        harness.spin(0.15)

        XCTAssertNil(splitter.parent)
        XCTAssertEqual(
            harness.scene.activeEnemyCount, 2,
            "one splitter came apart into \(harness.scene.activeEnemyCount) fragments"
        )
    }

    func testSplitterFragmentsSeparateLeftAndRightWhileBothDescend() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let origin = CGPoint(x: 200, y: 600)
        let splitter = harness.addEnemy(.splitter, at: origin)
        splitter.health = 1
        harness.player.position = CGPoint(x: 200, y: 200)
        harness.fireBullets(onto: origin)
        harness.spin(0.3)

        XCTAssertNil(splitter.parent)
        let fragments = harness.gameContent.children.compactMap { $0 as? Enemy }
        XCTAssertEqual(fragments.count, 2)
        XCTAssertTrue(fragments.contains { $0.position.x < origin.x - 10 },
                      "neither fragment launched to the left")
        XCTAssertTrue(fragments.contains { $0.position.x > origin.x + 10 },
                      "neither fragment launched to the right")
        XCTAssertTrue(fragments.allSatisfy { $0.position.y < origin.y - 10 },
                      "one fragment launched upwards instead of towards the player")
    }

    // MARK: - Ghost

    func testAPhasedGhostLetsRoundsThrough() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let ghost = harness.addEnemy(.ghost, at: CGPoint(x: 200, y: 600))
        // Held where the test puts it rather than left to fade in and out on its own.
        ghost.removeAllActions()
        ghost.alpha = 0.3
        let health = ghost.health
        harness.player.position = CGPoint(x: 200, y: 200)

        let phasedRounds = harness.fireBullets(onto: ghost.position)
        harness.spin(0.3)

        XCTAssertEqual(ghost.health, health, "a phased-out ghost took damage")
        XCTAssertTrue(phasedRounds.allSatisfy { $0.parent != nil }, "a phased-out ghost stopped a round")

        // Solid again, it is an ordinary target.
        phasedRounds.forEach { $0.removeFromParent() }
        ghost.alpha = 0.7
        harness.fireBullets(onto: ghost.position)
        harness.spin(0.3)

        XCTAssertTrue(ghost.parent == nil || ghost.health < health, "a solid ghost could not be hit")
    }

    // MARK: - Ramming

    func testRammingWhileInvulnerableDestroysAndPays() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 200, y: 300)
        harness.scene.debugSetInvulnerable(true)
        let lives = harness.scene.currentLives
        let before = harness.scene.currentScore

        let tank = harness.addEnemy(.tank, at: player.position)
        harness.spin(0.4)

        XCTAssertNil(tank.parent, "an invulnerable ship flew through a tank without destroying it")
        XCTAssertGreaterThanOrEqual(
            harness.scene.currentScore - before, EnemyType.tank.points,
            "the rammed tank was destroyed but never paid"
        )
        XCTAssertTrue(
            harness.scene.medalsEarnedSoFar.contains(.hunter),
            "a rammed enemy did not count as destroyed for the hunter medal"
        )
        XCTAssertEqual(harness.scene.currentLives, lives)
    }

    func testRammingAMineWhileInvulnerableSetsItOff() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 200, y: 300)
        harness.scene.debugSetInvulnerable(true)
        let lives = harness.scene.currentLives
        let before = harness.scene.currentScore

        let mine = harness.addEnemy(.mine, at: player.position)
        harness.spin(0.4)

        XCTAssertNil(mine.parent)
        XCTAssertGreaterThanOrEqual(
            harness.scene.currentScore - before, EnemyType.mine.points,
            "the mine vanished without going off or paying"
        )
        XCTAssertEqual(harness.scene.currentLives, lives, "its shrapnel hurt an invulnerable ship")
    }

    // MARK: - The death sequence

    func testTheShipIsDisarmedOnceItsLastLifeIsGone() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        let player = harness.player
        // Every hit cut short of its blink, so the next one lands.
        var hits = 0
        while harness.scene.currentLives > 0 && hits < 10 {
            harness.scene.debugSetInvulnerable(false)
            let livesBefore = harness.scene.currentLives
            harness.addEnemyBullet(at: player.position)
            spin(harness, until: { harness.scene.currentLives < livesBefore }, timeout: 2)
            hits += 1
        }
        XCTAssertEqual(harness.scene.currentLives, 0, "the ship never ran out of lives")

        XCTAssertNil(player.physicsBody, "the core stayed live through the ship's own death")
        XCTAssertNil(player.childNode(withName: "collector")?.physicsBody,
                     "the collector stayed live through the ship's own death")

        // More fire and a pickup arrive while it goes down.
        harness.addEnemyBullet(at: player.position)
        let extraLife = PowerUp(type: .extraLife, position: player.position)
        harness.gameContent.addChild(extraLife)
        harness.spin(0.3)

        XCTAssertEqual(harness.scene.currentLives, 0, "a dead ship lost or gained a life")
        XCTAssertNotNil(extraLife.physicsBody, "a dead ship collected a power-up")
    }

    // MARK: - After the boss

    func testNothingHurtsTheShipOnceTheBossIsDead() {
        let harness = GameplayHarness()
        harness.startPlaying(level: 1)
        defer { harness.teardown() }

        harness.scene.bossManager.spawnBoss(level: 1) {}
        XCTAssertTrue(spin(harness, until: { harness.scene.bossManager.isBossActive() }),
                      "the boss never finished its entrance")
        guard let boss = harness.scene.bossManager.getBoss() else { return XCTFail("no boss") }

        // Down to its last hit, then killed by a real round through the contact path.
        _ = harness.scene.bossManager.bossTakeDamage(amount: boss.maxHealthPoints - 1)
        let player = harness.player
        player.position = CGPoint(x: 200, y: 200)
        var volleys = 0
        while harness.scene.bossManager.isBossActive() && volleys < 50 {
            harness.fireBullets(onto: boss.position)
            harness.spin(0.03)
            volleys += 1
        }
        XCTAssertFalse(harness.scene.bossManager.isBossActive(), "the boss never died")
        harness.spin(0.2)

        let lives = harness.scene.currentLives
        harness.addEnemyBullet(at: player.position)
        harness.spin(0.4)

        XCTAssertEqual(harness.scene.currentLives, lives, "a stray round took a life after the boss was dead")
        XCTAssertTrue(
            harness.scene.medalsEarnedSoFar.contains(.untouched),
            "a stray round after the boss died cost the no-hit medal"
        )
    }

    // MARK: - Grace

    func testAnAsteroidThatBreaksTheShieldDoesNotLetTheNextHitThrough() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 200, y: 300)
        player.hasShield = true
        // Read before the rock arrives: the pieces it splits into can land the hit
        // themselves, before anything else gets the chance.
        let lives = harness.scene.currentLives

        let rock = Asteroid(sceneSize: harness.scene.size, scene: harness.scene, size: .large,
                            startPosition: player.position)
        harness.gameContent.addChild(rock)
        harness.spin(0.15)
        XCTAssertFalse(player.hasShield, "the asteroid did not break the shield, so this test proves nothing")

        harness.addEnemyBullet(at: player.position)
        harness.spin(0.15)

        XCTAssertEqual(harness.scene.currentLives, lives,
                       "the shield broke and the very next thing to touch the ship hurt it")
    }

    func testAnOverdriveDoesNotCutTheBlinkAfterAHitShort() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        let player = harness.player
        let lives = harness.scene.currentLives
        let hitAround = harness.scene.gameplayClock
        harness.addEnemyBullet(at: player.position)
        XCTAssertTrue(spin(harness, until: { harness.scene.currentLives < lives }, timeout: 2), "the hit never landed")
        let livesAfterHit = harness.scene.currentLives

        // Its own grace is a second; the hit's blink is two.
        harness.scene.debugTriggerOverdrive()
        XCTAssertTrue(harness.scene.isOverdriveActive)
        XCTAssertLessThan(harness.scene.gameplayClock - hitAround, 0.5, "the overdrive came too late to test anything")

        // Past where the overdrive's grace would have ended, inside the hit's blink.
        spin(harness, until: { harness.scene.gameplayClock >= hitAround + 1.6 })
        harness.addEnemyBullet(at: player.position)
        harness.spin(0.1)

        XCTAssertEqual(
            harness.scene.currentLives, livesAfterHit,
            "the overdrive's one-second grace replaced what was left of the two-second blink"
        )
    }
}
