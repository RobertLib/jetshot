//
//  BossCatalog.swift
//  jetshot
//
//  Who waits at the end of each of the fifty levels.
//

import UIKit

/// The machines the swarm sends to hold the route.
///
/// There used to be one boss: a flat polygon with the same bolt-on rings, cannons and
/// radar sweeps, recoloured and resized seventeen times, patrolling left and right and
/// drawing attacks out of a shared bag. It was the only thing in the game still drawn
/// as a 2D sticker, sitting in front of a world of real wireframe.
///
/// Each archetype is now its own machine, built in the films' wireframe the way the
/// player's ship is (see `BossArt`), with its own way of moving (`BossFlightStyle`), its
/// own hardware that the player can shoot off (`BossPart`) and its own signature attacks.
/// The sectors of the route introduce them in turn — the wraith in the rift, the
/// tesseract in the quantum bleed, the maw among the gravity wells — and the later
/// sectors bring the earlier ones back better armed (`tier`).
///
/// `nonisolated` for the reason `GameRules` gives: the roster is plain data, and the
/// pure rules and tests read it from any context.
nonisolated enum BossArchetype: Int, CaseIterable, Sendable {
    /// A hexagonal sentinel with an eye, gun pods on its flanks.
    case warden
    /// A scythe-armed interceptor that dives at the ship.
    case mantis
    /// An orbital station; satellites wheel round its core and fire as they go.
    case gyre
    /// A honeycomb brood carrier that lays mines.
    case hive
    /// A crystal laser platform.
    case lancer
    /// A segmented wyrm whose every segment is a gun.
    case serpent
    /// A phantom out of the rift that blinks across the screen.
    case wraith
    /// A four-dimensional cube turning through the quantum bleed.
    case tesseract
    /// A small singularity with an accretion disc.
    case maw
    /// The entity at the epicentre — the final boss.
    case heart

    /// How the archetype moves when no attack is steering it.
    var flight: BossFlightStyle {
        switch self {
        case .warden, .lancer: return .patrol
        case .mantis: return .weave
        case .gyre, .maw, .heart: return .orbit
        case .hive: return .drift
        case .serpent: return .snake
        case .wraith: return .haunt
        case .tesseract: return .shift
        }
    }

    /// The move that introduces the archetype: always in its opening act, so the very
    /// first thing a boss does tells the player which machine this is.
    var signature: BossAttackPattern {
        switch self {
        case .warden: return .podVolley
        case .mantis: return .swoop
        case .gyre: return .orbitalSpiral
        case .hive: return .mineLayer
        case .lancer: return .prismSplit
        case .serpent: return .segmentVolley
        case .wraith: return .blink
        case .tesseract: return .hyperShift
        case .maw: return .accretion
        case .heart: return .orbitalSpiral
        }
    }
}

/// How a boss moves between attacks. See `Boss.flightTarget(dt:)`.
nonisolated enum BossFlightStyle: Sendable {
    /// Side to side, with a slight bob.
    case patrol
    /// Side to side, dipping through a shallow figure of eight.
    case weave
    /// A slow figure of eight.
    case orbit
    /// A heavy, slow drift.
    case drift
    /// A fast serpentine sweep the body can follow.
    case snake
    /// A slow drift broken by teleports.
    case haunt
    /// Snaps between fixed stations and holds at each.
    case shift
}

/// The light a boss is drawn in.
struct BossPalette {
    /// The hull's lines.
    let hull: UIColor
    /// Secondary structure, telegraphs and the impact sparks of rounds landing on it.
    let accent: UIColor
    /// The entity at its heart, its eye and its muzzles.
    let core: UIColor
}

// Boss configuration for each level
struct BossConfig {
    let level: Int
    let archetype: BossArchetype
    /// How many times this archetype has been met before on the route, 0...5. Adds
    /// hardware, attacks and speed.
    let tier: Int
    let maxHealth: Int
    /// Seconds per leg of the boss's sweep across the screen.
    let movementSpeed: TimeInterval
    /// Full width of the silhouette, in points.
    let size: CGFloat
    /// Every attack the boss has, grouped by the act of the fight it joins in.
    ///
    /// Ordered by `patternActs`, which is load-bearing: `Boss.availableAttackPatterns()`
    /// takes the prefix whose act the fight has reached, so an attack authored into the
    /// wrong group turns up an act early.
    let attackPatterns: [BossAttackPattern]
    /// The act (0...2) in which each of `attackPatterns` joins the fight, parallel to it
    /// and non-decreasing.
    let patternActs: [Int]
    let palette: BossPalette
    let points: Int

