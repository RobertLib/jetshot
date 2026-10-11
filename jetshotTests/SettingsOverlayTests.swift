//
//  SettingsOverlayTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The settings panel opens over the button that opened it, so the second tap of a
/// double tap used to land on the panel as it was still scaling in — closing it again,
/// or flipping a switch nobody had seen.
@MainActor
final class SettingsOverlayTests: XCTestCase {

    /// In the menu, with ENDLESS still locked, SETTINGS sits right under the panel's CLOSE.
    func testADoubleTapOnSettingsLeavesThePanelOpen() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let menu = MenuScene(size: harness.view.bounds.size)
            harness.present(menu, settle: 1.0)

            guard let settings = menu.childNode(withName: "settingsButton") else {
                return XCTFail("the menu did not build SETTINGS")
            }
            let point = settings.position
            menu.touchesBegan([HarnessTouch(point)], with: nil)

            guard let overlay = menu.childNode(withName: SettingsOverlay.nodeName) else {
                return XCTFail("SETTINGS did not open the panel")
            }
            XCTAssertNotNil(FilmUI.button(at: point, under: overlay, names: ["settingsCloseButton"]),
                            "SETTINGS no longer sits under CLOSE, so this test proves nothing")

            harness.spin(0.1)
            menu.touchesBegan([HarnessTouch(point)], with: nil)
            harness.spin(0.4)

            XCTAssertNotNil(menu.childNode(withName: SettingsOverlay.nodeName),
                            "the second tap of a double tap closed the panel it had just opened")

            // Once it has opened, the same tap is CLOSE again: the grace delays the
            // panel's input, it does not lose it.
            menu.touchesBegan([HarnessTouch(point)], with: nil)
            harness.spin(0.4)
            XCTAssertNil(menu.childNode(withName: SettingsOverlay.nodeName),
                         "CLOSE did nothing once the panel had opened")
        }
    }

    /// In the pause menu SETTINGS sits by the HAPTICS row.
    func testARowTappedAsThePanelOpensDoesNotFlip() throws {
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        let overlay = SettingsOverlay(sceneSize: scene.size)
        scene.addChild(overlay)

        let row = try XCTUnwrap(overlay.childNode(withName: "//\(GameSetting.haptics.nodeName)"))
        let point = try XCTUnwrap(row.parent).convert(row.position, to: scene)

        let before = HapticManager.shared.isHapticsEnabled
        defer { HapticManager.shared.isHapticsEnabled = before }

        overlay.handleTap(at: point)
        XCTAssertEqual(HapticManager.shared.isHapticsEnabled, before,
                       "a tap as the panel opened flipped a switch")

        RunLoop.current.run(until: Date().addingTimeInterval(SettingsOverlay.openingGrace + 0.1))
        overlay.handleTap(at: point)
        XCTAssertNotEqual(HapticManager.shared.isHapticsEnabled, before,
                          "the row did not answer once the panel had opened")
    }
}
