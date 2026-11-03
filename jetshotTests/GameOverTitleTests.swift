//
//  GameOverTitleTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The game-over title for an endless run.
@MainActor
final class GameOverTitleTests: XCTestCase {

    /// "LEVEL FAILED" under a tag reading ENDLESS · ROUND 27.
    func testAnEndlessRunDoesNotEndInALevelFailed() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let endless = GameOverScene(size: harness.view.bounds.size, score: 486_300, level: 1,
                                    isEndless: true, endlessRound: 27, isEndlessRecord: true)
        harness.present(endless, settle: 0.2)
        let endlessTexts = texts(in: endless)
        XCTAssertTrue(endlessTexts.contains(L10n.GameOver.endlessTitle), "the endless title is missing")
        XCTAssertFalse(endlessTexts.contains(L10n.GameOver.title), "an endless run ended in LEVEL FAILED")

        let campaign = GameOverScene(size: harness.view.bounds.size, score: 12_000, level: 7)
        harness.present(campaign, settle: 0.2)
        XCTAssertTrue(texts(in: campaign).contains(L10n.GameOver.title), "a failed level lost its title")
    }

    private func texts(in node: SKNode) -> Set<String> {
        var found = Set<String>()
        if let label = node as? SKLabelNode, let text = label.attributedText?.string ?? label.text {
            found.insert(text)
        }
        for child in node.children {
            found.formUnion(texts(in: child))
        }
        return found
    }
}