    /// The name on the health bar: the archetype, and the mark of this encounter with it.
    var displayName: String {
        let name = L10n.Boss.name(archetype)
        // The heart is only ever met once; a numeral on it would suggest otherwise.
        return tier > 0 && archetype != .heart ? "\(name) \(Self.mark(tier))" : name
    }

    /// Roman numerals for the second and later meetings: "II" for tier 1.
    static func mark(_ tier: Int) -> String {
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
        return numerals[min(max(tier, 0), numerals.count - 1)]
    }

    /// The boss at the end of `level`.
    ///
    /// Every level now has its own boss. Fifty levels used to share seventeen configs —
    /// levels 11 to 14 all fought level 10's boss — and from level 8 on most of those
    /// differed only in the length of the health bar. The roster below gives each level
    /// an (archetype, tier) pair that no other level has, and never repeats an archetype
    /// on consecutive levels.
    static func config(for level: Int) -> BossConfig {
        let clamped = min(max(level, 1), roster.count)
        let (archetype, tier) = roster[clamped - 1]
        let blueprint = Self.blueprint(for: archetype)

        let moves = blueprint.moves
            .filter { tier >= $0.tier }
            .enumerated()
            .sorted { ($0.element.act, $0.offset) < ($1.element.act, $1.offset) }
            .map { $0.element }

        return BossConfig(
            level: clamped,
            archetype: archetype,
            tier: tier,
            maxHealth: interpolate(healthCurve, at: clamped),
            movementSpeed: max(1.0, blueprint.legTime - 0.22 * TimeInterval(tier)),
            size: blueprint.size + blueprint.growth * CGFloat(tier),
            attackPatterns: moves.map { $0.pattern },
            patternActs: moves.map { $0.act },
            palette: palette(for: archetype, tier: tier),
            points: interpolate(pointsCurve, at: clamped)
        )
    }

    // MARK: - The route

    /// One entry per level. Sectors of five, matching `BackdropLook.route`: the first
    /// introduces the five machines of the old war; the rift brings the wraith, the
    /// quantum bleed the tesseract, the wells the maw, and each of those sectors ends on
    /// its own resident, stronger. The second pass through the worlds remixes them all
    /// a mark higher, and the epicentre ends on the heart.
    static let roster: [(BossArchetype, Int)] = [
        // Horizon (1-5)
        (.warden, 0), (.mantis, 0), (.gyre, 0), (.hive, 0), (.lancer, 0),
        // Ruins (6-10)
        (.serpent, 0), (.warden, 1), (.mantis, 1), (.gyre, 1), (.hive, 1),
        // Rift (11-15)
        (.wraith, 0), (.lancer, 1), (.serpent, 1), (.warden, 2), (.wraith, 1),
        // Quantum (16-20)
        (.tesseract, 0), (.mantis, 2), (.gyre, 2), (.hive, 2), (.tesseract, 1),
        // Wells (21-25)
        (.maw, 0), (.lancer, 2), (.serpent, 2), (.wraith, 2), (.maw, 1),
        // Horizon again (26-30)
        (.warden, 3), (.mantis, 3), (.tesseract, 2), (.gyre, 3), (.lancer, 3),
        // Ruins again (31-35)
        (.hive, 3), (.serpent, 3), (.maw, 2), (.wraith, 3), (.warden, 4),
        // Rift again (36-40)
        (.tesseract, 3), (.mantis, 4), (.gyre, 4), (.lancer, 4), (.wraith, 4),
        // Quantum again (41-45)
        (.tesseract, 4), (.hive, 4), (.serpent, 4), (.maw, 3), (.tesseract, 5),
        // Epicentre (46-50)
        (.gyre, 5), (.maw, 4), (.serpent, 5), (.wraith, 5), (.heart, 5)
    ]

    // MARK: - Health and bounty

    /// The authored health of the old milestone bosses, now interpolated so the levels
    /// between milestones climb instead of repeating the last one.
    private static let healthCurve: [(level: Int, value: Int)] = [
        (1, 20), (2, 35), (3, 50), (4, 70), (5, 90), (6, 110), (7, 135), (8, 160),
        (10, 200), (15, 250), (20, 300), (25, 350), (30, 400), (35, 450), (40, 500),
        (45, 550), (50, 600)
    ]

    private static let pointsCurve: [(level: Int, value: Int)] = [
        (1, 500), (2, 750), (3, 1000), (4, 1250), (5, 1500), (6, 1750), (7, 2000),
        (8, 2500), (10, 3000), (15, 3500), (20, 4000), (25, 4500), (30, 5000),
        (35, 5500), (40, 6000), (45, 6500), (50, 7500)
    ]

