//
//  BossArt.swift
//  jetshot
//
//  The bosses, drawn the way the films draw everything: real wireframe in
//  perspective, light-tube lines, depth on the far side of a hull.
//

import SpriteKit
import simd

/// What a boss looks like this frame, and what drawing it found out.
///
/// `Boss` writes the inputs (health, the hit flash, the wind-up, where the ship is), the
/// renderer reads them, and on the way out it reports where the boss's hardware ended up
/// on screen — its gun pods, satellites, segments — because that hardware is drawn in 3D
/// and turns, and only the projection knows where it is. `Boss` hangs the hit volumes of
/// its `BossPart`s and the muzzles of its attacks off those points.
final class BossLook {
    let archetype: BossArchetype
    let tier: Int
    let palette: BossPalette
    /// Half the boss's width, in points: one model unit.
    let unit: Float
    /// How far the canvas camera sits from the boss's plane; the maw's occluder splits
    /// its accretion disc there.
    var cameraDistance: Float = 0

    // MARK: Inputs

    var t: Float = 0
    var health: Float = 1
    /// White-hot after a hit, decaying.
    var hitFlash: Float = 0
    /// The wind-up before an attack, 0...1.
    var charge: Float = 0
    /// Lean into the direction of travel, radians.
    var bank: Float = 0
    /// Unit vector from the boss towards the ship, for the eyes that follow it.
    var gaze = SIMD2<Float>(0, -1)
    /// The entrance scan, 0...1. Edges below the scan line are not lit yet.
    var reveal: Float = 0
    /// The death throes, 0...1: the hull flies apart.
    var dying: Float = 0
    /// Overall visibility, for blinking and folding out of space.
    var fade: Float = 1
    /// Multiplier on the speed of anything that orbits.
    var spin: Float = 1
    /// The mantis's arms swept back for a dive, 0...1.
    var sweep: Float = 0
    /// Which `BossPart`s are still intact.
    var partAlive: [Bool]
    /// Serpent: each segment's offset from the head, in points.
    var trail: [CGPoint] = []

    // MARK: Outputs

    /// Where each part sits, in the boss's own coordinates.
    var partPoints: [CGPoint]
    /// Muzzles of the boss's weapons, and whether each is still able to fire.
    var muzzlePoints: [CGPoint] = []
    var muzzleAlive: [Bool] = []
    /// The muzzle of last resort: the eye, the emitter, the hole.
    var corePoint: CGPoint = .zero

    // MARK: Per-frame

    fileprivate var orbit: Float = 0
    fileprivate var lastT: Float = 0
    fileprivate var hullLit = UIColor.white
    fileprivate var accentLit = UIColor.white
    fileprivate var coreLit = UIColor.white

    init(archetype: BossArchetype, tier: Int, palette: BossPalette, unit: Float) {
        self.archetype = archetype
        self.tier = tier
        self.palette = palette
        self.unit = unit
        let parts = BossArt.partCount(for: archetype, tier: tier)
        partAlive = Array(repeating: true, count: parts)
        partPoints = Array(repeating: .zero, count: parts)
    }
}

enum BossArt {

    // MARK: - Hardware

    /// How many destructible parts an archetype carries at a tier.
    static func partCount(for archetype: BossArchetype, tier: Int) -> Int {
        switch archetype {
        case .warden: return tier < 2 ? 2 : 4
        case .gyre: return [3, 3, 4, 5, 6, 6][min(max(tier, 0), 5)]
        case .hive: return tier < 2 ? 2 : 3
        case .lancer: return tier >= 1 ? 2 : 0
        case .serpent: return 5 + min(max(tier, 0), 5)
        case .heart: return 4
        case .mantis, .wraith, .tesseract, .maw: return 0
        }
    }

    /// Radius of a part's hit volume, as a fraction of the boss's half width.
    static func partRadius(for archetype: BossArchetype, index: Int, count: Int) -> CGFloat {
        switch archetype {
        case .warden: return 0.2
        case .gyre: return 0.16
        case .hive: return 0.2
        case .lancer: return 0.16
        case .serpent: return 0.36 * (1 - 0.45 * CGFloat(index) / CGFloat(max(1, count - 1)))
        case .heart: return 0.13
        default: return 0.15
        }
    }

    /// The core's hit volume: circles in the boss's own plane, centres and radii in
    /// half widths.
    ///
    /// It used to be one circle 0.8 half widths across for every machine, drawn round
    /// the hardware as well as the hull. Rounds come up from below, so whichever volume
    /// a round meets first takes it — and that was the core's rim, under the gun pods,
    /// bays and satellites it was meant to be reaching. The heart's shell nodes sat
    /// wholly inside it and could not be shot off at all.
    ///
    /// So a machine whose hardware the old circle covered is now fitted to its hull, and
    /// the hardware hangs outside: the warden to its plating, the gyre to its gyroscope,
    /// the serpent to its head, the heart to its shell, and the hive to the comb itself,
    /// cell by cell, with its bays below. Each still covers its own eye or emitter, so a
    /// round aimed at the heart of the machine still lands. A part passing *behind* a
    /// hull — a satellite or shell node at the top of its orbit — is still covered by
    /// it, as it should be. The rest keep the old circle: they carry nothing to shoot
    /// off, or, like the lancer's capacitors, carry it well clear of the rim.
    static func coreVolume(for archetype: BossArchetype, tier: Int) -> [(center: CGPoint, radius: CGFloat)] {
        switch archetype {
        case .warden: return [(.zero, 0.6)]
        case .gyre: return [(.zero, 0.44)]
        case .serpent: return [(.zero, 0.68)]
        case .heart: return [(.zero, 0.54)]
        case .hive:
            // The comb leans back with the rest of the boss, which shortens it on screen.
            let lean = CGFloat(cos(tilt))
            return hiveCells(tier: tier).map { (CGPoint(x: CGFloat($0.x), y: CGFloat($0.y) * lean), 0.2) }
        case .mantis, .lancer, .wraith, .tesseract, .maw: return [(.zero, 0.8)]
        }
    }

    /// The canvas extent a boss needs, as a multiple of its half width. Most fit their
    /// silhouette; the serpent's body trails a long way behind its head.
    static func extent(for archetype: BossArchetype) -> CGFloat {
        switch archetype {
        case .serpent: return 4.6
        case .mantis: return 1.25
        default: return 1.3
        }
    }

    // MARK: - Frame

    /// How far every boss leans back, top away from the camera, in radians.
    private static let tilt: Float = 0.42

    static func render(_ look: BossLook, _ c: WireCanvas, t: Float) {
        let dt = max(0, min(0.1, t - look.lastT))
        look.lastT = t
        look.t = t
        look.orbit += dt * look.spin
        look.hitFlash = max(0, look.hitFlash - dt * 6)

        look.hullLit = lit(look.palette.hull, look)
        look.accentLit = lit(look.palette.accent, look)
        look.coreLit = lit(look.palette.core, look)

        let wobble = sin(t * 0.6) * 0.05
        let q = rotation(look.bank * 0.55 + wobble, Vec3(0, 1, 0)) * rotation(-tilt, Vec3(1, 0, 0))
        let pen = Pen(c: c, look: look, q: q, u: look.unit)

        look.muzzlePoints.removeAll(keepingCapacity: true)
        look.muzzleAlive.removeAll(keepingCapacity: true)

        switch look.archetype {
        case .warden: drawWarden(pen, look)
        case .mantis: drawMantis(pen, look)
        case .gyre: drawGyre(pen, look)
        case .hive: drawHive(pen, look)
        case .lancer: drawLancer(pen, look)
        case .serpent: drawSerpent(pen, look)
        case .wraith: drawWraith(pen, look)
        case .tesseract: drawTesseract(pen, look)
        case .maw: drawMaw(pen, look)
        case .heart: drawHeart(pen, look)
        }

        // The entrance: a line of light running down the hull, lighting it as it goes.
        if look.reveal < 1, look.dying == 0 {
            let y = scanLine(look.reveal)
            let fade = 1 - smooth(0.75, 1, look.reveal)
            c.line(q.act(Vec3(-1.15, y, 0.2)) * look.unit, q.act(Vec3(1.15, y, 0.2)) * look.unit,
                   color: StoryPalette.white, alpha: fade, width: 1.6)
            c.line(q.act(Vec3(-1.3, y, 0.2)) * look.unit, q.act(Vec3(1.3, y, 0.2)) * look.unit,
                   color: look.palette.accent, alpha: fade * 0.6, width: 3.5)
        }
    }

