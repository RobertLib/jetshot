//
//  LaserEnemyBeamTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The laser enemy's beam, against the same rules as a boss's (see `SustainedHazardTests`).
///
/// It is named `laserBeam`, not `bosslaser`, and every beam rule in `GameScene` used to
/// know only the boss's name — so the laser enemy's beam was handled as a round: spent by
/// the first ship it touched however protected, deleted by the barrier, missed by the
/// Overdrive and the nuke, and never a sustained hazard.
///
/// The beam here hangs off the enemy that fires it, as `Enemy` builds it, with a static
/// hit volume in the `enemyBullet` category testing against the player — placed by hand,
/// so the test does not wait on the enemy's randomised fire timer.
@MainActor
final class LaserEnemyBeamTests: XCTestCase {

    /// A laser enemy above the ship with its beam reaching down through `bottom`.
    @discardableResult
    private func addBeam(_ harness: GameplayHarness, downTo bottom: CGPoint) -> SKNode {
        let top = CGPoint(x: bottom.x, y: bottom.y + 320)
        let enemy = harness.addEnemy(.laser, at: top)

        let length: CGFloat = 400
        let beam = SKNode()
        beam.name = "laserBeam"
        // Centred so it overshoots `bottom` by 80 pt, in the enemy's own space.
        beam.position = enemy.convert(CGPoint(x: bottom.x, y: top.y - length / 2), from: harness.gameContent)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: length))
        body.categoryBitMask = PhysicsCategory.enemyBullet
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        body.isDynamic = false
        beam.physicsBody = body
        enemy.addChild(beam)
        return beam
    }

    private func shipCore(_ harness: GameplayHarness) -> CGPoint {
        let ship = harness.player.position
        return CGPoint(x: ship.x + Player.hitboxCenter.x, y: ship.y + Player.hitboxCenter.y)
    }

    func testTheBeamIsNotSpentOnAProtectedShipAndBitesOnceItCanHurt() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugSetInvulnerable(true)
        let beam = addBeam(harness, downTo: shipCore(harness))
        harness.spin(0.3)
        XCTAssertNotNil(beam.parent, "the beam was used up by touching an invulnerable ship")
        let livesInside = harness.scene.currentLives

        harness.scene.debugSetInvulnerable(false)
        harness.spin(0.3)

        XCTAssertEqual(harness.scene.currentLives, livesInside - 1,
                       "a ship sitting in the beam was never hit once its protection ran out")
        XCTAssertNotNil(beam.parent, "the beam was used up by the hit")
    }

    func testABarrierDoesNotDeleteTheBeam() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugSetInvulnerable(true)
        harness.scene.debugActivatePowerUp(.barrier)
        harness.spin(0.1)

        let beam = addBeam(harness, downTo: shipCore(harness))
        harness.spin(0.6)

        XCTAssertNotNil(beam.parent, "a barrier segment deleted the beam")
        XCTAssertEqual(beam.name, "laserBeam")
    }

    func testTheOverdriveBurstClearsTheBeam() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        let beam = addBeam(harness, downTo: CGPoint(x: 80, y: harness.scene.size.height * 0.45))
        harness.spin(0.1)

        harness.scene.debugTriggerOverdrive()
        harness.spin(0.9)

        XCTAssertTrue(harness.scene.isOverdriveActive, "the overdrive did not fire")
        XCTAssertNil(beam.physicsBody, "the overdrive burst left the beam able to hurt")
        XCTAssertNil(beam.parent, "the overdrive burst left the beam burning")
    }

    func testTheNukeClearsTheBeam() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        let beam = addBeam(harness, downTo: CGPoint(x: 80, y: harness.scene.size.height * 0.45))
        let nuke = PowerUp(type: .nuke, position: harness.player.position)
        harness.gameContent.addChild(nuke)
        harness.spin(0.9)

        XCTAssertNil(nuke.physicsBody, "the nuke was never picked up")
        XCTAssertNil(beam.physicsBody, "the nuke left the beam able to hurt")
    }
}
