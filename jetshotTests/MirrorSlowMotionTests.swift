import XCTest
import SpriteKit
@testable import jetshot

@MainActor
final class MirrorSlowMotionTests: XCTestCase {
    private func reflectedRound(in harness: GameplayHarness) -> PlayerRound {
        harness.player.position = CGPoint(x: 350, y: 100)
        let mirror = harness.addEnemy(.mirror, at: CGPoint(x: 50, y: 700))
        mirror.removeAllActions()
        let round = ProjectileFX.playerRound()
        round.position = mirror.position
        harness.gameContent.addChild(round)
        harness.scene.debugMirrorReflection(round, from: mirror)
        return round
    }

    private func speed(of round: PlayerRound) -> CGFloat {
        guard let body = round.physicsBody else {
            XCTFail("the reflected round lost its physics body")
            return 0
        }
        return hypot(body.velocity.dx, body.velocity.dy)
    }

    func testSlowMotionSlowsAnExistingReflectionOnceAndRestoresItOnExpiry() {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl()
        defer { harness.teardown() }
        let round = reflectedRound(in: harness)
        XCTAssertEqual(speed(of: round), 320, accuracy: 0.01)
        XCTAssertFalse(scene.bossManager.ownsRound(round))

        scene.debugActivatePowerUp(.slowMotion)
        harness.spin(0.2)
        XCTAssertTrue(harness.player.hasSlowMotion)
        XCTAssertEqual(round.speed, 0.5, accuracy: 0.001)
        XCTAssertEqual(speed(of: round), 160, accuracy: 0.01)
        XCTAssertEqual(scene.physicsWorld.speed, 1, accuracy: 0.001)

        // Several periodic sweeps must not keep halving the same velocity.
        harness.spin(0.3)
        XCTAssertEqual(speed(of: round), 160, accuracy: 0.01)

        // Advance the real expiry action faster while the round remains on screen.
        harness.gameContent.speed = 10
        let deadline = Date().addingTimeInterval(2)
        while harness.player.hasSlowMotion && Date() < deadline {
            harness.spin(0.02)
        }
        XCTAssertFalse(harness.player.hasSlowMotion, "the scheduled expiry never fired")
        XCTAssertNotNil(round.parent, "the round left before its restored speed could be checked")
        XCTAssertEqual(round.speed, 1, accuracy: 0.001)
        XCTAssertEqual(speed(of: round), 320, accuracy: 0.01)
    }

    func testAReflectionBornDuringSlowMotionLeavesSlowedAndPreservesHitStop() {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl()
        defer { harness.teardown() }

        scene.debugActivatePowerUp(.slowMotion)
        scene.debugTriggerOverdrive() // a global hit-stop, independently of SLOW MO
        XCTAssertEqual(scene.physicsWorld.speed, HitStop.overdrive.timeScale, accuracy: 0.001)

        let round = reflectedRound(in: harness)
        // Checked immediately, before the periodic slow-motion sweep can repair it.
        XCTAssertEqual(round.speed, 0.5, accuracy: 0.001)
        XCTAssertEqual(speed(of: round), 160, accuracy: 0.01)
        XCTAssertEqual(scene.physicsWorld.speed, HitStop.overdrive.timeScale, accuracy: 0.001)

        harness.spin(0.6)
        XCTAssertNotNil(round.parent)
        XCTAssertEqual(scene.physicsWorld.speed, 1, accuracy: 0.001,
                       "SLOW MO prevented the global hit-stop from ending")
        XCTAssertEqual(speed(of: round), 160, accuracy: 0.01,
                       "ending hit-stop or repeating the sweep changed the reflection's pace")
    }
}
