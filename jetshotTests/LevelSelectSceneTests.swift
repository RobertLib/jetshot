//
//  LevelSelectSceneTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The level grid is how every level is entered, and it had no coverage at all.
///
/// Its page arithmetic is the fragile part: `loadPage` iterates `startLevel...endLevel`,
/// and a `Range` whose bounds cross traps rather than yielding nothing — so a page past
/// the end of the grid is a crash, not an empty screen. Every caller derives the starting
/// page from a level number it read back from stored progress, which is the same
/// "saved level outruns totalLevels" case `LevelManager` already defends elsewhere.
///
/// Buttons are named `levelButton_<n>`, which is what makes the grid observable here.
@MainActor
final class LevelSelectSceneTests: XCTestCase {

    /// Two sectors of five. Read from the scene rather than restated, so the page
    /// arithmetic below follows it if a page is ever cut differently.
    private let levelsPerPage = LevelSelectScene.levelsPerPage

    private func presentGrid(_ harness: GameplayHarness, startLevel: Int? = nil) -> LevelSelectScene {
        let scene = LevelSelectScene(size: harness.view.bounds.size, startLevel: startLevel)
        // Long enough for the staggered per-button entrance animation to have run.
        harness.present(scene, settle: 1.2)
        return scene
    }

    private func button(_ level: Int, in scene: SKScene) -> SKNode? {
        return scene.childNode(withName: "//levelButton_\(level)")
    }

    // MARK: - Page arithmetic

    func testTheFirstPageShowsTheFirstTwoSectors() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let scene = presentGrid(harness)

