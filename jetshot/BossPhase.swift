//
//  BossPhase.swift
//  jetshot
//

import CoreGraphics
import Foundation

// Boss attack patterns.
//
// `nonisolated` like `PhysicsCategory` and `ExplosionSize`: a bare enum of cases carries
// no state and has no business on the main actor. `BossPhaseRules` reasons about these
// and is pure, so it cannot see a main-actor type — and nor can `jetshotTests`.
nonisolated enum BossAttackPattern: CaseIterable, Sendable {
    case straightShot   // Single bullet straight down
    case doubleShot     // Two bullets side by side
    case tripleShot     // Three bullets
    case spread         // Wide spread of bullets
    case aimed          // Aimed at player position
    case spiral         // Rotating spiral pattern
    case wave           // Wave pattern
    case burst          // Quick burst of bullets
    case homing         // Slower bullets that track player
    case laser          // Brief warning then laser beam
    case circularBarrage // Dense fan of bullets around boss
    case cascade         // Cascading bullets falling down from left to right
    case doubleSpiral    // Two spirals rotating in opposite directions
    case barrageRain     // Dense rain of bullets across screen width
    case zigzagPattern   // Zigzag pattern of bullets
    case sectorSweep     // Sweeping sector fire (rotating barrage)

    // Signature moves: each belongs to an archetype and uses its hardware.

    /// Warden: every gun pod fires an aimed burst in turn.
    case podVolley
    /// Warden, heart: the eye locks on and fires a beam down the line it locked.
    case eyeLance
    /// Mantis: a dive at the ship, slashing at the bottom of it.
    case swoop
    /// Mantis: streams from the blade tips that curve across each other.
    case scytheArcs
    /// Gyre, heart: the satellites spin up and fire outwards as they wheel round.
    case orbitalSpiral
    /// Gyre, maw, heart: a ring of rounds with one gap in it, then another.
    case ringPulse
    /// Hive, heart: slow mines that burst into rings.
    case mineLayer
    /// Hive: seekers out of every bay.
    case broodSwarm
    /// Lancer, heart: a beam that sweeps a sector, or two that close on a corridor.
    case sweepBeam
    /// Lancer: slow prisms that split into fans aimed at the ship.
    case prismSplit
    /// Serpent: every segment fires, head to tail, and back again aimed.
    case segmentVolley
    /// Serpent: alternate segments release rings.
    case coilBurst
    /// Wraith: vanishes, reappears elsewhere and bursts.
    case blink
    /// Wraith, heart: rifts open at the sides of the screen and fire across it.
    case riftPortals
    /// Tesseract: walls of rounds, each with a gap a little way along from the last.
    case latticeWalls
    /// Tesseract: folds out of space, unfolds at another station, fires a cross.
    case hyperShift
    /// Maw, heart: a ring of rounds closes on the ship from all sides but one.
    case implosion
    /// Maw, heart: spiral arms of rounds that curve as they fly.
    case accretion

    /// Whether the attack covers enough of the screen to earn the long wind-up.
    var isHeavy: Bool {
        switch self {
        case .circularBarrage, .barrageRain, .sectorSweep, .doubleSpiral, .cascade, .laser,
             .ringPulse, .latticeWalls, .riftPortals, .implosion, .sweepBeam, .eyeLance, .coilBurst:
            return true
        default:
            return false
        }
    }
}

/// Structure for a boss fight: what the boss is allowed to do, and how fast, as its
/// health falls.
///
/// Every one of the fifty levels ends with a boss — `checkLevelCompletion()` hands the
/// level to `spawnBoss()` and the only way out from there is killing it — so this is the
/// climax the player reaches fifty times. It did not have a shape. `BossManager` drew
/// each attack with `patterns.randomElement()` from one flat list, on a flat 1.5–3.5 s
/// timer, from the boss's first frame to its last: nothing escalated and nothing could be
/// read.
///
/// These rules give a fight three acts on the health thresholds the boss's damage states
/// use — so it visibly comes apart on the same beats that its behaviour turns up. Which
/// attacks join in each act is authored per boss (`BossConfig.patternActs`): an opening
/// act that introduces the machine with its signature, a second that adds pressure, and
/// a third that brings out the move it is known for.
///
/// `nonisolated` for the reason `GameRules` gives: pure arithmetic over plain values is
/// the part worth pinning down in tests, and `jetshotTests` cannot reach main-actor state.
nonisolated enum BossPhaseRules {

    /// Health fractions at which the boss escalates, descending.
    static let thresholds: [CGFloat] = [0.66, 0.33]

    /// Number of acts a fight is divided into.
    static var phaseCount: Int { thresholds.count + 1 }

    /// Which act a boss at `fraction` health is in: 0 while it is healthy, rising to
    /// `phaseCount - 1` as it dies.
    static func phase(forHealthFraction fraction: CGFloat) -> Int {
        var phase = 0
        for threshold in thresholds where fraction <= threshold {
            phase += 1
        }
        return min(phase, phaseCount - 1)
    }

    /// Multiplier on the gap between attacks for an act.
    ///
    /// A cornered boss attacks faster. Against the 1.5–3.5 s base range this takes the
    /// final act to 0.93–2.17 s, which is a clearly different fight from the opening one
    /// without becoming unreadable — the telegraph below still fits inside the shortest
    /// gap with room to react.
    static func attackDelayScale(forPhase phase: Int) -> Double {
        switch phase {
        case 0: return 1.0
        case 1: return 0.8
        default: return 0.62
        }
    }

    /// How many of a boss's attacks are available in an act, given the act each one
    /// joins in (non-decreasing, as `BossConfig` authors them). The result is a prefix
    /// length.
    ///
    /// Never fewer than two, or a boss with a thin opening act would repeat one attack:
    /// `BossManager.nextAttack()` refuses to draw the same one twice running.
    static func patternCount(forPhase phase: Int, acts: [Int]) -> Int {
        guard !acts.isEmpty else { return 0 }
        let unlocked = acts.prefix { $0 <= phase }.count
        return max(min(2, acts.count), unlocked)
    }

    /// How long the boss winds up before an attack lands.
    ///
    /// A wind-up turns an attack into something the player is given the chance to read.
    /// The ones that cover the most screen get the longer warning.
    static func telegraphDuration(for pattern: BossAttackPattern) -> TimeInterval {
        return pattern.isHeavy ? 0.6 : 0.4
    }

    /// Pause on a phase change, before the boss resumes attacking.
    ///
    /// The fight stops dead for a moment so the transition registers as an event. It also
    /// hands the player a breather at exactly the point the boss is about to get harder,
    /// which is what stops the last act reading as an unfair spike.
    static let phaseTransitionPause: TimeInterval = 1.1

    /// Health of each destructible part, as a share of the boss's.
    ///
    /// Small enough that focusing a pod down takes a few seconds of fire, large enough
    /// that a stream aimed at the core does not strip the hardware by accident. Every
    /// round that lands on a part still comes off the boss's own bar as well, so going
    /// for the guns never slows the fight.
    static func partHealth(bossHealth: Int, partCount: Int) -> Int {
        guard partCount > 0 else { return 0 }
        let share = partCount > 5 ? 0.07 : 0.11
        return max(3, Int((Double(bossHealth) * share).rounded()))
    }
}