    /// A palette colour as lit this frame: going white under a hit, burning towards
    /// ember as the boss dies on its feet.
    private static func lit(_ base: UIColor, _ look: BossLook) -> UIColor {
        var color = base
        if look.health < 0.33 {
            color = StoryPalette.mix(color, StoryPalette.ember, (0.33 - look.health) / 0.33 * 0.35)
        }
        if look.hitFlash > 0.01 {
            color = StoryPalette.mix(color, StoryPalette.white, look.hitFlash * 0.7)
        }
        return color
    }

    fileprivate static func scanLine(_ reveal: Float) -> Float { 1.3 - 2.7 * reveal }

    // MARK: - Shared geometry

    /// An outline lofted through several levels — each a height and a scale — with
    /// struts between them. The bevelled plating every hull here is built from.
    static func shell(_ outline: [SIMD2<Float>], levels: [(z: Float, scale: Float)]) -> WireMesh {
        var vertices: [Vec3] = []
        var edges: [(Int, Int)] = []
        let n = outline.count
        for (l, level) in levels.enumerated() {
            for p in outline { vertices.append(Vec3(p.x * level.scale, p.y * level.scale, level.z)) }
            for i in 0..<n {
                edges.append((l * n + i, l * n + (i + 1) % n))
                if l > 0 { edges.append(((l - 1) * n + i, l * n + i)) }
            }
        }
        return WireMesh(vertices: vertices, edges: edges)
    }

    private static let unitSphere = WireMesh.geodesic(radius: 1, subdivisions: 1)
    private static let coarseSphere = WireMesh.geodesic(radius: 1, subdivisions: 0)
    private static let octa = WireMesh.octahedron(radius: 1)
    private static let cube = WireMesh.box(Vec3(1, 1, 1))
    private static let entity = WireMesh.spiked(radius: 1, spike: 1.75)
    private static let hex = WireMesh.hexPrism(radius: 1, depth: 1)

    /// The film's hostile entity, which every enemy in the game carries at its heart.
    private static func entityCore(_ pen: Pen, _ look: BossLook, at p: Vec3, radius: Float) {
        let t = look.t
        let q = rotation(t * 1.1, Vec3(0.3, 1, 0.2)) * rotation(t * 0.7, Vec3(1, 0, 0.3))
        pen.mesh(entity, at: p, rotation: q, scale: radius, color: look.coreLit, alpha: 0.95, width: 1.0,
                 backAlpha: 0.35)
        pen.glow(p, radius: radius * 1.6 * (1 + 0.5 * look.charge), look.coreLit, alpha: 0.5 + 0.4 * look.charge)
        pen.glow(p, radius: radius * 0.5, StoryPalette.white, alpha: 0.9)
    }

    /// A muzzle gathering light for the shot it is about to fire.
    private static func chargeGlow(_ pen: Pen, _ look: BossLook, at p: Vec3) {
        guard look.charge > 0.01 else { return }
        pen.glow(p, radius: 0.05 + 0.1 * look.charge, look.accentLit, alpha: look.charge * 0.9)
        pen.glow(p, radius: 0.02 + 0.03 * look.charge, StoryPalette.white, alpha: look.charge)
    }

    /// Engine light and an exhaust flickering away up the screen.
    private static func engine(_ pen: Pen, _ look: BossLook, at p: Vec3, size: Float = 1) {
        let t = look.t
        let flicker = 0.85 + 0.15 * sin(t * 41 + p.x * 9)
        pen.glow(p, radius: 0.07 * size * flicker, look.accentLit, alpha: 0.85)
        pen.glow(p, radius: 0.03 * size, StoryPalette.white, alpha: 0.9)
        for k in 0..<3 {
            let side = (Float(k) - 1) * 0.025 * size
            let length = (0.16 + 0.06 * sin(t * 29 + Float(k) * 2 + p.x * 5)) * size
            pen.line(p + Vec3(side, 0, 0), p + Vec3(side * 1.6, length, 0), look.accentLit, alpha: 0.5, width: 1)
        }
    }

    private static func hash(_ x: Float) -> Float {
        let s = sin(x * 12.9898) * 43758.5453
        return s - floor(s)
    }

    private static func polar(_ r: Float, _ a: Float, z: Float = 0) -> Vec3 {
        Vec3(cos(a) * r, sin(a) * r, z)
    }

    private static func bezier(_ a: Vec3, _ b: Vec3, _ c: Vec3, _ s: Float) -> Vec3 {
        let u = 1 - s
        return a * (u * u) + b * (2 * u * s) + c * (s * s)
    }

    // MARK: - Warden

    private static let wardenOutline: [SIMD2<Float>] = [
        SIMD2(0, 0.52), SIMD2(0.4, 0.4), SIMD2(0.6, 0.06), SIMD2(0.4, -0.4),
        SIMD2(0, -0.58), SIMD2(-0.4, -0.4), SIMD2(-0.6, 0.06), SIMD2(-0.4, 0.4)
    ]
    private static let wardenHull = shell(wardenOutline, levels: [(-0.1, 0.88), (0, 1), (0.16, 0.66)])
    private static let pod = WireMesh.box(Vec3(0.09, 0.15, 0.07))

    private static func wardenPods(tier: Int) -> [Vec3] {
        tier < 2
            ? [Vec3(-0.8, 0.02, 0), Vec3(0.8, 0.02, 0)]
            : [Vec3(-0.82, 0.14, 0), Vec3(0.82, 0.14, 0), Vec3(-0.6, -0.56, 0), Vec3(0.6, -0.56, 0)]
    }

    private static func drawWarden(_ pen: Pen, _ look: BossLook) {
        let t = look.t
        let hull = look.hullLit, accent = look.accentLit

        pen.mesh(wardenHull, color: hull, alpha: 0.95, width: 1.35, backAlpha: 0.35)

        // Plating running in from the top of the hull to the eye socket.
        for (i, p) in wardenOutline.enumerated() where i % 2 == 0 {
            let outer = Vec3(p.x * 0.66, p.y * 0.66, 0.16)
            let a = atan2(p.y, p.x)
            pen.line(outer, polar(0.21, a, z: 0.17), hull, alpha: 0.45, width: 1)
        }

        // The eye: a socket, an iris that tightens on the wind-up, and a pupil that
        // follows the ship.
        let socket = (0..<24).map { polar(0.21, Float($0) / 24 * 2 * .pi, z: 0.17) }
        pen.poly(socket, closed: true, accent, alpha: 0.9, width: 1.3)
        let iris = 0.13 * (1 - 0.35 * look.charge) + 0.008 * sin(t * 3)
        let irisRing = (0..<20).map { polar(iris, Float($0) / 20 * 2 * .pi + t, z: 0.18) }
        pen.poly(irisRing, closed: true, look.coreLit, alpha: 0.8, width: 1.1)
        let pupil = Vec3(look.gaze.x * 0.07, look.gaze.y * 0.07, 0.19)
        entityCore(pen, look, at: pupil, radius: 0.07)
        // A brow, angled down to the eye.
        for s: Float in [-1, 1] {
            pen.line(Vec3(s * 0.34, 0.27, 0.14), Vec3(s * 0.09, 0.2, 0.19), hull, alpha: 0.85, width: 1.5)
        }

        // Antennae from the second meeting on.
        if look.tier >= 1 {
            for (x, h) in [(-0.2, 0.62), (0, 0.74), (0.2, 0.62)] as [(Float, Float)] {
                let base = Vec3(x, x == 0 ? 0.52 : 0.46, 0.04)
                let tip = Vec3(x * 1.2, h, 0.04)
                pen.line(base, tip, hull, alpha: 0.7, width: 1)
                pen.glow(tip, radius: 0.025, accent, alpha: 0.5 + 0.5 * max(0, sin(t * 4 + x * 9)))
            }
        }

        // Shield rings, later.
        if look.tier >= 3 {
            pen.dashedRing(radius: 1.02, u: Vec3(1, 0, 0), v: simd_normalize(Vec3(0, 0.4, 0.92)),
                           phase: t * 0.8, dashes: 7, fill: 0.55, color: accent, alpha: 0.55, width: 1.2)
        }
        if look.tier >= 4 {
            pen.dashedRing(radius: 1.1, u: simd_normalize(Vec3(1, 0, 0.3)), v: simd_normalize(Vec3(0, 0.9, -0.4)),
                           phase: -t * 0.6, dashes: 5, fill: 0.4, color: hull, alpha: 0.45, width: 1)
        }

        for x: Float in [-0.2, 0.2] { engine(pen, look, at: Vec3(x, 0.5, -0.02)) }

        // Gun pods on struts: the parts the player can shoot off.
        for (i, p) in wardenPods(tier: look.tier).enumerated() {
            let alive = look.partAlive[i]
            let side: Float = p.x < 0 ? -1 : 1
            let attach = Vec3(side * (p.y < -0.3 ? 0.4 : 0.6), p.y < -0.3 ? -0.4 : 0.06, 0)
            let inner = Vec3(p.x - side * 0.09, p.y, 0)
            pen.line(attach + Vec3(0, 0.05, 0.02), inner + Vec3(0, 0.08, 0.02), hull, alpha: alive ? 0.8 : 0.25)
            pen.line(attach + Vec3(0, -0.05, -0.02), inner + Vec3(0, -0.08, -0.02), hull, alpha: alive ? 0.8 : 0.25)
            let muzzle = p + Vec3(0, -0.33, 0)
            if alive {
                pen.mesh(pod, at: p, color: hull, alpha: 0.95, width: 1.15, backAlpha: 0.35)
                for dx: Float in [-0.035, 0.035] {
                    pen.line(p + Vec3(dx, -0.15, 0.02), p + Vec3(dx, -0.31, 0.02), accent, alpha: 0.9, width: 1.2)
                }
                pen.glow(p + Vec3(0, 0.08, 0.08), radius: 0.03, accent, alpha: 0.5 + 0.5 * max(0, sin(t * 5 + Float(i))))
                chargeGlow(pen, look, at: muzzle)
            } else {
                pen.mesh(pod, at: p, rotation: rotation(0.4, Vec3(0.3, 0, 1)), color: hull, alpha: 0.22, width: 1)
                if hash(floor(t * 7) + Float(i) * 3.1) > 0.7 {
                    pen.glow(p, radius: 0.05, StoryPalette.ember, alpha: 0.7)
                }
            }
            look.partPoints[i] = pen.project(p)
            look.muzzlePoints.append(pen.project(muzzle))
            look.muzzleAlive.append(alive)
        }

        chargeGlow(pen, look, at: pupil)
        look.corePoint = pen.project(Vec3(0, -0.08, 0.18))
    }

