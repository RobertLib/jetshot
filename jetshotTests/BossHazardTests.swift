//
//  BossHazardTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// What a boss's attacks leave around it, against the moments a fight is interrupted,
/// and a beam against a ship that is not moving.
@MainActor
final class BossHazardTests: XCTestCase {

    private static let ringName = "bossTelegraphRing"

    private func startFight(_ harness: GameplayHarness, level: Int = 1) -> Boss? {
        harness.startPlaying(level: level)
        harness.scene.bossManager.spawnBoss(level: level) {}
        harness.spin(2.4)
        return harness.gameContent.children.compactMap { $0 as? Boss }.first
    }

    /// Waits for the boss to start winding up an attack: its ring is on it.
    private func waitForTelegraph(_ harness: GameplayHarness, on boss: Boss) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if boss.childNode(withName: Self.ringName) != nil { return true }
            harness.spin(0.02)
        }
        return false
    }

    /// The ring used to be an unnamed child of the boss that only removed itself, so a
    /// phase change cancelled the wind-up and left the ring closing on nothing.
    func testAPhaseChangeSweepsTheWindUpRing() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        guard let boss = startFight(harness) else { return XCTFail("no boss") }
        guard waitForTelegraph(harness, on: boss) else { return XCTFail("the boss never wound up an attack") }

        let manager = harness.scene.bossManager!
        var changed = false
        while !changed && manager.isBossActive() { changed = manager.bossTakeDamage().phaseChanged }
        XCTAssertTrue(changed, "the boss never changed phase")

        XCTAssertNil(boss.childNode(withName: Self.ringName), "the wind-up ring outlived the phase change")
    }

    func testTheKillSweepsTheWindUpRing() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        guard let boss = startFight(harness) else { return XCTFail("no boss") }
        guard waitForTelegraph(harness, on: boss) else { return XCTFail("the boss never wound up an attack") }

        let manager = harness.scene.bossManager!
        while manager.isBossActive() { _ = manager.bossTakeDamage(amount: boss.maxHealthPoints) }

        XCTAssertNil(boss.childNode(withName: Self.ringName), "the wind-up ring kept closing over the exploding boss")
    }

    /// A beam sweeping onto a ship that has sat perfectly still.
    ///
    /// The beam's body is static and moved by its rotation, and the physics engine only
    /// updates a contact while one of its bodies is awake and dynamic. A still ship's
    /// body does go to rest — for a frame or two every half second — but it is woken
    /// again straight away, so the sweep still meets it. Pinned so that stays true: a
    /// ship whose body stayed asleep would be swept straight through, with no contact
    /// begun and none listed for `applySustainedContactDamage()` to find either. The
    /// ship is put to rest as the sweep begins, the worst case.
    func testASweepingBeamHitsAShipThatIsSittingStill() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        // Long past the half second a body has to be still for before it may rest.
        harness.spin(1.5)
        let lives = harness.scene.currentLives

        let ship = harness.player.position
        let pivot = CGPoint(x: ship.x, y: harness.scene.size.height * 0.8)
        let length = harness.scene.size.height
        let beam = SKNode()
        beam.name = "bosslaser"
        beam.position = pivot
        // Pointing well off to one side of the ship, then swept across it.
        let down = atan2(ship.y - pivot.y, ship.x - pivot.x)
        beam.zRotation = down - 0.9
        let body = SKPhysicsBody(rectangleOf: CGSize(width: length, height: 14), center: CGPoint(x: length / 2, y: 0))
        body.categoryBitMask = PhysicsCategory.enemyBullet
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        body.isDynamic = false
        beam.physicsBody = body
        harness.gameContent.addChild(beam)
        harness.spin(0.3)
        XCTAssertEqual(harness.scene.currentLives, lives, "the beam hit the ship before it reached it")

        // About the pace of the lancer's sweep where it crosses the ship.
        harness.player.physicsBody?.isResting = true
        beam.run(.customAction(withDuration: 1.6) { node, elapsed in
            node.zRotation = down - 0.9 + 1.8 * elapsed / 1.6
        })
        harness.spin(1.8)

        XCTAssertLessThan(harness.scene.currentLives, lives, "a beam swept straight through a ship sitting still")
    }
}