    private static func interpolate(_ curve: [(level: Int, value: Int)], at level: Int) -> Int {
        guard let upper = curve.firstIndex(where: { $0.level >= level }) else { return curve.last?.value ?? 1 }
        guard upper > 0 else { return curve[0].value }
        let a = curve[upper - 1], b = curve[upper]
        let t = Double(level - a.level) / Double(b.level - a.level)
        return a.value + Int((Double(b.value - a.value) * t).rounded())
    }

    // MARK: - Blueprints

    private struct Move {
        let pattern: BossAttackPattern
        /// The act of the fight it joins in.
        let act: Int
        /// The first tier that has it.
        let tier: Int
    }

    private struct Blueprint {
        let size: CGFloat
        let growth: CGFloat
        let legTime: TimeInterval
        let moves: [Move]
    }

    private static func m(_ pattern: BossAttackPattern, act: Int, tier: Int = 0) -> Move {
        Move(pattern: pattern, act: act, tier: tier)
    }

    /// Each archetype's arsenal. Opening act: its signature and a couple of light
    /// attacks to read it by. Second act: the pressure. Third: the screen-filling move
    /// it is known for. Later tiers fill each act out.
    private static func blueprint(for archetype: BossArchetype) -> Blueprint {
        switch archetype {
        case .warden:
            return Blueprint(size: 140, growth: 12, legTime: 3.0, moves: [
                m(.straightShot, act: 0), m(.podVolley, act: 0), m(.doubleShot, act: 0),
                m(.aimed, act: 0, tier: 2),
                m(.tripleShot, act: 1), m(.spread, act: 1), m(.burst, act: 1, tier: 1),
                m(.sectorSweep, act: 1, tier: 3),
                m(.eyeLance, act: 2), m(.barrageRain, act: 2, tier: 2), m(.circularBarrage, act: 2, tier: 4)
            ])
        case .mantis:
            return Blueprint(size: 164, growth: 10, legTime: 2.4, moves: [
                m(.spread, act: 0), m(.swoop, act: 0), m(.aimed, act: 0),
                m(.zigzagPattern, act: 0, tier: 2),
                m(.scytheArcs, act: 1), m(.wave, act: 1, tier: 1), m(.doubleSpiral, act: 1, tier: 3),
                m(.sectorSweep, act: 2), m(.burst, act: 2, tier: 2), m(.barrageRain, act: 2, tier: 4)
            ])
        case .gyre:
            return Blueprint(size: 152, growth: 12, legTime: 2.8, moves: [
                m(.straightShot, act: 0), m(.orbitalSpiral, act: 0), m(.tripleShot, act: 0, tier: 1),
                m(.aimed, act: 0, tier: 2),
                m(.spiral, act: 1), m(.wave, act: 1), m(.doubleSpiral, act: 1, tier: 2),
                m(.burst, act: 1, tier: 4),
                m(.ringPulse, act: 2), m(.circularBarrage, act: 2, tier: 1), m(.sectorSweep, act: 2, tier: 3),
                m(.barrageRain, act: 2, tier: 5)
            ])
        case .hive:
            return Blueprint(size: 156, growth: 12, legTime: 3.2, moves: [
                m(.doubleShot, act: 0), m(.mineLayer, act: 0), m(.spread, act: 0, tier: 1),
                m(.cascade, act: 1), m(.homing, act: 1), m(.broodSwarm, act: 1, tier: 1),
                m(.burst, act: 1, tier: 3),
                m(.barrageRain, act: 2), m(.circularBarrage, act: 2, tier: 2), m(.zigzagPattern, act: 2, tier: 4)
            ])
        case .lancer:
            return Blueprint(size: 148, growth: 10, legTime: 2.9, moves: [
                m(.aimed, act: 0), m(.prismSplit, act: 0), m(.straightShot, act: 0),
                m(.tripleShot, act: 0, tier: 2),
                m(.laser, act: 1), m(.spread, act: 1, tier: 1), m(.sectorSweep, act: 1, tier: 2),
                m(.sweepBeam, act: 2), m(.zigzagPattern, act: 2, tier: 1), m(.burst, act: 2, tier: 3),
                m(.cascade, act: 2, tier: 4)
            ])
        case .serpent:
            return Blueprint(size: 96, growth: 6, legTime: 2.6, moves: [
                m(.segmentVolley, act: 0), m(.aimed, act: 0), m(.straightShot, act: 0),
                m(.spread, act: 0, tier: 1),
                m(.wave, act: 1), m(.coilBurst, act: 1), m(.zigzagPattern, act: 1, tier: 1),
                m(.homing, act: 1, tier: 4),
                m(.cascade, act: 2), m(.barrageRain, act: 2, tier: 2), m(.doubleSpiral, act: 2, tier: 3),
                m(.sectorSweep, act: 2, tier: 5)
            ])
        case .wraith:
            return Blueprint(size: 150, growth: 10, legTime: 3.4, moves: [
                m(.aimed, act: 0), m(.blink, act: 0), m(.spread, act: 0),
                m(.burst, act: 0, tier: 2),
                m(.homing, act: 1), m(.wave, act: 1, tier: 1), m(.doubleSpiral, act: 1, tier: 2),
                m(.zigzagPattern, act: 1, tier: 4),
                m(.riftPortals, act: 2), m(.sectorSweep, act: 2, tier: 1), m(.circularBarrage, act: 2, tier: 3),
                m(.barrageRain, act: 2, tier: 5)
            ])
        case .tesseract:
            return Blueprint(size: 146, growth: 10, legTime: 2.6, moves: [
                m(.tripleShot, act: 0), m(.hyperShift, act: 0), m(.aimed, act: 0),
                m(.spread, act: 0, tier: 1),
                m(.burst, act: 1), m(.zigzagPattern, act: 1), m(.sectorSweep, act: 1, tier: 2),
                m(.doubleSpiral, act: 1, tier: 3), m(.homing, act: 1, tier: 5),
                m(.latticeWalls, act: 2), m(.cascade, act: 2, tier: 1), m(.barrageRain, act: 2, tier: 2),
                m(.circularBarrage, act: 2, tier: 4)
            ])
        case .maw:
            return Blueprint(size: 164, growth: 12, legTime: 3.0, moves: [
                m(.aimed, act: 0), m(.accretion, act: 0), m(.spiral, act: 0),
                m(.homing, act: 0, tier: 2),
                m(.doubleSpiral, act: 1), m(.circularBarrage, act: 1, tier: 1), m(.wave, act: 1, tier: 2),
                m(.burst, act: 1, tier: 4),
                m(.implosion, act: 2), m(.ringPulse, act: 2, tier: 2), m(.sectorSweep, act: 2, tier: 3)
            ])
        case .heart:
            return Blueprint(size: 170, growth: 10, legTime: 1.8, moves: [
                m(.aimed, act: 0), m(.orbitalSpiral, act: 0), m(.mineLayer, act: 0),
                m(.accretion, act: 0), m(.spread, act: 0),
                m(.riftPortals, act: 1), m(.ringPulse, act: 1), m(.eyeLance, act: 1),
                m(.doubleSpiral, act: 1), m(.homing, act: 1),
                m(.sweepBeam, act: 2), m(.implosion, act: 2), m(.latticeWalls, act: 2),
                m(.barrageRain, act: 2), m(.circularBarrage, act: 2)
            ])
        }
    }