    // MARK: - Mantis

    private static let mantisSections: [(y: Float, w: Float, h: Float)] = [
        (0.46, 0.08, 0.05), (0.3, 0.15, 0.1), (0.08, 0.16, 0.13), (-0.2, 0.11, 0.1), (-0.42, 0.06, 0.06)
    ]

    private static func drawMantis(_ pen: Pen, _ look: BossLook) {
        let t = look.t
        let hull = look.hullLit, accent = look.accentLit
        let sw = look.sweep

        // Fuselage: diamond cross-sections lofted to a needle nose.
        let nose = Vec3(0, -0.68, 0.02)
        let tail = Vec3(0, 0.54, 0)
        var previous: [Vec3]?
        for (i, s) in mantisSections.enumerated() {
            let loop = [Vec3(s.w, s.y, 0), Vec3(0, s.y, s.h), Vec3(-s.w, s.y, 0), Vec3(0, s.y, -s.h)]
            pen.poly(loop, closed: true, hull, alpha: 0.9, width: 1.2)
            if let previous {
                for k in 0..<4 { pen.line(previous[k], loop[k], hull, alpha: k == 3 ? 0.35 : 0.9, width: 1.2) }
            } else {
                for k in 0..<4 { pen.line(tail, loop[k], hull, alpha: k == 3 ? 0.35 : 0.8) }
            }
            if i == mantisSections.count - 1 {
                for k in 0..<4 { pen.line(loop[k], nose, hull, alpha: k == 3 ? 0.35 : 0.95, width: 1.2) }
            }
            previous = loop
        }
        entityCore(pen, look, at: Vec3(0, 0.08, 0.15), radius: 0.06)
        for s: Float in [-1, 1] {
            pen.glow(Vec3(s * 0.06, -0.38, 0.07), radius: 0.035, look.coreLit, alpha: 0.9)
            pen.poly([Vec3(s * 0.05, -0.56, 0.01), Vec3(s * 0.13, -0.66, 0.02), Vec3(s * 0.07, -0.77, 0)],
                     closed: false, hull, alpha: 0.9, width: 1.2)
        }

        // Scythe arms. Breathing in flight, swept back for a dive.
        let breathe = 0.04 * sin(t * 2.2)
        for s: Float in [-1, 1] {
            let shoulder = Vec3(s * 0.14, 0.16, 0.05)
            let elbow = Vec3(s * (0.64 - 0.2 * sw), 0.36 + 0.12 * sw + breathe, 0.12)
            let tip = Vec3(s * (0.92 - 0.44 * sw), -0.52 + 0.5 * sw - breathe, 0.02)
            let control = Vec3(s * (1.04 - 0.32 * sw), 0.02 + 0.2 * sw, 0.08)

            for dz: Float in [-0.035, 0.035] {
                pen.line(shoulder + Vec3(0, 0, dz), elbow + Vec3(0, 0, dz), hull, alpha: 0.9, width: 1.3)
            }
            for k in 1...3 {
                let p = lerp(shoulder, elbow, Float(k) / 4)
                pen.line(p + Vec3(0, 0, -0.035), p + Vec3(0, 0, 0.035), hull, alpha: 0.6, width: 1)
            }
            // Wing membrane back to the tail.
            pen.line(Vec3(s * 0.08, 0.46, 0), elbow, hull, alpha: 0.4, width: 1)
            pen.line(Vec3(s * 0.15, 0.3, 0.05), elbow, hull, alpha: 0.35, width: 1)

            // The blade: an outer curve, an inner edge tapering into it, ribs between.
            var outer: [Vec3] = []
            var inner: [Vec3] = []
            for k in 0...8 {
                let f = Float(k) / 8
                let p = bezier(elbow, control, tip, f)
                outer.append(p)
                inner.append(p + Vec3(-s * 0.08 * (1 - f), 0.02 * (1 - f), 0))
            }
            pen.poly(outer, closed: false, accent, alpha: 0.95, width: 1.5)
            pen.poly(inner, closed: false, hull, alpha: 0.8, width: 1.1)
            for k in stride(from: 1, to: 8, by: 2) { pen.line(outer[k], inner[k], hull, alpha: 0.5, width: 1) }
            pen.glow(tip, radius: 0.03, StoryPalette.white, alpha: 0.6)
            chargeGlow(pen, look, at: tip)
            look.muzzlePoints.append(pen.project(tip))
            look.muzzleAlive.append(true)
        }

        // Forelegs from the third meeting on.
        if look.tier >= 2 {
            for s: Float in [-1, 1] {
                let tip = Vec3(s * 0.46, -0.58 + 0.03 * sin(t * 3 + s), 0)
                pen.poly([Vec3(s * 0.1, -0.22, 0.02), Vec3(s * 0.4, -0.3, 0.05), tip], closed: false,
                         hull, alpha: 0.85, width: 1.2)
                chargeGlow(pen, look, at: tip)
                look.muzzlePoints.append(pen.project(tip))
                look.muzzleAlive.append(true)
            }
        }
        if look.tier >= 4 {
            for y: Float in [0.34, 0.2, 0.04] {
                pen.line(Vec3(0, y, 0.12), Vec3(0, y + 0.06, 0.26), accent, alpha: 0.7, width: 1.1)
            }
        }

        for x: Float in [-0.06, 0.06] { engine(pen, look, at: Vec3(x, 0.52, 0), size: 0.8) }
        chargeGlow(pen, look, at: nose)
        look.corePoint = pen.project(nose)
    }

    // MARK: - Gyre

