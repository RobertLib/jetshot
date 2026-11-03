//
//  GameViewControllerTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// How the game comes up: the first scene, and the screen edge it shares with play.
@MainActor
final class GameViewControllerTests: XCTestCase {

    /// The first scene used to be built in `viewDidLoad()`, at the storyboard's 375×667
    /// and with no window to read safe-area insets from, so every screen laid out for
    /// it was laid out for the wrong one.
    func testTheFirstSceneIsBuiltForTheRealScreen() throws {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: GameViewController.self))
        let controller = try XCTUnwrap(storyboard.instantiateInitialViewController() as? GameViewController)
        let view = try XCTUnwrap(controller.view as? SKView)
        XCTAssertNil(view.scene, "a scene was built before the view had a screen to fit")

        let size = CGSize(width: 402, height: 874)
        let windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = windowScene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            view.presentScene(nil)
            window.isHidden = true
        }
        window.layoutIfNeeded()

        let scene = try XCTUnwrap(view.scene, "no scene once the view was laid out in its window")
        XCTAssertTrue(scene is MenuScene)
        XCTAssertEqual(scene.size, size, "the first scene was not built at the window's size")

        // Once only: a later layout pass leaves the scene alone.
        view.setNeedsLayout()
        window.layoutIfNeeded()
        XCTAssertTrue(view.scene === scene, "a second layout pass replaced the first scene")
    }

    /// The ship flies near the bottom edge, so a drag there should not leave the game on
    /// the first swipe.
    func testTheBottomEdgeBelongsToTheGameFirst() {
        let controller = GameViewController()
        XCTAssertEqual(controller.preferredScreenEdgesDeferringSystemGestures, .bottom)
        XCTAssertTrue(controller.prefersHomeIndicatorAutoHidden)
    }
}
