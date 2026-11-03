//
//  ProgressRefreshTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The screens around the game catching up with progress an iCloud merge has changed
/// while they were up.
///
/// The menu and the level grid read stored progress once, as they are built. A merge
/// that landed afterwards — the first sync on a new device, seconds after launch — left
/// them showing the old state: no ENDLESS for a player with a campaign behind them, and
/// padlocks on levels they had cleared elsewhere. `CloudStorageManager` says so with
/// `.progressDidChange`; these post it the way it does, on the main thread, after
/// changing the progress underneath the screen.
@MainActor
final class ProgressRefreshTests: XCTestCase {

    // MARK: - Menu

    func testTheMenuOffersEndlessOnceAMergeHasClearedLevelOne() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let menu = MenuScene(size: harness.view.bounds.size)
            harness.present(menu, settle: 0.6)
            XCTAssertNil(menu.childNode(withName: "endlessButton"),
                         "a clean save already offered ENDLESS, so this proves nothing")

            LevelManager.shared.completeLevel(1, score: 5_000)
            _ = LevelManager.shared.recordEndlessRun(score: 58_210, round: 9)
            NotificationCenter.default.post(name: .progressDidChange, object: nil)

            XCTAssertNotNil(menu.childNode(withName: "endlessButton"),
                            "the menu still hid ENDLESS after a merge cleared level 1")
            XCTAssertNotNil(menu.childNode(withName: "endlessRecord"),
                            "the menu did not show the record the merge brought in")
        }
    }

    /// The settings panel shows no progress, so a refresh behind it leaves it open.
    func testTheSettingsPanelStaysOpenThroughARefresh() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let menu = MenuScene(size: harness.view.bounds.size)
            harness.present(menu, settle: 1.2)
            guard let settingsButton = menu.childNode(withName: "settingsButton") else {
                return XCTFail("the menu did not build SETTINGS")
            }
            tapDown(settingsButton, in: menu)
            guard let panel = menu.childNode(withName: SettingsOverlay.nodeName) else {
                return XCTFail("SETTINGS did not open, so this proves nothing")
            }

            LevelManager.shared.completeLevel(1, score: 5_000)
            NotificationCenter.default.post(name: .progressDidChange, object: nil)

            XCTAssertNotNil(menu.childNode(withName: "endlessButton"), "the menu was not refreshed")
            XCTAssertTrue(menu.childNode(withName: SettingsOverlay.nodeName) === panel,
                          "the refresh closed the settings panel under the player's finger")
        }
    }

    /// Once START has been chosen the menu is leaving, and is left as it is.
    func testAMenuOnItsWayOutIsNotRebuilt() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let menu = MenuScene(size: harness.view.bounds.size)
            harness.present(menu, settle: 1.2)
            guard let start = menu.childNode(withName: "startButton") else {
                return XCTFail("the menu did not build START")
            }
            tapDown(start, in: menu)

            LevelManager.shared.completeLevel(1, score: 5_000)
            NotificationCenter.default.post(name: .progressDidChange, object: nil)

            XCTAssertTrue(menu.childNode(withName: "startButton") === start,
                          "a menu already leaving for the level grid was rebuilt")
        }
    }

    /// A menu that has been replaced stops listening, rather than rebuilding itself off
    /// screen on every merge for as long as anything holds it.
    func testAMenuThatHasLeftStopsListening() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let menu = MenuScene(size: harness.view.bounds.size)
            harness.present(menu, settle: 0.3)
            harness.present(LevelSelectScene(size: harness.view.bounds.size), settle: 0.3)

            LevelManager.shared.completeLevel(1, score: 5_000)
            NotificationCenter.default.post(name: .progressDidChange, object: nil)

            XCTAssertTrue(menu.children.isEmpty, "a menu no longer on screen rebuilt itself")
        }
    }

    /// A merge that changes nothing the menu shows — a better score on a level already
    /// cleared — leaves it alone: a rebuild replays the stack's fade-in, which holds
    /// every button out of reach for half a second.
    func testAMergeThatChangesNothingShownLeavesTheMenuAlone() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 5_000)
            let menu = MenuScene(size: harness.view.bounds.size)
            harness.present(menu, settle: 1.2)
            guard let start = menu.childNode(withName: "startButton") else {
                return XCTFail("the menu did not build START")
            }

            LevelManager.shared.completeLevel(1, score: 9_000)
            NotificationCenter.default.post(name: .progressDidChange, object: nil)

            XCTAssertTrue(menu.childNode(withName: "startButton") === start,
                          "a merge that changed nothing on the menu rebuilt it anyway")
        }
    }

    // MARK: - Level select

    func testTheGridUnlocksWhatAMergeHasUnlocked() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let grid = LevelSelectScene(size: harness.view.bounds.size)
            harness.present(grid, settle: 1.2)
            XCTAssertNotNil(padlock(on: 2, in: grid), "level 2 was open on a clean save, so this proves nothing")

            LevelManager.shared.completeLevel(1, score: 5_000)
            NotificationCenter.default.post(name: .progressDidChange, object: nil)

            XCTAssertNotNil(grid.childNode(withName: "//levelButton_2"), "the refresh lost the page")
            XCTAssertNil(padlock(on: 2, in: grid), "level 2 stayed padlocked after a merge unlocked it")
        }
    }

    /// The refresh keeps the page the player is on.
    func testTheGridRefreshesOnThePageItIsOn() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let grid = LevelSelectScene(size: harness.view.bounds.size, startLevel: 25)
            harness.present(grid, settle: 1.2)

            LevelManager.shared.completeLevel(1, score: 5_000)
            NotificationCenter.default.post(name: .progressDidChange, object: nil)

            XCTAssertNotNil(grid.childNode(withName: "//levelButton_25"), "the refresh went back to the first page")
        }
    }

    /// The reset confirmation is not taken down mid-question; the grid catches up as soon
    /// as it has gone.
    func testAMergeUnderTheResetDialogWaitsForItToClose() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let grid = LevelSelectScene(size: harness.view.bounds.size)
            harness.present(grid, settle: 1.2)
            grid.debugShowResetDialog()
            harness.spin(0.4)
            guard let dialog = grid.childNode(withName: "confirmationDialog"),
                  let no = dialog.childNode(withName: "confirmNo") else {
                return XCTFail("the reset confirmation did not open")
            }

            LevelManager.shared.completeLevel(1, score: 5_000)
            NotificationCenter.default.post(name: .progressDidChange, object: nil)

            XCTAssertTrue(grid.childNode(withName: "confirmationDialog") === dialog,
                          "the refresh took the reset confirmation down mid-question")

            let point = dialog.convert(no.position, to: grid)
            grid.touchesBegan([HarnessTouch(point)], with: nil)
            grid.touchesEnded([HarnessTouch(point)], with: nil)
            harness.spin(0.5)

            XCTAssertNil(grid.childNode(withName: "confirmationDialog"), "NO did not close the dialog")
            XCTAssertNotNil(grid.childNode(withName: "//levelButton_2"), "the grid was not rebuilt")
            XCTAssertNil(padlock(on: 2, in: grid), "the grid never caught up once the dialog had gone")
        }
    }

    // MARK: - Helpers

    private func padlock(on level: Int, in scene: SKScene) -> SKNode? {
        scene.childNode(withName: "//levelButton_\(level)")?.childNode(withName: "padlock")
    }

    private func tapDown(_ node: SKNode, in scene: SKScene) {
        let point = node.parent?.convert(node.position, to: scene) ?? node.position
        scene.touchesBegan([HarnessTouch(point)], with: nil)
        scene.touchesEnded([HarnessTouch(point)], with: nil)
    }
}