    private static func drawGyre(_ pen: Pen, _ look: BossLook) {
        let t = look.t
        let hull = look.hullLit, accent = look.accentLit

        // Core: a geodesic sphere with the entity inside it.
        let sphereQ = rotation(t * 0.6, Vec3(0.2, 1, 0.1))
        pen.mesh(unitSphere, rotation: sphereQ, scale: 0.27, color: hull, alpha: 0.85, width: 1.15, backAlpha: 0.22)
        entityCore(pen, look, at: .zero, radius: 0.09)
        let belt = (0..<28).map { k -> Vec3 in
            let a = Float(k) / 28 * 2 * .pi
            return sphereQ.act(Vec3(cos(a), 0, sin(a))) * 0.31
        }
        pen.poly(belt, closed: true, accent, alpha: 0.7, width: 1.2)

        // Inner gyroscope.
        for (i, axis) in [Vec3(1, 0.3, 0), Vec3(-0.2, 1, 0.4)].enumerated() {
            let qr = rotation(t * (1.4 + Float(i) * 0.6) * (i == 0 ? 1 : -1), axis)
            let (u, v) = StoryScenery.basis(qr.act(simd_normalize(axis)))
            pen.dashedRing(radius: 0.4 + Float(i) * 0.07, u: u, v: v, phase: t * 2, dashes: 4, fill: 0.5,
                           color: i == 0 ? accent : hull, alpha: 0.6, width: 1)
        }

        // The orbit and the satellites riding it.
        let ru = Vec3(1, 0, 0)
        let rv = simd_normalize(Vec3(0, -0.72, 0.7))
        let radius: Float = 0.84
        let ring = (0..<48).map { k -> Vec3 in
            let a = Float(k) / 48 * 2 * .pi
            return (ru * cos(a) + rv * sin(a)) * radius
        }
        pen.poly(ring, closed: true, hull, alpha: 0.6, width: 1.1)
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi + .pi / 4
            let dir = ru * cos(a) + rv * sin(a)
            pen.line(dir * 0.33, dir * (radius - 0.04), hull, alpha: 0.3, width: 1)
        }
        if look.tier >= 3 {
            pen.dashedRing(radius: 1.0, u: simd_normalize(Vec3(1, 0.25, 0)), v: simd_normalize(Vec3(0, 0.55, 0.8)),
                           phase: -t * 0.5, dashes: 9, fill: 0.45, color: accent, alpha: 0.4, width: 1)
        }

        let count = look.partAlive.count
        let phase = look.orbit * 0.7
        for i in 0..<count {
            let a = phase + Float(i) / Float(count) * 2 * .pi
            let p = (ru * cos(a) + rv * sin(a)) * radius
            let depth = clamp01(0.45 + 0.55 * sin(a))
            if look.partAlive[i] {
                let qs = rotation(t * 2 + Float(i), Vec3(0.4, 1, 0.2))
                pen.mesh(octa, at: p, rotation: qs, scale: 0.095, color: accent, alpha: 0.6 + 0.4 * depth, width: 1.2)
                pen.glow(p, radius: 0.06, look.coreLit, alpha: 0.3 + 0.4 * depth)
                // A short comet tail along the orbit.
                let tail = (0...5).map { k -> Vec3 in
                    let b = a - Float(k) * 0.07
                    return (ru * cos(b) + rv * sin(b)) * radius
                }
                pen.poly(tail, closed: false, accent, alpha: 0.4 * depth, width: 1.6)
                chargeGlow(pen, look, at: p)
            } else {
                pen.line(p + Vec3(-0.05, -0.05, 0), p + Vec3(0.05, 0.05, 0), hull, alpha: 0.25)
                pen.line(p + Vec3(-0.05, 0.05, 0), p + Vec3(0.05, -0.05, 0), hull, alpha: 0.25)
            }
            look.partPoints[i] = pen.project(p)
            look.muzzlePoints.append(look.partPoints[i])
            look.muzzleAlive.append(look.partAlive[i])
        }

