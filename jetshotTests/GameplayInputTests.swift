//
//  GameplayInputTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The loop the player actually drives: the intro handing over control, dragging the
/// ship, holding to fire, the fire rate, overheating, and pausing.
///
/// All of it runs through the real code path — `touchesBegan`/`touchesMoved` with real
/// touches, and `update(_:)` ticked by the SKView's own render loop rather than called by
/// hand, so the shooting cadence is timed by the same clock the game uses in play.
///
/// These tests each wait out the ~3 s level intro (`startPlayingWithControl`), because
/// that is what makes `isGameStarted` true. See `GameplayHarness` for why the intro needs
/// a nudge to complete in a test host at all.
final class GameplayInputTests: XCTestCase {

    // MARK: - Handing over control

    @MainActor
    func testIntroHandsOverControlAndStartsTheLevel() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        // startGame() unpauses gameplay and puts the ship at its resting position.
        XCTAssertEqual(harness.gameContent.isPaused, false, "gameplay is still paused after the intro")
        XCTAssertGreaterThan(harness.player.position.y, 0, "the ship never flew in")
        XCTAssertNotNil(harness.node(named: "pauseButton"), "the HUD has no pause button")
    }

    @MainActor
    func testEnemiesArriveOnceTheLevelIsRunning() {
        let harness = GameplayHarness()
        // The one test in the suite that wants the level to run itself, so the only one
        // that opts out of the harness's default suspension. See
        // `GameScene.isLevelProgressionSuspended`.
        harness.startPlayingWithControl(suspendLevelProgression: false)
        defer { harness.teardown() }

        // Waves are scheduled on gameContentNode's clock; nothing should spawn until the
        // level is actually running, and then it should.
        harness.spin(4.0)
        XCTAssertGreaterThan(
            harness.scene.activeEnemyCount, 0,
            "no enemy ever arrived, so the level could never be completed"
        )
    }

    // MARK: - Moving the ship

    @MainActor
    func testTouchMovesTheShipTowardTheFinger() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        let start = harness.player.position
        harness.touchDown(at: CGPoint(x: start.x + 120, y: start.y + 60))
        harness.spin(0.8) // moveTo is animated

        XCTAssertGreaterThan(
            harness.player.position.x, start.x,
            "the ship ignored the touch"
        )
    }

    @MainActor
    func testDragFollowsTheFinger() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.touchDown(at: harness.player.position)
        harness.spin(0.2)

        harness.drag(to: CGPoint(x: 60, y: 200))
        let afterLeft = harness.player.position.x

        harness.drag(to: CGPoint(x: 330, y: 200))
        let afterRight = harness.player.position.x

        XCTAssertLessThan(afterLeft, 150, "the ship did not follow the drag left (x=\(afterLeft))")
        XCTAssertGreaterThan(afterRight, afterLeft, "the ship did not follow the drag right")
        XCTAssertGreaterThan(afterRight, 250, "the ship lagged well behind the finger (x=\(afterRight))")
    }

    @MainActor
    func testShipStaysOnScreenWhenDraggedPastTheEdge() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        let size = harness.scene.size
        harness.touchDown(at: harness.player.position)

        for target in [CGPoint(x: -400, y: 300), CGPoint(x: size.width + 400, y: 300)] {
            harness.drag(to: target, duration: 0.25)
            XCTAssertTrue(
                (0...size.width).contains(harness.player.position.x),
                "dragging to \(target) put the ship off screen at x=\(harness.player.position.x)"
            )
        }
    }

    @MainActor
    func testTouchesDoNotMoveTheShipWhilePaused() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        // Resolve the ship before pausing and keep hold of it, so the assertion below is
        // about the same node either way.
        let ship = harness.player

        guard let pauseButton = harness.node(named: "pauseButton") else {
            return XCTFail("no pause button to tap")
        }
        harness.touchDown(at: harness.scenePosition(of: pauseButton))
        harness.spin(0.4)
        XCTAssertTrue(harness.gameContent.isPaused, "the pause button did not pause the game")

        // Somewhere on the playfield, well clear of the pause panel in the middle, so the
        // tap is a gameplay touch rather than a menu button or the dismiss background.
        let parked = ship.position
        harness.touchDown(at: CGPoint(x: parked.x + 120, y: 120))
        harness.spin(0.4)

        XCTAssertEqual(
            ship.position.x, parked.x, accuracy: 0.5,
            "the ship moved while the game was paused"
        )
    }

    // MARK: - Firing

    @MainActor
    func testHoldingOverTheShipFires() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        XCTAssertEqual(harness.bulletsInFlight, 0, "something was already firing")
        harness.holdFire(for: 1.0)

        XCTAssertGreaterThan(harness.bulletsInFlight, 0, "holding the trigger fired nothing")
    }

    @MainActor
    func testReleasingTheTouchStopsFire() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.holdFire(for: 0.8)
        XCTAssertGreaterThan(harness.bulletsInFlight, 0, "the guns never started")

        harness.touchUp(at: harness.player.position)
        harness.clearBullets()
        harness.spin(1.0)

        XCTAssertEqual(
            harness.bulletsInFlight, 0,
            "the guns kept firing after the finger came off the glass"
        )
    }

    @MainActor
    func testFireRateFollowsTheConfiguredInterval() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.holdFire(for: 1.2)
        let fired = harness.bulletsInFlight

        // One bullet per shootInterval, and bullets live 1.5 s so none have expired yet.
        // Generous bounds: this is guarding the order of magnitude, not the frame timing.
        let expected = 1.2 / GameConfiguration.defaultShootInterval // = 4
        XCTAssertGreaterThanOrEqual(
            Double(fired), expected * 0.5,
            "only \(fired) shots in 1.2 s — the guns are far slower than \(GameConfiguration.defaultShootInterval)s"
        )
        XCTAssertLessThanOrEqual(
            Double(fired), expected * 2.0,
            "\(fired) shots in 1.2 s — the fire-rate throttle is not holding"
        )
    }

    @MainActor
    func testRapidFireIsFasterThanNormalFire() {
        let normal = GameplayHarness()
        normal.startPlayingWithControl()
        normal.holdFire(for: 1.0)
        let normalShots = normal.bulletsInFlight
        normal.teardown()

        let rapid = GameplayHarness()
        rapid.startPlayingWithControl()
        rapid.player.hasRapidFire = true
        rapid.holdFire(for: 1.0)
        let rapidShots = rapid.bulletsInFlight
        rapid.teardown()

        XCTAssertGreaterThan(
            rapidShots, normalShots,
            "rapid fire (\(rapidShots)) was no faster than normal fire (\(normalShots))"
        )
    }

    @MainActor
    func testHoldingAwayFromTheShipDoesNotFire() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        // Establish that firing works at all from directly over the ship, so a silent
        // result below means the range gate fired — not that nothing ever shoots.
        harness.holdFire(for: 0.8)
        XCTAssertGreaterThan(harness.bulletsInFlight, 0, "the guns never fired from point blank")
        harness.touchUp(at: harness.player.position)
        harness.spin(0.3)

        // Now hold well off to the side. `touchesMoved` steers the ship instantly to the
        // finger, so hold *without* moving: touchesBegan sets touchLocation while
        // moveTo(x:) glides the ship over, and until it arrives the gap keeps the guns
        // shut. Assert only while the gap is genuinely out of range.
        let gate = GameConfiguration.shootDistanceThreshold
        let fingerX = harness.player.position.x + gate + 140
        harness.clearBullets()
        harness.touchDown(at: CGPoint(x: fingerX, y: harness.player.position.y))
        harness.spin(0.12)

        let gap = abs(harness.player.position.x - fingerX)
        try? XCTSkipIf(gap <= gate, "the ship closed the gap too quickly to observe the range gate")
        XCTAssertEqual(
            harness.bulletsInFlight, 0,
            "the guns fired while the finger was \(Int(gap))pt from the ship (gate is \(Int(gate))pt)"
        )
    }

    @MainActor
    func testMoreGunsMeanMoreBulletsPerVolley() {
        let single = GameplayHarness()
        single.startPlayingWithControl(bulletCount: 1)
        single.holdFire(for: 0.8)
        let singleShots = single.bulletsInFlight
        single.teardown()

        let quad = GameplayHarness()
        quad.startPlayingWithControl(bulletCount: 4)
        quad.holdFire(for: 0.8)
        let quadShots = quad.bulletsInFlight
        quad.teardown()

        XCTAssertGreaterThan(
            quadShots, singleShots,
            "a 4-gun loadout (\(quadShots)) put out no more fire than a single gun (\(singleShots))"
        )
    }

    // MARK: - Overheat

    @MainActor
    func testSustainedFireOverheatsAndSilencesTheGuns() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        // Rapid fire reaches the limit in about a quarter of the time it otherwise
        // would, which is what keeps this test short.
        harness.player.hasRapidFire = true
        harness.holdFire(for: 0.5)
        XCTAssertGreaterThan(
            harness.bulletsInFlight, 0,
            "the guns never fired at all, so a silent gauge later would prove nothing"
        )

        // Still holding the trigger throughout. If overheat works, the fire stops on its
        // own; if it does not, the poll runs out its timeout and this fails.
        XCTAssertTrue(
            harness.holdUntilGunsFallSilent(),
            "the guns never overheated — the gauge and its OVERHEATED state are dead weight"
        )
    }

    @MainActor
    func testGunsComeBackAfterTheOverheatCooldown() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.player.hasRapidFire = true
        XCTAssertTrue(
            harness.holdUntilGunsFallSilent(),
            "the guns did not overheat, so there is nothing to recover from"
        )

        // Let go and wait out the cooldown, then fire again.
        harness.touchUp(at: harness.player.position)
        harness.spin(GameConfiguration.overheatCooldownTime + 1.0)
        harness.clearBullets()
        harness.holdFire(for: 1.0)

        XCTAssertGreaterThan(
            harness.bulletsInFlight, 0,
            "the guns stayed dead after the overheat cooldown expired"
        )
    }

    // MARK: - Pause

    @MainActor
    func testPauseButtonPausesAndResumeRestoresGameplay() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        guard let pauseButton = harness.node(named: "pauseButton") else {
            return XCTFail("no pause button in the HUD")
        }

        harness.touchDown(at: harness.scenePosition(of: pauseButton))
        harness.spin(0.5)
        XCTAssertTrue(harness.gameContent.isPaused, "tapping pause did not stop gameplay")
        XCTAssertEqual(harness.scene.physicsWorld.speed, 0, "physics kept running while paused")

        guard let resumeButton = harness.node(named: "resumeButton") else {
            return XCTFail("the pause menu has no resume button, so the player is stuck")
        }
        harness.touchDown(at: harness.scenePosition(of: resumeButton))
        harness.spin(0.8)

        XCTAssertFalse(harness.gameContent.isPaused, "resume did not restart gameplay")
        XCTAssertEqual(harness.scene.physicsWorld.speed, 1.0, accuracy: 0.001, "physics stayed stopped after resume")
    }

    @MainActor
    func testPausingDoesNotStopTheGunsPermanently() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        _ = harness.player // resolve the ship up front, before any pausing

        guard let pauseButton = harness.node(named: "pauseButton") else {
            return XCTFail("no pause button")
        }
        harness.touchDown(at: harness.scenePosition(of: pauseButton))
        harness.spin(0.5)
        guard let resumeButton = harness.node(named: "resumeButton") else {
            return XCTFail("no resume button")
        }
        harness.touchDown(at: harness.scenePosition(of: resumeButton))
        harness.spin(0.8)
        XCTAssertFalse(harness.gameContent.isPaused, "resume did not take")

        // If an enemy reached the ship while the menu was up, the guns being silent would
        // say nothing about the pause round trip.
        try? XCTSkipUnless(harness.playerIsAlive, "the ship was destroyed before fire could be retested")

        harness.clearBullets()
        harness.holdFire(for: 1.0)
        XCTAssertGreaterThan(
            harness.bulletsInFlight, 0,
            "the guns never came back after a pause/resume round trip"
        )
    }

    /// The pause button has to survive being used. `hidePauseOverlay()` clears the names
    /// off the dismissed panel so its dead buttons stop answering to them, and it did
    /// that with `enumerateChildNodes(withName: "//*")` — whose `//` prefix searches from
    /// the root of the tree, not from the overlay. One pause/resume therefore stripped the
    /// name off every node in the scene, and since touch dispatch matches on names, the
    /// pause button went permanently dead after the first use.
    @MainActor
    func testPauseCanBeReopenedAfterResuming() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        guard let pauseButton = harness.node(named: "pauseButton") else {
            return XCTFail("no pause button in the HUD")
        }
        let pausePoint = harness.scenePosition(of: pauseButton)

        harness.touchDown(at: pausePoint)
        harness.spin(0.5)
        XCTAssertTrue(harness.gameContent.isPaused, "tapping pause did not stop gameplay")

        guard let resumeButton = harness.node(named: "resumeButton") else {
            return XCTFail("the pause menu has no resume button")
        }
        harness.touchDown(at: harness.scenePosition(of: resumeButton))
        // Long enough for the overlay's 0.4 s dismissal fade to finish, so this is the
        // steady state a player would tap in, not the window during the fade.
        harness.spin(0.9)
        XCTAssertFalse(harness.gameContent.isPaused, "resume did not restart gameplay")

        // Names the rest of the scene relies on must have survived the dismissal.
        XCTAssertNotNil(harness.node(named: "pauseButton"), "the pause button lost its name on resume")
        XCTAssertNotNil(harness.node(named: "player"), "the ship lost its name on resume")

        harness.touchDown(at: pausePoint)
        harness.spin(0.5)
        XCTAssertTrue(harness.gameContent.isPaused, "the game could not be paused a second time")
        XCTAssertNotNil(harness.node(named: "resumeButton"), "the pause menu did not come back")
    }

    /// A pause-menu button that cannot be *found* does nothing at all, silently: every
    /// handler wraps its real work in `if let button = ...`, so a failed lookup costs the
    /// press animation *and* the action. The lookups are subtle enough to get wrong twice
    /// over — the buttons are grandchildren of the overlay (overlay → panel → button), so
    /// a bare `childNode(withName:)` finds nothing because that form searches only
    /// immediate children, while the `//` form finds them by searching the entire scene
    /// from the root and merely happens to be right.
    ///
    /// SETTINGS is the one that proves the chain end to end without leaving the scene:
    /// the other four resume or present a different scene. Reaching the panel means the
    /// lookup resolved, the handler ran and its completion fired.
    @MainActor
    func testPauseMenuSettingsButtonOpensThePanel() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        guard let pauseButton = harness.node(named: "pauseButton") else {
            return XCTFail("no pause button in the HUD")
        }
        harness.touchDown(at: harness.scenePosition(of: pauseButton))
        harness.spin(0.5)
        XCTAssertTrue(harness.gameContent.isPaused, "tapping pause did not stop gameplay")

        guard let settingsButton = harness.node(named: "pauseSettingsButton") else {
            return XCTFail("the pause menu has no settings button")
        }
        harness.touchDown(at: harness.scenePosition(of: settingsButton))
        // The handler scales the button down and back up over 0.2 s and only then opens
        // the panel, so the assertion has to outlast that animation.
        harness.spin(0.6)

        XCTAssertNotNil(
            harness.node(named: SettingsOverlay.nodeName),
            "the settings panel never opened, so the pause menu's button lookup came back empty"
        )
        // Gameplay must still be frozen underneath it.
        XCTAssertTrue(harness.gameContent.isPaused, "opening settings resumed the game")
    }
}