            for level in 1...levelsPerPage {
                XCTAssertNotNil(button(level, in: scene), "level \(level) is missing from the first page")
            }
            XCTAssertNil(button(levelsPerPage + 1, in: scene), "the first page spilled past its \(levelsPerPage) levels")
        }
    }

    /// Walks every page the grid claims to have, so no arm of the arithmetic goes unvisited.
    func testEveryPageIsReachableAndShowsItsOwnLevels() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let totalLevels = GameConfiguration.totalLevels
            let totalPages = (totalLevels + levelsPerPage - 1) / levelsPerPage

            for page in 0..<totalPages {
                let firstOnPage = page * levelsPerPage + 1
                let lastOnPage = min(firstOnPage + levelsPerPage - 1, totalLevels)

                let scene = presentGrid(harness, startLevel: firstOnPage)

                XCTAssertNotNil(
                    button(firstOnPage, in: scene),
                    "page \(page) does not show its first level (\(firstOnPage))"
                )
                XCTAssertNotNil(
                    button(lastOnPage, in: scene),
                    "page \(page) does not show its last level (\(lastOnPage))"
                )
            }
        }
    }

    /// The final page must stop at the last real level rather than rendering buttons for
    /// levels that do not exist.
    func testTheLastPageStopsAtTheFinalLevel() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let totalLevels = GameConfiguration.totalLevels
            let scene = presentGrid(harness, startLevel: totalLevels)

            XCTAssertNotNil(button(totalLevels, in: scene), "the last page is missing level \(totalLevels)")
            XCTAssertNil(
                button(totalLevels + 1, in: scene),
                "the grid rendered a button for level \(totalLevels + 1), which does not exist"
            )
        }
    }

    /// The regression this file exists for. A start level past the end of the grid used to
    /// put `currentPage` beyond the last page, and `loadPage` then trapped with
    /// "Range requires lowerBound <= upperBound" — `startLevel: 61` was enough.
    func testAStartLevelPastTheEndOfTheGridStillOpens() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            for startLevel in [
                GameConfiguration.totalLevels + 1,
                GameConfiguration.totalLevels + 11,
                61,
                999,
                Int.max / 2
            ] {
                let scene = presentGrid(harness, startLevel: startLevel)

                XCTAssertNotNil(
                    button(GameConfiguration.totalLevels, in: scene),
                    "startLevel \(startLevel) did not fall back to the last page"
                )
            }
        }
    }

    func testNonPositiveStartLevelsOpenTheFirstPage() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            for startLevel in [0, -1, -999] {
                let scene = presentGrid(harness, startLevel: startLevel)
                XCTAssertNotNil(button(1, in: scene), "startLevel \(startLevel) did not open the first page")
            }
        }
    }

    /// The departing page used to remove a pressed tile before its callback could
    /// launch the level, leaving the scene committed to an exit that never happened.
    func testTappingAnOutgoingUnlockedTileLeavesInputWorkingAfterPaging() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            for level in 1...20 {
                LevelManager.shared.completeLevel(level, score: 100)
            }
            let scene = presentGrid(harness)
            guard let outgoing = button(5, in: scene) else { return XCTFail("level 5 is missing") }

            swipeForward(in: scene)
            harness.spin(0.12)
            XCTAssertNotNil(outgoing.parent, "the test missed the departing page")
            tap(outgoing, in: scene)
            harness.spin(0.8)

            XCTAssertNil(outgoing.parent, "paging did not replace the old tiles")
            XCTAssertNotNil(button(11, in: scene))
            swipeForward(in: scene)
            harness.spin(0.8)
            guard let next = button(21, in: scene) else {
                return XCTFail("the outgoing tile's tap left paging permanently blocked")
            }

            tap(next, in: scene)
            harness.spin(0.08)
            XCTAssertLessThan(next.xScale, 0.99, "a settled page no longer accepts level selection")
            harness.spin(0.4)
        }
    }

    /// The incoming page still moves after its number has changed. A second swipe
    /// during that slide must not start another transition over it.
    func testAnotherSwipeWaitsUntilTheIncomingPageHasSettled() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let scene = presentGrid(harness)
            swipeForward(in: scene)
            let deadline = Date().addingTimeInterval(2)
            while button(11, in: scene) == nil && Date() < deadline {
                harness.spin(0.02)
            }
            XCTAssertNotNil(button(11, in: scene), "the incoming page has not arrived")

            swipeForward(in: scene)
            harness.spin(0.8)
            XCTAssertNotNil(button(11, in: scene), "a second swipe replaced a page still arriving")
            XCTAssertNil(button(21, in: scene))

            swipeForward(in: scene)
            harness.spin(0.8)
            XCTAssertNotNil(button(21, in: scene), "paging did not resume after the slide")
        }
    }

    /// A resize removes the moving page and its completion action. The new grid must
    /// answer input even though that old completion will never mark the slide finished.
    func testResizingDuringPagingLeavesTheRebuiltGridInteractive() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let scene = presentGrid(harness)
            swipeForward(in: scene)
            harness.spin(0.12)
            scene.size = CGSize(width: scene.size.width + 1, height: scene.size.height)
            harness.spin(1.2)

            XCTAssertNotNil(button(1, in: scene), "the rebuilt grid did not keep its current page")
            swipeForward(in: scene)
            harness.spin(0.8)
            XCTAssertNotNil(button(11, in: scene), "the rebuilt grid stayed locked on the canceled slide")
        }
    }

    // MARK: - Lock state

    /// The two branches of `handleLevelTap` are told apart by the feedback they animate,
    /// not by the scene that follows: unlocked runs a scale press and then `startLevel`,
    /// locked runs a rotation shake and nothing else.
    ///
    /// `startLevel` presents with an `SKTransition`, and a transition never completes in a
    /// unit-test host — `view.scene` keeps reporting the level select forever (see the
    /// comment on `GameplayHarness`). So the assertion is on the branch actually taken,
    /// which is where this scene's own logic lives: the name parsing in `handleTap` and
    /// the `isLevelUnlocked` check.
    ///
    /// This case and the next tap the *same* button, level 5 on the first page, and differ
    /// only in the stored progress — so a failure cannot be blamed on hit-testing.
    func testTappingALockedLevelOnlyShakesIt() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let scene = presentGrid(harness)
            XCTAssertFalse(
                LevelManager.shared.isLevelUnlocked(5),
                "level 5 should be locked on a fresh install"
            )

            guard let locked = button(5, in: scene) else {
                return XCTFail("level 5 is missing from the grid")
            }

            tap(locked, in: scene)
            harness.spin(0.08) // mid-shake; the sequence returns to zero by 0.3s

            XCTAssertGreaterThan(
                abs(locked.zRotation), 0.001,
                "a locked level gave no rejection feedback, so the tap never reached handleLevelTap"
            )
            XCTAssertEqual(
                locked.xScale, 1.0, accuracy: 0.01,
                "a locked level ran the *press* animation, so it was treated as unlocked"
            )
        }
    }

    func testTappingAnUnlockedLevelPressesItAndLeaves() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            for level in 1...4 {
                LevelManager.shared.completeLevel(level, score: 100)
            }

            let scene = presentGrid(harness)
            XCTAssertTrue(
                LevelManager.shared.isLevelUnlocked(5),
                "level 5 should be unlocked after clearing 1-4"
            )

            guard let unlocked = button(5, in: scene) else {
                return XCTFail("level 5 is missing from the grid")
            }

            tap(unlocked, in: scene)
            harness.spin(0.08) // mid-press; scaleDown runs to 0.9 over 0.1s

            XCTAssertLessThan(
                unlocked.xScale, 0.99,
                "an unlocked level did not run its press animation, so startLevel was never reached"
            )
            XCTAssertEqual(
                unlocked.zRotation, 0.0, accuracy: 0.001,
                "an unlocked level ran the locked *shake*, so it was treated as locked"
            )

            // Let the press finish so `startLevel` actually runs, which is also the only
            // thing that exercises its arsenal lookup for the level below.
            harness.spin(0.4)
        }
    }

    /// A second tap mid-refusal used to read the padlock's colour while the first flash
    /// still had it red, and restore *that* — so a quick double-tap left it red for good.
    func testRepeatedTapsOnALockedTileLeaveItsPadlockAtRest() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let scene = presentGrid(harness)
            guard let locked = button(5, in: scene),
                  let padlock = locked.childNode(withName: "padlock") as? SKShapeNode else {
                return XCTFail("level 5 is missing, or has no padlock")
            }
            let rest = rgba(padlock.strokeColor)

            tap(locked, in: scene)
            harness.spin(0.1)
            tap(locked, in: scene)
            harness.spin(0.8)

            let after = rgba(padlock.strokeColor)
            for (channel, (a, b)) in zip(["red", "green", "blue", "alpha"], zip(rest, after)) {
                XCTAssertEqual(a, b, accuracy: 0.01, "the padlock's \(channel) did not return to rest after two quick taps")
            }
            XCTAssertEqual(locked.zRotation, 0, accuracy: 0.001, "the refusal shake did not settle back to level")
        }
    }

    // MARK: - Reset confirmation

    /// The dialog owns every touch until it has *gone*, not just until it starts to fade.
    /// Dismissing used to switch it off at once while it stayed on screen for 0.2s, and
    /// the grid behind is hit-tested through any scrim — so the second tap of a
    /// double-tap on NO started the level under the button, and a swipe paged the grid.
    func testTheResetDialogStaysModalUntilItHasGone() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            for level in 1...6 {
                LevelManager.shared.completeLevel(level, score: 100)
            }
            let scene = presentGrid(harness)
            scene.debugShowResetDialog()
            harness.spin(0.4)

            guard let no = scene.childNode(withName: "//confirmNo"),
                  let open = button(7, in: scene),
                  let locked = button(9, in: scene) else {
                return XCTFail("the dialog or the tiles under it did not build")
            }

            tap(no, in: scene)

            // Mid-fade: an unlocked tile, a locked one and a swipe all have to be ignored.
            tap(open, in: scene)
            tap(locked, in: scene)
            swipe(from: CGPoint(x: scene.size.width * 0.8, y: scene.size.height / 2),
                  to: CGPoint(x: scene.size.width * 0.2, y: scene.size.height / 2), in: scene)
            harness.spin(0.08)

            XCTAssertEqual(open.xScale, 1, accuracy: 0.01, "a tap through the closing dialog pressed level 7")
            XCTAssertEqual(locked.zRotation, 0, accuracy: 0.001, "a tap through the closing dialog reached level 9")

            harness.spin(0.6)
            XCTAssertNil(scene.childNode(withName: "//confirmationDialog"), "NO did not close the dialog")
            XCTAssertNotNil(button(1, in: scene), "a swipe through the closing dialog paged the grid")
            XCTAssertNil(button(levelsPerPage + 1, in: scene), "a swipe through the closing dialog paged the grid")

            // And once it has gone, the grid answers again.
            tap(locked, in: scene)
            harness.spin(0.08)
            XCTAssertGreaterThan(abs(locked.zRotation), 0.001, "the grid stayed locked after the dialog had gone")
        }
    }

    /// After YES the dialog stays modal until the grid has been rebuilt on the cleared
    /// progress, so the stale tiles — still showing levels as open — cannot be reached.
    func testAfterYesTheGridAnswersOnlyOnceRebuiltOnTheClearedProgress() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            for level in 1...6 {
                LevelManager.shared.completeLevel(level, score: 100)
            }
            let scene = presentGrid(harness)
            scene.debugShowResetDialog()
            harness.spin(0.4)

            guard let yes = scene.childNode(withName: "//confirmYes"),
                  let stale = button(1, in: scene) else {
                return XCTFail("the dialog or the tiles under it did not build")
            }

            tap(yes, in: scene)
            tap(stale, in: scene)
            harness.spin(0.08)
            XCTAssertEqual(stale.xScale, 1, accuracy: 0.01, "a tap reached the stale grid behind the closing dialog")

            harness.spin(0.6)
            XCTAssertFalse(LevelManager.shared.isLevelUnlocked(3), "YES did not clear the progress")
            guard let rebuilt = button(3, in: scene) else {
                return XCTFail("the grid was not rebuilt after the reset")
            }
            XCTAssertNotNil(rebuilt.childNode(withName: "padlock"), "the rebuilt grid still shows level 3 as open")

            tap(rebuilt, in: scene)
            harness.spin(0.08)
            XCTAssertGreaterThan(abs(rebuilt.zRotation), 0.001, "the rebuilt grid does not answer taps")
        }
    }

    /// The YES / NO pair is cut from the dialog's width. At the fixed half-column width
    /// it came to 280pt, which overran the 272pt dialog a 320pt-wide screen gets — an
    /// SE or a mini with Display Zoom on.
    func testTheResetDialogsButtonsFitInsideItOnANarrowScreen() {
        let harness = GameplayHarness(size: CGSize(width: 320, height: 568))
        defer { harness.teardown() }

        withCleanProgress {
            let scene = presentGrid(harness)
            scene.debugShowResetDialog()
            harness.spin(0.4)

            guard let glass = scene.childNode(withName: "//confirmationGlass") as? SKSpriteNode,
                  let no = scene.childNode(withName: "//confirmNo") as? SKShapeNode,
                  let yes = scene.childNode(withName: "//confirmYes") as? SKShapeNode,
                  let noBox = no.path?.boundingBoxOfPath,
                  let yesBox = yes.path?.boundingBoxOfPath else {
                return XCTFail("the dialog did not build")
            }

            // All in the dialog's own points: the glass and the buttons share a parent.
            let half = glass.size.width / 2
            XCTAssertGreaterThanOrEqual(no.position.x + noBox.minX, -half, "NO pokes out of the dialog's left edge")
            XCTAssertLessThanOrEqual(yes.position.x + yesBox.maxX, half, "YES pokes out of the dialog's right edge")
            XCTAssertLessThan(no.position.x + noBox.maxX, yes.position.x + yesBox.minX, "NO and YES overlap")
        }
    }

    // MARK: - Helpers

    /// A tap is `touchesBegan` then `touchesEnded` at the same point: no movement keeps
    /// `hasMoved` false, and a zero delta stays under the swipe threshold, so
    /// `touchesEnded` routes it to `handleTap`.
    private func tap(_ node: SKNode, in scene: SKScene) {
        let point = node.parent?.convert(node.position, to: scene) ?? node.position
        scene.touchesBegan([HarnessTouch(point)], with: nil)
        scene.touchesEnded([HarnessTouch(point)], with: nil)
    }

    /// A fast horizontal flick: both ends share a zero timestamp, well inside the swipe's
    /// time limit.
    private func swipe(from start: CGPoint, to end: CGPoint, in scene: SKScene) {
        scene.touchesBegan([HarnessTouch(start)], with: nil)
        scene.touchesEnded([HarnessTouch(end)], with: nil)
    }

    private func swipeForward(in scene: SKScene) {
        swipe(from: CGPoint(x: scene.size.width * 0.8, y: scene.size.height / 2),
              to: CGPoint(x: scene.size.width * 0.2, y: scene.size.height / 2), in: scene)
    }

    private func rgba(_ color: UIColor) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }
}