        chargeGlow(pen, look, at: Vec3(0, -0.2, 0.1))
        look.corePoint = pen.project(Vec3(0, -0.22, 0.1))
    }

    // MARK: - Hive

    private static let hiveR: Float = 0.19

    private static func hiveCells(tier: Int) -> [SIMD2<Float>] {
        let dx: Float = 0.329, dy: Float = 0.285
        var cells: [SIMD2<Float>] = [
            SIMD2(0, 0.05), SIMD2(-dx, 0.05), SIMD2(dx, 0.05),
            SIMD2(-dx / 2, 0.05 + dy), SIMD2(dx / 2, 0.05 + dy),
            SIMD2(-dx / 2, 0.05 - dy), SIMD2(dx / 2, 0.05 - dy)
        ]
        if tier >= 1 { cells += [SIMD2(-dx * 1.5, 0.05 + dy), SIMD2(dx * 1.5, 0.05 + dy)] }
        if tier >= 3 { cells += [SIMD2(-dx * 2, 0.05), SIMD2(dx * 2, 0.05), SIMD2(0, 0.05 + dy * 2)] }
        return cells
    }

    private static func hiveBays(tier: Int) -> [Vec3] {
        let base = [Vec3(-0.33, -0.52, 0), Vec3(0.33, -0.52, 0)]
        return tier < 2 ? base : base + [Vec3(0, -0.6, 0)]
    }

    private static func drawHive(_ pen: Pen, _ look: BossLook) {
        let t = look.t
        let hull = look.hullLit, accent = look.accentLit

        for (i, cell) in hiveCells(tier: look.tier).enumerated() {
            let height: Float = 0.06 + 0.08 * hash(Float(i) + 0.5)
            let centre = Vec3(cell.x, cell.y, height / 2 - 0.05)
            pen.mesh(hex, at: centre, scale: 1, color: hull, alpha: 0.9, width: 1.1, backAlpha: 0.3,
                     stretch: Vec3(hiveR * 0.94, hiveR * 0.94, height))
            // Brood light rippling through the comb.
            let pulse = max(0, sin(t * 2.4 - Float(i) * 0.9))
            pen.glow(Vec3(cell.x, cell.y, height), radius: 0.07 + 0.03 * pulse, accent, alpha: 0.2 + 0.5 * pulse)
            if i == 0 { entityCore(pen, look, at: Vec3(cell.x, cell.y, height + 0.04), radius: 0.07) }
        }

        // Claws hooked under the comb.
        for s: Float in [-1, 1] {
            let swing = 0.03 * sin(t * 1.6 + s)
            pen.poly([Vec3(s * 0.46, -0.22, 0), Vec3(s * 0.66, -0.56 + swing, 0.04), Vec3(s * 0.52, -0.8 + swing, 0)],
                     closed: false, hull, alpha: 0.85, width: 1.3)
        }

        for (i, bay) in hiveBays(tier: look.tier).enumerated() {
            let alive = look.partAlive[i]
            let ring = (0..<6).map { k -> Vec3 in
                bay + polar(0.17, Float(k) / 6 * 2 * .pi + .pi / 2, z: 0.02)
            }
            if alive {
                pen.poly(ring, closed: true, accent, alpha: 0.95, width: 1.4)
                pen.mesh(hex, at: bay + Vec3(0, 0, -0.02), color: hull, alpha: 0.7, width: 1,
                         stretch: Vec3(0.17, 0.17, 0.08))
                let iris = 0.05 + 0.06 * look.charge + 0.01 * sin(t * 6 + Float(i))
                let irisRing = (0..<12).map { bay + polar(iris, Float($0) / 12 * 2 * .pi, z: 0.04) }
                pen.poly(irisRing, closed: true, look.coreLit, alpha: 0.85, width: 1.1)
                pen.glow(bay + Vec3(0, 0, 0.04), radius: 0.05, look.coreLit, alpha: 0.5 + 0.4 * look.charge)
            } else {
                pen.poly(Array(ring.prefix(4)), closed: false, hull, alpha: 0.25)
                if hash(floor(t * 6) + Float(i) * 2.3) > 0.72 {
                    pen.glow(bay, radius: 0.06, StoryPalette.ember, alpha: 0.7)
                }
            }
            look.partPoints[i] = pen.project(bay)
            look.muzzlePoints.append(pen.project(bay + Vec3(0, -0.08, 0)))
            look.muzzleAlive.append(alive)
        }

        for x: Float in [-0.25, 0, 0.25] { engine(pen, look, at: Vec3(x, look.tier >= 3 ? 0.78 : 0.5, 0), size: 0.9) }
        chargeGlow(pen, look, at: Vec3(0, 0.05, 0.12))
        look.corePoint = pen.project(Vec3(0, -0.2, 0.08))
    }

    // MARK: - Lancer

    private static func drawLancer(_ pen: Pen, _ look: BossLook) {
        let t = look.t
        let hull = look.hullLit, accent = look.accentLit
        let charge = look.charge

        // The crystal: a hexagonal bipyramid turning on its long axis, a second one
        // inside it turning the other way.
        let tip = Vec3(0, -0.82, 0)
        for (scale, color, speed) in [(Float(1), hull, Float(0.5)), (Float(0.5), accent, Float(-0.9))] {
            let girdle = (0..<6).map { k -> Vec3 in
                let a = t * speed + Float(k) / 6 * 2 * .pi
                return Vec3(cos(a) * 0.21 * scale, 0.06, sin(a) * 0.21 * scale)
            }
            let top = Vec3(0, 0.06 + 0.58 * scale, 0), bottom = Vec3(0, 0.06 - 0.88 * scale, 0)
            pen.poly(girdle, closed: true, color, alpha: 0.9, width: 1.2)
            for (k, g) in girdle.enumerated() {
                let back: Float = g.z < 0 ? 0.4 : 1
                pen.line(top, g, color, alpha: 0.9 * back, width: 1.2)
                pen.line(g, bottom, color, alpha: 0.9 * back, width: 1.2)
                // Energy running down to the emitter on the wind-up.
                if scale == 1, charge > 0.01 {
                    let s = (t * 1.8 + Float(k) / 6).truncatingRemainder(dividingBy: 1)
                    pen.glow(lerp(g, tip, s), radius: 0.03, look.coreLit, alpha: charge)
                }
            }
        }
        entityCore(pen, look, at: Vec3(0, 0.06, 0), radius: 0.07)

        // Focusing rings, tightening and spinning up as it charges.
        for (i, (y, r)) in [(Float(-0.26), Float(0.22)), (-0.42, 0.165), (-0.58, 0.11)].enumerated() {
            let radius = r * (1 - 0.25 * charge)
            pen.dashedRing(radius: radius, center: Vec3(0, y, 0), u: Vec3(1, 0, 0), v: Vec3(0, 0, 1),
                           phase: t * (1.5 + 4 * charge) * (i % 2 == 0 ? 1 : -1), dashes: 6, fill: 0.7,
                           color: i == 1 ? look.coreLit : accent, alpha: 0.6 + 0.4 * charge, width: 1.2)
        }

        // Fins.
        for s: Float in [-1, 1] {
            let a = Vec3(s * 0.17, 0.26, 0)
            let b = Vec3(s * (0.94 + 0.03 * charge), 0.42 + 0.06 * charge, 0)
            let c = Vec3(s * 0.34, -0.34, 0)
            for dz: Float in [-0.03, 0.03] {
                pen.poly([a + Vec3(0, 0, dz), b + Vec3(0, 0, dz), c + Vec3(0, 0, dz)], closed: true, hull,
                         alpha: dz > 0 ? 0.9 : 0.4, width: 1.2)
            }
            for k in 1...3 {
                let f = Float(k) / 4
                pen.line(a, lerp(b, c, f), hull, alpha: 0.35, width: 1)
            }
            if look.tier == 0 {
                chargeGlow(pen, look, at: b)
                look.muzzlePoints.append(pen.project(b))
                look.muzzleAlive.append(true)
            }
        }

        if look.tier >= 3 {
            pen.dashedRing(radius: 0.55, center: Vec3(0, 0.1, -0.12), u: Vec3(1, 0, 0), v: Vec3(0, 1, 0),
                           phase: t * 0.7, dashes: 8, fill: 0.5, color: accent, alpha: 0.45, width: 1)
        }

        // Capacitors at the fin tips: shootable.
        for i in 0..<look.partAlive.count {
            let s: Float = i == 0 ? -1 : 1
            let p = Vec3(s * 0.86, 0.38, 0.03)
            if look.partAlive[i] {
                pen.mesh(coarseSphere, at: p, rotation: rotation(t * 1.5, Vec3(0.3, 1, 0)), scale: 0.085,
                         color: accent, alpha: 0.95, width: 1.1)
                pen.glow(p, radius: 0.07, look.coreLit, alpha: 0.45 + 0.4 * charge)
                chargeGlow(pen, look, at: p)
            } else {
                pen.mesh(coarseSphere, at: p, scale: 0.06, color: hull, alpha: 0.2, width: 1)
            }
            look.partPoints[i] = pen.project(p)
            look.muzzlePoints.append(look.partPoints[i])
            look.muzzleAlive.append(look.partAlive[i])
        }

        pen.glow(tip, radius: 0.05 + 0.12 * charge, look.coreLit, alpha: 0.6 + 0.4 * charge)
        pen.glow(tip, radius: 0.02 + 0.04 * charge, StoryPalette.white, alpha: 0.9)
        look.corePoint = pen.project(tip)
    }

    // MARK: - Serpent

    private static let serpentHead = shell([
        SIMD2(0, -0.62), SIMD2(0.3, -0.2), SIMD2(0.42, 0.16), SIMD2(0.2, 0.42),
        SIMD2(-0.2, 0.42), SIMD2(-0.42, 0.16), SIMD2(-0.3, -0.2)
    ], levels: [(-0.08, 0.86), (0, 1), (0.16, 0.6)])

    private static func drawSerpent(_ pen: Pen, _ look: BossLook) {
        let t = look.t
        let hull = look.hullLit, accent = look.accentLit
        let u = look.unit
        let count = look.partAlive.count

        // The spine, drawn first so the segments sit over it.
        var spine: [Vec3] = [.zero]
        for i in 0..<count {
            let p = i < look.trail.count ? look.trail[i] : CGPoint(x: 0, y: CGFloat(Float(i + 1) * 0.62 * u))
            spine.append(Vec3(Float(p.x) / u, Float(p.y) / u, 0))
        }
        pen.flat.poly(spine, closed: false, accent, alpha: 0.45, width: 1.4)

        // Segments, tail first so nearer the head overlaps.
        for i in stride(from: count - 1, through: 0, by: -1) {
            let here = spine[i + 1], ahead = spine[i]
            let dir = ahead - here
            let angle = atan2(dir.y, dir.x) - .pi / 2
            let segment = pen.moved(to: here, turned: angle)
            let r: Float = 0.36 * (1 - 0.45 * Float(i) / Float(max(1, count - 1)))
            let alive = look.partAlive[i]
            if alive {
                segment.mesh(hex, rotation: rotation(.pi / 6, Vec3(0, 0, 1)), color: hull, alpha: 0.9, width: 1.15,
                             backAlpha: 0.35, stretch: Vec3(r, r, 0.14))
                let inner = (0..<6).map { polar(r * 0.45, Float($0) / 6 * 2 * .pi + t * 1.5, z: 0.08) }
                segment.poly(inner, closed: true, accent, alpha: 0.7, width: 1)
                for s: Float in [-1, 1] {
                    let wave = 0.04 * sin(t * 5 - Float(i) * 0.8)
                    segment.line(Vec3(s * r, 0, 0.03), Vec3(s * (r + 0.17), -0.05 + wave, 0.06), hull, alpha: 0.8)
                }
                segment.glow(Vec3(0, 0, 0.08), radius: 0.06, look.coreLit, alpha: 0.55)
                chargeGlow(segment, look, at: Vec3(0, 0, 0.08))
            } else {
                segment.mesh(hex, rotation: rotation(.pi / 6 + 0.3, Vec3(0.2, 0, 1)), color: hull, alpha: 0.2, width: 1,
                             stretch: Vec3(r * 0.85, r * 0.85, 0.1))
                if hash(floor(t * 6) + Float(i) * 1.7) > 0.75 {
                    segment.glow(.zero, radius: 0.07, StoryPalette.ember, alpha: 0.7)
                }
            }
            look.partPoints[i] = CGPoint(x: CGFloat(here.x * u), y: CGFloat(here.y * u))
        }
        // Muzzles in segment order, head to tail, whatever order they were drawn in.
        for i in 0..<count {
            look.muzzlePoints.append(look.partPoints[i])
            look.muzzleAlive.append(look.partAlive[i])
        }

        // The head, turned away from its body and down towards the ship.
        let first = spine.count > 1 ? spine[1] : Vec3(0, 1, 0)
        var away = SIMD2<Float>(-first.x, -first.y)
        let length = simd_length(away)
        away = length > 1e-3 ? away / length : SIMD2(0, -1)
        let heading = simd_normalize(away * 0.5 + SIMD2(0, -1) * 0.5)
        let head = pen.moved(to: .zero, turned: atan2(heading.y, heading.x) + .pi / 2)
        head.mesh(serpentHead, color: hull, alpha: 0.95, width: 1.35, backAlpha: 0.35)
        for s: Float in [-1, 1] {
            head.glow(Vec3(s * 0.17, -0.06, 0.13), radius: 0.045, look.coreLit, alpha: 0.95)
            head.line(Vec3(s * 0.32, 0.08, 0.13), Vec3(s * 0.08, -0.02, 0.17), hull, alpha: 0.85, width: 1.4)
            let bite = 0.03 * sin(t * 4) + 0.06 * look.charge
            head.poly([Vec3(s * 0.12, -0.46, 0), Vec3(s * (0.3 + bite), -0.64, 0.02), Vec3(s * (0.15 + bite), -0.8, 0)],
                      closed: false, accent, alpha: 0.95, width: 1.3)
        }
        entityCore(head, look, at: Vec3(0, 0.14, 0.15), radius: 0.07)
        chargeGlow(head, look, at: Vec3(0, -0.62, 0.02))
        look.corePoint = head.project(Vec3(0, -0.66, 0.02))
    }

    // MARK: - Wraith

    private static func wraithBody(_ pen: Pen, _ look: BossLook, hull: UIColor, accent: UIColor, alpha: Float) {
        let t = look.t
        // A crown of curved blades round a hollow.
        for k in 0..<7 {
            let offset = Float(k) - 3
            let theta = Float.pi / 2 + offset * 0.36
            let bend: Float = offset == 0 ? 0 : (offset < 0 ? 0.32 : -0.32)
            let reach: Float = 0.8 - 0.07 * abs(offset) + 0.03 * sin(t * 2 + offset)
            let tip = polar(reach, theta + bend, z: 0.02)
            var a: [Vec3] = [], b: [Vec3] = []
            for j in 0...6 {
                let f = Float(j) / 6
                a.append(bezier(polar(0.27, theta - 0.13, z: 0.1), polar(0.55, theta + bend * 0.5 - 0.06, z: 0.08), tip, f))
                b.append(bezier(polar(0.27, theta + 0.13, z: 0.1), polar(0.6, theta + bend * 0.5 + 0.08, z: 0.08), tip, f))
            }
            pen.poly(a, closed: false, hull, alpha: alpha * 0.95, width: 1.25)
            pen.poly(b, closed: false, hull, alpha: alpha * 0.7, width: 1.1)
            pen.line(a[3], b[3], hull, alpha: alpha * 0.4, width: 1)
        }
        let rim = (0..<28).map { polar(0.27, Float($0) / 28 * 2 * .pi, z: 0.1) }
        pen.poly(rim, closed: true, accent, alpha: alpha * 0.8, width: 1.3)
        pen.dashedRing(radius: 0.34, u: Vec3(1, 0, 0), v: Vec3(0, 1, 0), phase: -t * 1.2, dashes: 6, fill: 0.5,
                       color: accent, alpha: alpha * 0.5, width: 1)

        // The eye: an almond with a slit that turns to the ship.
        var upper: [Vec3] = [], lower: [Vec3] = []
        let open: Float = 0.1 + 0.04 * look.charge
        for j in 0...10 {
            let y = 0.17 - 0.34 * Float(j) / 10
            let w = open * (1 - (y / 0.17) * (y / 0.17))
            upper.append(Vec3(w, y, 0.14))
            lower.append(Vec3(-w, y, 0.14))
        }
        pen.poly(upper, closed: false, look.coreLit, alpha: alpha, width: 1.3)
        pen.poly(lower, closed: false, look.coreLit, alpha: alpha, width: 1.3)
        let gx = look.gaze.x * 0.045
        pen.line(Vec3(gx, 0.11, 0.15), Vec3(gx, -0.11, 0.15), StoryPalette.white, alpha: alpha, width: 1.6)
    }

    private static func drawWraith(_ pen: Pen, _ look: BossLook) {
        let t = look.t
        let hull = look.hullLit, accent = look.accentLit

        // Rift interference: displaced ghosts of the body, now and then, and always
        // while it is phasing.
        let glitch = hash(floor(t * 7)) > 0.78 || look.fade < 0.95
        if glitch {
            let jitter = CGFloat(3 + 4 * hash(floor(t * 23)))
            for (dx, color) in [(jitter, StoryPalette.violet), (-jitter, StoryPalette.ice)] {
                pen.c.settings.offset = CGPoint(x: dx, y: 0)
                pen.c.applyOffset()
                wraithBody(pen, look, hull: color, accent: color, alpha: 0.3)
            }
            pen.c.settings.offset = .zero
            pen.c.applyOffset()
        }
        let flicker: Float = 0.88 + 0.12 * sin(t * 13) * sin(t * 3.7)
        wraithBody(pen, look, hull: hull, accent: accent, alpha: flicker)
        pen.glow(Vec3(look.gaze.x * 0.045, 0, 0.15), radius: 0.07, look.coreLit, alpha: 0.7 + 0.3 * look.charge)

        // The hands: two long claws reaching down, opening on the wind-up.
        for s: Float in [-1, 1] {
            let open = 0.12 * look.charge + 0.06 * sin(t * 1.3)
            let theta = -Float.pi / 2 + s * (0.72 + open)
            let tip = polar(0.95, theta - s * 0.35, z: 0.02)
            var edge: [Vec3] = []
            for j in 0...7 {
                edge.append(bezier(polar(0.28, theta + s * 0.1, z: 0.1), polar(0.7, theta, z: 0.06), tip, Float(j) / 7))
            }
            pen.poly(edge, closed: false, accent, alpha: 0.95 * flicker, width: 1.5)
            pen.line(polar(0.3, theta - s * 0.12, z: 0.1), edge[4], hull, alpha: 0.6 * flicker, width: 1)
            chargeGlow(pen, look, at: tip)
            look.muzzlePoints.append(pen.project(tip))
            look.muzzleAlive.append(true)
        }

        // Tendrils trailing underneath.
        for k in 0..<5 {
            let x0 = -0.16 + 0.08 * Float(k)
            let points = (0...8).map { j -> Vec3 in
                let f = Float(j) / 8
                let sway = (0.02 + 0.07 * f) * sin(t * 3.1 + Float(k) * 1.3 + Float(j) * 0.7)
                return Vec3(x0 * (1 + f * 0.6) + sway, -0.26 - 0.66 * f * (1 - 0.1 * abs(Float(k) - 2)), 0.04)
            }
            pen.poly(points, closed: false, hull, alpha: 0.55 * flicker, width: 1)
            pen.glow(points[8], radius: 0.022, accent, alpha: 0.7)
        }

        look.corePoint = pen.project(Vec3(0, -0.12, 0.15))
    }

    // MARK: - Tesseract

    private static let hypercube: [SIMD4<Float>] = (0..<16).map { i in
        SIMD4<Float>(i & 1 == 0 ? -1 : 1, i & 2 == 0 ? -1 : 1, i & 4 == 0 ? -1 : 1, i & 8 == 0 ? -1 : 1)
    }
    private static let hyperEdges: [(Int, Int)] = {
        var edges: [(Int, Int)] = []
        for i in 0..<16 { for bit in [1, 2, 4, 8] where i & bit == 0 { edges.append((i, i | bit)) } }
        return edges
    }()

    private static func drawTesseract(_ pen: Pen, _ look: BossLook) {
        let t = look.t
        let hull = look.hullLit, accent = look.accentLit

        // A faint lattice behind it: the grid of the space it is folding through.
        for k in -3...3 {
            let f = Float(k) * 0.3
            pen.line(Vec3(f, -0.9, -0.35), Vec3(f, 0.9, -0.35), accent, alpha: 0.1, width: 1)
            pen.line(Vec3(-0.9, f, -0.35), Vec3(0.9, f, -0.35), accent, alpha: 0.1, width: 1)
        }

        // Turn in two planes through the fourth axis, then project down.
        let a = t * 0.62, b = t * 0.41
        let ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b)
        let scale = 0.68 * look.fade
        var projected: [Vec3] = []
        var depth: [Float] = []
        for v in hypercube {
            var x = v.x * ca - v.w * sa
            var w = v.x * sa + v.w * ca
            let z = v.z * cb - w * sb
            w = v.z * sb + w * cb
            let roll = t * 0.23
            let y = v.y * cos(roll) - x * sin(roll)
            x = v.y * sin(roll) + x * cos(roll)
            let f = 1 / (2.4 - w)
            x *= f
            projected.append(Vec3(x, y * f, z * f) * scale)
            depth.append(w)
        }
        for (i, j) in hyperEdges {
            let near = clamp01((depth[i] + depth[j]) * 0.25 + 0.5)
            pen.line(projected[i], projected[j], near > 0.5 ? hull : accent, alpha: 0.45 + 0.55 * near,
                     width: 1 + 0.6 * near)
        }
        for (i, p) in projected.enumerated() {
            pen.glow(p, radius: 0.025, accent, alpha: 0.3 + 0.4 * clamp01(depth[i] * 0.5 + 0.5))
        }
        entityCore(pen, look, at: .zero, radius: 0.07 * max(0.2, look.fade))

        // Orbiting cubes from the third meeting on; before that it fires from its own
        // lowest corners.
        let cubes = look.tier >= 2 ? min(4, look.tier) : 0
        if cubes > 0 {
            let ru = Vec3(1, 0, 0), rv = simd_normalize(Vec3(0, -0.754, 0.66))
            for k in 0..<cubes {
                let angle = look.orbit * 0.9 + Float(k) / Float(cubes) * 2 * .pi
                let p = (ru * cos(angle) + rv * sin(angle)) * 0.9 * look.fade
                pen.mesh(cube, at: p, rotation: rotation(t * 2 + Float(k), Vec3(1, 1, 0.3)), scale: 0.06,
                         color: accent, alpha: 0.9, width: 1.1)
                pen.glow(p, radius: 0.05, look.coreLit, alpha: 0.4)
                chargeGlow(pen, look, at: p)
                look.muzzlePoints.append(pen.project(p))
                look.muzzleAlive.append(true)
            }
        } else {
            let lowest = projected.indices.sorted { projected[$0].y < projected[$1].y }
            var picked: [Vec3] = []
            for index in lowest where picked.count < 2 {
                let p = projected[index]
                if picked.allSatisfy({ abs($0.x - p.x) > 0.15 }) { picked.append(p) }
            }
            for p in picked.sorted(by: { $0.x < $1.x }) {
                chargeGlow(pen, look, at: p)
                look.muzzlePoints.append(pen.project(p))
                look.muzzleAlive.append(true)
            }
        }
        look.corePoint = pen.project(Vec3(0, -0.05, 0.05))
    }

    // MARK: - Maw

    private static func drawMaw(_ pen: Pen, _ look: BossLook) {
        let t = look.t
        let hull = look.hullLit, accent = look.accentLit
        let c = pen.c
        let fade = look.fade

        // Anything behind the hole's plane is drawn behind its shadow.
        c.settings.depthSplit = look.cameraDistance
        c.disc(pen.world(.zero), radius: 0.3 * look.unit * max(0.05, 1 - look.dying), color: .black, alpha: 0.98)

        // Photon ring and the lensed far side of the disc arching over the top.
        let view = (Vec3(1, 0, 0), Vec3(0, 1, 0))
        pen.flat.ring(radius: 0.32, u: view.0, v: view.1, color: look.coreLit, alpha: 0.95, width: 2)
        pen.flat.glow(.zero, radius: 0.42, look.coreLit, alpha: 0.25 * fade)
        let arc = (0...16).map { k -> Vec3 in polar(0.41 + 0.02 * sin(t * 2), 0.25 + Float(k) / 16 * (.pi - 0.5)) }
        pen.flat.poly(arc, closed: false, hull, alpha: 0.6, width: 1.4)

        // The accretion disc: dashed rings turning faster the closer in they are.
        let du = Vec3(1, 0, 0), dv = simd_normalize(Vec3(0, -0.754, 0.66))
        let radii: [Float] = look.tier >= 2 ? [0.42, 0.55, 0.69, 0.84, 0.98] : [0.42, 0.55, 0.69, 0.84]
        for (i, r) in radii.enumerated() {
            let speed = 2.2 * pow(0.42 / r, 1.5)
            let mix = (r - 0.42) / 0.56
            let color = StoryPalette.mix(look.coreLit, hull, mix)
            pen.dashedRing(radius: r, u: du, v: dv, phase: t * speed * look.spin, dashes: 8 + 3 * i, fill: 0.62,
                           color: color, alpha: 0.9 - 0.12 * Float(i), width: 1.3)
        }
        // Matter spiralling in.
        for k in 0..<22 {
            let seed = hash(Float(k) * 3.7 + 1)
            let life = (t * 0.32 * look.spin + seed).truncatingRemainder(dividingBy: 1)
            let r = 1.0 - 0.66 * life
            let angle = seed * 2 * .pi + t * 1.1 / r
            let p = (du * cos(angle) + dv * sin(angle)) * r
            pen.glow(p, radius: 0.02, StoryPalette.mix(look.coreLit, accent, 1 - life), alpha: min(1, life * (1 - life) * 5))
        }
        if look.tier >= 2 {
            for s: Float in [-1, 1] {
                for k in 0..<4 {
                    let f = ((t * 1.5 + Float(k) / 4).truncatingRemainder(dividingBy: 1))
                    pen.flat.line(Vec3(0, s * (0.34 + f * 0.6), 0), Vec3(0, s * (0.39 + f * 0.6), 0), accent,
                                  alpha: (1 - f) * 0.8, width: 1.5)
                }
            }
        }
        if look.tier >= 3 {
            pen.flat.ring(radius: 1.02, u: view.0, v: view.1, color: accent, alpha: 0.15, width: 1)
        }
        chargeGlow(pen, look, at: Vec3(0, -0.3, 0))
        look.corePoint = pen.project(Vec3(0, -0.3, 0))
    }

    // MARK: - Heart

    private static let heartShellMask: [Bool] = (0..<unitSphere.edges.count).map { hash(Float($0) * 1.37) > 0.28 }

    private static func drawHeart(_ pen: Pen, _ look: BossLook) {
        let t = look.t
        let hull = look.hullLit, accent = look.accentLit

        // The entity, full size, inside a cracked shell.
        let coreQ = rotation(t * 0.4, Vec3(0.3, 1, 0.2)) * rotation(t * 0.27, Vec3(1, 0, 0.4))
        pen.mesh(entity, rotation: coreQ, scale: 0.3, color: hull, alpha: 0.95, width: 1.3, backAlpha: 0.3)
        pen.glow(.zero, radius: 0.24 * (1 + 0.3 * look.charge), look.palette.hull, alpha: 0.45)
        let shellQ = rotation(-t * 0.2, Vec3(0.2, 1, -0.3))
        pen.mesh(unitSphere, rotation: shellQ, scale: 0.54, color: accent, alpha: 0.5, width: 1, backAlpha: 0.2,
                 mask: heartShellMask)

        // Gyroscope rings.
        let axes = [Vec3(1, 0.25, 0), Vec3(0.2, 1, 0.3), Vec3(0.4, -0.3, 1)]
        for (i, axis) in axes.enumerated() {
            let q = rotation(t * (0.5 + Float(i) * 0.25) * (i == 1 ? -1 : 1), axis)
            let (u, v) = StoryScenery.basis(q.act(simd_normalize(axis)))
            pen.dashedRing(radius: 0.74 + Float(i) * 0.1, u: u, v: v, phase: t * 1.5, dashes: 6 + i, fill: 0.55,
                           color: i == 1 ? look.coreLit : (i == 0 ? accent : hull), alpha: 0.6, width: 1.2)
        }

        // The eye, opening on the wind-up.
        let open: Float = 0.08 + 0.05 * look.charge + 0.01 * sin(t * 2)
        var lidTop: [Vec3] = [], lidBottom: [Vec3] = []
        for j in 0...12 {
            let x = -0.22 + 0.44 * Float(j) / 12
            let h = open * (1 - (x / 0.22) * (x / 0.22))
            lidTop.append(Vec3(x, h, 0.56))
            lidBottom.append(Vec3(x, -h, 0.56))
        }
        pen.poly(lidTop, closed: false, look.coreLit, alpha: 1, width: 1.5)
        pen.poly(lidBottom, closed: false, look.coreLit, alpha: 1, width: 1.5)
        let pupil = Vec3(look.gaze.x * 0.06, look.gaze.y * 0.03, 0.57)
        let iris = (0..<16).map { pupil + polar(0.065, Float($0) / 16 * 2 * .pi + t) }
        pen.poly(iris, closed: true, accent, alpha: 0.9, width: 1.2)
        pen.glow(pupil, radius: 0.06, look.coreLit, alpha: 0.9)
        pen.glow(pupil, radius: 0.025, StoryPalette.white, alpha: 1)
        chargeGlow(pen, look, at: pupil)

        // Tendrils.
        for k in 0..<6 {
            let x0 = -0.25 + 0.1 * Float(k)
            let points = (0...9).map { j -> Vec3 in
                let f = Float(j) / 9
                let sway = (0.02 + 0.08 * f) * sin(t * 2.6 + Float(k) * 1.1 + Float(j) * 0.6)
                return Vec3(x0 * (1 + f * 0.8) + sway, -0.45 - 0.55 * f, -0.05)
            }
            pen.poly(points, closed: false, hull, alpha: 0.5, width: 1)
            pen.glow(points[9], radius: 0.022, accent, alpha: 0.7)
        }

        // Shell nodes: the four guns the player can take off it. They wheel on the
        // orbit, not the clock: the orbital spiral spins them up through `look.spin`,
        // which only reaches the orbit, and on `t` they turned at the idle rate through
        // it, so the heart's signature drew straight lines instead of spiral arms.
        for i in 0..<look.partAlive.count {
            let angle = Float.pi / 4 + Float(i) * .pi / 2 + look.orbit * 0.25
            let p = polar(0.66, angle, z: 0.05)
            if look.partAlive[i] {
                pen.mesh(octa, at: p, rotation: rotation(t * 1.8 + Float(i), Vec3(0.4, 1, 0.2)), scale: 0.085,
                         color: accent, alpha: 1, width: 1.2)
                pen.glow(p, radius: 0.06, look.coreLit, alpha: 0.5)
                pen.flat.line(p * 0.82, p * 0.6, accent, alpha: 0.4, width: 1)
                chargeGlow(pen, look, at: p)
            } else if hash(floor(t * 6) + Float(i) * 2.9) > 0.7 {
                pen.glow(p, radius: 0.06, StoryPalette.ember, alpha: 0.7)
            }
            look.partPoints[i] = pen.project(p)
            look.muzzlePoints.append(look.partPoints[i])
            look.muzzleAlive.append(look.partAlive[i])
        }
        look.corePoint = pen.project(pupil)
    }
}

