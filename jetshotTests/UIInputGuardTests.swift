//
//  UIInputGuardTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Taps that arrive when a screen should no longer be listening.
///
/// Two ways that happened. A screen that had already chosen a way out kept answering,
/// so a second tap could start a second transition — ENDLESS presented on touch-down
/// with nothing to stop the next one, and every other button was saved only because the
/// first transition happened to pause the second press animation (see `FilmUI.Exit`).
/// And the endless perk picker hit-tested its cards from the first frame, while they
/// were still invisible, so a thumb re-gripping the glass as the boss fell took a perk
/// nobody had seen.
@MainActor
final class UIInputGuardTests: XCTestCase {

    // MARK: - Leaving a screen

    /// START commits the menu to leaving: SETTINGS, tapped while START is still
    /// animating its press, must not open over a screen that is on its way out.
    func testOnceStartIsChosenTheMenuIgnoresTheNextTap() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let menu = MenuScene(size: harness.view.bounds.size)
            harness.present(menu, settle: 1.0)

            guard let start = menu.childNode(withName: "startButton"),
                  let settings = menu.childNode(withName: "settingsButton") else {
                return XCTFail("the menu did not build START and SETTINGS")
            }

            tapDown(start, in: menu)
            tapDown(settings, in: menu)
            harness.spin(0.05)

            XCTAssertNil(menu.childNode(withName: SettingsOverlay.nodeName),
                         "SETTINGS opened on a menu already leaving for the level grid")
        }
    }

    /// ENDLESS presents on touch-down with no press animation, so nothing at all used to
    /// stand between it and a second tap.
    func testOnceEndlessIsChosenTheMenuIgnoresTheNextTap() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 5_000)
            let menu = MenuScene(size: harness.view.bounds.size)
            harness.present(menu, settle: 1.0)

            guard let endless = menu.childNode(withName: "endlessButton"),
                  let settings = menu.childNode(withName: "settingsButton") else {
                return XCTFail("the menu did not build ENDLESS and SETTINGS")
            }

            tapDown(endless, in: menu)
            tapDown(endless, in: menu)
            tapDown(settings, in: menu)
            harness.spin(0.05)

            XCTAssertNil(menu.childNode(withName: SettingsOverlay.nodeName),
                         "the menu kept answering taps after ENDLESS had started a run")
        }
    }

    /// A results screen takes one way out. A second button tapped while the first is
    /// still pressing must not start a press — and with it a transition — of its own.
    func testAResultsScreenTakesOnlyOneWayOut() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let scene = GameOverScene(size: harness.view.bounds.size, score: 1_234, level: 3)
        // Long enough for the buttons' entrance: they are not tappable until revealed.
        harness.present(scene, settle: 2.0)

        guard let menu = scene.childNode(withName: "//menuButton"),
              let levels = scene.childNode(withName: "//levelsButton") else {
            return XCTFail("the game-over screen did not build its ways out")
        }

        tapDown(menu, in: scene)
        tapDown(levels, in: scene)
        harness.spin(0.06)

        XCTAssertLessThan(menu.xScale, 0.99, "MENU did not press, so the test proves nothing")
        XCTAssertEqual(levels.xScale, 1, accuracy: 0.001,
                       "LEVELS pressed as well, on a screen already leaving for the menu")
    }

    // MARK: - Perk picker

    /// A card answers only once it has finished arriving.
    func testAPerkCardStillArrivingCannotBeTaken() throws {
        let harness = GameplayHarness()
        harness.startPlayingWithControl(endless: true)
        defer { harness.teardown() }

        harness.scene.debugOfferPerks()
        harness.spin(0.05) // the picker is up; the first card has not started to arrive

        let centre = try XCTUnwrap(harness.scene.debugPerkCardCentre(0), "the picker showed no cards")
        harness.touchDown(at: centre)
        harness.touchUp(at: centre)
        // Comfortably past the 0.58s a pick takes to play out and apply, so a tap that
        // had been taken would show here rather than still be in flight.
        harness.spin(1.2)

        XCTAssertTrue(harness.scene.isPerkPickerUp, "a card was taken before it had appeared")
        XCTAssertEqual(harness.scene.perkStacks.values.reduce(0, +), 0, "a perk was applied from an invisible card")

        // Once it has arrived, the same tap takes it.
        harness.touchDown(at: centre)
        harness.touchUp(at: centre)
        harness.spin(1.0)

        XCTAssertFalse(harness.scene.isPerkPickerUp, "an arrived card did not answer a tap")
        XCTAssertEqual(harness.scene.perkStacks.values.reduce(0, +), 1, "the pick was not applied exactly once")
    }

    // MARK: - Helpers

    /// A touch landing on `node`'s centre. These screens act on touch-down.
    private func tapDown(_ node: SKNode, in scene: SKScene) {
        let point = node.parent?.convert(node.position, to: scene) ?? node.position
        scene.touchesBegan([HarnessTouch(point)], with: nil)
        scene.touchesEnded([HarnessTouch(point)], with: nil)
    }
}
