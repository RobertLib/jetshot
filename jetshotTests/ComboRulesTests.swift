//
//  ComboRulesTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// The chain multiplier is folded into every score award in the game, so a mistake in
/// this table is a mistake in every number the player ever sees. It is also pure
/// arithmetic over a hand-written table, which is exactly the shape of thing that drifts
/// silently when someone retunes a tier — hence pinning the boundaries rather than
/// spot-checking the middle of each band.
final class ComboRulesTests: XCTestCase {

    // MARK: - Multiplier table

    func testChainBelowFirstTierPaysFlat() {
        for chain in 0..<ComboRules.tiers[0].chain {
            XCTAssertEqual(
                ComboRules.multiplier(forChain: chain), 1,
                "a chain of \(chain) is below the first tier and must not multiply"
            )
        }
    }

    func testEveryTierPaysItsMultiplierAtItsExactThreshold() {
        for tier in ComboRules.tiers {
            XCTAssertEqual(
                ComboRules.multiplier(forChain: tier.chain), tier.multiplier,
                "tier at chain \(tier.chain) should pay x\(tier.multiplier) on the kill that reaches it"
            )
        }
    }

    func testEachTierIsStillPaidOneKillBelowTheNextOne() {
        // The band, not just its threshold: an off-by-one in the `chain >= tier.chain`
        // scan would show up here and nowhere else.
        for (offset, tier) in ComboRules.tiers.enumerated() {
            guard offset + 1 < ComboRules.tiers.count else { continue }
            let lastChainInBand = ComboRules.tiers[offset + 1].chain - 1
            XCTAssertEqual(
                ComboRules.multiplier(forChain: lastChainInBand), tier.multiplier,
                "chain \(lastChainInBand) is still inside the x\(tier.multiplier) band"
            )
        }
    }

    func testMultiplierNeverDecreasesAsTheChainGrows() {
        var previous = ComboRules.multiplier(forChain: 0)
        for chain in 1...200 {
            let current = ComboRules.multiplier(forChain: chain)
            XCTAssertGreaterThanOrEqual(
                current, previous,
                "the multiplier went backwards at chain \(chain), so a kill would cost the player score"
            )
            previous = current
        }
    }

    func testTiersAreAuthoredInAscendingOrder() {
        // `multiplier(forChain:)` scans the table and keeps the last match, which only
        // yields the right answer while the table ascends on both fields.
        for (offset, tier) in ComboRules.tiers.enumerated() where offset > 0 {
            let previous = ComboRules.tiers[offset - 1]
            XCTAssertGreaterThan(tier.chain, previous.chain, "tier \(offset) is out of order")
            XCTAssertGreaterThan(tier.multiplier, previous.multiplier, "tier \(offset) pays no more than the one below it")
        }
    }

    // MARK: - Tier index

    func testTierIndexIsZeroBelowTheFirstTier() {
        XCTAssertEqual(ComboRules.tierIndex(forChain: 0), 0)
        XCTAssertEqual(ComboRules.tierIndex(forChain: ComboRules.tiers[0].chain - 1), 0)
    }

    func testTierIndexStepsExactlyOncePerTier() {
        // `ComboSystem` fires its step-up cue when this value increases, so a tier that
        // failed to register here would be a silent promotion.
        var seen: [Int] = []
        var previous = 0
        for chain in 0...(ComboRules.tiers.last!.chain + 10) {
            let index = ComboRules.tierIndex(forChain: chain)
            XCTAssertGreaterThanOrEqual(index, previous, "tier index fell at chain \(chain)")
            if index > previous {
                XCTAssertEqual(index, previous + 1, "tier index skipped a step at chain \(chain)")
                seen.append(chain)
            }
            previous = index
        }
        XCTAssertEqual(seen, ComboRules.tiers.map(\.chain), "the steps did not land on the authored thresholds")
        XCTAssertEqual(previous, ComboRules.tiers.count)
    }

    // MARK: - Decay window

    func testWindowShrinksWithTheChainAndThenHoldsAtTheFloor() {
        XCTAssertEqual(ComboRules.window(forChain: 0), ComboRules.baseWindow, accuracy: 0.0001)

        let midChain = 10
        let expectedMid = ComboRules.baseWindow - ComboRules.windowDecayPerKill * TimeInterval(midChain)
        XCTAssertEqual(ComboRules.window(forChain: midChain), expectedMid, accuracy: 0.0001)

        // Far past the point where the linear decay would go negative.
        XCTAssertEqual(ComboRules.window(forChain: 500), ComboRules.minWindow, accuracy: 0.0001)
    }

    func testWindowIsNeverBelowTheFloorOrAboveTheBase() {
        for chain in 0...500 {
            let window = ComboRules.window(forChain: chain)
            XCTAssertGreaterThanOrEqual(window, ComboRules.minWindow, "chain \(chain) would expire unreachably fast")
            XCTAssertLessThanOrEqual(window, ComboRules.baseWindow, "chain \(chain) is more forgiving than a fresh chain")
        }
    }

    func testWindowStaysLongerThanTheTightestWaveCadence() {
        // The floor is tuned against spawn density: if the window could close faster than
        // enemies arrive, a long chain would be impossible to hold no matter how well the
        // player shot. `minSpawnInterval` is the tightest the pacing pass can ever make a
        // wave, so the floor has to leave room above it.
        XCTAssertGreaterThan(
            ComboRules.minWindow, GameConfiguration.minSpawnInterval,
            "the chain can lapse faster than the spawner can feed it"
        )
    }

    func testAnOverheatCannotOutlastTheTightestChainWindow() {
        // The constraint that sets `overheatCooldownTime`. If the gun can be locked out
        // for longer than a chain survives without a kill, then every overheat destroys
        // whatever chain the player was holding regardless of how well they were flying
        // — which would make the scoring system punish exactly the players engaging with
        // it hardest.
        XCTAssertLessThan(
            GameConfiguration.overheatCooldownTime, ComboRules.minWindow,
            "an overheat outlasts the chain window, so overheating always costs the chain"
        )
    }

    // MARK: - Next-tier hint

    func testNextTierChainPointsAtTheUpcomingThreshold() {
        XCTAssertEqual(ComboRules.nextTierChain(forChain: 0), ComboRules.tiers[0].chain)

        for (offset, tier) in ComboRules.tiers.enumerated() where offset + 1 < ComboRules.tiers.count {
            XCTAssertEqual(
                ComboRules.nextTierChain(forChain: tier.chain),
                ComboRules.tiers[offset + 1].chain,
                "the hint under the meter points at the wrong target from chain \(tier.chain)"
            )
        }
    }

    func testNextTierChainIsNilAtTheTopOfTheTable() {
        // The meter switches from "N TO xM" to a plain chain count on this, so a
        // non-nil answer here would print a target that can never be reached.
        XCTAssertNil(ComboRules.nextTierChain(forChain: ComboRules.tiers.last!.chain))
        XCTAssertNil(ComboRules.nextTierChain(forChain: ComboRules.tiers.last!.chain + 50))
    }
}