// MARK: - Pen

/// Draws into a boss's canvas in its model space — one unit is half the boss's width —
/// and applies the per-boss treatment to every line on the way: the entrance scan, the
/// damage flicker, the death throes, the blink.
private struct Pen {
    let c: WireCanvas
    let look: BossLook
    let q: simd_quatf
    let u: Float
    /// Where this pen's origin sits in model space, before its rotation.
    var origin = Vec3.zero
    /// Extra local rotation about the screen normal, before the boss's own tilt.
    var turn = identityRotation
    /// Whether to skip the tilt, for things drawn face-on in the view plane.
    var faceOn = false

    init(c: WireCanvas, look: BossLook, q: simd_quatf, u: Float) {
        self.c = c
        self.look = look
        self.q = q
        self.u = u
    }

    /// The same pen drawing face-on to the camera.
    var flat: Pen {
        var pen = self
        pen.faceOn = true
        return pen
    }

    /// A pen whose origin sits at `point` (model units, in the screen plane) and whose
    /// drawing is turned by `angle` about the screen normal there.
    func moved(to point: Vec3, turned angle: Float) -> Pen {
        var pen = self
        pen.origin = point
        pen.turn = rotation(angle, Vec3(0, 0, 1))
        return pen
    }

    private var orientation: simd_quatf { faceOn ? turn : q * turn }

