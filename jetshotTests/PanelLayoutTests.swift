//
//  PanelLayoutTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Pins the two pieces of typography the results panels and the menu buttons rest on:
/// optical centring, and the rhythm the panel stack lays out.
///
/// Both were invisible from the code. `verticalAlignmentMode = .center` centres the box
/// SpriteKit measures, which grows upwards for accented capitals — so every button whose
/// translation carries a diacritic sat visibly low while the English original looked
/// right. And all three results panels hand-placed their rows against a fixed panel
/// height, which left dead space at both ends while the figures under the score sat on a
/// tighter pitch than anything around them.
final class PanelLayoutTests: XCTestCase {

    @MainActor private var font: String { UITheme.Typography.fontBold }

    /// Text that reaches above the cap line in Czech but not in English — the pair the
    /// whole optical-centring problem turns on.
    private let accented = "NASTAVENÍ"
    private let plain = "SETTINGS"

    // MARK: - Optical centring

    /// The bug, stated as a measurement: the box SpriteKit reports is taller for the
    /// accented string, and that extra height is all above the caps.
    @MainActor
    func testAccentedCapitalsReportATallerBoxThanTheirCapBand() {
        let label = SKLabelNode(fontNamed: font)
        label.fontSize = 20

        label.text = plain
        XCTAssertEqual(label.frame.height, UITheme.capBandHeight(of: label), accuracy: 0.5,
                       "an unaccented string should have no room above its caps to correct for")

        label.text = accented
        XCTAssertGreaterThan(
            label.frame.height, UITheme.capBandHeight(of: label) + 1,
            "the accented string no longer reports a taller box, so there is nothing to correct"
        )
    }

    /// What the fix has to achieve: the caps, not the accents, straddle the centre.
    @MainActor
    func testCentringPutsTheCapBandOnTheRequestedLine() {
        for text in [accented, plain] {
            let label = SKLabelNode(fontNamed: font)
            label.text = text
            label.fontSize = 20
            UITheme.centerOnCapBand(label, centerY: 0)

            // `.center` alignment keeps the origin at the box centre, so the cap band
            // sits at the bottom of that box: its own centre is half the difference
            // below the origin.
            let box = label.frame.height
            let cap = UITheme.capBandHeight(of: label)
            let capCentre = label.position.y - (box - cap) / 2

            XCTAssertEqual(capCentre, 0, accuracy: 0.5,
                           "\(text) is not centred on its cap band")
        }
    }

    /// The English case has to come out exactly where plain `.center` put it, or this
    /// "fix" would be a silent redesign of every untranslated layout in the game.
    @MainActor
    func testUnaccentedTextIsLeftExactlyWhereItWas() {
        let label = SKLabelNode(fontNamed: font)
        label.text = plain
        label.fontSize = 20
        UITheme.centerOnCapBand(label, centerY: 0)

        XCTAssertEqual(label.position.y, 0, accuracy: 0.01,
                       "an unaccented label was moved off the line .center already had it on")
    }

    /// Scale entrances and pulses run on these labels, and they scale about the node's
    /// origin — so the alignment mode has to stay `.center`. On `.baseline` a pulse
    /// would grow the text up out of its slot.
    @MainActor
    func testCentringKeepsTheOriginAtTheBoxCentre() {
        let label = SKLabelNode(fontNamed: font)
        label.text = accented
        label.fontSize = 20
        UITheme.centerOnCapBand(label)

        XCTAssertEqual(label.verticalAlignmentMode, .center,
                       "alignment left .center, so every scale animation on this label now grows from the baseline")
    }

    // MARK: - Buttons

    @MainActor
    func testButtonTextIsOpticallyCentredWhateverTheLanguage() {
        // Heights the menu and the results panels actually use.
        for height in [CGFloat(50), 44, 42] {
            for text in [accented, plain, "NEKONEČNÁ HRA", "ENDLESS"] {
                let button = UITheme.createButton(
                    text: text, color: .cyan,
                    width: UITheme.Dimensions.buttonWidthLarge,
                    name: "b", height: height
                )
                guard let label = button.children.compactMap({ $0 as? SKLabelNode }).first else {
                    return XCTFail("the button has no label")
                }

                let box = label.frame.height
                let cap = UITheme.capBandHeight(of: label)
                let capCentre = label.position.y - (box - cap) / 2

                XCTAssertEqual(
                    capCentre, 0, accuracy: 0.5,
                    "\"\(text)\" sits \(String(format: "%.1f", capCentre))pt off centre in a \(Int(height))pt button"
                )
            }
        }
    }

    // MARK: - Panel rhythm