    // MARK: - Palettes

    /// Hull light. Deliberately none of the colours the playfield has already spoken
    /// for: hot pink is hostile fire, cyan is the player, green the shards.
    private static let crimson = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)
    private static let ember = UIColor(red: 1.0, green: 0.52, blue: 0.22, alpha: 1)
    private static let amber = UIColor(red: 1.0, green: 0.72, blue: 0.3, alpha: 1)
    private static let violet = UIColor(red: 0.68, green: 0.46, blue: 1.0, alpha: 1)
    private static let azure = UIColor(red: 0.38, green: 0.56, blue: 1.0, alpha: 1)
    private static let frost = UIColor(red: 0.84, green: 0.88, blue: 1.0, alpha: 1)

    private static let palettes: [BossPalette] = [
        BossPalette(hull: crimson, accent: ember, core: StoryPalette.gold),
        BossPalette(hull: ember, accent: amber, core: StoryPalette.red),
        BossPalette(hull: amber, accent: crimson, core: StoryPalette.red),
        BossPalette(hull: violet, accent: frost, core: StoryPalette.red),
        BossPalette(hull: azure, accent: frost, core: StoryPalette.gold),
        BossPalette(hull: frost, accent: violet, core: StoryPalette.red)
    ]

    /// Each archetype has a home colouring and moves one along the list per tier, so a
    /// machine met again looks like a later model rather than the same one.
    private static func palette(for archetype: BossArchetype, tier: Int) -> BossPalette {
        let home: Int
        switch archetype {
        case .warden: home = 0
        case .mantis: home = 1
        case .hive: home = 2
        case .lancer: home = 3
        case .gyre: home = 4
        case .tesseract: home = 5
        case .serpent: home = 1
        case .wraith: home = 3
        case .maw: home = 2
        case .heart:
            return BossPalette(hull: crimson, accent: amber, core: StoryPalette.white)
        }
        return palettes[(home + tier) % palettes.count]
    }
}