    /// Model space (relative to this pen) to the canvas's world.
    func world(_ v: Vec3) -> Vec3 {
        let shifted = Vec3(origin.x, origin.y, 0) * u
        return shifted + orientation.act(v) * u
    }

    func project(_ v: Vec3) -> CGPoint {
        c.project(world(v)) ?? CGPoint(x: CGFloat(origin.x * u), y: CGFloat(origin.y * u))
    }

    // MARK: Treatment

    /// The model-space point the treatment keys off: the pen's origin plus `v`, turned.
    private func modelPoint(_ v: Vec3) -> Vec3 { origin + turn.act(v) }

    private func treat(_ mid: Vec3) -> Float {
        var alpha = look.fade
        if look.reveal < 1 {
            let line = BossArt.scanLine(look.reveal)
            alpha *= smooth(line - 0.02, line + 0.14, mid.y)
        }
        if look.health < 0.66, look.dying == 0 {
            let severity = (0.66 - look.health) / 0.66
            let bucket = floor(look.t * 9)
            let h = Pen.hash(mid.x * 13.1 + mid.y * 7.7 + mid.z * 3.3 + bucket * 1.618)
            if h < severity * 0.3 { alpha *= 0.18 }
        }
        return alpha
    }

    private static func hash(_ x: Float) -> Float {
        let s = sin(x * 12.9898) * 43758.5453
        return s - floor(s)
    }

