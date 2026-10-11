//
//  BackdropStage.swift
//  jetshot
//
//  What each level of a sector looks like.
//
//  A sector is one place on the film's route and keeps its world for all five of
//  its levels — the grid, the ruins, the tunnel. But five levels over the same
//  ground with the same sky is the same level five times as far as the eye is
//  concerned, so each level is a different leg through that place: the ground
//  changes shape, different things stand on it, something different is happening
//  over it, and a different body hangs in the sky. The second pass through a world
//  takes other legs again, so no two of the fifty levels share a stage.
//
//  `nonisolated` and free of SpriteKit for the reason `GameRules` gives: it is a
//  table of plain values, and the tests read it from any thread.
//

nonisolated enum BackdropGround: Equatable, Sendable {
    case flat
    /// Long swells rolling across the flight path.
    case dunes
    /// A winding channel with walls rising either side of it.
    case canyon
    /// Cells of the grid break away and fall as the ship nears them.
    case shattered
    /// The grid pulled down into the gravity wells.
    case sagging
}

/// The colour mood laid over a world's palette.
nonisolated enum BackdropMood: Equatable, Sendable {
    case standard
    /// The star going down: warm horizon, the grid taking on its colour.
    case dusk
    /// Ice light, as under an aurora.
    case cold
    /// Fire on the ground.
    case ember
    /// Pale and electric, for lightning.
    case storm
}

nonisolated enum BackdropFeature: Hashable, Sendable {
    // On the ground
    case debris, towers, pylons, spires, wrecks, arches, craters, crystals, vents, funnels
    // Happening over it
    case runners, meteors, searchlights, convoy, shockwaves, storm, inflow
    // In the sky
    case giant, dwarf, starDeaths, ringedWorld, gasGiant, shatteredMoon, eclipse, twinSuns
    case aurora, battle, blackHole, epicentre, riftEye
    // In the rift
    case pulses, breaches, oncoming, irises, helix
    // In the quantum bleed
    case tiltedGrids, walls, lattice, fold, shards, tesseracts, relics
}

