//
//  ProgressionRulesTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// Pins down the medal and endless-perk rules in `ProgressionRules`.
///
/// Pure functions over plain numbers, like `ComboRulesTests`.
final class ProgressionRulesTests: XCTestCase {

    // MARK: - Medals

    func testEveryChainTargetIsATierTheMeterAnnounces() {
        let thresholds = Set(ComboRules.tiers.map { $0.chain })
        for level in 1...GameConfiguration.totalLevels {
            XCTAssertTrue(
                thresholds.contains(MedalRules.chainTarget(forLevel: level)),
                "level \(level)'s chain medal asks for a length the meter never marks"
            )
        }
    }

    func testChainTargetsNeverGetEasier() {
        var previous = 0
        for level in 1...GameConfiguration.totalLevels {
            let target = MedalRules.chainTarget(forLevel: level)
            XCTAssertGreaterThanOrEqual(target, previous, "level \(level) asks for a shorter chain than the one before")
            previous = target
        }
    }

    func testACleanThoroughChainedRunEarnsEverything() {
        let medals = MedalRules.earned(level: 30, hitsTaken: 0, bestChain: 40, enemiesDestroyed: 100, enemiesSeen: 100)
        XCTAssertEqual(medals, .all)
    }

    func testOneHitCostsOnlyTheUntouchedMedal() {
        let medals = MedalRules.earned(level: 30, hitsTaken: 1, bestChain: 40, enemiesDestroyed: 100, enemiesSeen: 100)
        XCTAssertEqual(medals, [.chain, .hunter])
    }

    func testTheChainMedalNeedsTheLevelsTarget() {
        let level = 30
        let target = MedalRules.chainTarget(forLevel: level)
        XCTAssertFalse(MedalRules.earned(level: level, hitsTaken: 5, bestChain: target - 1,
                                         enemiesDestroyed: 0, enemiesSeen: 10).contains(.chain))
        XCTAssertTrue(MedalRules.earned(level: level, hitsTaken: 5, bestChain: target,
                                        enemiesDestroyed: 0, enemiesSeen: 10).contains(.chain))
    }

    func testTheHunterMedalSitsAtItsThreshold() {
        XCTAssertTrue(MedalRules.isHunter(destroyed: 85, seen: 100))
        XCTAssertFalse(MedalRules.isHunter(destroyed: 84, seen: 100))
        XCTAssertTrue(MedalRules.isHunter(destroyed: 0, seen: 0), "a level with nothing to kill cannot be failed")
    }

    func testMedalSetsRoundTripThroughTheirStoredForm() {
        for raw in 0...7 {
            XCTAssertEqual(MedalSet(rawValue: raw).rawValue, raw)
        }
        XCTAssertEqual(MedalSet.all.count, 3)
        XCTAssertEqual(MedalSet.ordered.count, 3)
    }

    // MARK: - Perks

    func testStackingAlwaysHelpsAndNeverInverts() {
        for stacks in 0..<3 {
            XCTAssertLessThan(PerkRules.fireIntervalScale(stacks: stacks + 1), PerkRules.fireIntervalScale(stacks: stacks))
            XCTAssertGreaterThan(PerkRules.fireIntervalScale(stacks: stacks + 1), 0)
            XCTAssertLessThan(PerkRules.heatScale(stacks: stacks + 1), PerkRules.heatScale(stacks: stacks))
            XCTAssertGreaterThan(PerkRules.chargeScale(stacks: stacks + 1), PerkRules.chargeScale(stacks: stacks))
            XCTAssertGreaterThan(PerkRules.grazeRadiusScale(stacks: stacks + 1), PerkRules.grazeRadiusScale(stacks: stacks))
        }
        XCTAssertEqual(PerkRules.fireIntervalScale(stacks: 0), 1)
        XCTAssertEqual(PerkRules.overdriveBonus(stacks: 0), 0)
        XCTAssertEqual(PerkRules.chainWindowBonus(stacks: 0), 0)
        XCTAssertEqual(PerkRules.grazeScoreScale(stacks: 0), 1)
    }

    func testAMaxedPerkIsNeverOffered() {
        let stacks: [EndlessPerk: Int] = [.magnet: 1, .fireRate: EndlessPerk.fireRate.maxStacks]
        let eligible = PerkRules.eligible(stacks: stacks, livesAtMax: false, arsenalAtMax: false)
        XCTAssertFalse(eligible.contains(.magnet))
        XCTAssertFalse(eligible.contains(.fireRate))
        XCTAssertTrue(eligible.contains(.coolant))
    }

    func testDeadCardsAreNotOffered() {
        let eligible = PerkRules.eligible(stacks: [:], livesAtMax: true, arsenalAtMax: true)
        XCTAssertFalse(eligible.contains(.armor), "an extra life was offered at full lives")
        XCTAssertFalse(eligible.contains(.arsenal), "more guns were offered on a full arsenal")
    }

    func testAnOfferIsThreeDistinctEligiblePerks() {
        var generator = SystemRandomNumberGenerator()
        let eligible = PerkRules.eligible(stacks: [:], livesAtMax: false, arsenalAtMax: false)
        for _ in 0..<50 {
            let offer = PerkRules.offer(from: eligible, using: &generator)
            XCTAssertEqual(offer.count, 3)
            XCTAssertEqual(Set(offer).count, 3, "the same perk was offered twice: \(offer)")
            XCTAssertTrue(offer.allSatisfy(eligible.contains))
        }
    }

    func testAShortPoolOffersWhatIsLeft() {
        var generator = SystemRandomNumberGenerator()
        XCTAssertEqual(PerkRules.offer(from: [.coolant], using: &generator), [.coolant])
        XCTAssertTrue(PerkRules.offer(from: [], using: &generator).isEmpty)
    }
}
