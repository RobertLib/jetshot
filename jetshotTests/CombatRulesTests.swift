//
//  CombatRulesTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// Pins down the combat arithmetic in `CombatRules`, `OverdriveRules` and `GrazeRules`.
///
/// Pure functions over plain numbers, so no scene and no main actor — the same
/// arrangement as `ComboRulesTests`.
final class CombatRulesTests: XCTestCase {

    // MARK: - Toughness

    func testToughnessStepsEveryTenLevels() {
        XCTAssertEqual(CombatRules.healthScale(forLevel: 1), 1.0)
        XCTAssertEqual(CombatRules.healthScale(forLevel: 10), 1.0, "level 10 is still the first block")
        XCTAssertEqual(CombatRules.healthScale(forLevel: 11), 1.2, accuracy: 1e-9)
        XCTAssertEqual(CombatRules.healthScale(forLevel: 50), 1.8, accuracy: 1e-9)
    }

    func testToughnessNeverFallsAsTheGameGoesOn() {
        var previous = 0.0
        for level in 1...GameConfiguration.totalLevels {
            let scale = CombatRules.healthScale(forLevel: level)
            XCTAssertGreaterThanOrEqual(scale, previous, "level \(level) is easier than the one before it")
            previous = scale
        }
    }

    /// The popcorn has to stay popcorn for most of the game: a 1 HP enemy scaled by 1.2
    /// or 1.4 and rounded up would quietly double how long every swarm takes to clear.
    func testOneHitEnemiesStayOneHitUntilTheLastBlock() {
        for level in 1...30 {
            XCTAssertEqual(CombatRules.health(base: 1, level: level), 1, "a one-hit enemy took two at level \(level)")
        }
        XCTAssertEqual(CombatRules.health(base: 1, level: 50), 2)
    }

    func testHealthIsNeverBelowOne() {
        XCTAssertEqual(CombatRules.health(base: 0, level: 1), 1)
        XCTAssertGreaterThanOrEqual(CombatRules.health(base: -3, level: 40), 1)
    }

    func testBossHealthIsScaledUpFromTheAuthoredFigure() {
        for authored in [20, 35, 300, 600] {
            let scaled = CombatRules.bossHealth(authored: authored)
            XCTAssertGreaterThan(scaled, authored, "a boss got easier when the guns got faster")
            XCTAssertLessThan(
                Double(scaled), Double(authored) * 2.4,
                "boss health grew by more than the fire rate did — the fights got longer"
            )
        }
    }

    // MARK: - Wingmen

    func testWingmenGrowCommonerButNeverDoubleEveryWave() {
        XCTAssertLessThan(CombatRules.wingmanChance(forLevel: 1), CombatRules.wingmanChance(forLevel: 20),
                          "the teaching levels should be the sparsest")
        for level in 1...GameConfiguration.totalLevels {
            let chance = CombatRules.wingmanChance(forLevel: level)
            XCTAssertGreaterThan(chance, 0)
            XCTAssertLessThanOrEqual(chance, 0.5, "level \(level) pairs up more than every other enemy")
        }
    }

    // MARK: - Shards

    func testEveryKillBurstsIntoAtLeastTwoShards() {
        for points in [0, 8, 10, 15, 50, 500] {
            XCTAssertGreaterThanOrEqual(CombatRules.shardCount(forPoints: points), 2)
            XCTAssertLessThanOrEqual(CombatRules.shardCount(forPoints: points), 8)
        }
    }

    func testTougherEnemiesPayMoreShards() {
        XCTAssertLessThan(
            CombatRules.shardCount(forPoints: 10),
            CombatRules.shardCount(forPoints: 50),
            "a tank paid out no more than a basic fighter"
        )
    }

    // MARK: - Overdrive

    func testChargeIsClampedToTheMeter() {
        XCTAssertEqual(OverdriveRules.charge(0.9, adding: 0.5), 1.0)
        XCTAssertEqual(OverdriveRules.charge(0.1, adding: -0.5), 0.0)
        XCTAssertEqual(OverdriveRules.charge(0.25, adding: 0.25), 0.5, accuracy: 1e-9)
    }

    /// The meter has to fill on a normal level. Level 1 is 32 basic enemies plus the
    /// wingmen that join them, and a boss with two phase breaks; if all of that cannot
    /// fill it with a few grazes, the player never meets the mechanic until much later.
    func testALevelOneRunCanFillTheMeter() {
        let kills = Int(32 * (1 + CombatRules.wingmanChance(forLevel: 1)))
        let shards = kills * CombatRules.shardCount(forPoints: 10) + 2 * CombatRules.bossPhaseShards
        let grazes = 10
        let charge = Double(shards) * OverdriveRules.chargePerShard + Double(grazes) * OverdriveRules.chargePerGraze
        XCTAssertGreaterThanOrEqual(charge, 1.0, "a level-1 run fills only \(Int(charge * 100))% of the meter")
    }

    func testGrazingIsWorthMoreThanAShard() {
        XCTAssertGreaterThan(OverdriveRules.chargePerGraze, OverdriveRules.chargePerShard,
                             "risk should pay better than collecting")
    }

    func testFullnessToleratesRounding() {
        var charge = 0.0
        for _ in 0..<50 { charge = OverdriveRules.charge(charge, adding: 0.02) }
        XCTAssertTrue(OverdriveRules.isFull(charge), "fifty 2% top-ups did not count as full (\(charge))")
    }

    // MARK: - Graze

    func testARoundTouchingTheCoreIsAHitNotAGraze() {
        let hitbox = Player.hitboxRadius
        XCTAssertFalse(GrazeRules.isGraze(distance: 0, bulletRadius: 5, hitboxRadius: hitbox))
        XCTAssertFalse(GrazeRules.isGraze(distance: hitbox + 5, bulletRadius: 5, hitboxRadius: hitbox))
    }

    func testARoundSkimmingPastIsAGraze() {
        let hitbox = Player.hitboxRadius
        XCTAssertTrue(GrazeRules.isGraze(distance: hitbox + 5 + 1, bulletRadius: 5, hitboxRadius: hitbox))
        XCTAssertTrue(GrazeRules.isGraze(distance: GrazeRules.radius + 5, bulletRadius: 5, hitboxRadius: hitbox))
    }

    func testARoundWellClearIsNothing() {
        XCTAssertFalse(GrazeRules.isGraze(distance: GrazeRules.radius + 6, bulletRadius: 5, hitboxRadius: Player.hitboxRadius))
    }

    // MARK: - Hit-stop

    func testOrdinaryBeatsAreShorterThanTheBigMoments() {
        XCTAssertLessThan(HitStop.heavyKill.duration, HitStop.bossPhase.duration)
        XCTAssertLessThan(HitStop.bossPhase.duration, HitStop.bossDefeat.duration)
        for beat in [HitStop.heavyKill, HitStop.playerHit, HitStop.overdrive, HitStop.bossPhase, HitStop.bossDefeat] {
            XCTAssertGreaterThan(beat.timeScale, 0, "a beat that stops time entirely would never end")
            XCTAssertLessThan(beat.timeScale, 1)
            XCTAssertLessThanOrEqual(beat.duration, 1.0, "a beat longer than a second is a cutscene")
        }
    }
}
