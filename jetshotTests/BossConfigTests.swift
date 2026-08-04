//
//  BossConfigTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// `BossConfig.config(for:)` is a 50-arm `switch` written by hand, and the boss it
/// returns is the completion gate for its level: `checkLevelCompletion()` stops counting
/// enemies the moment `bossSpawned` is set, so from then on the only way out of the level
/// is killing what this function produced. A single arm with no attack patterns, or with
/// non-positive health, is an unfinishable level — and reaching level 43 to find out is
/// not a test strategy.
///
/// Cheap to run and covers every arm, so it stays separate from the timing-bound
/// integration pass in `BossFightTests`.
///
/// `@MainActor` because the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, which puts `BossConfig` on the main actor — unlike the deliberately
/// `nonisolated` pure rules in `GameRules`.
@MainActor
final class BossConfigTests: XCTestCase {

    private var allLevels: [Int] { Array(1...GameConfiguration.totalLevels) }

    func testEveryLevelProducesAFightableBoss() {
        for level in allLevels {
            let config = BossConfig.config(for: level)

            XCTAssertGreaterThan(
                config.maxHealth, 0,
                "level \(level)'s boss starts dead, so the level can never be completed"
            )
            XCTAssertFalse(
                config.attackPatterns.isEmpty,
                "level \(level)'s boss has no attack patterns, so the fight is a formality"
            )
            XCTAssertGreaterThan(config.size, 0, "level \(level)'s boss has no size")
            XCTAssertGreaterThan(
                config.movementSpeed, 0,
                "level \(level)'s boss would teleport between edges"
            )
            XCTAssertGreaterThan(
                config.points, 0,
                "level \(level)'s boss pays nothing for the hardest kill in the level"
            )
        }
    }

    /// Every boss has to fit the narrowest supported screen with room to patrol.
    ///
    /// `config.size` is the full silhouette, so a boss fits when its *half* width clears
    /// the edge — which is exactly the margin `startMovement()` insets by. This caught a
    /// real defect: that margin used the whole diameter, which left the level 50 boss
    /// sweeping two points on a 402pt iPhone and inverted the range entirely at 375pt.
    /// 375pt is the narrowest portrait width on the iOS 16 deployment target.
    func testEveryBossFitsTheNarrowestSupportedScreenWithRoomToPatrol() {
        let narrowestWidth: CGFloat = 375
        let edgePadding: CGFloat = 8
        // A sweep narrower than this is not the side-to-side patrol the code intends.
        let minimumSweep: CGFloat = 60

        for level in allLevels {
            let config = BossConfig.config(for: level)
            let margin = config.size * 0.5 + edgePadding
            let sweep = (narrowestWidth - margin) - margin

            XCTAssertGreaterThan(
                sweep, minimumSweep,
                "level \(level)'s boss (size \(config.size)) has only \(sweep)pt to patrol "
                + "on a \(narrowestWidth)pt screen"
            )
        }
    }

    /// Progression sanity: the fight should never get outright easier as levels advance,
    /// and the reward should never shrink. Equality is fine — plenty of adjacent levels
    /// deliberately share a boss tier.
    func testDifficultyAndRewardNeverRegress() {
        for level in 2...GameConfiguration.totalLevels {
            let previous = BossConfig.config(for: level - 1)
            let current = BossConfig.config(for: level)

            XCTAssertGreaterThanOrEqual(
                current.maxHealth, previous.maxHealth,
                "level \(level)'s boss is softer than level \(level - 1)'s"
            )
            XCTAssertGreaterThanOrEqual(
                current.points, previous.points,
                "level \(level)'s boss pays less than level \(level - 1)'s"
            )
        }
    }

    /// Reached if saved progress ever outruns `totalLevels`, the same fallback
    /// `LevelConfigTests` pins down for the level generator.
    func testOutOfRangeLevelsStillProduceABoss() {
        for level in [0, -1, GameConfiguration.totalLevels + 1, 999] {
            let config = BossConfig.config(for: level)
            XCTAssertGreaterThan(
                config.maxHealth, 0,
                "level \(level) fell through to a boss that cannot be fought"
            )
            XCTAssertFalse(config.attackPatterns.isEmpty, "level \(level) fell through to a passive boss")
        }
    }

    // Deliberately no upper bound on `maxHealth`. The final boss takes 600 bullet hits,
    // which is a balance decision rather than a defect, and any threshold asserted here
    // would just be this test's own opinion of how long a boss fight should last.
}