nonisolated struct BackdropStage: Equatable, Sendable {
    var ground: BackdropGround = .flat
    var features: Set<BackdropFeature>
    var mood: BackdropMood = .standard
    /// The rift's cross-section: sides, radius against the standard tunnel, and how
    /// fast the rings turn.
    var sides: Int = 6
    var radius: Float = 1
    var twist: Float = 1

    func has(_ feature: BackdropFeature) -> Bool { features.contains(feature) }

    static func of(_ look: BackdropLook) -> BackdropStage {
        let stage = min(4, max(0, look.stage))
        let table: [BackdropStage]
        switch (look.theme, look.variant % 2) {
        case (.horizon, 0): table = horizon
        case (.horizon, _): table = horizonAgain
        case (.ruins, 0): table = ruins
        case (.ruins, _): table = ruinsAgain
        case (.rift, 0): table = rift
        case (.rift, _): table = riftAgain
        case (.quantum, 0): table = quantum
        case (.quantum, _): table = quantumAgain
        case (.well, _): table = well
        case (.epicentre, _): table = epicentre
        }
        return table[stage]
    }

    // MARK: - The route

    /// Levels 1–5: the spacetime grid at the end of ages.
    private static let horizon: [BackdropStage] = [
        // The opening: open grid, the red giant going down.
        BackdropStage(features: [.debris, .giant, .dwarf, .starDeaths]),
        // Dunes, with light running along the grid lines.
        BackdropStage(ground: .dunes, features: [.runners, .giant, .dwarf]),
        // A line of pylons arcing to each other, an aurora over the horizon.
        BackdropStage(features: [.pylons, .debris, .giant, .aurora], mood: .cold),
        // A broken moon raining down on the grid.
        BackdropStage(features: [.craters, .meteors, .shatteredMoon, .starDeaths], mood: .ember),
        // Into a canyon at dusk, searchlights sweeping the floor.
        BackdropStage(ground: .canyon, features: [.searchlights, .debris, .giant, .starDeaths], mood: .dusk)
    ]

    /// Levels 26–30: the grid again, the other side of it.
    private static let horizonAgain: [BackdropStage] = [
        BackdropStage(ground: .dunes, features: [.convoy, .eclipse, .aurora]),
        BackdropStage(features: [.shockwaves, .runners, .giant, .dwarf]),
        BackdropStage(ground: .canyon, features: [.meteors, .craters, .shatteredMoon], mood: .ember),
        BackdropStage(ground: .shattered, features: [.storm, .giant], mood: .storm),
        BackdropStage(features: [.pylons, .shockwaves, .twinSuns], mood: .dusk)
    ]

    /// Levels 6–10: the dead megastructure.
    private static let ruins: [BackdropStage] = [
        BackdropStage(features: [.towers, .ringedWorld]),
        // Spires, and the searchlights still sweeping between them.
        BackdropStage(features: [.spires, .searchlights, .ringedWorld], mood: .cold),
        // The graveyard of a fleet.
        BackdropStage(features: [.wrecks, .debris, .gasGiant]),
        // Gates over the road, traffic of light still running under them.
        BackdropStage(features: [.arches, .runners, .twinSuns]),
        // The city burning, a battle on the horizon.
        BackdropStage(features: [.towers, .vents, .battle, .ringedWorld], mood: .ember)
    ]

    /// Levels 31–35.
    private static let ruinsAgain: [BackdropStage] = [
        BackdropStage(features: [.towers, .convoy, .ringedWorld]),
        BackdropStage(ground: .dunes, features: [.arches, .meteors, .shatteredMoon]),
        BackdropStage(features: [.wrecks, .storm, .gasGiant], mood: .storm),
        BackdropStage(features: [.spires, .battle, .aurora], mood: .cold),
        // A city on the cliffs of a canyon.
        BackdropStage(ground: .canyon, features: [.towers, .searchlights, .ringedWorld], mood: .dusk)
    ]

    /// Levels 11–15: the rift tunnel.
    private static let rift: [BackdropStage] = [
        BackdropStage(features: [.riftEye]),
        // Square, turning faster, light pulsing down it.
        BackdropStage(features: [.pulses, .riftEye], sides: 4, twist: 1.8),
        // Narrow and three-sided, its walls breached and arcing.
        BackdropStage(features: [.breaches, .riftEye], mood: .storm, sides: 3, radius: 0.85, twist: 0.6),
        // Wide, with wreckage flying back down it.
        BackdropStage(features: [.oncoming, .riftEye], mood: .ember, sides: 8, radius: 1.2, twist: 0.8),
        // Wound into a helix, irises opening ahead.
        BackdropStage(features: [.helix, .irises, .riftEye], mood: .dusk, twist: 1.3)
    ]

    /// Levels 36–40.
    private static let riftAgain: [BackdropStage] = [
        BackdropStage(features: [.breaches, .riftEye], sides: 4, twist: 0.7),
        BackdropStage(features: [.irises, .pulses, .riftEye]),
        BackdropStage(features: [.helix, .oncoming, .riftEye], sides: 8, radius: 1.15, twist: 1.5),
        BackdropStage(features: [.oncoming, .pulses], mood: .storm, sides: 3, radius: 0.9, twist: 2),
        BackdropStage(features: [.pulses, .breaches, .irises, .riftEye], mood: .ember, sides: 12, radius: 1.1)
    ]

    /// Levels 16–20: the quantum bleed.
    private static let quantum: [BackdropStage] = [
        BackdropStage(features: [.tiltedGrids, .tesseracts]),
        // Walls of another space either side.
        BackdropStage(features: [.walls, .relics]),
        // A lattice, cells lighting up.
        BackdropStage(features: [.lattice, .tesseracts], mood: .cold),
        // A grid rolling like cloth.
        BackdropStage(features: [.fold, .relics]),
        // Grids broken into drifting panes.
        BackdropStage(features: [.shards, .tesseracts], mood: .ember)
    ]

    /// Levels 41–45.
    private static let quantumAgain: [BackdropStage] = [
        BackdropStage(features: [.walls, .tesseracts]),
        BackdropStage(features: [.fold, .lattice]),
        BackdropStage(features: [.tiltedGrids, .relics], mood: .cold),
        BackdropStage(features: [.shards, .relics], mood: .storm),
        BackdropStage(features: [.walls, .fold, .tesseracts], mood: .ember)
    ]

    /// Levels 21–25: the gravity wells.
    private static let well: [BackdropStage] = [
        BackdropStage(features: [.funnels, .debris, .blackHole]),
        // The grid itself dragged down, light pouring into the dips.
        BackdropStage(ground: .sagging, features: [.runners, .blackHole], mood: .cold),
        // Stars falling into the wells.
        BackdropStage(features: [.funnels, .meteors, .blackHole], mood: .ember),
        BackdropStage(ground: .sagging, features: [.storm, .crystals, .blackHole], mood: .storm),
        // Gravitational waves rolling through it all.
        BackdropStage(ground: .sagging, features: [.shockwaves, .convoy, .blackHole], mood: .dusk)
    ]

    /// Levels 46–50: the epicentre, closer every level.
    private static let epicentre: [BackdropStage] = [
        BackdropStage(features: [.inflow, .epicentre]),
        BackdropStage(ground: .shattered, features: [.inflow, .epicentre], mood: .ember),
        BackdropStage(features: [.crystals, .storm, .inflow, .epicentre], mood: .storm),
        BackdropStage(ground: .canyon, features: [.shockwaves, .inflow, .epicentre], mood: .dusk),
        BackdropStage(ground: .shattered, features: [.crystals, .storm, .inflow, .battle, .epicentre], mood: .ember)
    ]
}
