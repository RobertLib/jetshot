//
//  EndlessDirector.swift
//  jetshot
//

import Foundation

/// Progression for the endless run: how big each round is, how fast it arrives, how deep
/// into the enemy roster it draws, and when a boss shows up.
///
/// The campaign answers "can I finish this?" and stops having an answer once all fifty
/// levels are cleared. Endless answers "how far can I get?", which never stops — and it is
/// the mode the chain multiplier was really built for, because a run with no completion
/// condition makes the score the entire point.
///
/// `nonisolated` for the reason `GameRules` and `ComboRules` give: this is arithmetic over
/// a round number, it is the part worth pinning down in tests, and `jetshotTests` cannot
/// reach main-actor state. Choosing *which* enemies fill a wave lives in `EndlessDirector`
/// below, because `EnemyType` is main-actor bound.
nonisolated enum EndlessRules {

    /// A boss every fifth round.
    ///
    /// Frequent enough that a run always has a near-term goal to aim at, and rare enough
    /// that reaching one still feels like arriving somewhere. Without them an endless run
    /// is a treadmill, which is the exact complaint the campaign's fifty identical late
    /// bosses were guilty of from the other direction.
    static let bossEveryRounds = 5

    /// Rounds after which the enemy roster stops widening and only the pressure rises.
    static let maxTier = 7

    static func isBossRound(_ round: Int) -> Bool {
        return round > 0 && round % bossEveryRounds == 0
    }

    /// How deep into the roster round `round` is allowed to draw.
    ///
    /// One new tier every three rounds, so the first boss at round 5 arrives with the
    /// player having met two tiers' worth of enemies — enough that the run has already
    /// changed shape once before it is asked to change again.
    static func tier(forRound round: Int) -> Int {
        guard round > 0 else { return 0 }
        return min((round - 1) / 3, maxTier)
    }

    /// Enemies in a round's main wave. Grows, then holds: past a certain point more
    /// enemies on screen stops being harder and starts being unreadable, and the
    /// difficulty has to come from the roster and the cadence instead.
    static func enemyCount(forRound round: Int) -> Int {
        return min(6 + round, 20)
    }

    /// Gap between spawns within a round, tightening toward a floor.
    ///
    /// The floor is `GameConfiguration.minSpawnInterval`, the same one the campaign's
    /// pacing pass respects, so an endless wave can never clump tighter than a level 50
    /// wave can.
    ///
    /// Opens at 0.83 s rather than the original 1.12: the first rounds were the slowest
    /// stretch of the whole mode, and with enemies now soaking a few rounds each and the
    /// guns firing a stream, round one emptied faster than it filled.
    static func spawnInterval(forRound round: Int) -> TimeInterval {
        return max(GameConfiguration.minSpawnInterval, 0.85 - 0.025 * TimeInterval(round))
    }

    /// Every third round closes on a formation, for the same reason the campaign's levels
    /// do: it breaks a run of loose waves into something with a shape.
    static func hasFormation(inRound round: Int) -> Bool {
        return round % 3 == 0
    }

    /// Which campaign boss stands in for a given endless boss round.
    ///
    /// The round number itself, clamped. An endless run therefore tours the authored boss
    /// identities in order — the round 5 boss is level 5's, the round 40 boss is level
    /// 40's — rather than refighting one, which is what the campaign's own late bosses
    /// used to do to themselves. Past level 50 the final boss repeats; by then the run is
    /// deep enough that its health and the player's arsenal decide it.
    static func bossLevel(forRound round: Int) -> Int {
        return min(GameConfiguration.totalLevels, max(1, round))
    }

    /// Which campaign level's hazard track (walls, asteroids) an endless round draws.
    ///
    /// Runs ahead of `bossLevel` so the environment escalates faster than the enemies do:
    /// by the time a run is deep, staying alive is as much about the playfield as about
    /// what is shooting at you.
    static func hazardLevel(forRound round: Int) -> Int {
        return min(GameConfiguration.totalLevels, max(1, round * 2))
    }
}

/// Builds the actual waves for an endless run.
///
/// Main-actor, unlike `EndlessRules` above, purely because `EnemyType` and `EnemyWave` are
/// — the same split `ComboSystem` makes against `ComboRules`.
final class EndlessDirector {

    /// The roster, widening by tier. Each tier adds a pair of enemies that changes what
    /// the player has to do rather than just how much of it: tier 1 starts weaving, tier 3
    /// starts charging and sniping, tier 6 starts splitting and teleporting.
    private static let tiers: [[EnemyType]] = [
        [.basic, .fast],
        [.striker, .zigzag],
        [.heavy, .scout],
        [.kamikaze, .sniper],
        [.turret, .bomber],
        [.eliteGuard, .spinner],
        [.ghost, .splitter],
        [.bouncer, .teleporter]
    ]

    /// Everything unlocked at `round`, oldest tier first.
    static func roster(forRound round: Int) -> [EnemyType] {
        let tier = EndlessRules.tier(forRound: round)
        return Array(tiers.prefix(tier + 1).joined())
    }

    /// What a round's loose wave draws from: the unlocked types that fly themselves.
    ///
    /// The scout, bomber, elite guard and spinner only move under `FormationManager`.
    /// Drawn into the loose wave, they used to be handed to `Enemy.startMovement`, which
    /// did nothing with them — so they parked just above the screen, out of reach and
    /// still firing, and the round, which ends only when the playfield is empty, never
    /// ended. Tier 0 is all line fighters, so this is never empty.
    static func looseRoster(forRound round: Int) -> [EnemyType] {
        return roster(forRound: round).filter { !$0.isFormationOnly }
    }

    /// What a round's formation draws from: the unlocked types that can fly in one.
    ///
    /// It used to be the whole roster, and `FormationManager` never runs a type's own
    /// movement routine — a turret in formation never docked or fired its bursts, a
    /// bouncer never bounced, a teleporter never teleported. See
    /// `EnemyType.canFlyInFormation`.
    static func formationRoster(forRound round: Int) -> [EnemyType] {
        return roster(forRound: round).filter { $0.canFlyInFormation }
    }

    /// The waves for one round.
    ///
    /// Deliberately drawn from the *whole* unlocked roster rather than only the newest
    /// tier: an endless run should keep every enemy the player has learned in circulation,
    /// so that what makes round 30 hard is the combination rather than simply the fact
    /// that round 30's enemies are new. The loose wave draws from `looseRoster`, the
    /// formation from `formationRoster`.
    static func waves(forRound round: Int) -> [EnemyWave] {
        let loose = looseRoster(forRound: round)
        guard !loose.isEmpty else { return [] }

        let interval = EndlessRules.spawnInterval(forRound: round)
        var waves: [EnemyWave] = []

        let main = (0..<EndlessRules.enemyCount(forRound: round)).map { _ in
            loose.randomElement() ?? .basic
        }
        waves.append(
            EnemyWave(enemies: main, spawnDelay: GameConfiguration.minWaveDelay, spawnInterval: interval)
        )

        if EndlessRules.hasFormation(inRound: round) {
            // One type per formation, so it reads as a single object arriving.
            let type = formationRoster(forRound: round).randomElement() ?? .basic
            let patterns: [FormationPattern] = [.vShape, .arrow, .line, .arc, .diamond, .circle]
            waves.append(
                EnemyWave(
                    enemies: Array(repeating: type, count: 6),
                    spawnDelay: GameConfiguration.minWaveDelay,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: patterns.randomElement() ?? .vShape
                )
            )
        }

        return waves
    }
}
