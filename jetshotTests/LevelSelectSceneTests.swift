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

    /// Mirrors `LevelSelectScene.levelsPerPage`, which is private.
    private let levelsPerPage = 12

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

    func testTheFirstPageShowsTheFirstTwelveLevels() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let scene = presentGrid(harness)

            for level in 1...levelsPerPage {
                XCTAssertNotNil(button(level, in: scene), "level \(level) is missing from the first page")
            }
            XCTAssertNil(button(levelsPerPage + 1, in: scene), "the first page spilled past its 12 levels")
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

    /// The final page is short — 50 levels over pages of 12 — so it must stop at the last
    /// real level rather than rendering buttons for levels that do not exist.
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

    // MARK: - Helpers

    /// A tap is `touchesBegan` then `touchesEnded` at the same point: no movement keeps
    /// `hasMoved` false, and a zero delta stays under the swipe threshold, so
    /// `touchesEnded` routes it to `handleTap`.
    private func tap(_ node: SKNode, in scene: SKScene) {
        let point = node.parent?.convert(node.position, to: scene) ?? node.position
        scene.touchesBegan([HarnessTouch(point)], with: nil)
        scene.touchesEnded([HarnessTouch(point)], with: nil)
    }
}
