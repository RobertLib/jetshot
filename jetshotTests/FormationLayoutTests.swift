//
//  FormationLayoutTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Pins `FormationPattern.positions(count:)` to exactly one slot per enemy.
///
/// `FormationManager.spawnFormation` places one enemy per slot, so a layout that comes up
/// short silently drops enemies while `EnemyManager` still counts the whole wave as
/// spawned. The diamond used to lay out about half its count (a 10-strong diamond got 5
/// slots) and the extended cross dropped the remainder of `(count - 1) / 4` (an 8-strong
/// cross got 5).
final class FormationLayoutTests: XCTestCase {

    private let patterns: [FormationPattern] = [.vShape, .line, .arc, .arrow, .diamond, .box, .circle, .cross]
    private let centreX: CGFloat = 195
    private let startY: CGFloat = 694
    private let spacing: CGFloat = 50

    @MainActor
    private func layout(_ pattern: FormationPattern, _ count: Int) -> [CGPoint] {
        return pattern.positions(count: count, centerX: centreX, startY: startY, spacing: spacing)
    }

    @MainActor
    func testEveryPatternLaysOutExactlyOneSlotPerEnemy() {
        for pattern in patterns {
            for count in 1...24 {
                XCTAssertEqual(layout(pattern, count).count, count, "\(pattern) laid out the wrong number of slots for \(count)")
            }
        }
    }

    @MainActor
    func testNoTwoEnemiesShareASlot() {
        for pattern in patterns {
            for count in 1...24 {
                let slots = layout(pattern, count)
                var stacked = 0
                for i in slots.indices {
                    for j in slots.indices where j > i
                        && hypot(slots[i].x - slots[j].x, slots[i].y - slots[j].y) < 1 {
                        stacked += 1
                    }
                }
                XCTAssertEqual(stacked, 0, "\(pattern) with \(count) puts enemies on top of each other")
            }
        }
    }

    @MainActor
    func testDiamondAndCrossStayInTheFormationBand() {
        // Neither may climb more than a row above `startY` — the old extended cross kept
        // its centre there and ran its up arm off the top of the screen — or reach down
        // into the half of the screen the player flies in.
        for pattern in [FormationPattern.diamond, .cross] {
            for count in 1...24 {
                let ys = layout(pattern, count).map(\.y)
                XCTAssertLessThanOrEqual(ys.max() ?? 0, startY + spacing, "\(pattern) with \(count) climbs off the top")
                XCTAssertGreaterThanOrEqual(ys.min() ?? 0, startY - 6 * spacing, "\(pattern) with \(count) reaches into the player's space")
            }
        }
    }

    @MainActor
    func testDiamondIsSymmetricAboutItsCentreLine() {
        for count in 1...24 {
            let slots = layout(.diamond, count)
            for slot in slots {
                let mirror = CGPoint(x: 2 * centreX - slot.x, y: slot.y)
                XCTAssertTrue(
                    slots.contains { hypot($0.x - mirror.x, $0.y - mirror.y) < 0.5 },
                    "a \(count)-strong diamond is lopsided at \(slot)"
                )
            }
        }
    }

    @MainActor
    func testTheSpawnerFieldsTheWholeWave() {
        // End to end through the spawner, on counts the old layouts came up short on —
        // including the ones levels 35 to 50 actually use.
        let cases: [(FormationPattern, Int)] = [(.diamond, 10), (.diamond, 14), (.diamond, 20), (.cross, 8), (.cross, 16)]
        for (pattern, count) in cases {
            let scene = SKScene(size: CGSize(width: 390, height: 844))
            let manager = FormationManager(scene: scene)
            manager.spawnFormation(pattern: pattern, types: Array(repeating: .eliteGuard, count: count), attackDelay: 2) {}

            XCTAssertEqual(scene.children.filter { $0 is Enemy }.count, count, "a \(count)-strong \(pattern) arrived short")
        }
    }
}
