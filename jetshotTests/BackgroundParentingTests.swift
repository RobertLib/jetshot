//
//  BackgroundParentingTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Pins the parenting of the background dressing and the resize path that depends on it.
///
/// Both are invisible from inside the game: the emitters render identically wherever they
/// hang, so the only symptom of getting it wrong is that they keep animating behind the
/// pause menu and quietly stop tracking the screen size. `GameScene.didChangeSize` looked
/// them up as immediate children of the *scene* while `didMove(to:)` parents them to
/// `gameContentNode`, and a name without a `//` prefix only matches immediate children —
/// so every lookup returned nil and the whole resize path was dead code.
final class BackgroundParentingTests: XCTestCase {

    @MainActor
    private func makeView() -> SKView {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: view.frame)
        window.addSubview(view)
        window.isHidden = false
        return view
    }

    @MainActor
    private func present(_ scene: SKScene, in view: SKView) {
        view.presentScene(scene)
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// The assumption the resize bug rested on, stated outright so it cannot drift back.
    @MainActor
    func testBareNameLookupDoesNotReachGrandchildren() {
        let scene = SKScene(size: CGSize(width: 100, height: 100))
        let container = SKNode()
        scene.addChild(container)
        let child = SKNode()
        child.name = "starfield"
        container.addChild(child)

        XCTAssertNil(scene.childNode(withName: "starfield"),
                     "a bare name matched a grandchild — the resize lookups would be fine as they were")
        XCTAssertNotNil(scene.childNode(withName: "//starfield"))
        XCTAssertNotNil(container.childNode(withName: "starfield"))
    }

    @MainActor
    func testGameplayBackgroundLivesUnderTheGameplayLayer() {
        let view = makeView()
        let scene = GameScene(size: view.bounds.size)
        scene.currentLevel = 4
        present(scene, in: view)

        guard let content = scene.gameContentNode else {
            return XCTFail("gameplay layer was never built")
        }

        // Everything the starfield helper produces has to be reachable from the layer
        // that setGameplayPaused(_:) actually pauses.
        for name in ["starfield", "shootingStars", "meteors", "starfieldFar", "starfieldMid",
                     "gradientBackground", "galaxy_0", "nebula_0"] {
            XCTAssertNotNil(content.childNode(withName: name),
                            "\(name) is not under gameContentNode — it would animate through a pause")
            XCTAssertNil(scene.childNode(withName: name),
                         "\(name) was parented straight to the scene")
        }

        view.presentScene(MenuScene(size: view.bounds.size))
    }

    @MainActor
    func testResizeRetargetsTheStarfieldToTheNewWidth() {
        let view = makeView()
        let scene = GameScene(size: view.bounds.size)
        scene.currentLevel = 2
        present(scene, in: view)

        guard let starfield = scene.gameContentNode?.childNode(withName: "starfield") as? SKEmitterNode else {
            return XCTFail("starfield emitter missing")
        }
        let originalRange = starfield.particlePositionRange.dx

        // A Split View / rotation style resize. didChangeSize is what has to notice.
        scene.size = CGSize(width: 700, height: 500)

        guard let resized = scene.gameContentNode?.childNode(withName: "starfield") as? SKEmitterNode else {
            return XCTFail("starfield emitter disappeared across the resize")
        }
        XCTAssertNotEqual(resized.particlePositionRange.dx, originalRange,
                          "the starfield kept the old screen width")
        XCTAssertEqual(resized.particlePositionRange.dx, 700, accuracy: 0.5)
        XCTAssertEqual(resized.position.y, 510, accuracy: 0.5,
                       "the spawn line was not moved to the new top edge")

        view.presentScene(MenuScene(size: view.bounds.size))
    }
}
