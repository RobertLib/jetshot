//
//  CameraShakeTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Pins the two properties of `GameScene.shakeCamera(intensity:duration:)` that are
/// invisible from inside the game.
///
/// The shake is built from *absolute* `SKAction.move(to:)` steps, so two shakes running
/// at once do not add up — they fight over the same position. Both failure modes below
/// look like "the shake is a bit off" on a device and nothing more, which is why they
/// are asserted here instead:
///
/// - An unkeyed `run` let them stack. `activateNuke` staggers its explosions 0.05 s
///   apart and every one calls `shakeCamera` with a 0.3 s shake, which put six to ten
///   sequences on the camera at once and came out as jitter.
/// - A bare `withKey:` fixes the stacking but lets the *last* caller always win, so one
///   small enemy popping during the boss defeat downgraded its 20-point shake to a
///   6-point one. Hence the intensity gate.
final class CameraShakeTests: XCTestCase {

    @MainActor
    private func makeView() -> SKView {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: view.frame)
        window.addSubview(view)
        window.isHidden = false
        return view
    }

    @MainActor
    private func presentGameScene() -> (view: SKView, scene: GameScene) {
        let view = makeView()
        let scene = GameScene(size: view.bounds.size)
        scene.currentLevel = 2
        view.presentScene(scene)
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return (view, scene)
    }

    /// Total duration of the sequence `shakeCamera` builds for a given `duration`:
    /// eight shake steps that split it, plus the 0.05 s return to centre.
    private func expectedSequenceDuration(for duration: TimeInterval) -> TimeInterval {
        return duration + 0.05
    }

    /// The camera has to pause with gameplay, like every other gameplay-timed node.
    ///
    /// It used to hang off the scene, which keeps ticking while the game is paused — the
    /// same bug `BackgroundParentingTests` covers for the background dressing. The
    /// symptom was a pause menu that rattled if you opened it during an explosion.
    @MainActor
    func testCameraLivesUnderTheGameplayLayer() {
        let (view, scene) = presentGameScene()
        defer { view.presentScene(MenuScene(size: view.bounds.size)) }

        guard let content = scene.gameContentNode else {
            return XCTFail("gameplay layer was never built")
        }
        guard let camera = scene.camera else {
            return XCTFail("no camera was installed")
        }

        XCTAssertTrue(camera.parent === content,
                      "the camera is not under gameContentNode — its shake would run through a pause")
        XCTAssertFalse(scene.children.contains(camera),
                       "the camera was parented straight to the scene")
    }

    /// Simultaneous shakes must resolve to a single action, not a pile of them.
    ///
    /// Asserted through the action key: without `withKey:` the lookup comes back nil and
    /// nothing stops the sequences from stacking.
    @MainActor
    func testShakesShareOneKeyedActionInsteadOfStacking() {
        let (view, scene) = presentGameScene()
        defer { view.presentScene(MenuScene(size: view.bounds.size)) }

        guard let camera = scene.camera else {
            return XCTFail("no camera was installed")
        }

        // A nuke's worth of same-intensity blasts arriving in one frame.
        for _ in 0..<10 {
            scene.shakeCamera(intensity: 8.0, duration: 0.3)
        }

        XCTAssertNotNil(camera.action(forKey: "cameraShake"),
                        "the shake is not keyed, so concurrent shakes stack and fight over the camera")
    }

    /// A weaker shake yields to a stronger one still playing; an equal or stronger one
    /// takes over.
    ///
    /// Clock-independent on purpose: no ticks run between the calls, so the sequence
    /// held under the key is compared by its total duration, which differs per shake.
    @MainActor
    func testWeakerShakeDoesNotCutAStrongerOneShort() {
        let (view, scene) = presentGameScene()
        defer { view.presentScene(MenuScene(size: view.bounds.size)) }

        guard let camera = scene.camera else {
            return XCTFail("no camera was installed")
        }

        // The boss defeat's big shake.
        scene.shakeCamera(intensity: 20.0, duration: 0.5)
        XCTAssertEqual(camera.action(forKey: "cameraShake")?.duration ?? -1,
                       expectedSequenceDuration(for: 0.5), accuracy: 0.001,
                       "the strong shake was never installed")

        // One small enemy popping must not replace it.
        scene.shakeCamera(intensity: 6.0, duration: 0.25)
        XCTAssertEqual(camera.action(forKey: "cameraShake")?.duration ?? -1,
                       expectedSequenceDuration(for: 0.5), accuracy: 0.001,
                       "a 6-point shake cut the boss's 20-point shake short")

        // An equal one may take over, which is what keeps a nuke shaking continuously.
        scene.shakeCamera(intensity: 20.0, duration: 0.2)
        XCTAssertEqual(camera.action(forKey: "cameraShake")?.duration ?? -1,
                       expectedSequenceDuration(for: 0.2), accuracy: 0.001,
                       "an equal-intensity shake failed to take over")

        // And so may a stronger one.
        scene.shakeCamera(intensity: 30.0, duration: 0.4)
        XCTAssertEqual(camera.action(forKey: "cameraShake")?.duration ?? -1,
                       expectedSequenceDuration(for: 0.4), accuracy: 0.001,
                       "a stronger shake failed to take over")
    }

    /// The symptom the parenting fix is actually for: a shake in flight when the player
    /// opens the pause menu must stop dead, not carry on rattling the menu.
    ///
    /// Asserted as *exact* position equality, which is deterministic rather than flaky:
    /// a paused node does not evaluate its actions at all, so the camera cannot move by
    /// even a fraction of a point. Parented to the scene it moved every frame.
    @MainActor
    func testAShakeInFlightFreezesWithThePauseMenu() {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl()
        defer { harness.teardown() }

        guard let camera = scene.camera else {
            return XCTFail("no camera was installed")
        }

        // Long and wide, so the shake is unmistakably mid-flight when the menu opens.
        scene.shakeCamera(intensity: 40.0, duration: 2.0)
        harness.spin(0.3)
        XCTAssertNotNil(camera.action(forKey: "cameraShake"), "the shake ended before the pause")

        guard let pauseButton = harness.node(named: "pauseButton") else {
            return XCTFail("no pause button")
        }
        harness.touchDown(at: harness.scenePosition(of: pauseButton))
        harness.spin(0.4)
        XCTAssertTrue(harness.gameContent.isPaused, "the pause never took, so this proves nothing")

        let frozenAt = camera.position
        harness.spin(0.6)

        XCTAssertEqual(camera.position.x, frozenAt.x, accuracy: 0.0001,
                       "the camera kept shaking behind the pause menu")
        XCTAssertEqual(camera.position.y, frozenAt.y, accuracy: 0.0001,
                       "the camera kept shaking behind the pause menu")
    }

    /// The gate must not latch. Once a shake has finished, the intensity it recorded is
    /// stale and the next shake — however weak — has to be allowed through.
    ///
    /// Driven through `GameplayHarness` rather than a bare presented scene, because this
    /// is the one case here that needs the shake to actually *advance*: `didMove(to:)`
    /// pauses gameplay for the level intro, and now that the camera hangs off
    /// `gameContentNode` its actions are frozen along with it until the intro hands over
    /// control. Which is the fix working — see `testCameraLivesUnderTheGameplayLayer`.
    @MainActor
    func testTheIntensityGateDoesNotLatchAfterAShakeEnds() {
        let harness = GameplayHarness()
        let scene = harness.startPlayingWithControl()
        defer { harness.teardown() }

        guard let camera = scene.camera else {
            return XCTFail("no camera was installed")
        }
        XCTAssertFalse(harness.gameContent.isPaused, "gameplay never started, so no shake can advance")

        scene.shakeCamera(intensity: 25.0, duration: 0.1)

        // Let it play out: 0.1 s of shake plus the 0.05 s return, with margin.
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline, camera.action(forKey: "cameraShake") != nil {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertNil(camera.action(forKey: "cameraShake"), "the shake never finished")

        scene.shakeCamera(intensity: 2.0, duration: 0.2)
        XCTAssertEqual(camera.action(forKey: "cameraShake")?.duration ?? -1,
                       expectedSequenceDuration(for: 0.2), accuracy: 0.001,
                       "the gate latched on a finished shake and locked out every weaker one after it")
    }
}
