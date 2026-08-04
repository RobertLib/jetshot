//
//  GameplayCollisionTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// End-to-end coverage of the collision pipeline: a real `SKPhysicsBody` overlap, the
/// real dispatch in `GameScene.didBegin(_:)`, and the real handler behind it.
///
/// This is the part of the game that was previously only reachable by playing it.
/// `PhysicsCategoryTests` pins down the *ordering* the dispatch relies on, but nothing
/// checked that a bullet meeting an enemy actually damages it, that a coin can only be
/// banked once, or that a shield really absorbs a hit — all of which live behind
/// `private` handlers and a physics step.
///
/// See `GameplayHarness` for why gameplay is unpaused directly instead of waiting out
/// the level intro.
final class GameplayCollisionTests: XCTestCase {

    // MARK: - Bullet vs enemy

    @MainActor
    func testBulletDestroysEnemyAndCleansTheCache() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let enemy = harness.addEnemy(.basic, at: CGPoint(x: 200, y: 500))
        XCTAssertEqual(harness.scene.activeEnemyCount, 1)

        harness.player.position = CGPoint(x: 200, y: 480)
        harness.fireBullets(onto: enemy.position)
        harness.spin(1.0)

        XCTAssertLessThanOrEqual(enemy.health, 0, "the bullet never damaged the enemy")
        XCTAssertNil(enemy.parent, "a destroyed enemy stayed in the scene")
        XCTAssertEqual(
            harness.scene.activeEnemyCount, 0,
            "the enemy cache still holds a destroyed enemy, which is the shape of the old leak"
        )
    }

    @MainActor
    func testBulletIsConsumedByTheHit() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let enemy = harness.addEnemy(.basic, at: CGPoint(x: 180, y: 520))
        harness.player.position = CGPoint(x: 180, y: 500)
        harness.fireBullets(onto: enemy.position)
        harness.spin(1.0)

        let remaining = harness.gameContent.children.filter { $0.name == "bullet" }
        XCTAssertTrue(remaining.isEmpty, "a bullet passed through the enemy instead of being spent")
    }

    @MainActor
    func testOneMovingBulletCostsExactlyOneHitPoint() {
        // The tank is the only enemy with 2 HP, so it is the only one that can show a
        // bullet landing twice. `didBegin(_:)` reports a contact per overlap and the
        // handler decrements unconditionally, so a shot that stayed inside the hitbox for
        // several frames would spend a 2 HP enemy in one trigger pull — the tank's whole
        // point is that it takes two.
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let tank = harness.addEnemy(.tank, at: CGPoint(x: 200, y: 500))
        XCTAssertEqual(tank.maxHealth, 2, "this test is only meaningful for a 2 HP enemy")

        harness.fireMovingBullets(from: CGPoint(x: 200, y: 380))
        harness.spin(1.2)

        XCTAssertEqual(tank.health, 1, "one bullet took \(tank.maxHealth - tank.health) hit points")
        XCTAssertNotNil(tank.parent, "the tank died to a single bullet")
        XCTAssertEqual(harness.scene.activeEnemyCount, 1)
    }

    @MainActor
    func testTwoMovingBulletsFinishTheTank() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let tank = harness.addEnemy(.tank, at: CGPoint(x: 200, y: 500))

        harness.fireMovingBullets(from: CGPoint(x: 200, y: 380))
        harness.spin(1.2)
        harness.fireMovingBullets(from: CGPoint(x: 200, y: 380))
        harness.spin(1.2)

        XCTAssertLessThanOrEqual(tank.health, 0, "the tank survived two clean hits")
        XCTAssertNil(tank.parent)
        XCTAssertEqual(harness.scene.activeEnemyCount, 0)
    }

    @MainActor
    func testManyKillsDoNotAccumulateInTheCache() {
        // The long-level shape: wave after wave shot down. Any handler that forgets to
        // unregister shows up here as a cache that never returns to zero.
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        for i in 0..<25 {
            let y = 300 + CGFloat(i % 5) * 40
            let enemy = harness.addEnemy(.basic, at: CGPoint(x: 60 + CGFloat(i % 4) * 80, y: y))
            harness.player.position = CGPoint(x: enemy.position.x, y: enemy.position.y - 20)
            harness.fireBullets(onto: enemy.position)
        }
        harness.spin(2.0)

        XCTAssertEqual(
            harness.scene.activeEnemyCount, 0,
            "enemies accumulated in the cache across repeated kills"
        )
    }

    // MARK: - Player vs coin

    @MainActor
    func testPlayerCollectsCoinOnContact() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        harness.player.position = CGPoint(x: 200, y: 300)
        let coin = Coin(position: harness.player.position)
        harness.gameContent.addChild(coin)
        harness.scene.registerCoin(coin)
        XCTAssertNotNil(coin.physicsBody, "the coin started with no body, so nothing could collect it")

        harness.spin(1.0)

        // The handler drops the body first thing, which is both the collected marker and
        // the guard against banking the same coin twice.
        XCTAssertNil(coin.physicsBody, "the coin was never collected")
    }

    @MainActor
    func testCoinCannotBeCollectedTwice() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        harness.player.position = CGPoint(x: 200, y: 300)
        let coin = Coin(position: harness.player.position)
        harness.gameContent.addChild(coin)
        harness.scene.registerCoin(coin)
        harness.spin(0.6)
        XCTAssertNil(coin.physicsBody)

        // Sit on it for longer: without the body guard the score would keep climbing for
        // as long as the player overlapped the coin.
        harness.spin(0.8)
        XCTAssertNil(coin.physicsBody)
        XCTAssertEqual(harness.scene.activeEnemyCount, 0)
    }

    // MARK: - Player vs enemy fire

    @MainActor
    func testEnemyBulletDamagesThePlayer() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 200, y: 300)
        XCTAssertNil(player.action(forKey: "invulnerability"), "player started out already hit")

        harness.addEnemyBullet(at: player.position)
        harness.spin(1.0)

        // Taking damage always ends in activateInvulnerability(), which runs a keyed
        // blink on the player — the one observable the damage path leaves behind.
        XCTAssertNotNil(
            player.action(forKey: "invulnerability"),
            "an enemy bullet hit the player without costing anything"
        )
    }

    @MainActor
    func testShieldAbsorbsEnemyFireWithoutDamage() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 200, y: 300)
        player.hasShield = true

        let bullet = harness.addEnemyBullet(at: player.position)
        harness.spin(1.0)

        XCTAssertNil(bullet.parent, "the shield let the bullet through")
        XCTAssertNil(
            player.action(forKey: "invulnerability"),
            "the shield absorbed the hit but the player took damage anyway"
        )
        XCTAssertTrue(player.hasShield, "a single absorbed hit should not drop the shield")
    }

    @MainActor
    func testInvulnerablePlayerShrugsOffASecondHit() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 200, y: 300)

        harness.addEnemyBullet(at: player.position)
        harness.spin(0.6)
        XCTAssertNotNil(player.action(forKey: "invulnerability"), "the first hit did not register")

        // Invulnerability is keyed precisely so a second activation cannot stack a
        // competing blink on top of the first.
        let secondBullet = harness.addEnemyBullet(at: player.position)
        harness.spin(0.6)

        XCTAssertNil(secondBullet.parent, "the bullet was not cleared during invulnerability")
        XCTAssertNotNil(player.action(forKey: "invulnerability"))
    }

    // MARK: - Player vs power-up

    @MainActor
    func testPowerUpIsPickedUpAndApplied() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 200, y: 300)
        XCTAssertFalse(player.hasShield)

        let powerUp = PowerUp(type: .shield, position: player.position)
        harness.gameContent.addChild(powerUp)
        harness.spin(1.0)

        XCTAssertNil(powerUp.physicsBody, "the power-up was never picked up")
        XCTAssertTrue(player.hasShield, "the shield power-up was collected but never applied")
    }

    @MainActor
    func testStackingPowerUpRaisesTheArsenal() {
        let harness = GameplayHarness()
        harness.startPlaying(bulletCount: 2)
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 200, y: 300)
        let before = player.bulletCount

        let powerUp = PowerUp(type: .multiShot, position: player.position)
        harness.gameContent.addChild(powerUp)
        harness.spin(1.0)

        XCTAssertNil(powerUp.physicsBody, "the power-up was never picked up")
        XCTAssertGreaterThan(player.bulletCount, before, "multiShot did not add a gun")
        XCTAssertLessThanOrEqual(
            player.bulletCount, GameConfiguration.maxBulletCount,
            "the arsenal went past its cap"
        )
    }

    // MARK: - Player vs enemy body

    @MainActor
    func testFlyingIntoAnEnemyCostsTheHit() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 200, y: 400)
        harness.addEnemy(.basic, at: player.position)
        harness.spin(1.0)

        XCTAssertNotNil(
            player.action(forKey: "invulnerability"),
            "ramming an enemy did not hurt the player"
        )
    }
}
