//
//  GameSceneLifecycleTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Smoke coverage for the scene lifecycle, which is where the riskiest edits live:
/// the removal of the duplicated `isBossActive` flag, the new `pruneEnemyCache()` on the
/// periodic tick, and the keyed invulnerability action. None of that is reachable from a
/// pure-function test, and all of it runs on every level start.
final class GameSceneLifecycleTests: XCTestCase {

    /// Presents a scene for real, so `didMove(to:)` and its deferred setup both run.
    @MainActor
    private func present(_ scene: SKScene, in view: SKView) {
        view.presentScene(scene)
        // didMove(to:) defers manager construction with DispatchQueue.main.async, so
        // the run loop has to turn before the scene is fully built.
        spinRunLoop(for: 0.6)
    }

    @MainActor
    private func spinRunLoop(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    @MainActor
    private func makeView() -> SKView {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        // A scene needs a window in the hierarchy before safeAreaInsets are meaningful,
        // which setupUI(view:) reads.
        let window = UIWindow(frame: view.frame)
        window.addSubview(view)
        window.isHidden = false
        return view
    }

    @MainActor
    func testLevelStartsWithoutCrashing() {
        let view = makeView()
        let scene = GameScene(size: view.bounds.size)
        scene.currentLevel = 1

        present(scene, in: view)

        XCTAssertNotNil(scene.gameContentNode, "gameplay layer was never built")
        XCTAssertEqual(scene.activeEnemyCount, 0, "enemies spawned before the level intro finished")
    }

    @MainActor
    func testUpdateTicksAreSafeBeforeAndAfterTheIntro() {
        let view = makeView()
        let scene = GameScene(size: view.bounds.size)
        scene.currentLevel = 3
        present(scene, in: view)

        // update(_:) receives absolute system time; feed it a plausible rising clock
        // including a large jump, which is what the maxFrameDelta clamp exists for.
        var now = Date().timeIntervalSinceReferenceDate
        for step in 0..<120 {
            now += (step == 60) ? 5.0 : 1.0 / 60.0
            scene.update(now)
        }
    }

    @MainActor
    func testMidLevelWeaponArsenalCarriesIn() {
        let view = makeView()
        let scene = GameScene(size: view.bounds.size)
        scene.currentLevel = 12
        scene.startingBulletCount = 5
        scene.startingSideMissileCount = 2

        present(scene, in: view)

        // Capped by GameConfiguration, and applied to the player during setup.
        let player = scene.gameContentNode?.childNode(withName: "player") as? Player
        XCTAssertNotNil(player, "player was not added to the gameplay layer")
        XCTAssertEqual(player?.bulletCount, 5)
        XCTAssertEqual(player?.sideMissileCount, min(2, GameConfiguration.maxSideMissileCount))
    }

    @MainActor
    func testTeardownReleasesTheScene() {
        // willMove(from:) does the real cleanup; if it leaves a strong reference behind
        // (a repeating action capturing self, a manager holding the scene) every level
        // played would stay in memory for the rest of the session.
        let view = makeView()

        weak var weakScene: GameScene?
        autoreleasepool {
            let scene = GameScene(size: view.bounds.size)
            scene.currentLevel = 7
            weakScene = scene
            present(scene, in: view)

            // Presenting another scene triggers willMove(from:) on the outgoing one.
            view.presentScene(MenuScene(size: view.bounds.size))
            spinRunLoop(for: 0.4)
        }
        spinRunLoop(for: 0.3)

        XCTAssertNil(weakScene, "GameScene survived teardown — every level would accumulate")
    }

    @MainActor
    func testEveryLevelCanBePresented() {
        // getLevelConfig(for:) is exercised for all 50 levels by LevelConfigTests, but
        // only as data. This walks a sample through real scene construction, where a
        // bad wave definition would surface as a crash in a manager instead.
        let view = makeView()

        for level in [1, 2, 10, 25, 40, GameConfiguration.totalLevels] {
            let scene = GameScene(size: view.bounds.size)
            scene.currentLevel = level
            present(scene, in: view)
            XCTAssertNotNil(scene.gameContentNode, "level \(level) failed to build")
        }

        view.presentScene(MenuScene(size: view.bounds.size))
        spinRunLoop(for: 0.3)
    }
}