    /// A panel sized by the stack has to have equal margins — that is the whole point of
    /// measuring the content instead of picking a height.
    func testPanelStackLeavesEqualMarginsTopAndBottom() {
        typealias Rhythm = UITheme.PanelRhythm
        let rows: [(gap: CGFloat, height: CGFloat)] = [
            (Rhythm.edge, 40),
            (Rhythm.emblemToTitle, 22),
            (Rhythm.aroundFigures, 70),
            (Rhythm.aroundFigures, 50),
            (Rhythm.buttonRow, 50)
        ]

        var stack = UITheme.PanelStack()
        for row in rows { stack.add(gapAbove: row.gap, height: row.height) }
        let panelHeight = stack.height

        stack.start(panelHeight: panelHeight)
        var centres: [CGFloat] = []
        for row in rows { centres.append(stack.next(gapAbove: row.gap, height: row.height)) }

        let topMargin = panelHeight / 2 - (centres[0] + rows[0].height / 2)
        let lastIndex = rows.count - 1
        let bottomMargin = (centres[lastIndex] - rows[lastIndex].height / 2) + panelHeight / 2

        XCTAssertEqual(topMargin, Rhythm.edge, accuracy: 0.01, "the top margin is not the edge gap")
        XCTAssertEqual(bottomMargin, Rhythm.edge, accuracy: 0.01, "the bottom margin is not the edge gap")
        XCTAssertEqual(topMargin, bottomMargin, accuracy: 0.01, "the panel is lopsided")
    }

    /// Rows come out in order, each separated by exactly the gap it was given — edge to
    /// edge, so a row's own height never leaks into the gap below it.
    func testPanelStackHonoursEachGapExactly() {
        typealias Rhythm = UITheme.PanelRhythm
        let rows: [(gap: CGFloat, height: CGFloat)] = [
            (Rhythm.edge, 30),
            (Rhythm.captionToValue, 18),
            (Rhythm.figureLine, 14)
        ]

        var stack = UITheme.PanelStack()
        for row in rows { stack.add(gapAbove: row.gap, height: row.height) }
        stack.start(panelHeight: stack.height)

        var previousBottom: CGFloat?
        for row in rows {
            let centre = stack.next(gapAbove: row.gap, height: row.height)
            if let bottom = previousBottom {
                XCTAssertEqual(bottom - (centre + row.height / 2), row.gap, accuracy: 0.01,
                               "the gap above a row was not the one it asked for")
            }
            previousBottom = centre - row.height / 2
        }
    }

    /// The complaint the rhythm exists to answer: a caption has to hug the number it
    /// labels more tightly than separate figures sit from each other. Equalise those two
    /// and the block reads as mashed together again.
    func testACaptionHugsItsValueMoreTightlyThanFiguresSitApart() {
        typealias Rhythm = UITheme.PanelRhythm
        XCTAssertLessThan(Rhythm.captionToValue, Rhythm.figureLine,
                          "a caption is no longer tighter to its value than two figures are to each other")
        XCTAssertLessThan(Rhythm.figureLine, Rhythm.aroundFigures,
                          "the figure block no longer sits closer together than it does to what surrounds it")
    }

    /// `stackLabels` centres the block on the container's origin, which is what lets the
    /// outer stack place it by its centre like any other row.
    ///
    /// Measured on the drawn boxes, not on cap bands: inside a stack the only thing a
    /// reader can judge is the air between the lines, so that is what the block is built
    /// and centred on. See `UITheme.stackLabels`.
    @MainActor
    func testStackedLabelBlockIsCentredOnItsContainer() {
        let container = SKNode()
        let rows: [(label: SKLabelNode, gapAbove: CGFloat)] = ["SKÓRE", "128450", "NOVÝ REKORD"]
            .enumerated()
            .map { index, text in
                let label = SKLabelNode(fontNamed: font)
                label.text = text
                label.fontSize = index == 1 ? 32 : 16
                label.horizontalAlignmentMode = .center
                return (label, index == 0 ? 0 : UITheme.PanelRhythm.figureLine)
            }

        let height = UITheme.stackLabels(rows, in: container)
        XCTAssertGreaterThan(height, 0)
        XCTAssertEqual(container.children.count, 3, "not every label was added")

        let top = rows[0].label.frame.maxY
        let bottom = rows[2].label.frame.minY

        XCTAssertEqual(top + bottom, 0, accuracy: 0.5, "the block is not centred on the container")
        XCTAssertEqual(top - bottom, height, accuracy: 0.5, "the reported height is not the block's height")
    }

    /// The gaps a reader sees between stacked rows have to be the ones asked for, whether
    /// or not the rows carry accents. Cap-band spacing made these measure equal and
    /// render unequal — 13.0 and 14.5 against a nominal 16 — which is the whole reason
    /// `stackLabels` works in drawn boxes.
    @MainActor
    func testStackedRowsAreSeparatedByTheGapTheyAskedFor() {
        let container = SKNode()
        let gap = UITheme.PanelRhythm.figureLine
        // Deliberately mixed: no accents, a tall acute, then a caron that reaches less far.
        let rows: [(label: SKLabelNode, gapAbove: CGFloat)] = ["128450", "NOVÝ REKORD", "NEJDELŠÍ SÉRIE"]
            .enumerated()
            .map { index, text in
                let label = SKLabelNode(fontNamed: font)
                label.text = text
                label.fontSize = index == 0 ? 32 : 15
                label.horizontalAlignmentMode = .center
                return (label, index == 0 ? 0 : gap)
            }

        UITheme.stackLabels(rows, in: container)

        for index in 1..<rows.count {
            let measured = rows[index - 1].label.frame.minY - rows[index].label.frame.maxY
            XCTAssertEqual(
                measured, gap, accuracy: 0.5,
                "the gap above \"\(rows[index].label.text ?? "")\" renders as \(String(format: "%.1f", measured))pt, not \(gap)pt"
            )
        }
    }
}
