//
//  MenuLayoutTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Pins the vertical rhythm of the menu's button stack.
///
/// The endless record caption used to sit at a hand-picked y that gave it about 5pt of
/// air above and 7pt below, between buttons that are themselves 16pt apart — so ENDLESS,
/// the record and SETTINGS read as one mashed block instead of a button with a caption
/// under it. And with no record yet, SETTINGS stayed at that same low y regardless,
/// leaving the gap the caption would have filled.
///
/// Both are pure spacing, which no other test can see and which nothing fails on, so
/// they are asserted here as measured gaps between the real nodes.
final class MenuLayoutTests: XCTestCase {

    // MARK: - Measuring

    /// A button's own outline in scene coordinates.
    ///
    /// Deliberately not `calculateAccumulatedFrame()`: the buttons carry a glow halo
    /// child padded out for the bloom's Gaussian tail, roughly three times the button's
    /// own height, which would swamp every gap measured here. Same reason
    /// `MenuScene.isTap(_:on:)` measures the path.
    /// START's own scale is applied because it carries a repeating pulse, so its outline
    /// is a little larger than its path for most of any given frame.
    @MainActor
    private func buttonRect(_ name: String, in scene: SKScene) -> CGRect? {
        guard let button = scene.childNode(withName: name) as? SKShapeNode,
              let box = button.path?.boundingBoxOfPath else { return nil }
        let scaled = CGRect(
            x: box.minX * button.xScale,
            y: box.minY * button.yScale,
            width: box.width * button.xScale,
            height: box.height * button.yScale
        )
        return scaled.offsetBy(dx: button.position.x, dy: button.position.y)
    }

    @MainActor
    private func captionRect(in scene: SKScene) -> CGRect? {
        guard let caption = scene.childNode(withName: "endlessRecord") else { return nil }
        return caption.calculateAccumulatedFrame()
    }

    /// Vertical space between two stacked rects. Negative means they overlap.
    private func gap(below upper: CGRect, above lower: CGRect) -> CGFloat {
        return upper.minY - lower.maxY
    }

    @MainActor
    private func presentMenu(_ harness: GameplayHarness) -> MenuScene {
        let scene = MenuScene(size: harness.view.bounds.size)
        harness.present(scene, settle: 0.6)
        return scene
    }

    // MARK: - With a record

    @MainActor
    func testTheRecordCaptionIsSpacedOffTheEndlessButtonItDescribes() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 5_000)
            _ = LevelManager.shared.recordEndlessRun(score: 486_300, round: 27)

            let scene = presentMenu(harness)

            guard let endless = buttonRect("endlessButton", in: scene),
                  let caption = captionRect(in: scene),
                  let settings = buttonRect("settingsButton", in: scene) else {
                return XCTFail("the menu did not build ENDLESS, its record and SETTINGS")
            }

            let above = gap(below: endless, above: caption)
            let below = gap(below: caption, above: settings)

            XCTAssertEqual(above, MenuScene.captionGap, accuracy: 0.5,
                           "the record caption is not sitting captionGap below the ENDLESS button")
            XCTAssertEqual(below, MenuScene.captionToButtonGap, accuracy: 0.5,
                           "the record caption is not sitting captionToButtonGap above SETTINGS")

            // The invariant behind the numbers: a caption belongs to the thing above it,
            // and the spacing is the only thing that says so. This is what fails if the
            // two gaps are ever equalised or flipped.
            XCTAssertGreaterThan(below, above * 1.5,
                                 "the caption is not clearly grouped with ENDLESS — it reads as SETTINGS' label")
        }
    }

    @MainActor
    func testNothingInTheMenuStackOverlaps() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 5_000)
            _ = LevelManager.shared.recordEndlessRun(score: 486_300, round: 27)

            let scene = presentMenu(harness)

            guard let start = buttonRect("startButton", in: scene),
                  let endless = buttonRect("endlessButton", in: scene),
                  let caption = captionRect(in: scene),
                  let settings = buttonRect("settingsButton", in: scene) else {
                return XCTFail("the menu stack did not build")
            }

            // Walked as a stack so the failure message names the offending pair.
            let stack: [(String, CGRect)] = [
                ("START", start), ("ENDLESS", endless),
                ("the record caption", caption), ("SETTINGS", settings)
            ]
            for (upper, lower) in zip(stack, stack.dropFirst()) {
                XCTAssertGreaterThan(gap(below: upper.1, above: lower.1), 0,
                                     "\(upper.0) overlaps \(lower.0)")
            }
        }
    }

    /// The record pushes SETTINGS down, so the tallest configuration has to still fit
    /// the shortest screen the app supports — iPhone 8 / SE, at 667pt, on iOS 16.
    @MainActor
    func testTheStackStillFitsTheShortestSupportedScreen() {
        let harness = GameplayHarness(size: CGSize(width: 375, height: 667))
        defer { harness.teardown() }

        withCleanProgress {
            LevelManager.shared.completeLevel(1, score: 5_000)
            _ = LevelManager.shared.recordEndlessRun(score: 999_999, round: 99)

            let scene = presentMenu(harness)

            guard let settings = buttonRect("settingsButton", in: scene) else {
                return XCTFail("SETTINGS did not build")
            }
            // The credits line sits at y = 30.
            XCTAssertGreaterThan(settings.minY, 45,
                                 "SETTINGS was pushed down onto the credits line on a 667pt screen")
        }
    }

    // MARK: - Without a record

    @MainActor
    func testWithoutARecordSettingsClosesUpInsteadOfHoldingTheSlotOpen() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            // Endless unlocked, but never played — so there is no caption to make room
            // for and SETTINGS should sit an ordinary button gap below ENDLESS.
            LevelManager.shared.completeLevel(1, score: 5_000)

            let scene = presentMenu(harness)

            XCTAssertNil(scene.childNode(withName: "endlessRecord"),
                         "a record caption was drawn with no record set")

            guard let endless = buttonRect("endlessButton", in: scene),
                  let settings = buttonRect("settingsButton", in: scene) else {
                return XCTFail("the menu did not build ENDLESS and SETTINGS")
            }

            XCTAssertEqual(gap(below: endless, above: settings), MenuScene.buttonGap, accuracy: 0.5,
                           "SETTINGS is still holding the missing caption's slot open")
        }
    }

    /// A cold start shows neither ENDLESS nor a record, and that path is deliberately
    /// left at its original spacing — asserted so the fix above cannot leak into it.
    @MainActor
    func testAColdStartShowsOnlyStartAndSettings() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            let scene = presentMenu(harness)

            XCTAssertNil(scene.childNode(withName: "endlessButton"),
                         "ENDLESS was offered before level 1 was cleared")
            XCTAssertNil(scene.childNode(withName: "endlessRecord"))

            guard let start = buttonRect("startButton", in: scene),
                  let settings = buttonRect("settingsButton", in: scene) else {
                return XCTFail("the menu did not build START and SETTINGS")
            }
            XCTAssertGreaterThan(gap(below: start, above: settings), MenuScene.buttonGap,
                                 "START and SETTINGS drew closer than a button gap apart")
        }
    }
}
