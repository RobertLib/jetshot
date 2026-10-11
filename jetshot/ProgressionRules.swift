//
//  ProgressionRules.swift
//  jetshot
//

import Foundation

// MARK: - Medals

/// The three medals a campaign level can award, as a bit set — which is also exactly
/// how they are stored, one `Int` per level (see `LevelManager.recordMedals`).
///
/// Medals are the replay layer the fifty levels were missing. Clearing a level and
/// collecting its coins were the only goals a level had, and both are met by the time
/// most players move on. A medal asks for a *different* way of playing the same level —
/// cleanly, aggressively, thoroughly — which is what makes going back to it a new game
/// rather than a repeat. Sky Force's per-stage medals are the model, without the
/// grinding they are tied to there: a medal unlocks nothing and costs nothing.
nonisolated struct MedalSet: OptionSet, Hashable {
    let rawValue: Int

    /// No damage taken. A hit the Overdrive absorbed still counts as a hit: the medal is
    /// about not being touched, and the insurance is the price of having been.
    static let untouched = MedalSet(rawValue: 1 << 0)
    /// The chain reached the level's target multiplier.
    static let chain = MedalSet(rawValue: 1 << 1)
    /// At least `MedalRules.hunterFraction` of the level's enemies destroyed.
    static let hunter = MedalSet(rawValue: 1 << 2)

    static let all: MedalSet = [.untouched, .chain, .hunter]

    /// In display order.
    static let ordered: [MedalSet] = [.untouched, .chain, .hunter]

    var count: Int { rawValue.nonzeroBitCount }
}

/// What it takes to earn each medal.
///
/// `nonisolated` and SpriteKit-free for the reason `ComboRules` gives: these are the
/// numbers worth pinning down in tests.
nonisolated enum MedalRules {

    /// Share of a level's enemies that has to be destroyed for the hunter medal.
    ///
    /// Not 100%: enemies that dive off the bottom edge in the middle of a crossfire are
    /// a matter of luck as much as of play, and a medal that one stray kamikaze can deny
    /// gets abandoned rather than chased.
    static let hunterFraction = 0.85

    /// Chain length the chain medal asks for on `level`.
    ///
    /// Stepped like the toughness blocks: x4 while the game is still teaching, x6 through
    /// the middle, x8 — the top of the table — from level 21. Each target is a tier
    /// threshold in `ComboRules.tiers`, so the meter itself announces the moment.
    static func chainTarget(forLevel level: Int) -> Int {
        switch level {
        case ...5: return 10
        case 6...20: return 25
        default: return 40
        }
    }

    /// The multiplier that chain target pays, for the medal's label.
    static func chainTargetMultiplier(forLevel level: Int) -> Int {
        return ComboRules.multiplier(forChain: chainTarget(forLevel: level))
    }

    /// The medals a finished run earned.
    static func earned(
        level: Int,
        hitsTaken: Int,
        bestChain: Int,
        enemiesDestroyed: Int,
        enemiesSeen: Int
    ) -> MedalSet {
        var medals: MedalSet = []
        if hitsTaken == 0 { medals.insert(.untouched) }
        if bestChain >= chainTarget(forLevel: level) { medals.insert(.chain) }
        if isHunter(destroyed: enemiesDestroyed, seen: enemiesSeen) { medals.insert(.hunter) }
        return medals
    }

    static func isHunter(destroyed: Int, seen: Int) -> Bool {
        guard seen > 0 else { return true }
        return Double(destroyed) / Double(seen) >= hunterFraction - 1e-9
    }
}

// MARK: - Endless perks

/// Upgrades offered after every endless boss: pick one of three, keep it for the run.
///
/// Endless was the campaign's levels strung together with nothing that changed but the
/// pressure. A choice every five rounds turns a run into a build — the thing that makes
/// roguelite shooters (Steredenn, Nova Drift) replayable — and gives each boss a reward
/// beyond survival. Nothing persists between runs; every run starts from the same ship.
nonisolated enum EndlessPerk: String, CaseIterable, Hashable {
    case fireRate
    case coolant
    case capacitor
    case longOverdrive
    case daredevil
    case chainKeeper
    case armor
    case arsenal
    case roundShield
    case magnet

    /// How many times a perk can be taken in one run.
    var maxStacks: Int {
        switch self {
        case .fireRate, .capacitor, .chainKeeper: return 3
        case .coolant, .longOverdrive, .daredevil: return 2
        case .armor, .arsenal: return 4
        case .roundShield, .magnet: return 1
        }
    }
}

/// The arithmetic behind each perk, as a function of how many times it has been taken.
nonisolated enum PerkRules {

    /// Fire interval multiplier: 15% faster per stack.
    static func fireIntervalScale(stacks: Int) -> Double {
        return pow(0.85, Double(max(0, stacks)))
    }

    /// Heat per shot multiplier: 30% cooler per stack.
    static func heatScale(stacks: Int) -> Double {
        return pow(0.7, Double(max(0, stacks)))
    }

    /// Overdrive charge multiplier: 35% faster per stack.
    static func chargeScale(stacks: Int) -> Double {
        return 1 + 0.35 * Double(max(0, stacks))
    }

    /// Seconds added to an Overdrive per stack.
    static func overdriveBonus(stacks: Int) -> TimeInterval {
        return 2.0 * TimeInterval(max(0, stacks))
    }

    /// Graze ring multiplier: 35% wider per stack.
    static func grazeRadiusScale(stacks: Int) -> Double {
        return 1 + 0.35 * Double(max(0, stacks))
    }

    /// Graze score multiplier: double per stack.
    static func grazeScoreScale(stacks: Int) -> Int {
        return 1 << max(0, stacks)
    }

    /// Seconds added to the chain window per stack.
    static func chainWindowBonus(stacks: Int) -> TimeInterval {
        return 0.6 * TimeInterval(max(0, stacks))
    }

    /// Which perks may be offered, given what the run already has.
    ///
    /// A perk at its cap is never offered, and neither is one that would do nothing:
    /// a life at full lives, guns on a full arsenal. An offer of a dead card is worse
    /// than an offer of two.
    static func eligible(
        stacks: [EndlessPerk: Int],
        livesAtMax: Bool,
        arsenalAtMax: Bool
    ) -> [EndlessPerk] {
        return EndlessPerk.allCases.filter { perk in
            if (stacks[perk] ?? 0) >= perk.maxStacks { return false }
            if perk == .armor && livesAtMax { return false }
            if perk == .arsenal && arsenalAtMax { return false }
            return true
        }
    }

    /// Up to `count` distinct perks to choose between.
    static func offer<G: RandomNumberGenerator>(
        from eligible: [EndlessPerk],
        count: Int = 3,
        using generator: inout G
    ) -> [EndlessPerk] {
        return Array(eligible.shuffled(using: &generator).prefix(count))
    }
}
