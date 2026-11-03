//
//  HomingMissileTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The homing-missile power-up in a running scene: how many missiles it launches, what
/// they do when their target dies first, and that walls do not stop them.
///
/// Missiles steer by `GameScene.deltaTime`, which only advances once the level has
/// handed over control, so the flight tests wait for that (`startPlayingWithControl`).
@MainActor
final class HomingMissileTests: XCTestCase {

    private func missiles(in harness: GameplayHarness) -> [SKNode] {
        return harness.gameContent.children.filter { $0.name == "homingMissile" }
    }

    private func launchSalvo(_ harness: GameplayHarness) {
        let pickup = PowerUp(type: .homingMissiles, position: harness.player.position)
        harness.gameContent.addChild(pickup)
    }

    /// Two targets used to mean two missiles, and one target one; only an empty screen
    /// got the full six.
    func testTheSalvoIsAlwaysFullSize() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        // Far up the screen, so nothing is hit before the last missile is away.
        harness.addEnemy(.tank, at: CGPoint(x: 100, y: harness.scene.size.height - 60))
        harness.addEnemy(.tank, at: CGPoint(x: 300, y: harness.scene.size.height - 60))

        launchSalvo(harness)
        harness.spin(1.2)

        XCTAssertEqual(
            missiles(in: harness).count, GameConfiguration.homingMissileCount,
            "two targets on screen launched \(missiles(in: harness).count) missiles"
        )
    }

    /// The target dies to something else while the salvo is in the air, and — like a
    /// formation enemy, which `FormationManager` keeps alive — is still referenced. The
    /// missiles must go after what is left rather than hover over the wreck.
    func testMissilesWhoseTargetDiesFindAnother() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        let first = harness.addEnemy(.tank, at: CGPoint(x: 90, y: harness.scene.size.height - 120))
        launchSalvo(harness)
        harness.spin(1.0)
        XCTAssertFalse(missiles(in: harness).isEmpty, "no missile was launched")

        let wreck = first.position
        first.markAsDestroyed()
        first.removeFromParent()
        let second = harness.addEnemy(.tank, at: CGPoint(x: 300, y: harness.scene.size.height * 0.55))
        harness.spin(3.0)

        XCTAssertTrue(
            second.parent == nil || second.health < second.maxHealth,
            "the salvo never went after the enemy that was left"
        )
        let loitering = missiles(in: harness).filter {
            hypot($0.position.x - wreck.x, $0.position.y - wreck.y) < 40
        }
        XCTAssertTrue(loitering.isEmpty, "\(loitering.count) missiles hovered over a dead target")
    }

    /// A phased ghost lets rounds through, but the missiles kept their lock on it: they
    /// flew to its centre and hovered there for as long as it stayed phased, while an
    /// enemy they could have hit went untouched. Once it is solid again it is a target
    /// like any other.
    func testMissilesDoNotHoverInsideAPhasedGhost() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        let ship = harness.player.position
        let ghost = harness.addEnemy(.ghost, at: CGPoint(x: ship.x, y: ship.y + 200))
        // Held phased out where the test puts it, rather than left to fade on its own.
        ghost.removeAllActions()
        ghost.alpha = 0.3
        let health = ghost.health
        // Further off than the ghost, so the ghost is the nearest target.
        let other = harness.addEnemy(.basic, at: CGPoint(x: ship.x + 120, y: ship.y + 420))
        other.health = 1

        launchSalvo(harness)
        // Long enough for the whole salvo to have reached the ghost's centre.
        harness.spin(2.0)

        XCTAssertEqual(ghost.health, health, "a phased-out ghost was hit")
        XCTAssertNil(other.parent, "the salvo never went after the enemy it could hit")
        let hovering = missiles(in: harness).filter {
            hypot($0.position.x - ghost.position.x, $0.position.y - ghost.position.y) < 12
        }
        XCTAssertTrue(hovering.isEmpty, "\(hovering.count) missiles hovered inside a phased-out ghost")

        ghost.alpha = 1
        harness.spin(2.0)

        XCTAssertTrue(ghost.parent == nil || ghost.health < health,
                      "the salvo never hit the ghost once it was solid again")
    }

    /// Homing missiles fly over walls. A wall tests against every player round, so its
    /// contact arrived even though the missile's own mask leaves walls out.
    func testAWallDoesNotStopAHomingMissile() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let spot = CGPoint(x: 200, y: 520)
        let wall = Obstacle(type: .wall, sceneSize: harness.scene.size, position: spot)
        wall.removeAllActions()
        harness.gameContent.addChild(wall)

        let missile = ProjectileFX.missile(homing: true)
        missile.position = spot
        harness.gameContent.addChild(missile)
        // The control: an ordinary bolt in the same wall is stopped.
        let bolt = ProjectileFX.playerRound(overdrive: false)
        bolt.position = spot
        harness.gameContent.addChild(bolt)
        harness.spin(0.3)

        XCTAssertNil(bolt.parent, "the wall stopped nothing, so this test proves nothing")
        XCTAssertNotNil(missile.parent, "a wall stopped a homing missile")
    }
}
