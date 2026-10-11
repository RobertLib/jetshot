//
//  PlayfieldFeedbackTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Small promises the playfield makes the player, each of which had quietly stopped
/// being kept: the Overdrive hint explains once rather than every time, a pause leaves
/// the picture square, a pickup's caption stays on screen, and the magnet pulls at the
/// speed it is rated for.
///
/// See `GameplayHarness` for how the scene is brought up.
@MainActor
final class PlayfieldFeedbackTests: XCTestCase {

    private func wait(_ harness: GameplayHarness, upTo timeout: TimeInterval,
                      until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            harness.spin(0.05)
        }
        return condition()
    }

    private func centre(of scene: SKScene) -> CGPoint {
        return CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
    }

    // MARK: - Overdrive hint

    /// Whether the centred banner currently up carries the "how to fire it" line.
    private func bannerExplainsOverdrive(_ harness: GameplayHarness) -> Bool? {
        guard let banner = harness.gameContent.childNode(withName: "centreBanner") else { return nil }
        var found = false
        banner.enumerateChildNodes(withName: ".//*") { node, stop in
            if (node as? SKLabelNode)?.text == L10n.HUD.overdriveHint {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    func testOnlyTheFirstFullMeterExplainsHowToFireIt() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugFillOverdrive()
        XCTAssertEqual(bannerExplainsOverdrive(harness), true, "the first full meter did not explain itself")

        harness.scene.debugTriggerOverdrive()
        XCTAssertTrue(harness.scene.isOverdriveActive)
        XCTAssertTrue(wait(harness, upTo: 9) { !harness.scene.isOverdriveActive }, "the Overdrive never ended")

        harness.scene.debugFillOverdrive()
        XCTAssertEqual(bannerExplainsOverdrive(harness), false,
                       "the hint came back on the second full meter of the level")
    }

    // MARK: - Camera on pause

    /// A shake caught by the pause used to freeze the camera off centre, and the camera
    /// frames the pause menu too.
    func testPausingMidShakeRecentresTheCamera() throws {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl()
        defer { harness.teardown() }
        let camera = try XCTUnwrap(scene.camera)

        scene.shakeCamera(intensity: 40.0, duration: 2.0)
        harness.spin(0.3)
        XCTAssertNotNil(camera.action(forKey: "cameraShake"), "the shake ended before the pause")

        let pause = try XCTUnwrap(harness.node(named: "pauseButton"))
        harness.touchDown(at: harness.scenePosition(of: pause))
        harness.spin(0.3)
        XCTAssertTrue(harness.gameContent.isPaused, "the pause never took, so this proves nothing")

        XCTAssertEqual(camera.position.x, centre(of: scene).x, accuracy: 0.0001, "the pause menu is off centre")
        XCTAssertEqual(camera.position.y, centre(of: scene).y, accuracy: 0.0001, "the pause menu is off centre")
        XCTAssertFalse(camera.hasActions(), "the shake is still queued to resume after the pause")
    }

    /// The same for the perk picker, which freezes the run the same way.
    func testThePerkPickerRecentresTheCamera() throws {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl(endless: true)
        defer { harness.teardown() }
        let camera = try XCTUnwrap(scene.camera)

        scene.shakeCamera(intensity: 40.0, duration: 2.0)
        harness.spin(0.3)
        scene.debugOfferPerks()
        XCTAssertTrue(scene.isPerkPickerUp, "the picker never came up, so this proves nothing")

        XCTAssertEqual(camera.position.x, centre(of: scene).x, accuracy: 0.0001, "the perk picker is off centre")
        XCTAssertEqual(camera.position.y, centre(of: scene).y, accuracy: 0.0001, "the perk picker is off centre")
    }

    // MARK: - Floating captions

    private func captions(_ text: String, in harness: GameplayHarness) -> [SKLabelNode] {
        return harness.gameContent.children.compactMap { $0 as? SKLabelNode }.filter { $0.text == text }
    }

    private func pickUp(_ type: PowerUpType, at x: CGFloat, in harness: GameplayHarness) {
        harness.player.position = CGPoint(x: x, y: 300)
        let powerUp = PowerUp(type: type, position: harness.player.position)
        harness.gameContent.addChild(powerUp)
        harness.spin(0.3)
        XCTAssertNil(powerUp.physicsBody, "the power-up was never picked up")
    }

    /// A pickup hard against either edge keeps its whole caption on screen.
    func testAPickupAtTheEdgeKeepsItsCaptionOnScreen() throws {
        let harness = GameplayHarness()
        harness.startPlaying(bulletCount: 1)
        defer { harness.teardown() }
        let width = harness.scene.size.width

        for x in [CGFloat(10), width - 10] {
            pickUp(.multiShot, at: x, in: harness)
            let caption = try XCTUnwrap(
                captions(L10n.PowerUp.multiShot, in: harness).min { abs($0.position.x - x) < abs($1.position.x - x) },
                "no caption was shown"
            )
            XCTAssertGreaterThanOrEqual(caption.frame.minX, 0, "the caption ran off the left edge")
            XCTAssertLessThanOrEqual(caption.frame.maxX, width, "the caption ran off the right edge")
        }
    }

    /// A caption wider than the whole screen is shrunk to fit it.
    func testACaptionWiderThanTheScreenIsShrunk() {
        let harness = GameplayHarness(size: CGSize(width: 110, height: 600))
        harness.startPlaying(bulletCount: 1)
        defer { harness.teardown() }

        pickUp(.multiShot, at: 55, in: harness)
        guard let caption = captions(L10n.PowerUp.multiShot, in: harness).first else {
            return XCTFail("no caption was shown")
        }
        XCTAssertGreaterThanOrEqual(caption.frame.minX, 0)
        XCTAssertLessThanOrEqual(caption.frame.maxX, 110)
    }

    // MARK: - Magnet

    /// Measured against a node moved by an action at `magnetSpeed` on the same clock,
    /// so frame pacing in the simulator cancels out. The pull used to land at half that
    /// at 60 fps: throttled to every second frame, it moved coins by one frame's time.
    func testTheMagnetPullsAtItsRatedSpeed() {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl()
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 80, y: 300)
        scene.debugActivatePowerUp(.magnet)

        // Level with the ship and 180pt out: inside the magnet's 200pt reach, and far
        // enough that it is still on its way in when the measurement ends.
        let coin = Coin(position: CGPoint(x: player.position.x + 180, y: player.position.y))
        harness.gameContent.addChild(coin)
        scene.registerCoin(coin)

        let reference = SKNode()
        harness.gameContent.addChild(reference)
        reference.run(.moveBy(x: GameConfiguration.magnetSpeed, y: 0, duration: 1.0))

        let start = coin.position.x
        harness.spin(0.3)
        XCTAssertNotNil(coin.parent, "the coin was collected before the measurement ended")

        let pulled = start - coin.position.x
        let rated = reference.position.x
        XCTAssertGreaterThan(rated, 30, "the gameplay clock barely ran, so this proves nothing")
        XCTAssertEqual(pulled / rated, 1.0, accuracy: 0.25,
                       "the magnet pulled at \(Int(pulled / rated * 100))% of its rated speed")
    }
}
