//
//  BossConfigTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// `BossConfig.config(for:)` builds each level's boss from a hand-written roster and a
/// blueprint per archetype, and the boss it returns is the completion gate for its
/// level: `checkLevelCompletion()` stops counting enemies the moment `bossSpawned` is
/// set, so from then on the only way out of the level is killing what this function
/// produced. A boss with no attack patterns, or with non-positive health, is an
/// unfinishable level — and reaching level 43 to find out is not a test strategy.
///
/// Cheap to run and covers every level, so it stays separate from the timing-bound
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
    /// the edge — which is exactly the margin `Boss.enterScene(completion:)` insets the
    /// arena by. This caught a real defect: that margin used the whole diameter, which
    /// left the level 50 boss sweeping two points on a 402pt iPhone and inverted the
    /// range entirely at 375pt.
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

    // MARK: - Fight identity

    /// The defect this was first written for: every milestone from level 8 to level 50
    /// used to declare the identical fourteen attack patterns, so thirty-five of the
    /// fifty bosses were the same fight behind a longer health bar. Now no two levels
    /// may share an arsenal at all.
    func testNoTwoBossesShareAnAttackList() {
        var seen: [[String]] = []

        for level in allLevels {
            let signature = BossConfig.config(for: level).attackPatterns.map { "\($0)" }
            XCTAssertFalse(
                seen.contains(signature),
                "level \(level)'s boss fights identically to an earlier one"
            )
            seen.append(signature)
        }
    }

    /// `BossPhaseRules.patternCount(forPhase:acts:)` takes a *prefix* of the list, so
    /// the attacks have to be grouped by the act they join in. One authored into the
    /// wrong group turns up an act early, and the escalation quietly stops escalating.
    func testEveryBossListIsGroupedByAct() {
        for level in allLevels {
            let config = BossConfig.config(for: level)
            XCTAssertEqual(
                config.patternActs.count, config.attackPatterns.count,
                "level \(level)'s boss has an act for every attack, or it does not"
            )
            XCTAssertEqual(
                config.patternActs, config.patternActs.sorted(),
                "level \(level)'s boss list is out of act order, so its opening act draws from a later one"
            )
            for act in 0..<BossPhaseRules.phaseCount {
                XCTAssertTrue(
                    config.patternActs.contains(act),
                    "level \(level)'s boss brings nothing new in act \(act), so that act does not escalate"
                )
            }
        }
    }

    /// The opening act is how the player learns which machine this is, so it has to
    /// contain the archetype's signature move — not a bag of generic shots that any
    /// boss could have fired.
    func testEveryBossOpensWithItsSignature() {
        for level in allLevels {
            let config = BossConfig.config(for: level)
            let opening = config.attackPatterns.prefix(
                BossPhaseRules.patternCount(forPhase: 0, acts: config.patternActs)
            )
            XCTAssertTrue(
                opening.contains(config.archetype.signature),
                "level \(level)'s \(config.archetype) does not open with its \(config.archetype.signature)"
            )
        }
    }

    func testNoBossListsTheSameAttackTwice() {
        for level in allLevels {
            let names = BossConfig.config(for: level).attackPatterns.map { "\($0)" }
            XCTAssertEqual(Set(names).count, names.count, "level \(level)'s boss lists an attack twice")
        }
    }

    /// Every act of every fight has to have at least two attacks to alternate between —
    /// `BossManager.nextAttack()` refuses to draw the same index twice running, and with
    /// a single option it would step aside onto itself — and each act has to bring in
    /// exactly the attacks authored into it, no more and no fewer.
    ///
    /// Counted from the authored acts, not from `patternCount`: that tops a thin opening
    /// up to two, so asking it for "at least two" could never fail, and an act authored
    /// with a single attack would have been papered over by attacks from the next one.
    func testEveryActUnlocksTheAttacksAuthoredIntoIt() {
        for level in allLevels {
            let config = BossConfig.config(for: level)
            let authored = zip(config.attackPatterns, config.patternActs)
            var previous: [String] = []
            for phase in 0..<BossPhaseRules.phaseCount {
                let intended = authored.filter { $0.1 <= phase }.map { "\($0.0)" }
                XCTAssertGreaterThanOrEqual(
                    intended.count, 2,
                    "level \(level)'s boss is authored with nothing to alternate between in phase \(phase)"
                )
                let available = config.attackPatterns
                    .prefix(BossPhaseRules.patternCount(forPhase: phase, acts: config.patternActs))
                    .map { "\($0)" }
                XCTAssertEqual(
                    available, intended,
                    "level \(level)'s boss does not fight phase \(phase) with the attacks authored up to it"
                )
                if phase > 0 {
                    XCTAssertGreaterThan(
                        intended.count, previous.count,
                        "level \(level)'s boss brings nothing new in phase \(phase)"
                    )
                }
                previous = intended
            }
        }
    }

    // MARK: - The roster

    /// The defect the roster was written for: fifty levels used to share seventeen
    /// bosses, and levels 11 to 14 all fought level 10's. Every level now meets a
    /// machine — an archetype at a tier — that no other level does.
    func testEveryLevelHasItsOwnBoss() {
        XCTAssertEqual(BossConfig.roster.count, GameConfiguration.totalLevels,
                       "the roster does not have exactly one boss per level")
        var seen = Set<String>()
        for level in allLevels {
            let config = BossConfig.config(for: level)
            let key = "\(config.archetype)-\(config.tier)"
            XCTAssertTrue(seen.insert(key).inserted, "level \(level) repeats an earlier level's boss (\(key))")
        }
    }

    func testNoTwoLevelsInARowFightTheSameMachine() {
        for level in 2...GameConfiguration.totalLevels {
            XCTAssertNotEqual(
                BossConfig.config(for: level).archetype, BossConfig.config(for: level - 1).archetype,
                "levels \(level - 1) and \(level) end on the same archetype"
            )
        }
    }

    /// A machine met again is a later model: it never comes back weaker.
    func testAnArchetypeNeverComesBackAtALowerTier() {
        var lastTier: [BossArchetype: Int] = [:]
        for level in allLevels {
            let config = BossConfig.config(for: level)
            if let previous = lastTier[config.archetype] {
                XCTAssertGreaterThan(config.tier, previous,
                                     "level \(level)'s \(config.archetype) is not an upgrade on the last one")
            }
            lastTier[config.archetype] = config.tier
        }
    }

    func testEveryArchetypeIsMetAndTheHeartEndsTheGame() {
        let met = Set(allLevels.map { BossConfig.config(for: $0).archetype })
        XCTAssertEqual(met, Set(BossArchetype.allCases), "an archetype is never fought")
        XCTAssertEqual(BossConfig.config(for: GameConfiguration.totalLevels).archetype, .heart)
        for level in 1..<GameConfiguration.totalLevels {
            XCTAssertNotEqual(BossConfig.config(for: level).archetype, .heart,
                              "the final boss turns up early, at level \(level)")
        }
    }

    /// The name on the health bar: the archetype, plus a numeral from the second
    /// meeting on — except the heart, which is only ever met once.
    func testTheNameMarksLaterMeetings() {
        let first = BossConfig.config(for: 1)
        XCTAssertEqual(first.displayName, L10n.Boss.name(first.archetype))
        let again = BossConfig.config(for: 7)
        XCTAssertEqual(again.archetype, first.archetype)
        XCTAssertEqual(again.displayName, L10n.Boss.name(again.archetype) + " II")
        let heart = BossConfig.config(for: GameConfiguration.totalLevels)
        XCTAssertEqual(heart.displayName, L10n.Boss.name(.heart))
    }

    // Deliberately no upper bound on `maxHealth`. The final boss takes 600 bullet hits,
    // which is a balance decision rather than a defect, and any threshold asserted here
    // would just be this test's own opinion of how long a boss fight should last.
}
