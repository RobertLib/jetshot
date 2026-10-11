//
//  CombatRules.swift
//  jetshot
//

import Foundation
import CoreGraphics

/// The arithmetic of a fight: how much a round hurts, how tough an enemy is, and what a
/// kill pays out in shards.
///
/// `nonisolated` and free of SpriteKit for the reason `GameRules` and `ComboRules` give:
/// these numbers are the part of the combat model worth pinning down in tests, and the
/// `jetshotTests` target cannot reach main-actor state.
///
/// ## Why enemies have hit points now
///
/// Every enemy but the tank used to die to a single round, at 3.3 rounds a second. That
/// is a game where nothing ever *takes* a hit — a target is either there or it is gone —
/// so the flash, the squash and the impact spark that sell a weapon had nothing to land
/// on, and adding firepower only shortened a fight that was already instantaneous. The
/// guns now fire a dense stream (see `GameConfiguration.defaultShootInterval`) and
/// enemies soak a few rounds of it, which is what turns shooting from clicking on things
/// into chewing through them.
nonisolated enum CombatRules {

    // MARK: - Damage

    /// What one round of each kind takes off a target.
    static let boltDamage = 1
    static let overdriveBoltDamage = 2
    static let sideMissileDamage = 2
    static let homingMissileDamage = 4

    // MARK: - Toughness

    /// Multiplier on an enemy's base health for a campaign level.
    ///
    /// Steps every ten levels rather than ramping, so a block of levels shares one
    /// toughness and the step is felt as "this world is harder". The player's arsenal
    /// grows from one barrel to eight over the same span, which is what this offsets: at
    /// level 41 a basic enemy still lasts about as long against a full arsenal as it did
    /// at level 1 against two barrels.
    static func healthScale(forLevel level: Int) -> Double {
        let tier = max(0, (max(1, level) - 1) / 10)
        return 1.0 + 0.2 * Double(tier)
    }

    /// An enemy's health on a given level. Rounded to nearest so the one-hit popcorn
    /// stays one-hit for most of the game — a 1.2 that rounded up would double it.
    static func health(base: Int, level: Int) -> Int {
        let scaled = Double(max(1, base)) * healthScale(forLevel: level)
        return max(1, Int(scaled.rounded(.toNearestOrAwayFromZero)))
    }

    /// Boss health is authored in hits at the old fire rate. Scaled by roughly the ratio
    /// between the old and new cadence, a little under it so a boss fight comes out
    /// slightly shorter than it was — the fights were the longest stretch of the game
    /// with the least going on in them.
    static let bossHealthScale: Double = 2.1

    static func bossHealth(authored: Int) -> Int {
        return max(1, Int((Double(authored) * bossHealthScale).rounded()))
    }

    // MARK: - Shards

    /// How many energy shards a kill throws out.
    ///
    /// Scaled with the enemy's points, so the dangerous ones burst into a proper shower
    /// and the popcorn into a couple of sparks. Never fewer than two: a single shard
    /// reads as a stray particle rather than as loot.
    static func shardCount(forPoints points: Int) -> Int {
        return min(8, max(2, points / 6 + 1))
    }

    /// Base score of one shard, before the score and chain multipliers.
    ///
    /// Deliberately small. Every shard is collected sooner or later, so shards measure
    /// how much was killed rather than how well; worth more, they inflated a run's score
    /// several times over and made every record set before them trivially beatable.
    static let shardScore = 2

    /// Shards a boss sheds when its armour cracks into the next phase, and when it dies.
    static let bossPhaseShards = 18
    static let bossDefeatShards = 40

    /// Kills of enemies at least this tough rate a hit-stop and a local bullet cancel —
    /// the heavy kills that should feel heavy.
    static let heavyKillHealth = 5

    /// Radius around a heavy kill inside which its neighbourhood's fire is cancelled.
    static let heavyKillCancelRadius: CGFloat = 90

    // MARK: - Wingmen

    /// Chance that an enemy spawned from an ordinary wave arrives with a wingman — a
    /// second of its kind in the mirrored lane.
    ///
    /// This is where a level's density comes from, rather than from squeezing the
    /// authored cadence: the waves keep their shape and their length, and the screen
    /// gains symmetric pairs, the arrangement a player reads as a designed attack rather
    /// than as more noise. Gentle on the teaching levels, capped at one in two.
    static func wingmanChance(forLevel level: Int) -> Double {
        return min(0.5, 0.2 + 0.015 * Double(max(1, level)))
    }
}

