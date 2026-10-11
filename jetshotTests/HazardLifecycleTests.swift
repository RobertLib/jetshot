//
//  HazardLifecycleTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Things that fall through the playfield, from where they start to where they leave it:
/// a pickup nobody caught, and the pieces of a broken rock.
@MainActor
final class HazardLifecycleTests: XCTestCase {

    // MARK: - Missed power-up

    /// A pickup the player never touches has to leave the tree when its fall ends.
    /// Every one that does not keeps its physics body, its 30 Hz wireframe and its glow
    /// running for the rest of the run, which is how an endless run slowly loses frames.
    func testMissedPowerUpLeavesTheTreeAfterItsFall() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        // Well clear of the falling pickup, so it really is missed.
        harness.player.position = CGPoint(x: 330, y: 500)

        let powerUp = PowerUp(type: .shield, position: CGPoint(x: 40, y: 300))
        powerUp.speed = 10 // its 8 s fall in 0.8 s
        harness.gameContent.addChild(powerUp)
        harness.spin(1.5)

        XCTAssertFalse(harness.player.hasShield, "precondition: the pickup was meant to be missed")
        XCTAssertNil(powerUp.parent, "a missed power-up stayed in the scene after its fall")
    }

    // MARK: - Asteroid pieces

    func testPieceFallTimeIsTheRemainingDropAtThePiecesSpeed() {
        let speed = AsteroidSize.medium.speed * 1.3
        let bottom = -AsteroidSize.medium.baseSize

        for height in [CGFloat(120), 400, 800] {
            let fall = AsteroidManager.pieceFall(
                from: CGPoint(x: 200, y: height), size: .medium, splitVelocityX: 0
            )
            XCTAssertEqual(fall.destination.y, bottom)
            XCTAssertEqual(
                fall.duration, TimeInterval((height - bottom) / speed), accuracy: 1e-6,
                "a piece broken \(Int(height)) pt up does not fall at its own speed"
            )
        }
    }

    func testPieceDriftIsItsSplitMomentumOverItsOwnFall() {
        // Sideways at a steady 60% of the split velocity for as long as it is falling —
        // not for as long as a full-screen drop would take.
        let low = AsteroidManager.pieceFall(from: CGPoint(x: 200, y: 150), size: .small, splitVelocityX: 80)
        let high = AsteroidManager.pieceFall(from: CGPoint(x: 200, y: 800), size: .small, splitVelocityX: 80)

        for fall in [low, high] {
            XCTAssertEqual((fall.destination.x - 200) / CGFloat(fall.duration), 48, accuracy: 1e-6)
        }
        XCTAssertLessThan(low.destination.x - 200, 100,
                          "a piece broken low on screen still slides most of the screen sideways")
    }

    /// The real split: pieces of a rock broken low get a fall timed for the drop they
    /// actually have left.
    func testPiecesOfARockBrokenLowFallAtFullSpeed() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        defer { harness.teardown() }

        let breakPoint = CGPoint(x: 200, y: 150)
        let rock = Asteroid(sceneSize: scene.size, scene: scene, size: .large, startPosition: breakPoint)
        harness.gameContent.addChild(rock)
        AsteroidManager(scene: scene, waves: []).splitAsteroid(rock)

        let pieces = harness.gameContent.children
            .compactMap { $0 as? Asteroid }
            .filter { $0 !== rock && $0.asteroidSize == .medium && $0.position == breakPoint }
        XCTAssertFalse(pieces.isEmpty, "the rock did not split")

        let remainingDrop = breakPoint.y + AsteroidSize.medium.baseSize
        let expected = TimeInterval(remainingDrop / (AsteroidSize.medium.speed * 1.3))
        for piece in pieces {
            guard let duration = piece.action(forKey: "asteroidMovement")?.duration else {
                XCTFail("a split piece was never set falling")
                continue
            }
            XCTAssertEqual(
                duration, expected, accuracy: 0.001,
                "a piece with \(Int(remainingDrop)) pt left to fall takes \(duration) s — "
                + "\(Int(remainingDrop / CGFloat(duration))) pt/s instead of \(Int(AsteroidSize.medium.speed * 1.3))"
            )
        }
    }
}
