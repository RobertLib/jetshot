//
//  AppLifecyclePauseTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The app leaving the foreground mid-level should stop the game behind a pause menu,
/// and coming back should find it still stopped.
///
/// SpriteKit pauses and unpauses the whole scene on its own as the app resigns and
/// becomes active, and does so before `GameScene`'s observers run. The observers used to
/// read `gameContentNode.isPaused`, so the auto-pause saw "already paused" and raised no
/// menu, and the return saw "running" and carried on — a phone call or a trip to the home
/// screen handed the player back a live game with no warning.
@MainActor
final class AppLifecyclePauseTests: XCTestCase {

    private func pauseOverlays(in harness: GameplayHarness) -> Int {
        guard let ui = harness.node(named: "uiNode") else { return 0 }
        return ui.children.filter { $0.name == "pauseOverlay" }.count
    }

    func testLeavingTheForegroundPausesBehindTheMenuAndStaysPaused() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }
        XCTAssertFalse(harness.gameContent.isPaused, "the level never started running")

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        harness.spin(0.2)
        XCTAssertEqual(pauseOverlays(in: harness), 1, "leaving the foreground raised no pause menu")

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        harness.spin(0.3)
        XCTAssertTrue(harness.gameContent.isPaused, "the game came back from the background running")
        XCTAssertEqual(pauseOverlays(in: harness), 1, "the pause menu was lost on the way back")
    }

    /// SpriteKit unpauses the scene, every descendant with it, once more on its first frame
    /// back — after every lifecycle observer has run. That used to stick: the menu stayed
    /// up over a level running again underneath, and every tap went to the ship instead
    /// of the menu, so there was no way to resume, retry or leave.
    func testTheMenuStillAnswersAfterSpriteKitUnpausesOnTheFirstFrameBack() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        // Stand in for `-[SKView _update:]`, which unpauses the whole tree on the first
        // frame after the return; a posted notification does not reproduce it here.
        harness.gameContent.isPaused = false
        harness.spin(0.3)

        XCTAssertTrue(harness.gameContent.isPaused, "the game came back running behind the pause menu")
        XCTAssertEqual(harness.scene.physicsWorld.speed, 0, "physics came back running behind the pause menu")

        guard let resume = harness.node(named: "resumeButton") else {
            return XCTFail("the pause menu was lost on the way back")
        }
        harness.touchDown(at: harness.scenePosition(of: resume))
        harness.spin(0.8)

        XCTAssertFalse(harness.gameContent.isPaused, "RESUME did not resume the game")
        XCTAssertEqual(pauseOverlays(in: harness), 0, "the pause menu is still up after RESUME")
    }

    /// The intro asks for a pause as well, but its entry animation runs on the gameplay
    /// clock — re-asserting that pause on the way back would freeze the intro for good.
    func testComingBackDuringTheIntroLetsItFinish() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        // Stand in for SpriteKit unpausing the scene's descendants on the way back, which
        // a posted notification does not reliably reproduce here.
        harness.gameContent.isPaused = false
        harness.spin(4.0)

        XCTAssertFalse(harness.gameContent.isPaused, "the intro was frozen by the return to the foreground")
        XCTAssertGreaterThan(harness.player.position.y, 0, "the ship never flew in")
        XCTAssertEqual(pauseOverlays(in: harness), 0, "a pause menu was raised over the intro")
    }
}
