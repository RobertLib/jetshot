//
//  BossPhaseTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// The phase rules decide what a boss is allowed to do and how often, for all fifty
/// climaxes in the game. They are pure arithmetic over the health fraction, so they are
/// worth pinning down here rather than by fighting a level 43 boss to find out.
final class BossPhaseTests: XCTestCase {

    // MARK: - Phase boundaries

    func testAFullHealthBossIsInTheOpeningPhase() {
        XCTAssertEqual(BossPhaseRules.phase(forHealthFraction: 1.0), 0)
    }

    func testPhaseAdvancesAtEachThresholdAndNeverPastTheLast() {
        // Thresholds are inclusive on the way down: landing exactly on 0.66 is already
        // the second act, which is what makes the boundary reachable at all for a boss
        // whose health divides evenly.
        XCTAssertEqual(BossPhaseRules.phase(forHealthFraction: 0.67), 0)
        XCTAssertEqual(BossPhaseRules.phase(forHealthFraction: 0.66), 1)
        XCTAssertEqual(BossPhaseRules.phase(forHealthFraction: 0.34), 1)
        XCTAssertEqual(BossPhaseRules.phase(forHealthFraction: 0.33), 2)
        XCTAssertEqual(BossPhaseRules.phase(forHealthFraction: 0.0), BossPhaseRules.phaseCount - 1)
    }

    func testPhaseNeverGoesBackwardsAsHealthFalls() {
        // `BossManager` only ever compares the phase before a hit against the phase
        // after it and escalates on an increase. A non-monotonic ladder would mean a
        // boss could quietly de-escalate mid-fight and never announce it.
        var previous = BossPhaseRules.phase(forHealthFraction: 1.0)
        for step in stride(from: 1.0, through: 0.0, by: -0.01) {
            let phase = BossPhaseRules.phase(forHealthFraction: CGFloat(step))
            XCTAssertGreaterThanOrEqual(phase, previous, "phase fell at \(step) health")
            XCTAssertLessThan(phase, BossPhaseRules.phaseCount)
            previous = phase
        }
    }

    // MARK: - Cadence

    func testEachPhaseAttacksAtLeastAsFastAsTheOneBefore() {
        for phase in 1..<BossPhaseRules.phaseCount {
            XCTAssertLessThanOrEqual(
                BossPhaseRules.attackDelayScale(forPhase: phase),
                BossPhaseRules.attackDelayScale(forPhase: phase - 1),
                "phase \(phase) gives the player more breathing room than phase \(phase - 1)"
            )
        }
    }

    func testTheOpeningPhaseUsesTheAuthoredCadenceUnchanged() {
        XCTAssertEqual(BossPhaseRules.attackDelayScale(forPhase: 0), 1.0, accuracy: 0.0001)
    }

    func testTheFastestCadenceStillLeavesRoomForTheLongestTelegraph() {
        // `scheduleNextAttack` carves the wind-up out of the gap between attacks rather
        // than adding it on top. If the longest telegraph ever exceeded the shortest gap
        // the lead-in would clamp to zero and the warning would start at the same instant
        // as the previous attack's recovery — no warning at all, exactly in the phase
        // where the patterns are heaviest.
        let fastestGap = GameConfiguration.bossAttackDelayMin
            * BossPhaseRules.attackDelayScale(forPhase: BossPhaseRules.phaseCount - 1)
        let longestTelegraph = BossPhaseRules.telegraphDuration(forPatternIndex: 9, totalPatterns: 10)

        XCTAssertLessThan(
            longestTelegraph, fastestGap,
            "the heaviest attack cannot be telegraphed inside the tightest attack gap"
        )
    }

    // MARK: - Pattern availability

    func testTheOpeningPhaseWithholdsTheHeavyEndOfTheList() {
        let total = 12
        let opening = BossPhaseRules.patternCount(forPhase: 0, totalPatterns: total)
        XCTAssertLessThan(opening, total, "the boss opens with everything it has")
        XCTAssertGreaterThanOrEqual(opening, 2)
    }

    func testTheFinalPhaseUnlocksEverything() {
        for total in 1...20 {
            XCTAssertEqual(
                BossPhaseRules.patternCount(forPhase: BossPhaseRules.phaseCount - 1, totalPatterns: total),
                total,
                "a dying boss is still holding something back from a \(total)-pattern list"
            )
        }
    }

    func testAvailablePatternsOnlyEverGrowAsTheBossWeakens() {
        for total in 1...20 {
            var previous = 0
            for phase in 0..<BossPhaseRules.phaseCount {
                let count = BossPhaseRules.patternCount(forPhase: phase, totalPatterns: total)
                XCTAssertGreaterThanOrEqual(
                    count, previous,
                    "phase \(phase) of a \(total)-pattern boss lost access to an attack"
                )
                XCTAssertLessThanOrEqual(count, total)
                previous = count
            }
        }
    }

    func testEveryPhaseOfEveryListHasSomethingToChooseFrom() {
        // A phase that resolved to a single pattern would repeat it, and `nextAttack()`
        // deliberately refuses to draw the same index twice running — with one option it
        // would step aside onto itself forever.
        for total in 2...20 {
            for phase in 0..<BossPhaseRules.phaseCount {
                XCTAssertGreaterThanOrEqual(
                    BossPhaseRules.patternCount(forPhase: phase, totalPatterns: total), 2,
                    "phase \(phase) of a \(total)-pattern boss has nothing to alternate between"
                )
            }
        }
    }

    func testAnEmptyListDegradesQuietly() {
        // Not reachable through `BossConfig` — `BossConfigTests` proves every arm ships
        // patterns — but `patternCount` divides work off the total and must not trap.
        XCTAssertEqual(BossPhaseRules.patternCount(forPhase: 0, totalPatterns: 0), 0)
        XCTAssertEqual(BossPhaseRules.patternCount(forPhase: 2, totalPatterns: 0), 0)
    }

    // MARK: - Telegraphs

    func testHeavyAttacksAreWarnedAboutForLonger() {
        let total = 9
        let light = BossPhaseRules.telegraphDuration(forPatternIndex: 0, totalPatterns: total)
        let heavy = BossPhaseRules.telegraphDuration(forPatternIndex: total - 1, totalPatterns: total)

        XCTAssertGreaterThan(heavy, light, "the screen-filling attacks get no more warning than a single shot")
        XCTAssertGreaterThan(light, 0, "an attack with no wind-up cannot be read")
    }

    func testTheHeavyBandIsTheFinalThirdOfAList() {
        XCTAssertFalse(BossPhaseRules.isHeavy(patternIndex: 5, totalPatterns: 9))
        XCTAssertTrue(BossPhaseRules.isHeavy(patternIndex: 6, totalPatterns: 9))
        XCTAssertTrue(BossPhaseRules.isHeavy(patternIndex: 8, totalPatterns: 9))
    }
}
