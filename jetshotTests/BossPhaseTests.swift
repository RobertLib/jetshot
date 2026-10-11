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
        let longestTelegraph = BossAttackPattern.allCases.map { BossPhaseRules.telegraphDuration(for: $0) }.max() ?? 0

        XCTAssertLessThan(
            longestTelegraph, fastestGap,
            "the heaviest attack cannot be telegraphed inside the tightest attack gap"
        )
    }

    // MARK: - Pattern availability

    /// Acts as `BossConfig` authors them: an opening, the pressure, the finale.
    private let typicalActs = [0, 0, 0, 1, 1, 1, 2, 2]

    func testTheOpeningPhaseWithholdsLaterActs() {
        let opening = BossPhaseRules.patternCount(forPhase: 0, acts: typicalActs)
        XCTAssertEqual(opening, 3, "the opening act should hold exactly the act-0 attacks")
        XCTAssertLessThan(opening, typicalActs.count, "the boss opens with everything it has")
        XCTAssertEqual(BossPhaseRules.patternCount(forPhase: 1, acts: typicalActs), 6)
    }

    func testTheFinalPhaseUnlocksEverything() {
        for acts in [[0, 1, 2], [0, 0, 1, 2, 2], typicalActs, [0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2]] {
            XCTAssertEqual(
                BossPhaseRules.patternCount(forPhase: BossPhaseRules.phaseCount - 1, acts: acts),
                acts.count,
                "a dying boss is still holding something back from \(acts)"
            )
        }
    }

    func testAvailablePatternsOnlyEverGrowAsTheBossWeakens() {
        for acts in [[0, 1, 2], [0, 0, 1, 2, 2], typicalActs] {
            var previous = 0
            for phase in 0..<BossPhaseRules.phaseCount {
                let count = BossPhaseRules.patternCount(forPhase: phase, acts: acts)
                XCTAssertGreaterThanOrEqual(count, previous, "phase \(phase) of \(acts) lost access to an attack")
                XCTAssertLessThanOrEqual(count, acts.count)
                previous = count
            }
        }
    }

    func testEveryPhaseOfEveryListHasSomethingToChooseFrom() {
        // A phase that resolved to a single pattern would repeat it, and `nextAttack()`
        // deliberately refuses to draw the same index twice running — with one option it
        // would step aside onto itself forever. A thin opening act is topped up.
        for acts in [[0, 1, 2], [0, 1, 1, 2], typicalActs] {
            for phase in 0..<BossPhaseRules.phaseCount {
                XCTAssertGreaterThanOrEqual(
                    BossPhaseRules.patternCount(forPhase: phase, acts: acts), 2,
                    "phase \(phase) of \(acts) has nothing to alternate between"
                )
            }
        }
    }

    func testAnEmptyListDegradesQuietly() {
        // Not reachable through `BossConfig` — `BossConfigTests` proves every boss ships
        // patterns — but `patternCount` must not trap on it.
        XCTAssertEqual(BossPhaseRules.patternCount(forPhase: 0, acts: []), 0)
        XCTAssertEqual(BossPhaseRules.patternCount(forPhase: 2, acts: []), 0)
    }

    // MARK: - Telegraphs

    func testHeavyAttacksAreWarnedAboutForLonger() {
        let light = BossPhaseRules.telegraphDuration(for: .straightShot)
        let heavy = BossPhaseRules.telegraphDuration(for: .barrageRain)

        XCTAssertGreaterThan(heavy, light, "the screen-filling attacks get no more warning than a single shot")
        XCTAssertGreaterThan(light, 0, "an attack with no wind-up cannot be read")
    }

    /// The attacks that cover the screen, or kill along a whole line, are the ones that
    /// earn the long wind-up.
    func testScreenFillingAttacksCountAsHeavy() {
        for pattern in [BossAttackPattern.sweepBeam, .eyeLance, .laser, .implosion, .latticeWalls,
                        .riftPortals, .ringPulse, .barrageRain, .circularBarrage] {
            XCTAssertTrue(pattern.isHeavy, "\(pattern) covers the screen but gets the short wind-up")
        }
        for pattern in [BossAttackPattern.straightShot, .aimed, .podVolley, .swoop, .blink, .hyperShift] {
            XCTAssertFalse(pattern.isHeavy, "\(pattern) is a light attack but gets the long wind-up")
        }
    }

    // MARK: - Parts

    func testPartsTakeAShareOfTheBossAndNeverNothing() {
        XCTAssertEqual(BossPhaseRules.partHealth(bossHealth: 100, partCount: 0), 0)
        XCTAssertGreaterThanOrEqual(BossPhaseRules.partHealth(bossHealth: 10, partCount: 2), 3)
        let pod = BossPhaseRules.partHealth(bossHealth: 400, partCount: 2)
        XCTAssertLessThan(pod * 2, 400, "shooting the pods off is a bigger job than killing the boss")
        let segment = BossPhaseRules.partHealth(bossHealth: 400, partCount: 10)
        XCTAssertLessThan(segment, pod, "a serpent's ten segments each take as long as a warden's pod")
    }
}
