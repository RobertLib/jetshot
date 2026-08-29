//
//  BossPhase.swift
//  jetshot
//

import CoreGraphics
import Foundation

/// Structure for a boss fight: what the boss is allowed to do, and how fast, as its
/// health falls.
///
/// Every one of the fifty levels ends with a boss — `checkLevelCompletion()` hands the
/// level to `spawnBoss()` and the only way out from there is killing it — so this is the
/// climax the player reaches fifty times. It did not have a shape. `BossManager` drew
/// each attack with `patterns.randomElement()` from one flat list, on a flat 1.5–3.5 s
/// timer, from the boss's first frame to its last: a level 50 fight was six hundred hit
/// points of the same random draw as its first, with nothing that escalated, nothing that
/// could be read, and no way to tell from watching it whether you were winning.
///
/// Worse, the lists themselves stopped changing. From level 8 to level 50 every milestone
/// declared the identical fourteen patterns, so thirty-five of the fifty bosses in the
/// game fought exactly alike and differed only in how long they took to chew through.
///
/// These rules give a fight three acts on the health thresholds `Boss.applyDamageVisuals`
/// was already using for its damage states — so the boss visibly cracks apart on the same
/// beats that its behaviour turns up, and the two read as one escalation instead of two
/// unrelated ones.
///
/// `nonisolated` for the reason `GameRules` gives: pure arithmetic over plain values is
/// the part worth pinning down in tests, and `jetshotTests` cannot reach main-actor state.
nonisolated enum BossPhaseRules {

    /// Health fractions at which the boss escalates, descending.
    ///
    /// Deliberately the same 0.66 / 0.33 that `Boss.applyDamageVisuals(healthPercent:)`
    /// already used to switch between its intact, cracked and burning silhouettes. Two
    /// separate ladders would have the boss look wounded on one beat and start fighting
    /// harder on another, and the player would read neither.
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

    /// The slice of a boss's authored pattern list available in an act.
    ///
    /// Each `BossConfig` lists its patterns from lightest to heaviest, so taking a prefix
    /// is what produces the escalation: the opening act is single shots and spreads, and
    /// the barrages and lasers at the end of the list only appear once the boss is
    /// actually in trouble. This is why the ordering of those arrays is load-bearing and
    /// not merely tidy.
    ///
    /// Never fewer than two, or a wounded boss with a short list would repeat one attack.
    static func patternCount(forPhase phase: Int, totalPatterns total: Int) -> Int {
        guard total > 0 else { return 0 }

        let fraction: CGFloat
        switch phase {
        case 0: fraction = 0.45
        case 1: fraction = 0.75
        default: fraction = 1.0
        }

        let count = Int((CGFloat(total) * fraction).rounded(.up))
        return max(min(2, total), min(count, total))
    }

    /// How long the boss winds up before an attack lands.
    ///
    /// Nothing was telegraphed at all before this: bullets simply appeared, which makes a
    /// dense pattern feel arbitrary rather than hard, because the only way to survive one
    /// is to already have been somewhere else. A wind-up turns the same attack into
    /// something the player is given the chance to read. The heavy end of a list gets
    /// longer warning precisely because it covers the most screen.
    static func telegraphDuration(forPatternIndex index: Int, totalPatterns total: Int) -> TimeInterval {
        guard total > 0 else { return 0.4 }
        return isHeavy(patternIndex: index, totalPatterns: total) ? 0.6 : 0.4
    }

    /// Whether a pattern sits in the heavy final third of its boss's list.
    static func isHeavy(patternIndex index: Int, totalPatterns total: Int) -> Bool {
        guard total > 0 else { return false }
        return CGFloat(index) >= CGFloat(total) * (2.0 / 3.0)
    }

    /// Pause on a phase change, before the boss resumes attacking.
    ///
    /// The fight stops dead for a moment so the transition registers as an event. It also
    /// hands the player a breather at exactly the point the boss is about to get harder,
    /// which is what stops the last act reading as an unfair spike.
    static let phaseTransitionPause: TimeInterval = 1.1
}
