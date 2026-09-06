//
//  ResultsPanelCentringTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The figure block — score, personal best, best chain — has to sit centred between the
/// title above it and the primary button below it, on every results screen.
///
/// Two things used to break that, and both were invisible in the source:
///
/// - The block's entrance ran `SKAction.moveBy(y: 10)` from its laid-out position.
///   `moveBy` is relative and permanent, so the block spent the rest of the scene's life
///   10pt above where the layout put it: 18pt of air above, 40pt below.
/// - The gaps either side were two separate constants that merely happened to be close
///   (28 and 30). The block's height changes with how much there is to report, so any
///   difference between them shows up differently on each screen.
///
/// Measured *after* the entrances have run, because that is the state the player sees —
/// asserting on the laid-out positions would have passed throughout the bug.
final class ResultsPanelCentringTests: XCTestCase {

    /// Long enough for the slowest figure-block entrance to finish (it waits 1.9s on the
    /// victory screen, then animates for 0.3s).
    private let settle: TimeInterval = 3.0

    @MainActor
    private func present(_ scene: SKScene) -> SKView {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: view.frame)
        window.addSubview(view)
        window.isHidden = false
        view.presentScene(scene)
        let deadline = Date().addingTimeInterval(settle)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return view
    }

    /// The results panel, told apart from its glow twin by the fact that the glow is a
    /// `copy()` taken before any content was added and so has no labels under it.
    @MainActor
    private func panel(in scene: SKScene) -> SKShapeNode? {
        return scene.children
            .compactMap { $0 as? SKShapeNode }
            .first { $0.children.contains { $0 is SKLabelNode } }
    }

    /// The figure block, by name. Structural matching is not enough: the victory screen
    /// has two more label-only containers above it — the body copy — and picking the
    /// first of them measured the wrong slot entirely.
    @MainActor
    private func figureBlock(in panel: SKShapeNode) -> SKNode? {
        return panel.childNode(withName: "figureBlock")
    }

    /// The bottom edge of whatever sits immediately above `block`.
    ///
    /// Found geometrically — the nearest edge above it — rather than by assuming which
    /// child that is. It is the title on three of these screens and a line of body copy
    /// on the fourth.
    @MainActor
    private func edgeAbove(_ block: SKNode, in panel: SKShapeNode) -> CGFloat? {
        let top = block.calculateAccumulatedFrame().maxY
        return panel.children
            .filter { $0 !== block }
            .map { $0.calculateAccumulatedFrame().minY }
            .filter { $0 >= top }
            .min()
    }

    /// A button's own outline, not its accumulated frame — the shadow child hangs 2pt
    /// below it and the glow further still, neither of which is an edge anyone sees.
    @MainActor
    private func outline(of button: SKShapeNode) -> (top: CGFloat, bottom: CGFloat)? {
        guard let box = button.path?.boundingBoxOfPath else { return nil }
        return (button.position.y + box.maxY, button.position.y + box.minY)
    }

    /// Asserts the block has the same air above it as below, on one screen.
    @MainActor
    private func assertCentred(
        _ scene: SKScene,
        primaryButton: String,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let view = present(scene)
        defer { view.presentScene(nil) }

        guard let panel = panel(in: scene) else {
            return XCTFail("\(label): no results panel", file: file, line: line)
        }
        guard let block = figureBlock(in: panel) else {
            return XCTFail("\(label): no figure block", file: file, line: line)
        }
        guard let above = edgeAbove(block, in: panel) else {
            return XCTFail("\(label): nothing found above the block", file: file, line: line)
        }
        guard let button = panel.childNode(withName: primaryButton) as? SKShapeNode,
              let buttonEdges = outline(of: button) else {
            return XCTFail("\(label): no \(primaryButton)", file: file, line: line)
        }

        let blockFrame = block.calculateAccumulatedFrame()
        let gapAbove = above - blockFrame.maxY
        let gapBelow = blockFrame.minY - buttonEdges.top

        XCTAssertGreaterThan(gapAbove, 0, "\(label): the block overlaps what is above it", file: file, line: line)
        XCTAssertGreaterThan(gapBelow, 0, "\(label): the block overlaps the button", file: file, line: line)
        XCTAssertEqual(
            gapAbove, gapBelow, accuracy: 6,
            "\(label): the figure block is off centre — \(Int(gapAbove))pt above it, \(Int(gapBelow))pt below",
            file: file, line: line
        )
    }

    // MARK: - The screens

    @MainActor
    func testGameOverFigureBlockIsCentred() {
        assertCentred(
            GameOverScene(size: CGSize(width: 390, height: 844), score: 128_450, level: 34),
            primaryButton: "retryButton",
            "game over"
        )
    }

    @MainActor
    func testEndlessGameOverFigureBlockIsCentred() {
        // Four figure lines rather than two — the case a pair of unequal gaps skews most.
        assertCentred(
            GameOverScene(
                size: CGSize(width: 390, height: 844), score: 486_300, level: 1,
                isEndless: true, endlessRound: 27, isEndlessRecord: true
            ),
            primaryButton: "retryButton",
            "endless game over"
        )
    }

    @MainActor
    func testLevelCompleteFigureBlockIsCentred() {
        withCleanProgress {
            assertCentred(
                LevelCompleteScene(
                    size: CGSize(width: 390, height: 844), level: 34, score: 128_450,
                    coinsCollected: 27, totalCoins: 34,
                    bulletCount: 6, sideMissileCount: 2, bestChain: 31
                ),
                primaryButton: "nextButton",
                "level complete"
            )
        }
    }

    @MainActor
    func testVictoryFigureBlockIsCentred() {
        assertCentred(
            GameCompletionScene(size: CGSize(width: 390, height: 844), totalScore: 2_847_600),
            primaryButton: "playAgainButton",
            "victory"
        )
    }

    /// The entrance has to land on the layout, not 10pt above it. Stated separately from
    /// the centring assertions so a regression names its own cause.
    @MainActor
    func testTheFigureBlockEndsWhereTheLayoutPutIt() {
        let scene = GameOverScene(size: CGSize(width: 390, height: 844), score: 128_450, level: 34)
        let view = present(scene)
        defer { view.presentScene(nil) }

        guard let panel = panel(in: scene), let block = figureBlock(in: panel) else {
            return XCTFail("the panel did not build")
        }
        XCTAssertNil(
            block.action(forKey: "figuresRise"),
            "the entrance is still running, so this measures nothing"
        )

        // Symmetry of the block about the midpoint of the space it was given is the
        // observable form of "it landed where it was placed".
        guard let button = panel.childNode(withName: "retryButton") as? SKShapeNode,
              let edges = outline(of: button),
              let above = edgeAbove(block, in: panel) else {
            return XCTFail("the panel is missing its title or button")
        }
        let frame = block.calculateAccumulatedFrame()
        let slotCentre = (above + edges.top) / 2
        XCTAssertEqual(
            frame.midY, slotCentre, accuracy: 6,
            "the block settled \(Int(frame.midY - slotCentre))pt off the centre of its slot"
        )
    }

    // MARK: - Even gaps inside the block

    /// Every gap between figure lines has to look the same, which means measuring the
    /// air between the glyphs actually drawn — not between cap bands.
    ///
    /// The two are not the same question. With cap-band spacing these gaps measured
    /// exactly 16.00 and 16.00 while rendering as 13.0 and 14.5, because the acute on
    /// `NOVÝ` overhangs its caps further than the caron on `NEJDELŠÍ` does. Asserting on
    /// cap bands would have called that even.
    @MainActor
    func testFigureLinesAreEvenlySpacedToTheEye() {
        withCleanProgress {
            let scene = LevelCompleteScene(
                size: CGSize(width: 390, height: 844), level: 34, score: 128_450,
                coinsCollected: 27, totalCoins: 34,
                bulletCount: 6, sideMissileCount: 2, bestChain: 31
            )
            let view = present(scene)
            defer { view.presentScene(nil) }

            guard let panel = panel(in: scene), let block = figureBlock(in: panel) else {
                return XCTFail("the panel did not build")
            }

            // Top to bottom, which is the order they were stacked in.
            let labels = block.children
                .compactMap { $0 as? SKLabelNode }
                .sorted { $0.position.y > $1.position.y }
            guard labels.count >= 4 else {
                return XCTFail("expected a caption, a score and two figure lines, got \(labels.count)")
            }

            // The caption/value pair is deliberately tighter, so the run of figure lines
            // starts at the value.
            let figureGaps = zip(labels.dropFirst(), labels.dropFirst(2)).map { upper, lower -> CGFloat in
                upper.frame.minY - lower.frame.maxY
            }
            guard let first = figureGaps.first else {
                return XCTFail("no figure lines to compare")
            }
            for (index, gap) in figureGaps.enumerated() {
                XCTAssertEqual(
                    gap, first, accuracy: 0.75,
                    "figure gap \(index + 1) is \(String(format: "%.1f", gap))pt against \(String(format: "%.1f", first))pt for the first — they do not read as even"
                )
            }

            // And the caption still hugs its number more tightly than the figures sit apart.
            let captionGap = labels[0].frame.minY - labels[1].frame.maxY
            XCTAssertLessThan(captionGap, first,
                              "the caption no longer reads as belonging to the number under it")
        }
    }
}