/// The Overdrive meter: filled by collecting shards and grazing fire, spent on a few
/// seconds of overwhelming firepower that opens by cancelling every hostile round on
/// screen.
///
/// It is the decision the game was missing. A full meter can be spent now for score, held
/// for the boss, or simply carried — because a full meter also fires itself when a hit
/// would otherwise land, at the cost of the charge. That last rule is what makes holding
/// it a real choice rather than hoarding: insurance against the hit you did not see,
/// traded against damage you could be doing now.
nonisolated enum OverdriveRules {

    /// Charge from one collected shard.
    ///
    /// Every shard is eventually collected, so this sets how often the meter fills. A
    /// level-1 run — about forty kills and the boss's two phase breaks — fills it once,
    /// during the boss, which is where a new player should first meet it. A late level
    /// with three times the traffic fills it three or four times.
    static let chargePerShard: Double = 0.008

    /// Charge from grazing one hostile round. Worth more than a shard because it costs
    /// risk rather than time.
    static let chargePerGraze: Double = 0.02

    /// How long the overdrive lasts once triggered.
    static let duration: TimeInterval = 6.0

    /// Invulnerability that follows activation, so the burst that cancels the screen
    /// cannot be immediately undone by a round that spawned on the same frame.
    static let activationGrace: TimeInterval = 1.0

    /// Overdrive fire cadence, as a fraction of the normal interval.
    static let fireIntervalScale: Double = 0.65

    /// Score multiplier on shards collected during an overdrive.
    static let shardScoreMultiplier = 2

    /// New charge after `amount` is added. Clamped to the meter.
    static func charge(_ current: Double, adding amount: Double) -> Double {
        return min(1.0, max(0.0, current + amount))
    }

    static func isFull(_ charge: Double) -> Bool {
        return charge >= 1.0 - 1e-9
    }
}

/// Grazing: flying close past a hostile round without being hit by it.
///
/// Only possible because the ship's hitbox is now a small core rather than the whole
/// hull (see `Player.hitboxRadius`). The gap between that core and the edge of the graze
/// ring is the space a skilled player lives in: it pays score, Overdrive charge and
/// weapon cooling, so threading fire is rewarded rather than merely survived.
nonisolated enum GrazeRules {

    /// Distance from the ship's core, plus the round's own radius, inside which a round
    /// counts as grazed.
    static let radius: CGFloat = 26

    /// Base score of a graze, before multipliers.
    static let score = 3

    /// Heat removed per graze. Close flying keeps the guns cool.
    static let heatRelief: CGFloat = 0.05

    /// Whether a round at `distance` from the ship's core, of the given hit radius, is a
    /// graze. Rounds that are actually touching the core are hits, not grazes — the
    /// contact handler deals with those, and must not be pre-empted by a graze payout on
    /// the same frame.
    ///
    /// `ring` is the graze radius in force — `radius`, widened by the endless run's
    /// DAREDEVIL perk.
    static func isGraze(distance: CGFloat, bulletRadius: CGFloat, hitboxRadius: CGFloat, ring: CGFloat = radius) -> Bool {
        return distance > hitboxRadius + bulletRadius && distance <= ring + bulletRadius
    }
}

/// Short freezes and slow-downs that mark the big moments.
///
/// Values follow the usual guidance for constant-fire games: never on an ordinary hit,
/// a few hundredths of a second on a heavy kill, and a longer slow-motion beat only on
/// events the player should stop and look at.
nonisolated enum HitStop {
    struct Beat {
        let duration: TimeInterval
        let timeScale: CGFloat
    }

    static let heavyKill = Beat(duration: 0.05, timeScale: 0.05)
    static let playerHit = Beat(duration: 0.14, timeScale: 0.1)
    static let overdrive = Beat(duration: 0.32, timeScale: 0.22)
    static let bossPhase = Beat(duration: 0.4, timeScale: 0.3)
    static let bossDefeat = Beat(duration: 0.9, timeScale: 0.3)
}
