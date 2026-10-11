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

        // The world behind the fight has to be reachable from the layer that
        // setGameplayPaused(_:) actually pauses.
        XCTAssertNotNil(content.childNode(withName: GameBackdrop.nodeName),
                        "the backdrop is not under gameContentNode — it would animate through a pause")
        XCTAssertNil(scene.childNode(withName: GameBackdrop.nodeName),
                     "the backdrop was parented straight to the scene")

        view.presentScene(MenuScene(size: view.bounds.size))
    }

    @MainActor
    func testResizeRetargetsTheBackdropToTheNewSize() {
        let view = makeView()
        let scene = GameScene(size: view.bounds.size)
        scene.currentLevel = 2
        present(scene, in: view)

        guard let backdrop = scene.gameContentNode?.childNode(withName: GameBackdrop.nodeName) as? GameBackdrop else {
            return XCTFail("backdrop missing")
        }
        XCTAssertEqual(backdrop.viewport.size, view.bounds.size)

        // A Split View / rotation style resize. didChangeSize is what has to notice.
        scene.size = CGSize(width: 700, height: 500)

        XCTAssertEqual(backdrop.viewport.width, 700, accuracy: 0.5, "the backdrop kept the old screen width")
        XCTAssertEqual(backdrop.viewport.height, 500, accuracy: 0.5, "the backdrop kept the old screen height")

        view.presentScene(MenuScene(size: view.bounds.size))
    }

    /// Fifty levels as ten sectors of five, each its own place on the film's route, and
    /// endless touring the same route.
    func testEverySectorOfTheCampaignIsItsOwnWorld() {
        let looks = stride(from: 1, through: 50, by: 5).map { BackdropLook.forLevel($0) }
        XCTAssertEqual(looks.count, 10)
        for (i, look) in looks.enumerated() {
            for j in (i + 1)..<looks.count {
                XCTAssertNotEqual(look, looks[j], "sectors \(i + 1) and \(j + 1) share a world")
            }
        }
        for level in 1...50 {
            let look = BackdropLook.forLevel(level)
            let first = BackdropLook.forLevel((level - 1) / 5 * 5 + 1)
            XCTAssertEqual(look.theme, first.theme, "level \(level) is not in its sector's world")
            XCTAssertEqual(look.variant, first.variant, "level \(level) is not in its sector's colouring")
        }
        XCTAssertEqual(BackdropLook.forEndlessRound(1), BackdropLook.forLevel(1))
    }

    /// Within a sector the world stays, but no two levels fly over the same thing:
    /// five levels of one unchanging picture is what made the campaign feel samey.
    func testNoTwoLevelsShareAStage() {
        let stages = (1...50).map { BackdropStage.of(BackdropLook.forLevel($0)) }
        for i in 0..<stages.count {
            for j in (i + 1)..<stages.count where BackdropLook.forLevel(i + 1).theme == BackdropLook.forLevel(j + 1).theme {
                XCTAssertNotEqual(stages[i], stages[j], "levels \(i + 1) and \(j + 1) look the same")
            }
        }
        for level in 1...50 {
            let stage = stages[level - 1]
            // Funnels cut their holes in a flat grid; they are not drawn into a shaped one.
            if stage.has(.funnels) {
                XCTAssertEqual(stage.ground, .flat, "level \(level) puts funnels in a shaped ground")
                XCTAssertFalse(stage.has(.shockwaves), "level \(level) rolls shock fronts through funnels")
            }
        }
    }
}
