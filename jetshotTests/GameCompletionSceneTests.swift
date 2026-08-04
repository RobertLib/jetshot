//
//  GameCompletionSceneTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Covers the victory screen, which shipped unreachable.
///
/// `didMove(to:)` used to present the ending crawl and return without ever building
/// itself, and the only call to `setupUI()` sat behind an `isInitialized` flag nothing
/// set — so the trophy, the total score and all three buttons never rendered. The crawl
/// now plays first (`LevelCompleteScene` -> `StoryScene(.ending)`) and this is where it
/// lands.
final class GameCompletionSceneTests: XCTestCase {

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
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    @MainActor
    func testVictoryScreenBuildsItsUI() {
        let view = makeView()
        let scene = GameCompletionScene(size: view.bounds.size, totalScore: 123_456)
        present(scene, in: view)

        // It must build itself rather than forwarding somewhere else.
        XCTAssertTrue(view.scene === scene, "the victory screen navigated away instead of rendering")

        // Every exit has to be present, or the player is stranded on a dead screen.
        for button in ["playAgainButton", "levelsButton", "menuButton"] {
            XCTAssertNotNil(scene.childNode(withName: "//\(button)"),
                            "\(button) is missing — the screen has no way out")
        }

        view.presentScene(MenuScene(size: view.bounds.size))
    }

    @MainActor
    func testVictoryScreenShowsTheTotalScore() {
        let view = makeView()
        let total = 987_654
        let scene = GameCompletionScene(size: view.bounds.size, totalScore: total)
        present(scene, in: view)

        // The total was previously computed, passed in, and then thrown away unrendered.
        var found = false
        scene.enumerateChildNodes(withName: "//*") { node, stop in
            if let label = node as? SKLabelNode, label.text?.contains("\(total)") == true {
                found = true
                stop.pointee = true
            }
        }
        XCTAssertTrue(found, "the total score never made it onto the screen")

        view.presentScene(MenuScene(size: view.bounds.size))
    }

    @MainActor
    func testResizeRebuildsInsteadOfGoingBlank() {
        // didChangeSize wipes every child and rebuilds; it is gated on isInitialized,
        // which didMove(to:) now actually sets.
        let view = makeView()
        let scene = GameCompletionScene(size: view.bounds.size, totalScore: 42)
        present(scene, in: view)

        scene.size = CGSize(width: 700, height: 500)

        XCTAssertNotNil(scene.childNode(withName: "//playAgainButton"),
                        "the screen went blank after a resize")

        view.presentScene(MenuScene(size: view.bounds.size))
    }
}
