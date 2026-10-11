//
//  SustainedHazardTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// A boss's beam, against the scene's damage and cancel rules.
///
/// A beam is unlike a round: it is not spent by what it touches, it can be sat in, and
/// it is named apart from rounds (`bosslaser`, not `enemyBullet`). Each of those used to
/// open a hole — a ship parked in a beam after its blink took no further damage, a
/// barrier segment deleted the whole beam, and the Overdrive burst left it burning.
///
/// The beam here is built the way `BossManager.fireBeam` builds one — a static
/// rectangle in the `enemyBullet` category, testing against the player — and placed by
/// hand, so no boss has to be on screen shooting at the ship while the rule is measured.
@MainActor
final class SustainedHazardTests: XCTestCase {

    @discardableResult
    private func addBeam(_ harness: GameplayHarness, across y: CGFloat) -> SKNode {
        let width = harness.scene.size.width
        let beam = SKNode()
        beam.name = "bosslaser"
        beam.position = CGPoint(x: 0, y: y)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: width, height: 14), center: CGPoint(x: width / 2, y: 0))
        body.categoryBitMask = PhysicsCategory.enemyBullet
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        body.isDynamic = false
        beam.physicsBody = body
        harness.gameContent.addChild(beam)
        return beam
    }

    /// The beam was entered while the ship could not be hurt, and the ship stays in it.
    /// Once the protection lapses the beam has to bite, without the ship leaving and
    /// coming back.
    func testABeamTheShipStaysInHurtsOnceItCanBeHurt() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugSetInvulnerable(true)
        let beam = addBeam(harness, across: harness.player.position.y + Player.hitboxCenter.y)
        harness.spin(0.3)
        let livesInside = harness.scene.currentLives

        harness.scene.debugSetInvulnerable(false)
        harness.spin(0.3)

        XCTAssertEqual(
            harness.scene.currentLives, livesInside - 1,
            "a ship sitting in a beam was never hit once its protection ran out"
        )
        XCTAssertNotNil(beam.parent, "the beam was used up by the hit")
    }

    func testABarrierDoesNotDeleteABeam() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugSetInvulnerable(true)
        harness.scene.debugActivatePowerUp(.barrier)
        harness.spin(0.1)

        let beam = addBeam(harness, across: harness.player.position.y + Player.hitboxCenter.y)
        harness.spin(0.6)

        XCTAssertNotNil(beam.parent, "a barrier segment deleted the whole beam")
        XCTAssertEqual(beam.name, "bosslaser")
    }

    func testTheOverdriveBurstClearsBeams() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        let beam = addBeam(harness, across: harness.scene.size.height * 0.7)
        harness.spin(0.1)

        harness.scene.debugTriggerOverdrive()
        // The burst opens with a hit-stop, which slows the beam's fade with everything
        // else on the gameplay clock.
        harness.spin(0.9)

        XCTAssertTrue(harness.scene.isOverdriveActive, "the overdrive did not fire")
        XCTAssertNil(beam.physicsBody, "the overdrive burst left the beam able to hurt")
        XCTAssertNil(beam.parent, "the overdrive burst left the beam burning")
    }
}