    // MARK: Lines

    func line(_ a: Vec3, _ b: Vec3, _ color: UIColor, alpha: Float = 1, width: Float = 1.3) {
        var a = a, b = b
        let mid = modelPoint((a + b) * 0.5)
        var shade = alpha * treat(mid)
        if look.dying > 0 {
            // The hull coming apart: every edge thrown out from the centre, tumbling
            // and shrinking as it goes.
            let d = look.dying
            let h = Pen.hash(mid.x * 12.9898 + mid.y * 78.233 + mid.z * 37.719)
            var dir = Vec3(mid.x, mid.y, mid.z * 0.5 + 0.2)
            let length = simd_length(dir)
            dir = length > 1e-3 ? dir / length : Vec3(0, 1, 0)
            let localMid = (a + b) * 0.5
            let push = turn.inverse.act(dir) * (0.25 + 1.1 * h) * pow(d, 0.75) * 1.4
            let tumble = simd_quatf(angle: (h - 0.5) * 7 * d, axis: simd_normalize(Vec3(h, 1 - h, 0.5)))
            let shrink = 1 - 0.55 * d
            a = localMid + push + tumble.act((a - localMid) * shrink)
            b = localMid + push + tumble.act((b - localMid) * shrink)
            shade *= pow(1 - d, 1.3)
        }
        guard shade > 0.012 else { return }
        c.line(world(a), world(b), color: color, alpha: shade, width: width * 1.2)
    }

    func poly(_ points: [Vec3], closed: Bool, _ color: UIColor, alpha: Float = 1, width: Float = 1.3) {
        guard points.count > 1 else { return }
        for i in 1..<points.count { line(points[i - 1], points[i], color, alpha: alpha, width: width) }
        if closed { line(points[points.count - 1], points[0], color, alpha: alpha, width: width) }
    }

    /// Draws a mesh, its far side faded by `backAlpha`. `stretch` scales each axis on
    /// top of `scale`; `mask` hides edges by index.
    func mesh(_ mesh: WireMesh, at p: Vec3 = .zero, rotation r: simd_quatf = identityRotation, scale s: Float = 1,
              color: UIColor, alpha: Float = 1, width: Float = 1.3, backAlpha: Float? = nil,
              stretch: Vec3 = Vec3(1, 1, 1), mask: [Bool]? = nil) {
        let vertices = mesh.vertices.map { p + r.act($0 * stretch * s) }
        let centre = c.toView(world(p))
        for (index, (i, j)) in mesh.edges.enumerated() {
            if let mask, index < mask.count, !mask[index] { continue }
            var a = alpha
            if let backAlpha {
                let mid = (c.toView(world(vertices[i])) + c.toView(world(vertices[j]))) * 0.5
                if simd_dot(mid - centre, mid) > 0 { a *= backAlpha }
            }
            line(vertices[i], vertices[j], color, alpha: a, width: width)
        }
    }

    func ring(radius: Float, center: Vec3 = .zero, u: Vec3, v: Vec3, color: UIColor, alpha: Float, width: Float = 1.3,
              segments: Int = 36) {
        let points = (0..<segments).map { k -> Vec3 in
            let a = Float(k) / Float(segments) * 2 * .pi
            return center + (u * cos(a) + v * sin(a)) * radius
        }
        poly(points, closed: true, color, alpha: alpha, width: width)
    }

    /// A dashed ring: the gaps are what make its turning visible.
    func dashedRing(radius: Float, center: Vec3 = .zero, u: Vec3, v: Vec3, phase: Float, dashes: Int, fill: Float,
                    color: UIColor, alpha: Float, width: Float = 1.3) {
        let span = 2 * Float.pi / Float(dashes)
        for d in 0..<dashes {
            let a0 = phase + Float(d) * span
            let points = (0...4).map { k -> Vec3 in
                let a = a0 + span * fill * Float(k) / 4
                return center + (u * cos(a) + v * sin(a)) * radius
            }
            poly(points, closed: false, color, alpha: alpha, width: width)
        }
    }

    // MARK: Light

    func glow(_ v: Vec3, radius: Float, _ color: UIColor, alpha: Float = 1) {
        var shade = alpha * treat(modelPoint(v))
        if look.dying > 0 { shade *= max(0, 1 - look.dying * 1.5) }
        guard shade > 0.012 else { return }
        c.glow(world(v), radius: radius * u, color: color, alpha: shade)
    }
}
