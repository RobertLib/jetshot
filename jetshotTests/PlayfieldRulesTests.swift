//
//  PlayfieldRulesTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Rules of the running scene that were each written down in a comment and not kept by
/// the code: lightning that strikes "every enemy on screen", SLOW MO that slows the
/// whole hostile side, a magnet that pulls only coins still to be collected, a camera
/// that stays centred through a resize, and a HUD score that prints like every other.
@MainActor
final class PlayfieldRulesTests: XCTestCase {

    // MARK: - Lightning

    /// Enemies are spawned 50 pt above the top edge, and formations fly in from there.
    /// Lightning used to strike everything in the tree, so ships that had not appeared
    /// yet died out of sight and paid out.
    func testLightningStrikesOnlyWhatIsOnScreen() {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl()
        defer { harness.teardown() }

        let size = scene.size
        let visible = harness.addEnemy(.basic, at: CGPoint(x: 120, y: size.height * 0.6))
        let incoming = harness.addEnemy(.basic, at: CGPoint(x: 260, y: size.height + 50))
        scene.debugActivatePowerUp(.lightning)
        let before = scene.currentScore

        harness.holdFire(for: 0.15)
        harness.touchUp(at: harness.player.position)
        harness.spin(0.1)

        XCTAssertNil(visible.parent, "the lightning missed the enemy on screen, so this test proves nothing")
        XCTAssertNotNil(incoming.parent, "the lightning struck an enemy that had not appeared yet")
        // Not exact: a shard or two from the kill may already have reached the ship.
        XCTAssertLessThan(scene.currentScore - before, 2 * EnemyType.basic.points,
                          "the lightning paid for more than the one enemy on screen")
    }

    // MARK: - Slow motion

    /// SLOW MO used to slow what was on screen and nothing else: the waves kept coming at
    /// the full rate, so the playfield filled twice as densely, and the walls and spinners
    /// — which fly on actions like the asteroids — kept their full speed.
    func testSlowMotionSlowsTheSpawnersAndTheObstacles() {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl()
        defer { harness.teardown() }

        // Out at the side, clear of the ship for as long as the test runs.
        let wall = Obstacle(type: .wall, sceneSize: scene.size,
                            position: CGPoint(x: 40, y: scene.size.height - 80))
        harness.gameContent.addChild(wall)

        scene.debugActivatePowerUp(.slowMotion)
        harness.spin(0.2)
        XCTAssertTrue(harness.player.hasSlowMotion)
        XCTAssertEqual(wall.speed, 0.5, accuracy: 0.001, "SLOW MO left a wall at full speed")

        let clock = scene.gameplayClock
        let spawner = scene.spawnerClock
        harness.spin(0.8)
        let elapsed = scene.gameplayClock - clock
        XCTAssertGreaterThan(elapsed, 0.3, "the gameplay clock barely ran, so this proves nothing")
        XCTAssertEqual((scene.spawnerClock - spawner) / elapsed, 0.5, accuracy: 0.05,
                       "the spawners did not slow with SLOW MO")

        // Run the real expiry out faster, as `MirrorSlowMotionTests` does.
        harness.gameContent.speed = 10
        let deadline = Date().addingTimeInterval(2)
        while harness.player.hasSlowMotion && Date() < deadline {
            harness.spin(0.02)
        }
        harness.gameContent.speed = 1
        XCTAssertFalse(harness.player.hasSlowMotion, "the scheduled expiry never fired")
        XCTAssertEqual(wall.speed, 1, accuracy: 0.001, "the wall stayed slowed after SLOW MO ended")

        let clockAfter = scene.gameplayClock
        let spawnerAfter = scene.spawnerClock
        harness.spin(0.5)
        XCTAssertEqual(scene.spawnerClock - spawnerAfter, scene.gameplayClock - clockAfter, accuracy: 0.001,
                       "the spawners stayed slowed after SLOW MO ended")
    }

    // MARK: - Magnet

    /// A collected coin flies to the score for 0.4 s, still in the scene and in the
    /// magnet's cache, and the magnet went on pulling it towards the ship.
    func testTheMagnetLeavesACollectedCoinToItsFlight() {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl()
        defer { harness.teardown() }

        let player = harness.player
        player.position = CGPoint(x: 80, y: 300)
        scene.debugActivatePowerUp(.magnet)

        // Level with the ship, well inside the magnet's reach, and flown straight up: any
        // pull towards the ship shows as sideways drift.
        let start = CGPoint(x: 230, y: 300)
        let coin = Coin(position: start)
        harness.gameContent.addChild(coin)
        scene.registerCoin(coin)
        coin.collect(scorePosition: CGPoint(x: start.x, y: 800))
        harness.spin(0.25)

        XCTAssertNotNil(coin.parent, "the coin's flight ended before it could be measured")
        XCTAssertEqual(coin.position.x, start.x, accuracy: 1, "the magnet pulled a collected coin off its flight")
    }

    // MARK: - Camera

    /// The shake's last step is an absolute move back to the centre it was started
    /// with. A resize mid-shake re-centred the camera and then let the shake carry on
    /// and land it back on the old centre.
    func testAResizeMidShakeLeavesTheCameraCentred() {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl()
        defer { harness.teardown() }

        let oldSize = scene.size
        scene.shakeCamera(intensity: 20, duration: 1.0)
        harness.spin(0.1)

        harness.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        harness.view.layoutIfNeeded()
        harness.spin(1.3)

        XCTAssertNotEqual(scene.size, oldSize, "the scene never resized, so this test proves nothing")
        guard let camera = scene.camera else { return XCTFail("the scene has no camera") }
        XCTAssertEqual(camera.position.x, scene.size.width / 2, accuracy: 0.5, "the camera ended off centre")
        XCTAssertEqual(camera.position.y, scene.size.height / 2, accuracy: 0.5, "the camera ended off centre")
    }

    // MARK: - HUD score

    /// The results, level select and pause menu all print the score grouped; the HUD
    /// printed bare digits.
    func testTheHUDScoreIsDigitGrouped() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        defer { harness.teardown() }

        scene.addScore(1_234_567, chainsCombo: false)
        let expected = scene.currentScore.formatted()
        XCTAssertGreaterThan(expected.count, String(scene.currentScore).count,
                             "this locale groups nothing, so this test proves nothing")

        var found = false
        scene.enumerateChildNodes(withName: "//*") { node, stop in
            if let label = node as? SKLabelNode, label.text == expected {
                found = true
                stop.pointee = true
            }
        }
        XCTAssertTrue(found, "the HUD does not show the score as \(expected)")
    }
}
