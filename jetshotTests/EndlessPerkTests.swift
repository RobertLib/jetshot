//
//  EndlessPerkTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The "choose an upgrade" stop an endless run makes after each boss, in a running
/// scene: it freezes the run, takes a real tap, applies the pick and lets the run go on.
@MainActor
final class EndlessPerkTests: XCTestCase {

    /// Waits for control, not just for the scene: the intro's entry animation ends in
    /// `startGame()`, which unpauses gameplay — and would do so behind a picker raised
    /// before it finished.
    private func startEndless(_ harness: GameplayHarness) {
        harness.startPlayingWithControl(endless: true)
    }

    func testThePickerFreezesTheRun() {
        let harness = GameplayHarness()
        startEndless(harness)
        defer { harness.teardown() }

        harness.scene.debugOfferPerks()
        harness.spin(0.3)

        XCTAssertTrue(harness.scene.isPerkPickerUp)
        XCTAssertTrue(harness.gameContent.isPaused, "the run kept going behind the picker")
        XCTAssertEqual(harness.scene.physicsWorld.speed, 0, accuracy: 0.001)
    }

    func testTappingACardTakesThatPerkAndResumes() throws {
        let harness = GameplayHarness()
        startEndless(harness)
        defer { harness.teardown() }

        harness.scene.debugOfferPerks()
        harness.spin(0.5) // let the cards slide in

        let centre = try XCTUnwrap(harness.scene.debugPerkCardCentre(0), "the picker showed no cards")
        harness.touchDown(at: centre)
        harness.touchUp(at: centre)
        harness.spin(1.0)

        XCTAssertFalse(harness.scene.isPerkPickerUp, "the picker stayed up after a pick")
        XCTAssertEqual(harness.scene.perkStacks.values.reduce(0, +), 1, "the pick was not applied exactly once")
        XCTAssertFalse(harness.gameContent.isPaused, "the run did not resume after the pick")
        XCTAssertEqual(harness.scene.physicsWorld.speed, 1.0, accuracy: 0.001)
    }

    /// The picker is modal: a tap that misses every card does nothing, and in particular
    /// the pause button underneath it cannot resume the frozen run.
    func testTheInRunPauseButtonCannotReachPastThePicker() throws {
        let harness = GameplayHarness()
        startEndless(harness)
        defer { harness.teardown() }

        harness.scene.debugOfferPerks()
        harness.spin(0.5)

        let pause = try XCTUnwrap(harness.node(named: "pauseButton"))
        let point = harness.scenePosition(of: pause)
        harness.touchDown(at: point)
        harness.touchUp(at: point)
        harness.spin(0.3)

        XCTAssertTrue(harness.scene.isPerkPickerUp, "a tap outside the cards dismissed the picker")
        XCTAssertTrue(harness.gameContent.isPaused, "the pause button reached the run behind the picker")
        XCTAssertNil(harness.node(named: "resumeButton"), "the pause menu opened over the picker")
    }
}
