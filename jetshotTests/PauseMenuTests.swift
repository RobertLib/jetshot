//
//  PauseMenuTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The pause menu's input rules, end to end through `touchesBegan`.
///
/// The menu is a letterboxed freeze-frame: the dimmed picture, the bars, the viewfinder
/// corners and a column of buttons. A tap anywhere off the column resumes; a tap on a
/// button runs that button once, however many times the finger lands during its press.
/// `GameplayInputTests` covers the buttons themselves.
@MainActor
final class PauseMenuTests: XCTestCase {

    /// Pauses through the HUD button and waits for the menu to settle: the viewfinder
    /// corners and the buttons fade in over the first ~0.75 s, and the corners are what
    /// used to swallow taps on the picture.
    private func pause(_ harness: GameplayHarness) {
        guard let pauseButton = harness.node(named: "pauseButton") else {
            return XCTFail("no pause button in the HUD")
        }
        harness.touchDown(at: harness.scenePosition(of: pauseButton))
        harness.spin(0.9)
        XCTAssertTrue(harness.gameContent.isPaused, "tapping pause did not stop gameplay")
    }

    private func overlays(in harness: GameplayHarness) -> Int {
        guard let ui = harness.node(named: "uiNode") else { return 0 }
        return ui.children.filter { $0.name == "pauseOverlay" || $0.name == "pauseOverlayFading" }.count
    }

    func testATapOnThePictureOffTheMenuResumes() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }
        pause(harness)

        // Left edge, half way up: inside the letterboxed picture, well clear of the
        // centred column.
        harness.touchDown(at: CGPoint(x: 14, y: harness.scene.size.height / 2))
        harness.spin(0.3)

        XCTAssertFalse(harness.gameContent.isPaused, "a tap on the dimmed picture did not resume")
    }

    /// The HUD pause button sits under the top letterbox bar while paused. A tap there
    /// is a tap outside the menu, and resumes through the same path as any other.
    func testATapOnTheTopBarResumes() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }
        guard let pauseButton = harness.node(named: "pauseButton") else {
            return XCTFail("no pause button in the HUD")
        }
        let hidden = harness.scenePosition(of: pauseButton)
        pause(harness)

        harness.touchDown(at: hidden)
        harness.spin(0.6)

        XCTAssertFalse(harness.gameContent.isPaused, "a tap on the letterbox bar did not resume")
        XCTAssertNil(harness.node(named: "resumeButton"), "the pause menu is still up")
    }

    /// Between two buttons is still the menu: a near miss must not throw the player
    /// back into the fight.
    func testATapBetweenButtonsDoesNothing() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }
        pause(harness)

        guard let resume = harness.node(named: "resumeButton"),
              let retry = harness.node(named: "pauseRetryButton") else {
            return XCTFail("the pause menu is missing its buttons")
        }
        let a = harness.scenePosition(of: resume), b = harness.scenePosition(of: retry)
        harness.touchDown(at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
        harness.spin(0.3)

        XCTAssertTrue(harness.gameContent.isPaused, "a tap between two buttons resumed the game")
        XCTAssertNotNil(harness.node(named: "resumeButton"), "a tap between two buttons closed the menu")
    }

    /// Each button's action runs from its press animation's completion. A second tap
    /// inside that window used to run a second action — for RESUME, a toggle straight
    /// back into pause.
    func testDoubleTappingResumeLeavesTheGameRunning() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }
        pause(harness)

        guard let resume = harness.node(named: "resumeButton") else {
            return XCTFail("the pause menu has no resume button")
        }
        let point = harness.scenePosition(of: resume)
        harness.touchDown(at: point)
        harness.touchDown(at: point)
        harness.spin(0.8)

        XCTAssertFalse(harness.gameContent.isPaused, "the second tap on RESUME paused the game again")
        XCTAssertNil(harness.node(named: "resumeButton"), "a pause menu came back after RESUME")
    }

    /// A tap on the picture during a button's press must not slip in a resume of its
    /// own either — after RESUME that is the same double toggle by another route.
    func testATapOutsideDuringAPressIsIgnored() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }
        pause(harness)

        guard let resume = harness.node(named: "resumeButton") else {
            return XCTFail("the pause menu has no resume button")
        }
        harness.touchDown(at: harness.scenePosition(of: resume))
        harness.touchDown(at: CGPoint(x: 14, y: harness.scene.size.height / 2))
        harness.spin(0.8)

        XCTAssertFalse(harness.gameContent.isPaused, "a tap outside during RESUME's press paused the game again")
    }

    /// Re-pausing while the last menu is still fading out has to replace it, not stack a
    /// second dim layer on top of it.
    func testPausingAgainDuringTheDismissalLeavesOneOverlay() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }
        pause(harness)

        guard let resume = harness.node(named: "resumeButton"),
              let pauseButton = harness.node(named: "pauseButton") else {
            return XCTFail("the pause menu or the pause button is missing")
        }
        harness.touchDown(at: harness.scenePosition(of: resume))
        // Past the 0.17 s press, inside the 0.4 s dismissal fade.
        harness.spin(0.3)
        XCTAssertFalse(harness.gameContent.isPaused, "RESUME did not resume")

        harness.touchDown(at: harness.scenePosition(of: pauseButton))
        harness.spin(0.05)

        XCTAssertTrue(harness.gameContent.isPaused, "the game could not be paused again")
        XCTAssertEqual(overlays(in: harness), 1, "a fresh pause menu was stacked on the fading one")
    }
}
