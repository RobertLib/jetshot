//
//  EndlessRulesTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// Endless has no authored content to fall back on: every round the player sees is
/// computed from a round number by these rules. A level generator that produces nonsense
/// is one broken level; a bad rule here is every round of every run, and there is no
/// fiftieth arm of a `switch` to eyeball it against.
final class EndlessRulesTests: XCTestCase {

    /// Deep enough to reach every clamp in the file several times over.
    private let deepRun = 1...200

    // MARK: - Boss cadence

    func testBossRoundsLandOnEveryFifthRound() {
        for round in deepRun {
            XCTAssertEqual(
                EndlessRules.isBossRound(round),
                round % EndlessRules.bossEveryRounds == 0,
                "round \(round) disagrees with the boss cadence"
            )
        }
    }

    func testRoundZeroIsNotABossRound() {
        // `endlessRound` is 1 before the first advance, but 0 % 5 == 0 would otherwise
        // make a zero round a boss round if this were ever reached from a reset.
        XCTAssertFalse(EndlessRules.isBossRound(0))
    }

    func testBossLevelWalksUpTheCampaignAndThenHolds() {
        XCTAssertEqual(EndlessRules.bossLevel(forRound: 5), 5)
        XCTAssertEqual(EndlessRules.bossLevel(forRound: 40), 40)
        XCTAssertEqual(
            EndlessRules.bossLevel(forRound: GameConfiguration.totalLevels + 25),
            GameConfiguration.totalLevels
        )
    }

    func testEveryBossRoundMapsToARealBossConfig() {
        // `BossConfig.config(for:)` has a fallback arm, but an endless run must never
        // depend on it: a round mapping to level 0 or a negative level would be a
        // silently different fight from the one the rules intend.
        for round in deepRun where EndlessRules.isBossRound(round) {
            let level = EndlessRules.bossLevel(forRound: round)
            XCTAssertTrue(
                (1...GameConfiguration.totalLevels).contains(level),
                "round \(round) asks for boss level \(level)"
            )
        }
    }

    // MARK: - Difficulty curve

    func testTierGrowsAndThenStopsAtTheRoster() {
        XCTAssertEqual(EndlessRules.tier(forRound: 1), 0)
        XCTAssertEqual(EndlessRules.tier(forRound: 4), 1)

        var previous = EndlessRules.tier(forRound: 1)
        for round in deepRun {
            let tier = EndlessRules.tier(forRound: round)
            XCTAssertGreaterThanOrEqual(tier, previous, "the roster shrank at round \(round)")
            XCTAssertLessThanOrEqual(tier, EndlessRules.maxTier)
            previous = tier
        }
        XCTAssertEqual(previous, EndlessRules.maxTier, "the deepest rounds never reach the full roster")
    }

    func testEnemyCountRisesToACapAndStaysReadable() {
        var previous = 0
        for round in deepRun {
            let count = EndlessRules.enemyCount(forRound: round)
            XCTAssertGreaterThanOrEqual(count, previous, "round \(round) sends fewer enemies than the one before")
            XCTAssertGreaterThan(count, 0)
            previous = count
        }
        // The cap is the point: past it, difficulty has to come from the roster and the
        // cadence rather than from an unreadable pile of ships.
        XCTAssertEqual(
            EndlessRules.enemyCount(forRound: 500),
            EndlessRules.enemyCount(forRound: 200),
            "the wave size never stops growing"
        )
    }

    func testSpawnIntervalTightensButNeverBelowTheCampaignFloor() {
        var previous = TimeInterval.greatestFiniteMagnitude
        for round in deepRun {
            let interval = EndlessRules.spawnInterval(forRound: round)
            XCTAssertLessThanOrEqual(interval, previous, "round \(round) spawns slower than the one before")
            XCTAssertGreaterThanOrEqual(
                interval, GameConfiguration.minSpawnInterval,
                "round \(round) clumps tighter than any authored level is allowed to"
            )
            previous = interval
        }
    }

    func testHazardsEscalateFasterThanBosses() {
        // The intent stated on `hazardLevel`: the playfield gets dangerous ahead of the
        // enemies, so a deep run is about flying as much as about shooting.
        for round in 1...20 {
            XCTAssertGreaterThanOrEqual(
                EndlessRules.hazardLevel(forRound: round),
                EndlessRules.bossLevel(forRound: round),
                "hazards lag the boss track at round \(round)"
            )
        }
        XCTAssertEqual(
            EndlessRules.hazardLevel(forRound: 500),
            GameConfiguration.totalLevels
        )
    }

    // MARK: - Generated waves

    @MainActor
    func testEveryRoundProducesSpawnableWaves() {
        for round in deepRun {
            let waves = EndlessDirector.waves(forRound: round)

            XCTAssertFalse(waves.isEmpty, "round \(round) spawns nothing, so the run would stall forever")

            for (index, wave) in waves.enumerated() {
                XCTAssertFalse(wave.enemies.isEmpty, "round \(round) wave \(index) is empty")
                XCTAssertGreaterThan(wave.spawnInterval, 0, "round \(round) wave \(index) would spawn every frame")
                XCTAssertGreaterThanOrEqual(wave.spawnDelay, 0)
                if wave.isFormation {
                    XCTAssertNotNil(
                        wave.formationPattern,
                        "round \(round) wave \(index) is a formation with no pattern"
                    )
                }
            }
        }
    }

    @MainActor
    func testTheRosterOnlyEverWidens() {
        var previous = 0
        for round in deepRun {
            let roster = EndlessDirector.roster(forRound: round)
            XCTAssertFalse(roster.isEmpty, "round \(round) has no enemies to draw from")
            XCTAssertGreaterThanOrEqual(roster.count, previous, "the roster shrank at round \(round)")
            previous = roster.count
        }
    }

    @MainActor
    func testAFormationRoundActuallyBringsAFormation() {
        for round in deepRun where EndlessRules.hasFormation(inRound: round) {
            let waves = EndlessDirector.waves(forRound: round)
            XCTAssertTrue(
                waves.contains(where: { $0.isFormation }),
                "round \(round) was meant to close on a formation"
            )
        }
    }

    @MainActor
    func testEarlyRoundsStayWithinTheStarterRoster() {
        // Round one is somebody's first minute of the mode. It must not be able to open
        // with a teleporter.
        let starters: Set<EnemyType> = [.basic, .fast]
        XCTAssertTrue(
            Set(EndlessDirector.roster(forRound: 1)).isSubset(of: starters),
            "the opening round draws from outside the starter roster"
        )
    }
}
