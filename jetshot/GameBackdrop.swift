//
//  GameBackdrop.swift
//  jetshot
//
//  The world the fight happens over.
//
//  The story films are real-time 3D wireframe — perspective, depth fog, light-tube
//  lines — and the game used to drop out of them into a flat navy gradient with
//  blurred blobs and tiled plating behind the action. This puts the films' world
//  behind the playfield instead: the same `WireCanvas`, a camera flying forward
//  and looking down over the scenery, so everything in it streams down the screen
//  with true parallax, the way a vertical shooter's ground should.
//
//  Every sector of the campaign is a place from the opening film — the grid at the
//  end of ages, the dead megastructures, the rift tunnel, the quantum bleed, the
//  gravity wells and finally the epicentre — so flying the fifty levels is flying
//  the route the film describes. Within a sector every level is its own leg of
//  that place (see `BackdropStage`): the ground changes shape, different things
//  stand on it and something different is going on over it.
//
//  Two canvases: `sky` holds what is effectively at infinity (stars, nebulae, the
//  bodies on the horizon) and only redraws at 30 Hz; `world` holds the scenery the
//  camera flies over and redraws every frame. Both are single batched draws.
//

import SpriteKit
import simd

nonisolated enum BackdropTheme: CaseIterable {
    /// Spacetime grid to a burning horizon, a red giant going down behind it.
    case horizon
    /// The wireframe ruins of a dead megastructure passing under the ship.
    case ruins
    /// A hexagonal rift tunnel.
    case rift
    /// Grids of other spaces cutting through each other, tesseracts adrift.
    case quantum
    /// A field of gravity wells, a black hole on the horizon.
    case well
    /// The heart of the collapse, ahead and growing.
    case epicentre
}

/// Which world, which of its two colourings, and which leg of it.
nonisolated struct BackdropLook: Equatable {
    var theme: BackdropTheme
    var variant: Int
    /// Which level of its sector, 0...4. See `BackdropStage`.
    var stage: Int = 0

    /// Fifty levels as ten sectors of five, each sector a place on the film's route
    /// and each level in it a different leg through that place. The second pass
    /// through a world wears its other colouring.
    static func forLevel(_ level: Int) -> BackdropLook {
        let index = max(1, level) - 1
        var look = route[(index / 5) % route.count]
        look.stage = index % 5
        return look
    }

    /// Endless changes world every three rounds, and leg every round.
    static func forEndlessRound(_ round: Int) -> BackdropLook {
        let index = max(1, round) - 1
        var look = route[(index / 3) % route.count]
        look.stage = index % 5
        return look
    }

    static let route: [BackdropLook] = [
        BackdropLook(theme: .horizon, variant: 0),
        BackdropLook(theme: .ruins, variant: 0),
        BackdropLook(theme: .rift, variant: 0),
        BackdropLook(theme: .quantum, variant: 0),
        BackdropLook(theme: .well, variant: 0),
        BackdropLook(theme: .horizon, variant: 1),
        BackdropLook(theme: .ruins, variant: 1),
        BackdropLook(theme: .rift, variant: 1),
        BackdropLook(theme: .quantum, variant: 1),
        BackdropLook(theme: .epicentre, variant: 0)
    ]
}

final class GameBackdrop: SKNode {

    static let nodeName = "backdrop"

    /// Overall brightness. The films run at 1; behind a playfield full of small fast
    /// things the world has to sit back, or it competes with the bullets.
    private static let baseIntensity: Float = 0.72
    private static let fov: Float = 62

    private let sky: WireCanvas
    private let world: WireCanvas
    private(set) var viewport: CGRect

    private(set) var look: BackdropLook
    private var stage: BackdropStage
    private var palette: Palette
    private var rig: Rig
    private var pending: BackdropLook?
    /// Visibility of the current world, for cross-fades between sectors.
    private var fade: Float = 0

    private var t: Float = 0
    private var travelled: Float = 0
    private var currentSpeed: Float = 0
    private var rush: Float = 0
    private var rushTarget: Float = 0
    private var alert: Float = 0
    private var alertTarget: Float = 0
    private var pulseAge: Float = 10
    private var glitchAmount: Float = 0
    private var focus: Float = 0
    private var focusTarget: Float = 0
    private var skyTimer: Float = .infinity
    /// How far through the level the player is, 0...1, eased.
    private var progress: Float = 0
    private var progressTarget: Float = 0
    /// A lightning flash lighting up the whole world, decaying.
    private var flash: Float = 0

    private let stars: [(dir: Vec3, size: Float, tint: UIColor, phase: Float)]

    // Events with a life of their own: they are anchored where they happened, so
    // they cannot be recomputed from the clock alone.
    private struct Strike {
        let from: Vec3
        let to: Vec3
        var age: Float
        let duration: Float
        let seed: UInt64
    }
    private var meteors: [Strike] = []
    private var bolts: [Strike] = []
    private var meteorTimer: Float = 0.6
    private var boltTimer: Float = 0.9
    private var dice = StoryRandom(seed: 0xD1CE)

    // This frame's ground: the shock fronts rolling over it and the wells pulling it down.
    private struct Front {
        let z: Float
        let height: Float
        let width: Float
    }
    private var fronts: [Front] = []
    private var sags: [Funnel] = []

    // Per-frame colours, worked out once rather than per line.
    private var gridColor: UIColor = StoryPalette.cyan
    private var accentColor: UIColor = StoryPalette.gold
    private var stormColor: UIColor = StoryPalette.ice
    private var master: Float = 0
    private var shake: CGPoint = .zero

    init(size: CGSize, look: BackdropLook) {
        let frame = CGRect(origin: .zero, size: size)
        viewport = frame
        sky = WireCanvas(viewport: frame)
        world = WireCanvas(viewport: frame)
        self.look = look
        stage = BackdropStage.of(look)
        palette = Self.palette(for: look, mood: stage.mood)
        rig = Self.rig(for: look.theme)

        var rng = StoryRandom(seed: 4_242)
        let tints = [StoryPalette.white, StoryPalette.ice, StoryPalette.sun, StoryPalette.violet]
        stars = (0..<170).map { _ in
            let big = rng.unit() > 0.94
            return (rng.direction(), big ? rng.float(7...10) : rng.float(2.6...5),
                    tints[Int(rng.unit() * Float(tints.count)) % tints.count], rng.float(0...(2 * .pi)))
        }
        super.init()
        name = Self.nodeName
        sky.zPosition = 0
        world.zPosition = 4
        addChild(sky)
        addChild(world)
        currentSpeed = rig.cruise
        // A few seconds of flight already behind it, so the first frame is mid-journey.
        travelled = 400
        update(dt: 0)
    }

    convenience init(size: CGSize, level: Int, endless: Bool) {
        self.init(size: size, look: endless ? .forEndlessRound(1) : .forLevel(level))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Ambient use

    /// The films' near-black, behind everything the backdrop draws.
    static let spaceColor = UIColor(red: 0.004, green: 0.006, blue: 0.02, alpha: 1)

    /// Extra dimming on top of the base brightness, for use behind a menu.
    var intensityScale: Float = 1

    /// The world as scenery behind a menu or a results screen: dimmer than in play,
    /// and driving itself, since those scenes have no update loop of their own to
    /// drive it from.
    @discardableResult
    static func attachAmbient(to scene: SKScene, look: BackdropLook) -> GameBackdrop {
        scene.childNode(withName: nodeName)?.removeFromParent()
        scene.backgroundColor = spaceColor
        let backdrop = GameBackdrop(size: scene.size, look: look)
        backdrop.intensityScale = 0.8
        backdrop.zPosition = -20
        scene.addChild(backdrop)
        backdrop.run(.repeatForever(.customAction(withDuration: 60) { [weak backdrop] _, elapsed in
            backdrop?.selfDrive(elapsed: elapsed)
        }), withKey: "selfDrive")
        return backdrop
    }

    private var driveElapsed: CGFloat = 0

    private func selfDrive(elapsed: CGFloat) {
        let dt = elapsed < driveElapsed ? elapsed : elapsed - driveElapsed
        driveElapsed = elapsed
        update(dt: TimeInterval(dt))
    }

    // MARK: - Control

    func resize(to size: CGSize) {
        viewport = CGRect(origin: .zero, size: size)
        sky.resize(viewport: viewport)
        world.resize(viewport: viewport)
        skyTimer = .infinity
    }

    /// Overdrive: the world rushes, the grid burns gold, the stars stretch.
    func setRush(_ on: Bool) { rushTarget = on ? 1 : 0 }

    /// A boss is on the field: the world goes to red alert.
    func setAlert(_ on: Bool) { alertTarget = on ? 1 : 0 }

    /// A ring of light across the world — a boss going down, a nuke.
    func pulse() { pulseAge = 0 }

    /// The picture jumps and tears for a moment — the player has been hit.
    func glitch(_ amount: Float = 1) { glitchAmount = max(glitchAmount, amount) }

    /// The ship's position across the screen, 0...1. The camera leans with it, so
    /// the near scenery slides against the far and the ground reads as ground.
    func follow(x fraction: CGFloat) { focusTarget = Float(min(1, max(0, fraction))) * 2 - 1 }

    /// How far through the level the player has got, 0...1. The world moves on with
    /// it — the star on the horizon goes down, the storm thickens, the epicentre
    /// looms — so the end of a level is not the same picture as its start.
    func setProgress(_ fraction: CGFloat) { progressTarget = Float(min(1, max(0, fraction))) }

    /// Fades through to another world.
    func transition(to next: BackdropLook) {
        guard next != look || pending != nil else { return }
        pending = next == look ? nil : next
    }

    // MARK: - Frame

    func update(dt rawDt: TimeInterval) {
        let dt = Float(min(max(rawDt, 0), 0.1))
        t += dt
        rush += (rushTarget - rush) * min(1, dt * 2.4)
        alert += (alertTarget - alert) * min(1, dt * 1.4)
        focus += (focusTarget - focus) * min(1, dt * 2.5)
        progress += (progressTarget - progress) * min(1, dt * 0.5)
        glitchAmount = max(0, glitchAmount - dt * 2.6)
        flash = max(0, flash - dt * 3.2)
        pulseAge += dt

        if let next = pending {
            fade -= dt / 0.8
            if fade <= 0 {
                fade = 0
                look = next
                stage = BackdropStage.of(next)
                palette = Self.palette(for: next, mood: stage.mood)
                rig = Self.rig(for: next.theme)
                meteors.removeAll()
                bolts.removeAll()
                pending = nil
                skyTimer = .infinity
            }
        } else if fade < 1 {
            fade = min(1, fade + dt / 1.4)
        }

        let targetSpeed = rig.cruise * (1 + 3.4 * rush)
        currentSpeed += (targetSpeed - currentSpeed) * min(1, dt * 3)
        travelled += currentSpeed * dt

        let pulseBoost = 0.55 * (1 - smooth(0.05, 1.4, pulseAge))
        master = Self.baseIntensity * intensityScale * fade * (1 + pulseBoost)
        if glitchAmount > 0 {
            master *= 0.75 + 0.5 * abs(sin(t * 61))
            shake = CGPoint(x: CGFloat(sin(t * 83) * 9 * glitchAmount), y: CGFloat(sin(t * 47) * 2 * glitchAmount))
        } else {
            shake = .zero
        }

        gridColor = StoryPalette.mix(StoryPalette.mix(palette.grid, StoryPalette.gold, rush * 0.7),
                                     StoryPalette.red, alert * 0.6)
        accentColor = StoryPalette.mix(palette.accent, StoryPalette.red, alert * 0.4)
        stormColor = StoryPalette.mix(StoryPalette.ice, palette.highlight, 0.25)

        let eye = self.eye()
        fronts = stage.has(.shockwaves) ? shockFronts(eye: eye) : []
        sags = stage.ground == .sagging ? funnels(near: eye) : []
        stepEvents(dt: dt, eye: eye)

        renderWorld(eye: eye)
        skyTimer += dt
        if skyTimer >= 1.0 / 30 || glitchAmount > 0 {
            skyTimer = 0
            renderSky()
        }
    }

    // MARK: - Camera

    private struct Rig {
        /// Camera height over the ground (or over the tunnel axis). Scenery on the
        /// ground is sized from it, so the same feature reads the same from any height.
        let height: Float
        /// Where the horizon sits, as a fraction of the screen height. Above 1 the
        /// camera is looking down into the depths with no horizon in frame.
        let horizon: CGFloat
        /// Cruising speed, world units a second.
        let cruise: Float
        /// Height band the dust drifts in.
        let dust: ClosedRange<Float>
    }

    private static func rig(for theme: BackdropTheme) -> Rig {
        switch theme {
        case .horizon: return Rig(height: 46, horizon: 0.77, cruise: 68, dust: 4...40)
        case .ruins: return Rig(height: 150, horizon: 0.8, cruise: 96, dust: 20...130)
        case .rift: return Rig(height: 0, horizon: 0.86, cruise: 150, dust: -90...60)
        case .quantum: return Rig(height: 0, horizon: 1.3, cruise: 80, dust: -240 ... -30)
        case .well: return Rig(height: 84, horizon: 0.74, cruise: 76, dust: 10...70)
        case .epicentre: return Rig(height: 52, horizon: 0.7, cruise: 72, dust: 4...46)
        }
    }

    private var focal: Float {
        Float(min(viewport.width, viewport.height) / 2) / tan(Self.fov * .pi / 360)
    }

    /// Pitch that puts the horizon at `rig.horizon` of the screen height. Worked out
    /// from the viewport so a phone and an iPad frame the same world the same way.
    private var pitch: Float {
        atan(Float((rig.horizon - 0.5) * viewport.height) / focal)
    }

    private var roll: Float { -focus * 0.025 + sin(t * 0.23) * 0.008 }

    private var forward: Vec3 {
        let p = pitch
        return Vec3(0, -sin(p), -cos(p))
    }

    private func eye() -> Vec3 {
        let sway = sin(t * 0.07) * 10 + focus * 26
        switch look.theme {
        case .rift:
            return tunnelCentre(travelled) + Vec3(focus * 14, 0, 0)
        default:
            return Vec3(sway, rig.height + sin(t * 0.19) * 2, -travelled)
        }
    }

    /// How wide a strip of ground is in view `depth` ahead, either side of the eye.
    /// Rows and columns are cut to it, so a near row is a handful of segments
    /// rather than a full-width polyline mostly off screen.
    private func halfWidth(at depth: Float) -> Float {
        let spread = Float(viewport.width / 2) / focal
        let distance = (depth * depth + rig.height * rig.height).squareRoot()
        return min(560, distance * spread * 1.2 + 40)
    }

    // MARK: - Events

    private func stepEvents(dt: Float, eye: Vec3) {
        let h = rig.height
        // Things get busier the deeper into the level the player is.
        let ramp = 0.75 + 0.6 * progress

        if stage.has(.meteors) {
            meteorTimer -= dt * ramp
            if meteorTimer <= 0 {
                meteorTimer = dice.float(0.45...1.15)
                let x = eye.x + dice.float(-1.6...1.6) * h
                let z = eye.z - dice.float(140...520)
                let impact = Vec3(x, ground(x, z), z)
                let dir = simd_normalize(Vec3(dice.float(-0.35...0.35), 1, -dice.float(0.5...0.9)))
                meteors.append(Strike(from: impact + dir * (9 * h / dir.y), to: impact, age: 0,
                                      duration: dice.float(0.8...1.2), seed: dice.next()))
            }
        }
        if stage.has(.storm) {
            boltTimer -= dt * ramp
            if boltTimer <= 0 {
                boltTimer = dice.float(0.35...1.4)
                let x = eye.x + dice.float(-2.2...2.2) * h
                let z = eye.z - dice.float(150...800)
                let target = Vec3(x, ground(x, z), z)
                let top = target + Vec3(dice.float(-1...1) * h, 9 * h, -dice.float(0...2) * h)
                bolts.append(Strike(from: top, to: target, age: 0, duration: 0.3, seed: dice.next()))
                flash = 1
            }
        }
        for i in meteors.indices { meteors[i].age += dt }
        meteors.removeAll { $0.age > $0.duration + 1.3 }
        for i in bolts.indices { bolts[i].age += dt }
        bolts.removeAll { $0.age > $0.duration + 0.8 }
    }

    // MARK: - World

    private func renderWorld(eye: Vec3) {
        world.settings = WireCanvas.Settings()
        world.settings.intensity = master
        world.settings.offset = shake
        world.settings.fogNear = 60
        world.settings.fogFar = look.theme == .quantum ? 1500 : 1000
        world.settings.widthReference = 90
        world.begin(WireCamera(position: eye, target: eye + forward * 100, roll: roll, fov: Self.fov))

        if master > 0.01 {
            switch look.theme {
            case .horizon, .ruins, .well, .epicentre: drawFloorWorld(eye: eye)
            case .rift: drawRift(eye: eye)
            case .quantum: drawQuantum(eye: eye)
            }
            drawDust(eye: eye)
            if rush > 0.02 { drawWarp(eye: eye) }
            if pulseAge < 1.6 { drawPulse(eye: eye) }
        }
        world.end()
    }

    /// Everything flown over rather than through: a ground, and what stands on it
    /// and goes on over it.
    private func drawFloorWorld(eye: Vec3) {
        let spacing: Float
        let alpha: Float
        switch look.theme {
        case .horizon: spacing = 34; alpha = 0.34
        case .ruins: spacing = 48; alpha = 0.26
        case .well: spacing = stage.ground == .sagging ? 44 : 62; alpha = 0.26
        default: spacing = 40; alpha = 0.26
        }
        let wells = stage.has(.funnels) ? funnels(near: eye) : []
        drawGround(eye: eye, spacing: spacing, alpha: alpha * (1 + 0.6 * flash), far: look.theme == .ruins ? 950 : 1000) { x, _ in
            // The funnels sit over the rows as holes in the grid, which is what a
            // well in spacetime looks like from above anyway.
            wells.contains { abs($0.centre.x - x) < $0.radius * 0.9 }
        }
        drawAlertScan(eye: eye)
        if stage.ground == .canyon { drawCanyonEdges(eye: eye) }

        if stage.has(.funnels) { for well in wells { drawFunnel(well, eye: eye) } }
        if stage.ground == .sagging { drawSagThroats() }
        if stage.has(.craters) { drawCraters(eye: eye) }
        if stage.has(.towers) { drawTowers(eye: eye) }
        if stage.has(.spires) { drawSpires(eye: eye) }
        if stage.has(.wrecks) { drawWrecks(eye: eye) }
        if stage.has(.arches) { drawArches(eye: eye) }
        if stage.has(.pylons) { drawPylons(eye: eye) }
        if stage.has(.crystals) { drawCrystals(eye: eye) }
        if stage.has(.vents) { drawVents(eye: eye) }
        if stage.has(.searchlights) { drawSearchlights(eye: eye) }
        if stage.has(.runners) { drawRunners(eye: eye, spacing: spacing) }
        if stage.has(.inflow) { drawInflow(eye: eye) }
        if stage.has(.debris) { drawDebris(eye: eye, band: (rig.height * 0.3)...(rig.height * 0.82), alpha: 0.5) }
        if stage.has(.convoy) { drawConvoy(eye: eye) }
        if stage.has(.meteors) { drawMeteors() }
        if stage.has(.storm) { drawBolts() }
    }

    // MARK: Ground

    /// The ground's height under a point, everything included: its shape, the wells
    /// pulling it down and the shock fronts rolling over it.
    private func ground(_ x: Float, _ z: Float) -> Float {
        let h = rig.height
        var y: Float = 0
        switch stage.ground {
        case .flat, .shattered:
            break
        case .dunes:
            let swell = sin(z * 0.011 + 1.5 * sin(x * 0.006))
            let cross = sin(x * 0.017 + z * 0.004)
            y = h * 0.28 * (0.6 * swell + 0.4 * cross)
        case .canyon:
            let w = canyonHalfWidth
            let d = abs(x - canyonCentre(z))
            let rugged = 0.78 + 0.22 * sin(z * 0.013 + x * 0.021)
            y = smooth(w, w + 0.8 * h, d) * h * 0.7 * rugged
        case .sagging:
            for well in sags {
                let dx = x - well.centre.x, dz = z - well.centre.z
                let r = well.radius * 0.6
                guard abs(dz) < r * 3 else { continue }
                y -= well.depth * 0.7 * exp(-(dx * dx + dz * dz) / (r * r))
            }
        }
        for front in fronts {
            let u = (z - front.z) / front.width
            y += front.height * exp(-u * u)
        }
        return y
    }

    private var canyonHalfWidth: Float { 0.85 * rig.height + 8 }

    /// The canyon's channel winds, slowly enough that the camera never meets a wall.
    private func canyonCentre(_ z: Float) -> Float { 0.35 * canyonHalfWidth * sin(z * 0.0021) }

    /// The lip of each cliff and the foot of each wall, traced along the canyon, so
    /// its shape reads at a glance rather than only from the bend in the grid.
    private func drawCanyonEdges(eye: Vec3) {
        let w = canyonHalfWidth
        let lip = StoryPalette.mix(accentColor, palette.highlight, 0.3)
        let zs = stride(from: eye.z + 40, through: eye.z - 1000, by: -25).map { $0 }
        for side in [Float(-1), 1] {
            for (offset, color, alpha) in [(w + 0.8 * rig.height, lip, Float(0.75)), (w, gridColor, Float(0.45))] {
                let points = zs.map { z -> Vec3 in
                    let x = canyonCentre(z) + side * offset
                    return Vec3(x, ground(x, z) + 0.5, z)
                }
                world.polyline(points, color: color, alpha: alpha, width: 1.5)
            }
        }
    }

    /// Whether the ground is a different height across a row as well as along it.
    private var groundVariesAcross: Bool {
        stage.ground == .dunes || stage.ground == .canyon || stage.ground == .sagging
    }

    /// A shock front every few seconds, rolling in from the horizon and under the ship.
    private func shockFronts(eye: Vec3) -> [Front] {
        let speed: Float = 260
        let life: Float = 1150 / speed
        let period: Float = 3.1
        var result: [Front] = []
        var age = t.truncatingRemainder(dividingBy: period)
        while age < life {
            let depth = 1050 - age * speed
            let strength = smooth(-90, 30, depth)
            result.append(Front(z: eye.z - depth, height: rig.height * 0.3 * strength, width: max(22, rig.height * 0.5)))
            age += period
        }
        return result
    }

    /// How lit a row is by a shock front passing over it, 0...1.
    private func frontGlow(_ z: Float) -> Float {
        var glow: Float = 0
        for front in fronts where front.height > 0.5 {
            let u = (z - front.z) / front.width
            glow = max(glow, exp(-u * u) * min(1, front.height / (rig.height * 0.3)))
        }
        return glow
    }

    private func drawGround(eye: Vec3, spacing g: Float, alpha: Float, far: Float,
                            gap: ((Float, Float) -> Bool)? = nil) {
        switch stage.ground {
        case .shattered:
            drawShatteredFloor(eye: eye, spacing: g, alpha: alpha, far: far)
        case .flat where fronts.isEmpty:
            drawFloor(eye: eye, spacing: g, color: gridColor, alpha: alpha, far: far, gap: gap)
        default:
            drawHeightfield(eye: eye, spacing: g, alpha: alpha, far: far)
        }
    }

    /// The flat ground grid. Rows are anchored in the world, so they stream at the
    /// speed of flight; columns run along the flight path.
    private func drawFloor(eye: Vec3, spacing g: Float, color: UIColor, alpha: Float,
                           halfWidth: Float = 560, far: Float = 1000, y: Float = 0,
                           gap: ((Float, Float) -> Bool)? = nil) {
        let near = eye.z + 40
        let end = eye.z - far
        var k = Int((near / g).rounded(.down))
        let last = Int((end / g).rounded(.up))
        let left = eye.x - halfWidth, right = eye.x + halfWidth
        while k >= last {
            let z = Float(k) * g
            world.line(Vec3(left, y, z), Vec3(right, y, z), color: color, alpha: alpha, width: 1.1)
            k -= 1
        }
        let first = Int((left / g).rounded(.up))
        let lastColumn = Int((right / g).rounded(.down))
        guard first <= lastColumn else { return }
        for i in first...lastColumn {
            let x = Float(i) * g
            if let gap, gap(x, eye.z) { continue }
            world.line(Vec3(x, y, near), Vec3(x, y, end), color: color, alpha: alpha, width: 1.1)
        }
    }

    /// The grid laid over a shaped ground: rows and columns as polylines through the
    /// same vertices, so they still meet where they cross.
    private func drawHeightfield(eye: Vec3, spacing g: Float, alpha: Float, far: Float) {
        let near = eye.z + 40
        let end = eye.z - far
        let across = groundVariesAcross
        let kNear = Int((near / g).rounded(.down))
        let kFar = Int((end / g).rounded(.up))
        guard kNear > kFar else { return }

        // Depths every column is sampled at: the rows, plus extra samples where a
        // shock front is, which is narrower than a cell.
        var zs: [Float] = []
        zs.reserveCapacity(64)
        for k in stride(from: kNear, to: kFar, by: -1) {
            let z0 = Float(k) * g
            zs.append(z0)
            let busy = fronts.contains { abs($0.z - (z0 - g / 2)) < $0.width * 2.2 + g / 2 }
            if busy {
                for s in 1..<4 { zs.append(z0 - g * Float(s) / 4) }
            }
        }
        zs.append(Float(kFar) * g)

        // Rows.
        var points: [Vec3] = []
        points.reserveCapacity(40)
        for k in stride(from: kNear, through: kFar, by: -1) {
            let z = Float(k) * g
            let reach = halfWidth(at: eye.z - z)
            let glow = frontGlow(z)
            let color = glow > 0.05 ? StoryPalette.mix(gridColor, palette.highlight, glow) : gridColor
            let a = alpha * (1 + glow * 1.4)
            if across {
                points.removeAll(keepingCapacity: true)
                let i0 = Int(((eye.x - reach) / g).rounded(.down))
                let i1 = Int(((eye.x + reach) / g).rounded(.up))
                for i in i0...i1 {
                    let x = Float(i) * g
                    points.append(Vec3(x, ground(x, z), z))
                }
                world.polyline(points, color: color, alpha: a, width: 1.1)
            } else {
                let y = ground(eye.x, z)
                world.line(Vec3(eye.x - reach, y, z), Vec3(eye.x + reach, y, z), color: color, alpha: a, width: 1.1)
            }
        }

        // Columns, each started only where it comes into view.
        let reach = halfWidth(at: far)
        let first = Int(((eye.x - reach) / g).rounded(.up))
        let lastColumn = Int(((eye.x + reach) / g).rounded(.down))
        guard first <= lastColumn else { return }
        for i in first...lastColumn {
            let x = Float(i) * g
            let off = abs(x - eye.x) - g
            points.removeAll(keepingCapacity: true)
            for z in zs where halfWidth(at: eye.z - z) >= off {
                points.append(Vec3(x, ground(x, z), z))
            }
            world.polyline(points, color: gridColor, alpha: alpha, width: 1.1)
        }
    }

    /// The floor coming apart: cells break away as the ship nears them and tumble
    /// into the dark, leaving holes the grid runs around.
    private func drawShatteredFloor(eye: Vec3, spacing g: Float, alpha: Float, far: Float) {
        let near = eye.z + 40
        let end = eye.z - far
        let breakDepth: Float = 640
        let kNear = Int((near / g).rounded(.down))
        let kFar = Int((end / g).rounded(.up))
        let left = eye.x - 560, right = eye.x + 560
        let i0 = Int((left / g).rounded(.down))
        let i1 = Int((right / g).rounded(.up))
        guard kNear > kFar, i1 > i0 else { return }

        func broken(_ i: Int, _ k: Int) -> Bool {
            let depth = eye.z - (Float(k) + 0.5) * g
            guard depth < breakDepth else { return false }
            return Self.fractured(i, k)
        }

        // Rows: a row at k borders the cells either side of it, and is there
        // wherever either of them still is.
        for k in stride(from: kNear, through: kFar, by: -1) {
            let z = Float(k) * g
            if eye.z - z > breakDepth + g {
                world.line(Vec3(left, 0, z), Vec3(right, 0, z), color: gridColor, alpha: alpha, width: 1.1)
                continue
            }
            var runStart: Int?
            for i in i0...i1 {
                let present = i < i1 && (!broken(i, k - 1) || !broken(i, k))
                if present, runStart == nil { runStart = i }
                if !present, let start = runStart {
                    world.line(Vec3(Float(start) * g, 0, z), Vec3(Float(i) * g, 0, z), color: gridColor, alpha: alpha, width: 1.1)
                    runStart = nil
                }
            }
        }
        // Columns: the edge between k and k + 1 borders the cells either side of the column.
        for i in i0...i1 {
            let x = Float(i) * g
            var runStart: Int?
            for k in kFar...kNear {
                let present = k < kNear && (!broken(i - 1, k) || !broken(i, k))
                if present, runStart == nil { runStart = k }
                if !present, let start = runStart {
                    world.line(Vec3(x, 0, Float(start) * g), Vec3(x, 0, Float(k) * g), color: gridColor, alpha: alpha, width: 1.1)
                    runStart = nil
                }
            }
        }

        // The tiles falling out of the holes.
        let fall = rig.height * 2.6
        let edge = StoryPalette.mix(gridColor, palette.highlight, 0.4)
        for k in stride(from: kNear, through: kFar, by: -1) {
            let depth = eye.z - (Float(k) + 0.5) * g
            guard depth < breakDepth else { break }
            let reach = halfWidth(at: depth)
            let ia = Int(((eye.x - reach) / g).rounded(.down))
            let ib = Int(((eye.x + reach) / g).rounded(.up))
            for i in ia...ib where Self.fractured(i, k) {
                let drop = easeIn(clamp01((breakDepth - depth) / 520))
                let a = 1 - smooth(0.55, 1, drop)
                guard a > 0.02 else { continue }
                var rng = StoryRandom(seed: 0x7113 &+ UInt64(bitPattern: Int64(i &* 7_919 &+ k)))
                let centre = Vec3((Float(i) + 0.5) * g, -drop * fall, (Float(k) + 0.5) * g)
                let tumble = rotation(drop * rng.float(1.2...2.6), simd_normalize(Vec3(rng.float(-1...1), 0.1, rng.float(-1...1))))
                let h = g * 0.5
                let corners = [Vec3(-h, 0, -h), Vec3(h, 0, -h), Vec3(h, 0, h), Vec3(-h, 0, h)].map { centre + tumble.act($0) }
                world.polyline(corners, closed: true, color: edge, alpha: alpha * 1.6 * a, width: 1.1)
            }
        }
    }

    /// Whether a cell of the shattered floor is one that gives way. Clustered, so
    /// the floor breaks in chunks rather than as a speckle.
    private static func fractured(_ i: Int, _ k: Int) -> Bool {
        hash(i >> 1, k >> 1, 0xF4AC) < 0.34 && hash(i, k, 0xC4AC) < 0.78
    }

    private static func hash(_ i: Int, _ k: Int, _ salt: UInt64) -> Float {
        let a = UInt64(bitPattern: Int64(i)) &* 0x9E37_79B1
        let b = UInt64(bitPattern: Int64(k)) &* 0x85EB_CA77
        var rng = StoryRandom(seed: salt &+ a &+ b)
        return rng.unit()
    }

    /// A line rolling down the ground from the horizon — the boss alarm.
    private func drawAlertScan(eye: Vec3, far: Float = 950) {
        guard alert > 0.02 else { return }
        let shaped = stage.ground != .flat && stage.ground != .shattered || !fronts.isEmpty
        for k in 0..<2 {
            let phase = (t * 0.55 + Float(k) * 0.5).truncatingRemainder(dividingBy: 1)
            let z = eye.z - far * (1 - phase) + 30
            let a = alert * smooth(0, 0.15, phase) * (1 - smooth(0.8, 1, phase))
            if shaped {
                let points = (0...16).map { s -> Vec3 in
                    let x = eye.x - 700 + Float(s) * 87.5
                    return Vec3(x, ground(x, z) + 1, z)
                }
                world.polyline(points, color: StoryPalette.red, alpha: a, width: 2.2)
            } else {
                world.line(Vec3(eye.x - 700, 0, z), Vec3(eye.x + 700, 0, z), color: StoryPalette.red, alpha: a, width: 2.2)
            }
        }
    }

    /// Walks the anchors `gap` apart that are in range, nearest first.
    private func anchors(eye: Vec3, gap: Float, near: Float, far: Float, _ body: (Int) -> Void) {
        var k = Int(((eye.z + near) / gap).rounded(.down))
        let last = Int(((eye.z - far) / gap).rounded(.up))
        while k >= last {
            body(k)
            k -= 1
        }
    }

    private func groundRing(_ centre: Vec3, radius: Float, segments: Int, color: UIColor, alpha: Float, width: Float = 1.2) {
        world.polyline(StoryScenery.circle(center: centre, radius: radius, u: Vec3(1, 0, 0), v: Vec3(0, 0, 1), segments: segments),
                       color: color, alpha: alpha, width: width)
    }

    // MARK: Towers

    private func drawTowers(eye: Vec3) {
        let lit = StoryPalette.mix(palette.highlight, StoryPalette.red, alert * 0.5)
        let scale = rig.height / 150
        anchors(eye: eye, gap: 80, near: 160, far: 900) { k in
            var rng = StoryRandom(seed: 0x5EED_0000 &+ UInt64(bitPattern: Int64(k)))
            let count = 2 + Int(rng.unit() * 2.6)
            for n in 0..<count {
                let x = rng.float(-560...560)
                let z = Float(k) * 80 + rng.float(-20...20)
                let w = rng.float(24...64) * scale, d = rng.float(24...64) * scale
                let tall = rng.unit() > 0.8
                let h = rng.float(16...60) * (tall ? 1.9 : 1) * scale
                // In a burning city, some of them are alight.
                let burning = stage.has(.vents) && Self.hash(k, n, 0xB0E2) < 0.3
                drawTower(at: Vec3(x, ground(x, z), z), half: Vec3(w, 0, d) * 0.5, height: h, seed: k &* 7 &+ n,
                          beacon: tall && !burning, lit: lit, burning: burning)
            }
        }
    }

    private func drawTower(at base: Vec3, half: Vec3, height h: Float, seed: Int, beacon: Bool, lit: UIColor,
                           burning: Bool = false) {
        let corners = [Vec3(-half.x, 0, -half.z), Vec3(half.x, 0, -half.z), Vec3(half.x, 0, half.z), Vec3(-half.x, 0, half.z)]
        let top = Vec3(0, h, 0)
        for i in 0..<4 {
            let a = base + corners[i], b = base + corners[(i + 1) % 4]
            world.line(a + top, b + top, color: accentColor, alpha: 0.95, width: 1.4)
            world.line(a, a + top, color: accentColor, alpha: 0.55, width: 1.2)
        }
        // The roof inset: one more ring reads as structure rather than as a box.
        if h > 30 {
            let inset: Float = 0.6
            let roof = corners.map { base + $0 * inset + top + Vec3(0, 4, 0) }
            world.polyline(roof, closed: true, color: accentColor, alpha: 0.5, width: 1)
        }
        // Windows on the face towards the camera, a few of them lit.
        let rows = Int(h / 9)
        if rows > 0 {
            for r in 0..<min(rows, 6) {
                let on = sin(t * 0.6 + Float(seed % 13) + Float(r) * 1.7) > 0.1
                guard on else { continue }
                let p = base + Vec3(Float((seed + r) % 3 - 1) * half.x * 0.5, Float(r) * 9 + 6, half.z)
                world.dot(p, size: 3, color: lit, alpha: 0.6)
            }
        }
        if burning {
            drawFire(at: base + top, size: rig.height * 0.45, seed: seed)
        }
        if beacon {
            let blink = pow(max(0, sin(t * 2.4 + Float(seed))), 8)
            world.dot(base + top + Vec3(0, 8, 0), size: 6, color: lit, alpha: 0.4 + 0.6 * blink)
            world.line(base + top, base + top + Vec3(0, 8, 0), color: accentColor, alpha: 0.6, width: 1)
        }
    }

    // MARK: Spires

    /// A forest of needles, beacons blinking on their tips.
    private func drawSpires(eye: Vec3) {
        let h = rig.height
        let lit = StoryPalette.mix(palette.highlight, StoryPalette.red, alert * 0.5)
        anchors(eye: eye, gap: 75, near: 120, far: 950) { k in
            var rng = StoryRandom(seed: 0x5B1E &+ UInt64(bitPattern: Int64(k)))
            let count = 2 + Int(rng.unit() * 1.8)
            for _ in 0..<count {
                let side: Float = rng.unit() > 0.5 ? 1 : -1
                let x = side * rng.float((0.25 * h)...(2.4 * h))
                let z = Float(k) * 75 + rng.float(-25...25)
                let base = Vec3(x, ground(x, z), z)
                let height = rng.float((0.3 * h)...(0.78 * h))
                let r = height * rng.float(0.08...0.13)
                let turn = rng.float(0...(2 * .pi))
                let tip = base + Vec3(0, height, 0)
                let foot = (0..<3).map { i -> Vec3 in
                    let a = turn + Float(i) * 2 * .pi / 3
                    return Vec3(cos(a) * r, 0, sin(a) * r)
                }
                for corner in foot { world.line(base + corner, tip, color: accentColor, alpha: 0.75, width: 1.2) }
                world.polyline(foot.map { base + $0 }, closed: true, color: accentColor, alpha: 0.4, width: 1)
                for f: Float in [0.3, 0.6] {
                    world.polyline(foot.map { base + $0 * (1 - f) + Vec3(0, height * f, 0) }, closed: true,
                                   color: gridColor, alpha: 0.5, width: 1)
                }
                let blink = pow(max(0, sin(t * 1.8 + Float(k) * 1.3 + x * 0.01)), 6)
                world.dot(tip, size: 5, color: lit, alpha: 0.3 + 0.7 * blink)
            }
        }
    }

    // MARK: Pylons

    /// Pylons in pairs either side of the route, power lines strung between them
    /// and arcs jumping the gap.
    private func drawPylons(eye: Vec3) {
        let h = rig.height
        let gap: Float = 230
        let offset = 1.15 * h + 14
        let arcColor = StoryPalette.mix(palette.highlight, StoryPalette.ice, 0.5)
        var previous: [Vec3]?
        anchors(eye: eye, gap: gap, near: 120, far: 1000) { k in
            let z = Float(k) * gap
            let tops = [Float(-1), 1].map { side -> Vec3 in
                let x = side * offset
                return drawPylon(at: Vec3(x, ground(x, z), z), side: side, height: 0.78 * h)
            }
            if let previous {
                for i in 0..<2 {
                    let a = previous[i], b = tops[i]
                    let wire = (0...6).map { s -> Vec3 in
                        let f = Float(s) / 6
                        return lerp(a, b, f) - Vec3(0, 0.16 * h * 4 * f * (1 - f), 0)
                    }
                    world.polyline(wire, color: gridColor, alpha: 0.4, width: 1)
                }
            }
            let phase = (t * 0.42 + Self.hash(k, 0, 0x9A7)).truncatingRemainder(dividingBy: 1)
            if phase < 0.22 {
                StoryScenery.lightning(world, from: tops[0], to: tops[1], t: t, seed: 0xA2C &+ UInt64(bitPattern: Int64(k)),
                                       jitter: h * 0.18, color: arcColor, alpha: 0.9)
                for top in tops { world.glow(top, radius: 0.22 * h, color: arcColor, alpha: 0.5) }
            } else {
                for top in tops { world.dot(top, size: 4, color: arcColor, alpha: 0.6) }
            }
            previous = tops
        }
    }

    /// One lattice pylon; returns where its arm ends, over the route.
    private func drawPylon(at base: Vec3, side: Float, height: Float) -> Vec3 {
        let foot = height * 0.12, head = height * 0.04
        func square(_ f: Float) -> [Vec3] {
            let s = foot + (head - foot) * f
            let y = height * f
            return [Vec3(-s, y, -s), Vec3(s, y, -s), Vec3(s, y, s), Vec3(-s, y, s)].map { base + $0 }
        }
        let bottom = square(0), top = square(1)
        for i in 0..<4 { world.line(bottom[i], top[i], color: accentColor, alpha: 0.7, width: 1.2) }
        for f: Float in [0.35, 0.7, 1] {
            world.polyline(square(f), closed: true, color: accentColor, alpha: 0.5, width: 1)
        }
        let crown = base + Vec3(0, height, 0)
        let arm = crown + Vec3(-side * height * 0.3, 0, 0)
        world.line(crown + Vec3(side * height * 0.12, 0, 0), arm, color: accentColor, alpha: 0.7, width: 1.2)
        return arm
    }

    // MARK: Arches

    /// Gates spanning the route, lights chasing along their beams.
    private func drawArches(eye: Vec3) {
        let h = rig.height
        let gap: Float = 300
        let span = 1.15 * h + 16
        let height = 0.62 * h
        let w = 0.06 * h
        let lit = StoryPalette.mix(palette.highlight, StoryPalette.red, alert * 0.6)
        anchors(eye: eye, gap: gap, near: 120, far: 950) { k in
            let z = Float(k) * gap
            let cx = stage.ground == .canyon ? canyonCentre(z) : 0
            let xs = [cx - span, cx + span]
            let topY = max(ground(xs[0], z), ground(xs[1], z)) + height
            for x in xs {
                let gy = ground(x, z)
                let corners = [Vec3(-w, 0, -w), Vec3(w, 0, -w), Vec3(w, 0, w), Vec3(-w, 0, w)]
                for c in corners {
                    world.line(Vec3(x + c.x, gy, z + c.z), Vec3(x + c.x, topY, z + c.z), color: accentColor, alpha: 0.7, width: 1.3)
                }
                world.polyline(corners.map { Vec3(x + $0.x, topY, z + $0.z) }, closed: true, color: accentColor, alpha: 0.6, width: 1)
            }
            // The beam: two chords and the bracing between them.
            let left = xs[0] - w, right = xs[1] + w
            let upper = topY + w * 1.4
            world.line(Vec3(left, topY, z), Vec3(right, topY, z), color: accentColor, alpha: 0.9, width: 1.4)
            world.line(Vec3(left, upper, z), Vec3(right, upper, z), color: accentColor, alpha: 0.7, width: 1.2)
            let braces = 8
            for b in 0..<braces {
                let x0 = left + (right - left) * Float(b) / Float(braces)
                let x1 = left + (right - left) * Float(b + 1) / Float(braces)
                world.line(Vec3(x0, b % 2 == 0 ? topY : upper, z), Vec3(x1, b % 2 == 0 ? upper : topY, z),
                           color: gridColor, alpha: 0.45, width: 1)
            }
            // Chasing lights, and the shimmer of a field strung between the pillars.
            let lights = 9
            for j in 0..<lights {
                let chase = (Float(j) - t * 7 + Float(k) * 3).truncatingRemainder(dividingBy: Float(lights))
                let on = (chase < 0 ? chase + Float(lights) : chase) < 1.6
                let p = Vec3(left + (right - left) * (Float(j) + 0.5) / Float(lights), topY - 1, z)
                world.dot(p, size: on ? 5 : 3, color: lit, alpha: on ? 0.95 : 0.25)
            }
            for f: Float in [0.25, 0.5, 0.75] {
                let shimmer = 0.5 + 0.5 * sin(t * 5 + f * 9 + Float(k))
                let y = ground(cx, z) + height * f
                world.line(Vec3(xs[0] + w, y, z), Vec3(xs[1] - w, y, z), color: palette.highlight, alpha: 0.12 + 0.18 * shimmer, width: 1)
            }
        }
    }

    // MARK: Wrecks

    /// Ships of a lost fleet, broken in two and half buried.
    private func drawWrecks(eye: Vec3) {
        let h = rig.height
        let gap: Float = 360
        let hull = StoryPalette.mix(accentColor, StoryPalette.ice, 0.35)
        anchors(eye: eye, gap: gap, near: 400, far: 1100) { k in
            var rng = StoryRandom(seed: 0x3EC_0000 &+ UInt64(bitPattern: Int64(k)))
            guard rng.unit() < 0.85 else { return }
            let side: Float = k % 2 == 0 ? 1 : -1
            let x = side * rng.float((0.3 * h)...(1.3 * h))
            let z = Float(k) * gap + rng.float(-60...60)
            let scale = h * rng.float(0.045...0.065)
            let q = rotation(yaw: rng.float(-0.8...0.8) + side * 0.4, pitch: rng.float(-0.12...0.02), roll: rng.float(-0.6...0.6))
            let gy = ground(x, z)
            let centre = Vec3(x, gy + scale * 1.5, z)
            let breakAt = rng.float(-6...4)
            let rearQ = q * rotation(rng.float(0.25...0.5) * (rng.unit() > 0.5 ? 1 : -1), Vec3(0, 1, 0))
            let rearCentre = centre + q.act(Vec3(0, -scale, scale * 9))
            func buried(_ rot: simd_quatf, _ at: Vec3, _ a: Vec3, _ b: Vec3) -> Float {
                let ya = at.y + rot.act(a * scale).y, yb = at.y + rot.act(b * scale).y
                return smooth(gy - scale * 2, gy + scale * 0.5, min(ya, yb))
            }
            world.mesh(WireMesh.ship, at: centre, rotation: q, scale: scale, color: hull, alpha: 0.75, width: 1.2,
                       backAlpha: 0.5) { a, b in
                max(a.z, b.z) < breakAt ? buried(q, centre, a, b) : 0
            }
            world.mesh(WireMesh.ship, at: rearCentre, rotation: rearQ, scale: scale, color: hull, alpha: 0.75, width: 1.2,
                       backAlpha: 0.5) { a, b in
                min(a.z, b.z) > breakAt + 2 ? buried(rearQ, rearCentre, a, b) : 0
            }
            // Still burning inside.
            for f in 0..<3 {
                let p = centre + q.act(Vec3(rng.float(-5...5), 2, rng.float(-14...10)) * scale)
                let flicker = 0.6 + 0.4 * sin(t * 9 + Float(f) * 2.3 + Float(k))
                world.glow(p, radius: scale * 4, color: StoryPalette.ember, alpha: 0.3 * flicker)
                world.dot(p, size: 4, color: StoryPalette.gold, alpha: 0.8 * flicker)
            }
        }
    }

    // MARK: Craters

    private func drawCraters(eye: Vec3) {
        let h = rig.height
        let rim = StoryPalette.mix(accentColor, palette.highlight, 0.3)
        anchors(eye: eye, gap: 110, near: 80, far: 950) { k in
            var rng = StoryRandom(seed: 0xC2A7 &+ UInt64(bitPattern: Int64(k)))
            guard rng.unit() < 0.7 else { return }
            let x = rng.float((-2.4 * h)...(2.4 * h))
            let z = Float(k) * 110 + rng.float(-30...30)
            let r = rng.float((0.25 * h)...(0.8 * h))
            let gy = ground(x, z)
            groundRing(Vec3(x, gy + 0.06 * r, z), radius: r, segments: 20, color: rim, alpha: 0.6)
            groundRing(Vec3(x, gy - 0.1 * r, z), radius: r * 0.55, segments: 14, color: gridColor, alpha: 0.35)
            let smoulder = 0.7 + 0.3 * sin(t * 2 + Float(k))
            world.glow(Vec3(x, gy, z), radius: r * 0.9, color: StoryPalette.ember, alpha: 0.18 * smoulder, fogged: true)
        }
    }

    // MARK: Crystals

    private static let crystalMesh: WireMesh = {
        var mesh = WireMesh.octahedron(radius: 1)
        mesh.vertices = mesh.vertices.map { Vec3($0.x * 0.36, $0.y, $0.z * 0.36) }
        return mesh
    }()

    /// Clusters of crystal growing out of the ground.
    private func drawCrystals(eye: Vec3) {
        let h = rig.height
        let color = StoryPalette.mix(palette.highlight, StoryPalette.violet, 0.35)
        anchors(eye: eye, gap: 140, near: 100, far: 950) { k in
            var rng = StoryRandom(seed: 0xC4157 &+ UInt64(bitPattern: Int64(k)))
            guard rng.unit() < 0.75 else { return }
            let side: Float = rng.unit() > 0.5 ? 1 : -1
            let x = side * rng.float((0.25 * h)...(2.4 * h))
            let z = Float(k) * 140 + rng.float(-40...40)
            let base = Vec3(x, ground(x, z), z)
            for _ in 0..<3 {
                let size = rng.float((0.1 * h)...(0.26 * h))
                let axis = simd_normalize(Vec3(rng.float(-1...1), 0.01, rng.float(-1...1)))
                let q = rotation(rng.float(-0.55...0.55), axis) * rotation(t * 0.25 + rng.float(0...6), Vec3(0, 1, 0))
                let p = base + Vec3(rng.float(-0.12...0.12) * h, size * 0.55, rng.float(-0.12...0.12) * h)
                world.mesh(Self.crystalMesh, at: p, rotation: q, scale: size, color: color, alpha: 0.8, width: 1.2, backAlpha: 0.45)
            }
            world.glow(base + Vec3(0, 0.08 * h, 0), radius: 0.35 * h, color: palette.highlight, alpha: 0.22, fogged: true)
        }
    }

    // MARK: Vents

    /// Fires burning out of the ground, embers rising off them.
    private func drawVents(eye: Vec3) {
        let h = rig.height
        anchors(eye: eye, gap: 120, near: 80, far: 900) { k in
            var rng = StoryRandom(seed: 0x7E47 &+ UInt64(bitPattern: Int64(k)))
            guard rng.unit() < 0.6 else { return }
            let x = rng.float((-1.6 * h)...(1.6 * h))
            let z = Float(k) * 120 + rng.float(-30...30)
            drawFire(at: Vec3(x, ground(x, z), z), size: h, seed: k)
        }
    }

    private static let emberColors = (0..<4).map { StoryPalette.mix(StoryPalette.gold, StoryPalette.ember, Float($0) / 3) }

    /// Flames licking up off a point, embers rising most of `size` above it.
    private func drawFire(at base: Vec3, size h: Float, seed: Int) {
        let flicker = 0.7 + 0.3 * sin(t * 11 + Float(seed) * 1.7)
        world.glow(base, radius: 0.32 * h, color: StoryPalette.ember, alpha: 0.4 * flicker, fogged: true)
        world.glow(base, radius: 0.1 * h, color: StoryPalette.sun, alpha: 0.6 * flicker, fogged: true)
        for f in 0..<5 {
            let lick = 0.16 * h * (1 + 0.6 * sin(t * 13 + Float(f) * 2.1 + Float(seed)))
            let lean = Vec3(sin(t * 3 + Float(f)) * 0.04 * h, lick, 0)
            let foot = base + Vec3(Float(f - 2) * 0.035 * h, 0, Float(f % 2) * 0.03 * h)
            world.line(foot, foot + lean * 0.5, color: StoryPalette.gold, alpha: 0.85, width: 1.6)
            world.line(foot + lean * 0.5, foot + lean, color: StoryPalette.ember, alpha: 0.5, width: 1.2)
        }
        let phase = Self.hash(seed, 3, 0xF14E)
        for j in 0..<12 {
            let u = (t * 0.35 + Float(j) / 12 + phase).truncatingRemainder(dividingBy: 1)
            let drift = sin(u * 6 + Float(j)) * 0.1 * h
            let p = base + Vec3(drift, u * 0.9 * h, drift * 0.5)
            world.dot(p, size: 2 + 4 * (1 - u), color: Self.emberColors[min(3, Int(u * 4))], alpha: 0.9 * (1 - u))
        }
    }

    // MARK: Searchlights

    /// Lamps on masts either side of the route, their beams sweeping the floor.
    private func drawSearchlights(eye: Vec3) {
        let h = rig.height
        let gap: Float = 240
        let color = StoryPalette.mix(StoryPalette.mix(StoryPalette.ice, accentColor, 0.25), StoryPalette.red, alert * 0.6)
        let canyon = stage.ground == .canyon
        anchors(eye: eye, gap: gap, near: 150, far: 950) { k in
            let side: Float = k % 2 == 0 ? 1 : -1
            let z = Float(k) * gap
            let cx = canyon ? canyonCentre(z) : 0
            let x = cx + side * (canyon ? canyonHalfWidth + 0.55 * h : 1.3 * h + 18)
            let gy = ground(x, z)
            let lamp = Vec3(x, gy + 0.5 * h, z)
            world.line(Vec3(x, gy, z), lamp, color: accentColor, alpha: 0.6, width: 1.2)
            let phase = Self.hash(k, 1, 0x5EA4) * 6
            let tx = cx + 1.1 * h * sin(t * 0.55 + phase)
            let tz = z - 0.25 * h + 0.4 * h * sin(t * 0.37 + phase * 1.7)
            let target = Vec3(tx, ground(tx, tz) + 0.4, tz)
            let spot = 0.26 * h
            let flat = Vec3(target.x - lamp.x, 0, target.z - lamp.z)
            let dir = simd_length_squared(flat) > 1e-4 ? simd_normalize(flat) : Vec3(1, 0, 0)
            let across = Vec3(-dir.z, 0, dir.x) * spot
            world.line(lamp, target + across, color: color, alpha: 0.3, width: 1.1)
            world.line(lamp, target - across, color: color, alpha: 0.3, width: 1.1)
            world.line(lamp, target, color: color, alpha: 0.1, width: 2.6)
            groundRing(target, radius: spot, segments: 14, color: color, alpha: 0.6)
            world.glow(target, radius: spot * 1.4, color: color, alpha: 0.2, fogged: true)
            world.glow(lamp, radius: 0.1 * h, color: StoryPalette.white, alpha: 0.5)
        }
    }

    // MARK: Runners

    /// Light racing along the grid lines, some away up the route, some down it, a
    /// few across.
    private func drawRunners(eye: Vec3, spacing g: Float) {
        let depth: Float = 1040
        // Columns the ship actually flies over, not ones only seen at the horizon.
        let lanes = Float(max(2, Int(2.4 * rig.height / g)))
        for j in 0..<14 {
            var rng = StoryRandom(seed: 0x2B4E &+ UInt64(j))
            let acrossRows = rng.unit() < 0.3
            let speed = rng.float(0.8...1.7) * rig.cruise * (rng.unit() < 0.5 ? -1 : 1)
            let length = g * rng.float(1.2...2.2)
            let color = j % 4 == 0 ? accentColor : palette.highlight
            let start = rng.float(0...depth)
            var trail: [Vec3] = []
            if !acrossRows {
                // Along a column, anchored in the world.
                let x = Float(Int(rng.float(-lanes...lanes))) * g
                var d = (-travelled - start - speed * t + 40).truncatingRemainder(dividingBy: depth)
                if d < 0 { d += depth }
                let head = eye.z - (d - 40)
                let back: Float = speed > 0 ? -1 : 1
                trail = (0...4).map { s -> Vec3 in
                    let z = head + back * length * Float(s) / 4
                    return Vec3(x, ground(x, z) + 0.6, z)
                }
            } else {
                // Across a row, which streams with the ground like everything else.
                var d = (-travelled - start).truncatingRemainder(dividingBy: depth)
                if d < 0 { d += depth }
                let z = ((eye.z - d) / g).rounded() * g
                var x = (start * 3 + speed * t).truncatingRemainder(dividingBy: 1000)
                if x < 0 { x += 1000 }
                let head = eye.x + x - 500
                let back: Float = speed > 0 ? -1 : 1
                trail = (0...4).map { s -> Vec3 in
                    let xs = head + back * length * Float(s) / 4
                    return Vec3(xs, ground(xs, z) + 0.6, z)
                }
            }
            for s in 0..<4 {
                world.line(trail[s], trail[s + 1], color: color, alpha: 1 - Float(s) / 4.5, width: 2.3 - Float(s) * 0.3)
            }
            world.glow(trail[0], radius: g * 0.18, color: color, alpha: 0.55)
            world.dot(trail[0], size: 5, color: StoryPalette.white, alpha: 0.9)
        }
    }

    // MARK: Convoy

    /// A silhouette of the player's ship light enough to fly a formation of in the
    /// background: the outline and a keel, a fifth of the full hull's edges.
    private static let convoyMesh: WireMesh = {
        let outline = WireMesh.shipOutline2D
        var vertices = outline.map { Vec3($0.x, 1, -$0.y) }
        var edges = (0..<outline.count).map { ($0, ($0 + 1) % outline.count) }
        vertices.append(Vec3(0, -2.4, -2))
        let keel = vertices.count - 1
        // Nose, wing tips and tail down to the keel.
        edges += [(keel, 0), (keel, 3), (keel, 15), (keel, 9)]
        return WireMesh(vertices: vertices, edges: edges)
    }()

    /// Every so often a formation overtakes the ship below it and pulls away up the route.
    private func drawConvoy(eye: Vec3) {
        let h = rig.height
        let period: Float = 15
        let shifted = t + 4
        let cycle = (shifted / period).rounded(.down)
        let u = (shifted - cycle * period) / 7.5
        guard u < 1 else { return }
        let depth = -60 + 1150 * pow(u, 1.3)
        let fade = smooth(-20, 110, depth) * (1 - smooth(800, 1080, depth))
        guard fade > 0.01 else { return }
        let side: Float = Int(cycle) % 2 == 0 ? 1 : -1
        let scale = h / 38
        let lead = Vec3(side * 0.6 * h, 0.34 * h, eye.z - depth)
        let formation: [Vec3] = [Vec3(0, 0, 0), Vec3(-1, 0.1, 1), Vec3(1, 0.1, 1), Vec3(-2, 0.2, 2), Vec3(2, -0.1, 2)]
        let hull = StoryPalette.mix(palette.highlight, StoryPalette.ice, 0.5)
        for (n, slot) in formation.enumerated() {
            let p = lead + Vec3(slot.x * 16 * scale, slot.y * h, slot.z * 26 * scale)
            let bank = rotation(sin(t * 0.8 + Float(n)) * 0.12, Vec3(0, 0, 1))
            world.mesh(Self.convoyMesh, at: p, rotation: bank, scale: scale, color: hull, alpha: 0.75 * fade, width: 1.3)
            for nozzle in WireMesh.shipNozzles {
                let flame = p + bank.act(nozzle * scale)
                world.glow(flame, radius: 4 * scale, color: StoryPalette.cyan, alpha: 0.7 * fade)
                world.line(flame, flame + Vec3(0, 0, 9 * scale), color: StoryPalette.blue, alpha: 0.5 * fade, width: 1.1)
            }
        }
    }

    // MARK: Meteors and lightning

    private func drawMeteors() {
        let h = rig.height
        for meteor in meteors {
            if meteor.age < meteor.duration {
                let e = easeIn(meteor.age / meteor.duration)
                let head = lerp(meteor.from, meteor.to, e)
                let back = simd_normalize(meteor.from - meteor.to)
                let length = h * (1.2 + 2.2 * e)
                for s in 0..<4 {
                    let a = head + back * length * Float(s) / 4
                    let b = head + back * length * Float(s + 1) / 4
                    world.line(a, b, color: s == 0 ? StoryPalette.sun : StoryPalette.ember,
                               alpha: 0.95 * (1 - Float(s) / 4), width: 2.4 - Float(s) * 0.35)
                }
                world.glow(head, radius: h * 0.16, color: StoryPalette.sun, alpha: 0.8)
                world.glow(head, radius: h * 0.05, color: StoryPalette.white, alpha: 0.9)
            } else {
                let a = meteor.age - meteor.duration
                let e = easeOut(min(1, a / 1.1))
                let fadeOut = 1 - smooth(0.2, 1.3, a)
                groundRing(meteor.to, radius: h * (0.2 + 2 * e), segments: 24, color: palette.highlight, alpha: 0.9 * fadeOut, width: 1.6)
                groundRing(meteor.to, radius: h * (0.1 + 1.2 * e), segments: 18, color: StoryPalette.ember, alpha: 0.65 * fadeOut)
                world.glow(meteor.to, radius: h * 0.8 * (1 - 0.5 * e), color: StoryPalette.sun, alpha: 0.95 * (1 - smooth(0, 0.45, a)))
                var rng = StoryRandom(seed: meteor.seed)
                for _ in 0..<6 {
                    let angle = rng.float(0...(2 * .pi))
                    let v = Vec3(cos(angle), rng.float(0.5...1.3), sin(angle))
                    let p = meteor.to + v * h * 0.9 * e - Vec3(0, h * 0.7 * e * e, 0)
                    world.line(p, p - v * h * 0.12, color: StoryPalette.gold, alpha: 0.8 * (1 - e), width: 1.1)
                }
            }
        }
    }

    private func drawBolts() {
        let h = rig.height
        for bolt in bolts {
            if bolt.age < bolt.duration {
                let flicker: Float = Int(bolt.age / 0.05) % 2 == 0 ? 1 : 0.55
                StoryScenery.lightning(world, from: bolt.from, to: bolt.to, t: t, seed: bolt.seed,
                                       jitter: h * 0.6, color: stormColor, alpha: flicker)
                var rng = StoryRandom(seed: bolt.seed &+ 1)
                let fork = lerp(bolt.from, bolt.to, 0.45)
                let end = fork + Vec3(rng.float(-1.4...1.4) * h, -rng.float(1.5...2.5) * h, rng.float(-0.6...0.6) * h)
                StoryScenery.lightning(world, from: fork, to: end, t: t, seed: bolt.seed &+ 2,
                                       jitter: h * 0.35, color: stormColor, alpha: flicker * 0.6)
                world.glow(bolt.to, radius: h * 0.9, color: stormColor, alpha: 0.6 * flicker)
            } else {
                let a = bolt.age - bolt.duration
                let e = easeOut(min(1, a / 0.8))
                groundRing(bolt.to, radius: h * (0.2 + 1.1 * e), segments: 18, color: stormColor, alpha: 0.7 * (1 - e))
            }
        }
    }

    // MARK: Rift

    private func tunnelCentre(_ s: Float) -> Vec3 {
        Vec3(58 * sin(s * 0.0041), 30 * sin(s * 0.0029 + 1.2), -s)
    }

    private func drawRift(eye: Vec3) {
        let spacing: Float = 34
        let radius: Float = 118 * stage.radius
        let sides = max(3, stage.sides)
        let s0 = travelled
        let helix = stage.has(.helix)
        var previous: [Vec3] = []
        var strands: [[Vec3]] = helix ? Array(repeating: [], count: sides) : []
        var k = Int(((s0 - 60) / spacing).rounded(.down))
        let last = Int(((s0 + 820) / spacing).rounded(.up))
        let strut = StoryPalette.mix(StoryPalette.blue, gridColor, 0.3)
        let alarm = alert > 0.02 ? Int((t * 1.6).rounded(.down)) : Int.min
        // A ring of light racing down the tunnel at the ship.
        let pulseAt: Float? = stage.has(.pulses) ? s0 + 900 - (t * 640).truncatingRemainder(dividingBy: 1280) : nil
        while k <= last {
            let s = Float(k) * spacing
            let centre = tunnelCentre(s)
            let twist = (Float(k) * 0.13 + t * 0.25) * stage.twist
            let ring = (0..<sides).map { i -> Vec3 in
                let a = Float(i) / Float(sides) * 2 * .pi + twist
                return centre + Vec3(cos(a) * radius, sin(a) * radius, 0)
            }
            let gold = k % 6 == 0
            let alarmed = alarm != Int.min && (k - alarm * 3) % 9 == 0
            let pulsed = pulseAt.map { abs(s - $0) < spacing * 0.75 } ?? false
            let color = alarmed ? StoryPalette.red
                : (pulsed || gold ? palette.highlight : (k % 2 == 0 ? gridColor : accentColor))
            let bright = gold || alarmed || pulsed
            let breached = stage.has(.breaches) && Self.hash(k, 0, 0xB4EA) < 0.2

            if !helix || k % 3 == 0 || bright {
                let alpha: Float = pulsed ? 1 : (bright ? 0.95 : 0.6)
                let width: Float = pulsed ? 2.4 : (gold ? 1.9 : 1.3)
                if breached {
                    drawBreachedRing(ring, k: k, color: color, alpha: alpha, width: width)
                } else {
                    world.polyline(ring, closed: true, color: color, alpha: alpha, width: width)
                }
            }
            if helix {
                for i in 0..<sides {
                    let a = Float(i) / Float(sides) * 2 * .pi + Float(k) * 0.24 + t * 0.4 * stage.twist
                    strands[i].append(centre + Vec3(cos(a) * radius, sin(a) * radius, 0))
                }
            } else if previous.count == sides {
                for i in 0..<sides { world.line(previous[i], ring[i], color: strut, alpha: 0.3, width: 1) }
            }
            if stage.has(.irises) && k % 9 == 4 {
                drawIris(ring, centre: centre, radius: radius, ahead: s - s0)
            }
            previous = ring
            k += 1
        }
        for strand in strands {
            world.polyline(strand, color: strut, alpha: 0.6, width: 1.3)
        }
        // Energy loose in the tunnel, strung along its axis.
        for j in 0..<10 {
            var rng = StoryRandom(seed: 0xE1E0 &+ UInt64(j))
            let period: Float = 880
            let s = s0 - 40 + period - (rng.float(0...period) + s0).truncatingRemainder(dividingBy: period)
            let p = tunnelCentre(s) + Vec3(rng.float(-70...70), rng.float(-60...60), 0) * stage.radius
            world.dot(p, size: 5, color: palette.highlight, alpha: 0.55)
        }
        if stage.has(.oncoming) { drawOncoming(s0: s0, radius: radius) }
    }

    /// A ring with sections of wall torn out: sparks at the edges of the gaps, and
    /// now and then an arc jumping across the tunnel.
    private func drawBreachedRing(_ ring: [Vec3], k: Int, color: UIColor, alpha: Float, width: Float) {
        let n = ring.count
        let forced = abs(k) % n
        for i in 0..<n {
            let missing = i == forced || Self.hash(k, i, 0xB4EB) < 0.3
            if !missing {
                world.line(ring[i], ring[(i + 1) % n], color: color, alpha: alpha, width: width)
                continue
            }
            var rng = StoryRandom(seed: 0x5A4C &+ UInt64(bitPattern: Int64(k &* 31 &+ i)) &+ UInt64(max(0, t / 0.08)))
            for end in [ring[i], ring[(i + 1) % n]] {
                for _ in 0..<2 {
                    world.dot(end + rng.direction() * rng.float(2...10), size: 3, color: StoryPalette.sun, alpha: 0.8)
                }
            }
        }
        if sin(t * 3.1 + Float(k) * 1.7) > 0.5 {
            StoryScenery.lightning(world, from: ring[forced], to: ring[(forced + n / 2) % n], t: t,
                                   seed: 0xA4C &+ UInt64(bitPattern: Int64(k)), jitter: 26, color: stormColor, alpha: 0.85)
        }
    }

    /// A shutter across the tunnel: closed far ahead, opening as the ship comes up on it.
    private func drawIris(_ ring: [Vec3], centre: Vec3, radius: Float, ahead: Float) {
        let open = 1 - smooth(180, 560, ahead)
        let inner = radius * (0.1 + 0.9 * open)
        guard open < 0.97 else { return }
        let n = ring.count
        let tips = (0..<n).map { i -> Vec3 in
            let d = ring[i] - centre
            let a = atan2(d.y, d.x) + 0.9
            return centre + Vec3(cos(a) * inner, sin(a) * inner, 0)
        }
        let a = 0.8 * (1 - open * 0.6)
        for i in 0..<n {
            world.line(ring[i], tips[i], color: accentColor, alpha: a, width: 1.4)
        }
        world.polyline(tips, closed: true, color: palette.highlight, alpha: a, width: 1.3)
        world.glow(centre, radius: inner * 0.9, color: palette.highlight, alpha: 0.35 * (1 - open))
    }

    /// Wreckage flying back down the tunnel past the ship.
    private func drawOncoming(s0: Float, radius: Float) {
        let color = StoryPalette.mix(accentColor, StoryPalette.ice, 0.4)
        for j in 0..<9 {
            var rng = StoryRandom(seed: 0x0C0E &+ UInt64(j))
            let period: Float = 900
            let ahead = period - 40 - (t * 380 + rng.float(0...period)).truncatingRemainder(dividingBy: period)
            let s = s0 + ahead
            let angle = rng.float(0...(2 * .pi))
            let r = radius * 0.55 * rng.unit().squareRoot()
            let p = tunnelCentre(s) + Vec3(cos(angle) * r, sin(angle) * r, 0)
            let spin = rotation(t * rng.float(0.8...2) + rng.float(0...6), rng.direction())
            world.mesh(Self.debrisMeshes[j % 3], at: p, rotation: spin, scale: rng.float(1.4...2.4), color: color,
                       alpha: 0.75 * smooth(-30, 40, ahead), width: 1.2, backAlpha: 0.35)
        }
    }

    // MARK: Quantum

    private func drawQuantum(eye: Vec3) {
        let cycle = (t / 3.4).rounded(.down)
        let local = t - cycle * 3.4
        let stutter = t > 2 && local < 0.3
        let clock = stutter ? cycle * 3.4 - local * 2.2 : t
        if stutter {
            world.settings.offset = CGPoint(x: shake.x + CGFloat(sin(t * 90) * 5), y: shake.y)
            world.applyOffset()
        }

        if stage.has(.tiltedGrids) {
            // Two grids of other spaces, at different depths and turning against each other.
            tiltedGrid(eye: eye, y: -220, spacing: 50, roll: 0.34 * sin(clock * 0.08),
                       color: gridColor, alpha: 0.46)
            tiltedGrid(eye: eye, y: -420, spacing: 74, roll: -0.42 * sin(clock * 0.06 + 1),
                       color: StoryPalette.mix(accentColor, gridColor, 0.25), alpha: 0.34)
        }
        if stage.has(.walls) { drawWalls(eye: eye, clock: clock) }
        if stage.has(.fold) { drawFold(eye: eye, clock: clock) }
        if stage.has(.lattice) { drawLattice(eye: eye, clock: clock) }
        if stage.has(.shards) { drawShards(eye: eye, clock: clock) }

        if stage.has(.tesseracts) {
            // Tesseracts adrift between them.
            anchors(eye: eye, gap: 280, near: -60, far: 1100) { k in
                var rng = StoryRandom(seed: 0x7E55 &+ UInt64(bitPattern: Int64(k)))
                let p = Vec3(rng.float(-330...330), rng.float(-200 ... -70), Float(k) * 280 + rng.float(-60...60))
                let spin = rotation(yaw: clock * 0.2 + rng.float(0...6), pitch: 0.35 + rng.float(-0.3...0.3))
                StoryOpening.tesseract(world, time: clock * 0.9 + rng.float(0...10), at: p,
                                       scale: rng.float(20...34), spin: spin,
                                       split: stutter ? 7 : 1.2, alpha: 0.7)
            }
        }
        if stage.has(.relics) { drawRelics(eye: eye, clock: clock) }
        world.settings.offset = shake
        world.applyOffset()

        // Particles that are, and then are not.
        var rng = StoryRandom(seed: 0xB1_1EED)
        for _ in 0..<56 {
            let x = rng.float(-360...360), y = rng.float(-300 ... -40)
            let z0 = rng.float(0...900), f = rng.float(1.3...3.5), ph = rng.float(0...6.3)
            let z = eye.z + 60 - ((z0 + travelled).truncatingRemainder(dividingBy: 900))
            let blink = pow(max(0, sin(t * f + ph)), 6)
            world.dot(Vec3(x, y, z), size: 4, color: palette.highlight, alpha: blink * 0.8)
        }
    }

    /// A grid in a horizontal plane `y` deep, turned about the flight axis by `roll`.
    private func tiltedGrid(eye: Vec3, y: Float, spacing g: Float, roll: Float, color: UIColor, alpha: Float) {
        let c = cos(roll), s = sin(roll)
        let pivot = Vec3(eye.x, eye.y, 0)
        func turn(_ p: Vec3) -> Vec3 {
            let d = p - pivot
            return pivot + Vec3(d.x * c - d.y * s, d.x * s + d.y * c, d.z)
        }
        let near = eye.z + 200
        let end = eye.z - 1150
        let half: Float = 640
        var k = Int((near / g).rounded(.down))
        let last = Int((end / g).rounded(.up))
        while k >= last {
            let z = Float(k) * g
            world.line(turn(Vec3(eye.x - half, y, z)), turn(Vec3(eye.x + half, y, z)), color: color, alpha: alpha, width: 1.1)
            k -= 1
        }
        let first = Int(((eye.x - half) / g).rounded(.up))
        let lastColumn = Int(((eye.x + half) / g).rounded(.down))
        for i in first...lastColumn {
            let x = Float(i) * g
            world.line(turn(Vec3(x, y, near)), turn(Vec3(x, y, end)), color: color, alpha: alpha, width: 1.1)
        }
    }

    /// Two walls of another space either side of the drop, closing in towards its floor.
    private func drawWalls(eye: Vec3, clock: Float) {
        let g: Float = 70
        let near = eye.z + 200, end = eye.z - 1150
        let levels = stride(from: Float(-40), through: -530, by: -70).map { $0 }
        let colors = [gridColor, StoryPalette.mix(accentColor, gridColor, 0.3)]
        for (index, side) in [Float(-1), 1].enumerated() {
            // Leaning in towards the bottom, so the drop reads as a gorge between them.
            let lean = 0.12 + 0.1 * sin(clock * 0.09 + side * 0.6)
            func x(_ y: Float) -> Float { side * (190 + y * tan(lean)) }
            let color = colors[index]
            for y in levels {
                world.line(Vec3(x(y), y, near), Vec3(x(y), y, end), color: color, alpha: 0.42, width: 1.1)
            }
            var k = Int((near / g).rounded(.down))
            let last = Int((end / g).rounded(.up))
            let top = levels[0], bottom = levels[levels.count - 1]
            while k >= last {
                let z = Float(k) * g
                world.line(Vec3(x(top), top, z), Vec3(x(bottom), bottom, z), color: color, alpha: 0.32, width: 1)
                k -= 1
            }
        }
    }

    /// A grid rolling like cloth in a wind.
    private func drawFold(eye: Vec3, clock: Float) {
        let g: Float = 66
        let near = eye.z + 200, end = eye.z - 1150
        func height(_ x: Float, _ z: Float) -> Float {
            -280 + 75 * sin(x * 0.010 + clock * 0.8) * cos(z * 0.0042 + clock * 0.35)
        }
        let i0 = Int(((eye.x - 600) / g).rounded(.down)), i1 = Int(((eye.x + 600) / g).rounded(.up))
        let kNear = Int((near / g).rounded(.down)), kFar = Int((end / g).rounded(.up))
        let columnColor = StoryPalette.mix(accentColor, gridColor, 0.35)
        var points: [Vec3] = []
        for k in stride(from: kNear, through: kFar, by: -1) {
            let z = Float(k) * g
            points.removeAll(keepingCapacity: true)
            for i in i0...i1 { points.append(Vec3(Float(i) * g, height(Float(i) * g, z), z)) }
            world.polyline(points, color: gridColor, alpha: 0.42, width: 1.1)
        }
        for i in i0...i1 {
            let x = Float(i) * g
            points.removeAll(keepingCapacity: true)
            for k in stride(from: kNear, through: kFar, by: -1) { points.append(Vec3(x, height(x, Float(k) * g), Float(k) * g)) }
            world.polyline(points, color: columnColor, alpha: 0.32, width: 1)
        }
    }

    /// A lattice hanging in the drop, edges of it lighting up a beat at a time.
    private func drawLattice(eye: Vec3, clock: Float) {
        let g: Float = 120
        func node(_ i: Int, _ j: Int, _ k: Int) -> Vec3 { Vec3(Float(i) * g, -90 - Float(j) * g, Float(k) * g) }
        let beat = UInt64(max(0, clock / 0.6))
        let rung = StoryPalette.mix(accentColor, gridColor, 0.4)
        anchors(eye: eye, gap: g, near: 100, far: 1150) { k in
            for j in 0..<3 { world.line(node(-3, j, k), node(3, j, k), color: gridColor, alpha: 0.32, width: 1.1) }
            for i in -3...3 {
                world.line(node(i, 0, k), node(i, 2, k), color: rung, alpha: 0.2, width: 1)
                for j in 0..<3 { world.dot(node(i, j, k), size: 4.5, color: palette.highlight, alpha: 0.6) }
            }
            var rng = StoryRandom(seed: 0x1A77 &+ UInt64(bitPattern: Int64(k)) &* 31 &+ beat)
            for _ in 0..<3 {
                let i = Int(rng.float(-3...2.99).rounded(.down)), j = Int(rng.float(0...1.99))
                let a = node(i, j, k)
                let b: Vec3
                switch rng.next() % 3 {
                case 0: b = node(i + 1, j, k)
                case 1: b = node(i, j + 1, k)
                default: b = node(i, j, k - 1)
                }
                world.line(a, b, color: palette.highlight, alpha: 0.8, width: 1.5)
            }
        }
        let near = eye.z + 100, end = eye.z - 1150
        for i in -3...3 {
            for j in 0..<3 {
                world.line(Vec3(Float(i) * g, -90 - Float(j) * g, near), Vec3(Float(i) * g, -90 - Float(j) * g, end),
                           color: gridColor, alpha: 0.26, width: 1)
            }
        }
    }

    /// The grids broken into panes, drifting and turning.
    private func drawShards(eye: Vec3, clock: Float) {
        for layer in 0..<2 {
            let g: Float = layer == 0 ? 120 : 170
            let y0: Float = layer == 0 ? -230 : -430
            let color = layer == 0 ? gridColor : StoryPalette.mix(accentColor, gridColor, 0.25)
            let alpha: Float = layer == 0 ? 0.55 : 0.4
            anchors(eye: eye, gap: g, near: 150, far: 1150) { k in
                for i in -4...4 {
                    var rng = StoryRandom(seed: 0x54A2_D000 &+ UInt64(layer) &* 7_777
                                          &+ UInt64(bitPattern: Int64(k)) &* 131 &+ UInt64(bitPattern: Int64(i)))
                    guard rng.unit() < 0.55 else { continue }
                    let c = Vec3(Float(i) * g, y0 + 30 * sin(clock * 0.5 + rng.float(0...6)), Float(k) * g)
                    let axis = simd_normalize(rng.direction())
                    let q = rotation(0.5 * sin(clock * 0.3 + rng.float(0...6)), axis)
                    let h = g * 0.42
                    let corners = [Vec3(-h, 0, -h), Vec3(h, 0, -h), Vec3(h, 0, h), Vec3(-h, 0, h)].map { c + q.act($0) }
                    world.polyline(corners, closed: true, color: color, alpha: alpha, width: 1.1)
                    world.line(corners[0], corners[2], color: color, alpha: alpha * 0.4, width: 1)
                }
            }
        }
    }

    private static let cageMesh = WireMesh.box(Vec3(1, 1, 1))
    private static let sentinelMesh = WireMesh.ring(radius: 1, segments: 6, ticks: 6, tickLength: 0.55)

    /// Things adrift in the bleed: crystals, cages with something inside, sentinel rings.
    private func drawRelics(eye: Vec3, clock: Float) {
        anchors(eye: eye, gap: 230, near: -60, far: 1100) { k in
            var rng = StoryRandom(seed: 0x4E11C &+ UInt64(bitPattern: Int64(k)))
            let p = Vec3(rng.float(-330...330), rng.float(-210 ... -70), Float(k) * 230 + rng.float(-60...60))
            let spin = rotation(clock * rng.float(0.3...0.7) + rng.float(0...6), simd_normalize(rng.direction()))
            let scale = rng.float(16...26)
            switch rng.next() % 3 {
            case 0:
                world.mesh(Self.crystalMesh, at: p, rotation: spin, scale: scale * 1.4, color: palette.highlight,
                           alpha: 0.75, width: 1.3, backAlpha: 0.4)
                world.glow(p, radius: scale * 0.6, color: palette.highlight, alpha: 0.3)
            case 1:
                world.mesh(Self.cageMesh, at: p, rotation: spin, scale: scale * 0.6, color: accentColor,
                           alpha: 0.7, width: 1.3, backAlpha: 0.45)
                world.mesh(Self.crystalMesh, at: p, rotation: spin.inverse, scale: scale * 0.5, color: palette.highlight,
                           alpha: 0.8, width: 1.1)
            default:
                world.mesh(Self.sentinelMesh, at: p, rotation: spin, scale: scale, color: gridColor, alpha: 0.75, width: 1.3)
                world.mesh(Self.sentinelMesh, at: p, rotation: spin * rotation(.pi / 2, Vec3(1, 0, 0)), scale: scale * 0.7,
                           color: accentColor, alpha: 0.6, width: 1.1)
                world.glow(p, radius: scale * 0.3, color: StoryPalette.white, alpha: 0.4)
            }
        }
    }

    // MARK: Wells

    private struct Funnel {
        let centre: Vec3
        let radius: Float
        let depth: Float
        let spin: Float
    }

    private func funnels(near eye: Vec3) -> [Funnel] {
        let gap: Float = 400
        var result: [Funnel] = []
        var k = Int(((eye.z + 260) / gap).rounded(.down))
        let last = Int(((eye.z - 1100) / gap).rounded(.up))
        while k >= last {
            var rng = StoryRandom(seed: 0xF0_0E1 &+ UInt64(bitPattern: Int64(k)))
            let side: Float = k % 2 == 0 ? 1 : -1
            let x = side * rng.float(70...210)
            result.append(Funnel(centre: Vec3(x, 0, Float(k) * gap), radius: rng.float(170...220),
                                 depth: rng.float(80...120), spin: rng.float(0.4...0.8) * (rng.unit() > 0.5 ? 1 : -1)))
            k -= 1
        }
        return result
    }

    private func drawFunnel(_ well: Funnel, eye: Vec3) {
        let distance = eye.z - well.centre.z
        let detailed = distance < 650
        func height(_ r: Float) -> Float { -well.depth * pow(18 / (r + 8), 1.2) }
        func twist(_ r: Float) -> Float { t * well.spin * (24 / (r + 10)) }
        let radii: [Float] = detailed ? [9, 14, 22, 34, 52, 80, 120, 165, well.radius] : [14, 40, 90, well.radius]
        let segments = detailed ? 26 : 16
        for (i, r) in radii.enumerated() {
            let k = Float(i) / Float(radii.count - 1)
            let y = height(r)
            let points = (0...segments).map { s -> Vec3 in
                let a = Float(s) / Float(segments) * 2 * .pi + twist(r)
                return well.centre + Vec3(cos(a) * r, y, sin(a) * r)
            }
            world.polyline(points, color: StoryPalette.mix(accentColor, gridColor, k), alpha: 0.95 - 0.4 * k, width: 1.3)
        }
        let spokes = detailed ? 12 : 6
        for sIndex in 0..<spokes {
            let a0 = Float(sIndex) / Float(spokes) * 2 * .pi
            let points = radii.map { r -> Vec3 in
                let a = a0 + twist(r)
                return well.centre + Vec3(cos(a) * r, height(r), sin(a) * r)
            }
            world.polyline(points, color: gridColor, alpha: 0.55, width: 1.1)
        }
        let throat = well.centre + Vec3(0, height(8) - 4, 0)
        world.glow(throat, radius: 40, color: palette.horizon, alpha: 0.35)
        world.glow(throat, radius: 9, color: StoryPalette.white, alpha: 0.6)
        guard detailed else { return }
        for ring in 0..<2 {
            StoryScenery.dashedRing(world, center: throat, radius: 12 + Float(ring) * 5, u: Vec3(1, 0, 0), v: Vec3(0, 0.25, 1),
                                    phase: t * (2.6 - Float(ring) * 0.8) * (well.spin > 0 ? 1 : -1), dashes: 6 + ring, fill: 0.6,
                                    color: StoryPalette.mix(StoryPalette.sun, StoryPalette.ember, Float(ring)),
                                    alpha: 0.8, width: 1.4)
        }
        // Stars falling in, stretched as they go.
        for j in 0..<6 {
            var rng = StoryRandom(seed: 0x1F_A11 &+ UInt64(j))
            let r0 = rng.float(70...150), a0 = rng.float(0...(2 * .pi)), speed = rng.float(0.1...0.2)
            let u = (t * speed + rng.unit()).truncatingRemainder(dividingBy: 1)
            func position(_ u: Float) -> Vec3 {
                let r = 8 + r0 * pow(1 - u, 1.6)
                let a = a0 + 6 * pow(u, 1.5) * (well.spin > 0 ? 1 : -1) + twist(r)
                return well.centre + Vec3(cos(a) * r, height(r) + 2, sin(a) * r)
            }
            let fadeIn = smooth(0, 0.1, u) * (1 - smooth(0.85, 1, u))
            world.polyline((0..<4).map { position(max(0, u - Float($0) * 0.014)) },
                           color: StoryPalette.sun, alpha: fadeIn * 0.7, width: 1.1)
        }
    }

    /// The bottoms of the dips in a sagging grid: a light at each, a ring turning round it.
    private func drawSagThroats() {
        for well in sags {
            let bottom = well.centre + Vec3(0, ground(well.centre.x, well.centre.z), 0)
            world.glow(bottom, radius: 30, color: palette.horizon, alpha: 0.4)
            world.glow(bottom, radius: 8, color: StoryPalette.white, alpha: 0.6)
            StoryScenery.dashedRing(world, center: bottom + Vec3(0, 4, 0), radius: well.radius * 0.18, u: Vec3(1, 0, 0),
                                    v: Vec3(0, 0, 1), phase: t * well.spin * 2, dashes: 7, fill: 0.55,
                                    color: StoryPalette.sun, alpha: 0.7, width: 1.3)
        }
    }

    // MARK: Epicentre

    /// The dying universe pouring past towards the core.
    private func drawInflow(eye: Vec3) {
        var rng = StoryRandom(seed: 0xC0_4E)
        let depth: Float = 1000
        for _ in 0..<44 {
            let x = rng.float(-380...380), y = rng.float(6...70)
            let z0 = rng.float(0...depth), speed = rng.float(1.6...2.6)
            var z = (z0 - travelled * speed).truncatingRemainder(dividingBy: depth)
            if z > 0 { z -= depth }
            let p = Vec3(x, y, eye.z + 80 + z)
            world.line(p, p + Vec3(0, 0, -14 * speed), color: palette.highlight, alpha: 0.5, width: 1)
        }
    }

    // MARK: Shared world furniture

    /// Motes in the air between the camera and the ground: the nearest layer, and
    /// the one that sells speed.
    private func drawDust(eye: Vec3) {
        var rng = StoryRandom(seed: 0xD057)
        let depth: Float = 720
        let streak = rush * min(90, currentSpeed * 0.12)
        for _ in 0..<44 {
            let x = rng.float(-300...300)
            let y = rng.float(rig.dust)
            let z0 = rng.float(0...depth)
            let z = eye.z + 40 - (depth - (z0 + travelled).truncatingRemainder(dividingBy: depth))
            let p = Vec3(eye.x * 0.6 + x, y + (look.theme == .rift ? eye.y : 0), z)
            if streak > 2 {
                world.line(p, p + Vec3(0, 0, -streak), color: StoryPalette.sun, alpha: 0.5, width: 1)
            } else {
                world.dot(p, size: 3, color: StoryPalette.ice, alpha: 0.32)
            }
        }
    }

    /// Overdrive: streaks of light rushing at the camera.
    private func drawWarp(eye: Vec3) {
        var rng = StoryRandom(seed: 0x3A_49)
        let depth: Float = 900
        let length = min(200, currentSpeed * 0.16)
        for _ in 0..<64 {
            let x = rng.float(-340...340)
            let y = look.theme == .rift || look.theme == .quantum ? rng.float(-150...80) : rng.float(4...max(30, rig.height * 1.4))
            let z0 = rng.float(0...depth)
            let z = eye.z + 60 - (depth - (z0 + travelled * 1.3).truncatingRemainder(dividingBy: depth))
            let p = Vec3(eye.x + x, look.theme == .rift ? eye.y + y : y, z)
            world.line(p, p + Vec3(0, 0, -length), color: StoryPalette.gold, alpha: rush * 0.7, width: 1.2)
        }
    }

    /// A ring of light racing out across the world.
    private func drawPulse(eye: Vec3) {
        let e = easeOut(pulseAge / 1.5)
        let a = 1 - smooth(0.2, 1.5, pulseAge)
        let flat = look.theme != .rift && look.theme != .quantum
        let centre = flat ? Vec3(eye.x, 0, eye.z - 320) : eye + forward * 260
        let (u, v) = flat ? (Vec3(1, 0, 0), Vec3(0, 0, 1)) : StoryScenery.basis(forward)
        world.polyline(StoryScenery.circle(center: centre, radius: 30 + 900 * e, u: u, v: v, segments: 64),
                       color: StoryPalette.sun, alpha: a, width: 2.4)
        world.polyline(StoryScenery.circle(center: centre, radius: 20 + 620 * e, u: u, v: v, segments: 48),
                       color: palette.highlight, alpha: a * 0.6, width: 1.6)
    }

    private static let debrisMeshes: [WireMesh] = [
        .rock(radius: 7, seed: 1, roughness: 0.4, subdivisions: 0),
        .octahedron(radius: 6),
        .rock(radius: 9, seed: 2, roughness: 0.5, subdivisions: 0)
    ]

    /// Wreckage tumbling between the ship and the ground — the middle distance.
    private func drawDebris(eye: Vec3, band: ClosedRange<Float>, alpha: Float) {
        anchors(eye: eye, gap: 150, near: 40, far: 800) { k in
            var rng = StoryRandom(seed: 0xDEB2 &+ UInt64(bitPattern: Int64(k)))
            guard rng.unit() < 0.55 else { return }
            let p = Vec3(rng.float(-260...260), rng.float(band), Float(k) * 150)
            let mesh = Self.debrisMeshes[Int(rng.next() % 3)]
            let spin = rotation(t * rng.float(0.3...0.9) + rng.float(0...6), rng.direction())
            world.mesh(mesh, at: p, rotation: spin, color: StoryPalette.mix(accentColor, StoryPalette.ice, 0.4),
                       alpha: alpha, width: 1.1, backAlpha: 0.35)
        }
    }

    // MARK: - Sky

    private func renderSky() {
        sky.settings = WireCanvas.Settings()
        sky.settings.intensity = master
        sky.settings.offset = shake
        sky.settings.fogNear = 100_000
        sky.settings.fogFar = 200_000
        sky.settings.widthReference = 3000
        sky.begin(WireCamera(position: .zero, target: forward * 100, roll: roll, fov: Self.fov))

        if master > 0.01 {
            drawStars()
            drawNebulae()
            switch look.theme {
            case .horizon, .epicentre: horizonGlow(strength: 1)
            case .ruins: horizonGlow(strength: 0.8)
            case .well: horizonGlow(strength: 0.7)
            case .rift, .quantum: break
            }
            if flash > 0.01 {
                sky.glow(skyPoint(0, 0.06), radius: 2600, color: stormColor, alpha: flash * 0.22)
            }
            if stage.has(.aurora) { drawAurora() }
            if stage.has(.battle) { drawBattle() }
            if stage.has(.giant) { drawGiant() }
            if stage.has(.dwarf) { drawDwarf() }
            if stage.has(.starDeaths) { drawStarDeath() }
            if stage.has(.ringedWorld) { drawRingedWorld() }
            if stage.has(.gasGiant) { drawGasGiant() }
            if stage.has(.shatteredMoon) { drawShatteredMoon() }
            if stage.has(.eclipse) { drawEclipse() }
            if stage.has(.twinSuns) { drawTwinSuns() }
            if stage.has(.blackHole) { drawBlackHole() }
            if stage.has(.epicentre) { drawEpicentreSky() }
            if stage.has(.riftEye) { drawRiftSky() }
        }
        sky.end()
    }

    private static let skyRadius: Float = 3000

    /// A point on the sky, `azimuth` to the right of dead ahead and `elevation`
    /// above the horizon, in radians.
    private func skyPoint(_ azimuth: Float, _ elevation: Float, distance: Float = GameBackdrop.skyRadius) -> Vec3 {
        Vec3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation)) * distance
    }

    /// A direction anchored to the screen rather than the horizon: `x` and `y` are
    /// in screen halves (-1...1 across the shorter side).
    private func screenPoint(_ x: Float, _ y: Float) -> Vec3 {
        let f = forward
        let right = Vec3(1, 0, 0)
        let up = simd_cross(right, f)
        let k = tan(Self.fov * .pi / 360)
        return simd_normalize(f + right * x * k + up * y * k) * Self.skyRadius
    }

    private func drawStars() {
        // The sky turns slowly over the ship, so even the farthest layer is moving.
        let q = rotation(-t * 0.006 * (1 + 3 * rush), Vec3(1, 0, 0))
        for star in stars {
            let twinkle = 0.65 + 0.35 * sin(t * 1.7 + star.phase)
            let p = q.act(star.dir) * 2000
            sky.dot(p, size: star.size, color: star.tint, alpha: 0.6 * twinkle, fogged: false)
        }
    }

    private func drawNebulae() {
        sky.glow(screenPoint(0.55, 0.9), radius: 1500, color: palette.nebulaA, alpha: 0.14)
        sky.glow(screenPoint(-0.7, -0.2), radius: 1300, color: palette.nebulaB, alpha: 0.1)
        sky.glow(screenPoint(0.2, -1.5), radius: 1800, color: palette.nebulaA, alpha: 0.07)
        if alert > 0.02 {
            sky.glow(screenPoint(0, 1.2), radius: 2200, color: StoryPalette.red, alpha: alert * 0.12)
        }
    }

    private func horizonGlow(strength: Float) {
        let color = StoryPalette.mix(palette.horizon, StoryPalette.red, alert * 0.6)
        let horizon = skyPoint(0, 0)
        sky.flare(horizon, length: Float(viewport.width) * 1.7, thickness: 26, color: color, alpha: 0.38 * strength)
        sky.glow(skyPoint(0, -0.03), radius: 1100, color: color, alpha: 0.2 * strength)
    }

    /// Edge alpha for a body on the horizon: the part below it has set.
    private func setting(_ centre: Vec3, _ q: simd_quatf, _ radius: Float) -> (Vec3, Vec3) -> Float {
        { a, b in
            let ya = centre.y + q.act(a * radius).y, yb = centre.y + q.act(b * radius).y
            return smooth(-0.04 * GameBackdrop.skyRadius, 0.01 * GameBackdrop.skyRadius, min(ya, yb))
        }
    }

    private static let giantMesh = WireMesh.globe(radius: 1, rings: 8, meridians: 12, segments: 26)
    private static let dwarfMesh = WireMesh.geodesic(radius: 1, subdivisions: 1)

    /// A red giant going down behind the grid, throwing loops of plasma. It sinks
    /// as the level goes on.
    private func drawGiant() {
        let start: Float = stage.mood == .dusk ? 0.035 : 0.06
        let centre = skyPoint(-0.26, start - 0.045 * progress)
        let radius = Self.skyRadius * 0.27
        let swell: Float = 1 + 0.025 * sin(t * 1.9)
        let q = rotation(t * 0.05, Vec3(0.2, 1, 0.1))
        sky.glow(centre, radius: radius * 2.1, color: palette.accent, alpha: 0.24)
        sky.mesh(Self.giantMesh, at: centre, rotation: q, scale: radius * swell, color: palette.accent, alpha: 0.6,
                 width: 1.3, backAlpha: 0.16, edgeAlpha: setting(centre, q, radius))
        sky.glow(centre, radius: radius * 0.7, color: StoryPalette.sun, alpha: 0.16)
        let (gu, gv) = StoryScenery.basis(-centre)
        for loop in 0..<4 {
            let a = Float(loop) * 0.6 + 0.6
            let base = gu * cos(a) + gv * sin(a)
            let side = gu * -sin(a) + gv * cos(a)
            let rise: Float = 0.16 + 0.08 * sin(t * 0.8 + Float(loop) * 2)
            let points = (0...14).map { k -> Vec3 in
                let s = Float(k) / 14 * .pi
                return centre + base * (radius * swell + radius * rise * sin(s)) + side * radius * 0.15 * cos(s)
            }
            sky.polyline(points, color: palette.highlight, alpha: 0.55, width: 1.2)
        }
    }

    /// A white dwarf, guttering.
    private func drawDwarf() {
        let dwarf = skyPoint(0.34, 0.07)
        let flicker: Float = 0.55 + 0.45 * abs(sin(t * 7.3) * sin(t * 2.9))
        sky.mesh(Self.dwarfMesh, at: dwarf, rotation: rotation(t * 0.5, Vec3(0, 1, 0.3)), scale: 70,
                 color: StoryPalette.ice, alpha: flicker * 0.8, width: 1.1, backAlpha: 0.3)
        sky.glow(dwarf, radius: 260, color: StoryPalette.ice, alpha: flicker * 0.3)
    }

    /// Every so often a star on the horizon goes out: it falls in, then a ring of light.
    private func drawStarDeath() {
        let period: Float = 17
        let cycle = (t / period).rounded(.down)
        let local = t - cycle * period
        var rng = StoryRandom(seed: 0x5_7A2 &+ UInt64(max(0, cycle)))
        let p = skyPoint(rng.float(-0.5...0.5), rng.float(0.04...0.12))
        let collapseAt: Float = 4
        if local < collapseAt + 0.8 {
            let k = clamp01((local - collapseAt) / 0.8)
            let s = 1 - easeIn(k)
            let appear = smooth(0, 1.5, local)
            sky.glow(p, radius: 90 * s + 20 * k, color: palette.highlight, alpha: appear * (0.4 + 0.5 * k))
            sky.dot(p, size: 8 * s + 3, color: StoryPalette.white, alpha: appear, fogged: false)
        } else {
            let after = local - collapseAt - 0.8
            let e = easeOut(after / 2.6)
            let a = 1 - smooth(0.3, 2.8, after)
            guard a > 0.01 else { return }
            let (u, v) = StoryScenery.basis(-p)
            sky.glow(p, radius: 60 + 380 * e, color: StoryPalette.white, alpha: a * 0.4)
            sky.polyline(StoryScenery.circle(center: p, radius: 30 + 600 * e, u: u, v: v, segments: 48),
                         color: palette.highlight, alpha: a * 0.8, width: 1.6)
        }
    }

    /// A ringed world hanging over the ruins.
    private func drawRingedWorld() {
        let centre = skyPoint(-0.34, 0.05)
        let radius = Self.skyRadius * 0.085
        let q = rotation(t * 0.04, Vec3(0.1, 1, 0))
        sky.mesh(Self.giantMesh, at: centre, rotation: q, scale: radius, color: palette.accent, alpha: 0.5,
                 width: 1.1, backAlpha: 0.15)
        sky.glow(centre, radius: radius * 1.8, color: palette.accent, alpha: 0.14)
        let tilt = rotation(0.32, Vec3(0, 0, 1)) * rotation(0.22, Vec3(1, 0, 0))
        let u = tilt.act(Vec3(1, 0, 0)), v = tilt.act(Vec3(0, 0, 1))
        for ring in 0..<3 {
            StoryScenery.dashedRing(sky, center: centre, radius: radius * (1.5 + Float(ring) * 0.22), u: u, v: v,
                                    phase: t * 0.05 * Float(ring + 1), dashes: 18 + ring * 4, fill: 0.7,
                                    color: StoryPalette.mix(palette.highlight, palette.accent, Float(ring) / 2),
                                    alpha: 0.55, width: 1.2)
        }
    }

    private static let bandedMesh = WireMesh.globe(radius: 1, rings: 12, meridians: 4, segments: 30)

    /// A banded gas giant rising off the horizon, two moons going round it.
    private func drawGasGiant() {
        let centre = skyPoint(0.3, 0.02 + 0.04 * progress)
        let radius = Self.skyRadius * 0.12
        let q = rotation(0.3, Vec3(0, 0, 1)) * rotation(t * 0.03, Vec3(0, 1, 0))
        sky.glow(centre, radius: radius * 1.9, color: palette.nebulaA, alpha: 0.18)
        sky.mesh(Self.bandedMesh, at: centre, rotation: q, scale: radius, color: palette.accent, alpha: 0.5,
                 width: 1.2, backAlpha: 0.12, edgeAlpha: setting(centre, q, radius))
        let (u, v) = StoryScenery.basis(-centre)
        for m in 0..<2 {
            let a = t * (0.12 + 0.07 * Float(m)) + Float(m) * 2
            let p = centre + u * cos(a) * radius * (1.6 + 0.5 * Float(m)) + v * sin(a) * radius * 0.35 * Float(1 + m)
            sky.mesh(Self.dwarfMesh, at: p, rotation: rotation(t * 0.3, Vec3(0, 1, 0)), scale: radius * 0.09,
                     color: StoryPalette.ice, alpha: 0.6, width: 1, backAlpha: 0.3)
            sky.glow(p, radius: radius * 0.25, color: StoryPalette.ice, alpha: 0.18)
        }
    }

    private static let moonMesh = WireMesh.globe(radius: 1, rings: 7, meridians: 10, segments: 24)
    private static let shardMeshes = (0..<4).map { WireMesh.rock(radius: 1, seed: 40 + UInt64($0), roughness: 0.6, subdivisions: 0) }

    /// A moon with a bite out of it, fragments streaming off the wound.
    private func drawShatteredMoon() {
        let centre = skyPoint(-0.28, 0.1)
        let radius = Self.skyRadius * 0.07
        let q = rotation(t * 0.02, Vec3(0.2, 1, 0))
        let wound = simd_normalize(Vec3(0.55, -0.55, 0.6))
        sky.glow(centre, radius: radius * 2, color: palette.accent, alpha: 0.16)
        sky.mesh(Self.moonMesh, at: centre, rotation: q, scale: radius, color: StoryPalette.ice, alpha: 0.5,
                 width: 1.1, backAlpha: 0.2) { a, b in
            1 - smooth(0.35, 0.6, simd_dot(q.act(simd_normalize(a + b + Vec3(0, 0.0001, 0))), wound))
        }
        sky.glow(centre + wound * radius * 0.7, radius: radius * 0.9, color: palette.highlight, alpha: 0.35)
        for j in 0..<9 {
            var rng = StoryRandom(seed: 0x5A0D &+ UInt64(j))
            let dir = simd_normalize(wound + rng.direction() * 0.45)
            let drift = (t * rng.float(0.01...0.025) + rng.unit()).truncatingRemainder(dividingBy: 1)
            let p = centre + dir * radius * (0.9 + 2.2 * drift)
            let spin = rotation(t * rng.float(0.2...0.6), rng.direction())
            let a = 0.6 * (1 - smooth(0.7, 1, drift)) * smooth(0, 0.1, drift)
            sky.mesh(Self.shardMeshes[j % 4], at: p, rotation: spin, scale: radius * rng.float(0.08...0.2) * (1 - 0.4 * drift),
                     color: StoryPalette.ice, alpha: a, width: 1)
        }
    }

    /// A star behind a black disc, its corona streaming out around the rim.
    private func drawEclipse() {
        let centre = skyPoint(0.16, 0.085)
        let radius = Self.skyRadius * 0.045
        let toCamera = simd_normalize(-centre)
        let behind = centre - toCamera * 10
        sky.settings.depthSplit = sky.depth(of: centre)
        sky.glow(behind, radius: radius * 5, color: palette.horizon, alpha: 0.4)
        sky.glow(behind, radius: radius * 1.9, color: StoryPalette.sun, alpha: 0.5)
        let (u, v) = StoryScenery.basis(toCamera)
        for i in 0..<18 {
            let a = Float(i) / 18 * 2 * .pi + 0.1 * sin(t * 0.3)
            let dir = u * cos(a) + v * sin(a)
            let reach = radius * (0.35 + 0.5 * (0.5 + 0.5 * sin(t * 1.3 + Float(i) * 2.4)) * (0.6 + 0.4 * Self.hash(i, 0, 0xEC1)))
            sky.line(behind + dir * radius * 1.02, behind + dir * (radius * 1.02 + reach), color: StoryPalette.sun, alpha: 0.4, width: 1.2)
        }
        sky.disc(centre, radius: radius, color: UIColor(red: 0.004, green: 0.004, blue: 0.012, alpha: 1))
        sky.polyline(StoryScenery.circle(center: centre, radius: radius * 1.02, u: u, v: v, segments: 40),
                     color: StoryPalette.white, alpha: 0.9, width: 1.5)
        sky.settings.depthSplit = nil
        sky.flare(centre, length: Float(viewport.width) * 1.0, thickness: 10, color: StoryPalette.sun, alpha: 0.3)
    }

    /// Two suns going round each other, the bigger one drawing plasma off the smaller.
    private func drawTwinSuns() {
        let centre = skyPoint(-0.2, 0.075 - 0.04 * progress)
        let a = t * 0.22
        let offset = Vec3(cos(a), 0.25 * sin(a), sin(a)) * 210
        let big = centre + offset, small = centre - offset * 1.4
        sky.glow(big, radius: 520, color: StoryPalette.gold, alpha: 0.3)
        sky.mesh(Self.dwarfMesh, at: big, rotation: rotation(t * 0.4, Vec3(0, 1, 0.3)), scale: 150,
                 color: StoryPalette.gold, alpha: 0.75, width: 1.2, backAlpha: 0.3)
        sky.glow(big, radius: 170, color: StoryPalette.sun, alpha: 0.6)
        sky.glow(small, radius: 380, color: StoryPalette.cyan, alpha: 0.28)
        sky.mesh(Self.dwarfMesh, at: small, rotation: rotation(-t * 0.6, Vec3(0.3, 1, 0)), scale: 100,
                 color: StoryPalette.ice, alpha: 0.75, width: 1.1, backAlpha: 0.3)
        sky.glow(small, radius: 110, color: StoryPalette.white, alpha: 0.6)
        let bend = (big + small) * 0.5 + Vec3(0, 140, 0)
        let stream = (0...12).map { k -> Vec3 in
            let s = Float(k) / 12
            let p = small * (1 - s) * (1 - s) + bend * 2 * s * (1 - s) + big * s * s
            return p + Vec3(0, 18 * sin(s * 9 - t * 3), 0)
        }
        sky.polyline(stream, color: palette.highlight, alpha: 0.5, width: 1.3)
        sky.flare(big, length: Float(viewport.width) * 1.2, thickness: 12, color: StoryPalette.sun, alpha: 0.35)
    }

    /// Aurora curtains over the horizon.
    private func drawAurora() {
        let colors = [StoryPalette.green, StoryPalette.cyan, StoryPalette.violet]
        for band in 0..<3 {
            let lift = Float(band) * 0.012
            var tops: [Vec3] = []
            for s in 0...22 {
                let az = -0.75 + 1.5 * Float(s) / 22
                let wave = sin(az * 5.5 + t * 0.35 + Float(band) * 1.7) * 0.5 + sin(az * 11 - t * 0.6 + Float(band)) * 0.25
                let topElevation = 0.1 + lift + 0.03 * wave
                let bottomElevation = 0.025 + lift * 0.5
                let shimmer = 0.55 + 0.45 * sin(t * 1.3 + az * 9 + Float(band) * 2)
                let top = skyPoint(az, topElevation)
                let mid = skyPoint(az, lerp(bottomElevation, topElevation, 0.45))
                sky.line(skyPoint(az, bottomElevation), mid, color: colors[band], alpha: 0.1 * shimmer, width: 2.4)
                sky.line(mid, top, color: colors[band], alpha: 0.2 * shimmer, width: 2.4)
                tops.append(top)
            }
            sky.polyline(tops, color: colors[band], alpha: 0.4, width: 1.4)
        }
    }

    /// A battle somewhere on the horizon: flashes, shock rings and tracer fire.
    private func drawBattle() {
        for j in 0..<5 {
            let period: Float = 1.9 + Float(j) * 0.55
            let shifted = t + Float(j) * 0.7
            let cycle = (shifted / period).rounded(.down)
            let local = shifted - cycle * period
            var rng = StoryRandom(seed: 0xBA77 &+ UInt64(j) &* 977 &+ UInt64(max(0, cycle)))
            let p = skyPoint(rng.float(-0.75...0.75), rng.float(0.004...0.05))
            let color = rng.unit() > 0.5 ? StoryPalette.ember : StoryPalette.gold
            let e = easeOut(min(1, local / 0.6))
            let a = 1 - smooth(0.05, 1.2, local)
            guard a > 0.01 else { continue }
            sky.glow(p, radius: 40 + 220 * e, color: color, alpha: a * 0.55)
            sky.glow(p, radius: 25 * (1 - e) + 8, color: StoryPalette.white, alpha: a * 0.8)
            let (u, v) = StoryScenery.basis(-p)
            sky.polyline(StoryScenery.circle(center: p, radius: 30 + 260 * e, u: u, v: v, segments: 24),
                         color: color, alpha: a * 0.5, width: 1.2)
        }
        for j in 0..<8 {
            var rng = StoryRandom(seed: 0x7AC3 &+ UInt64(j))
            let a0 = rng.float(-0.7...0.7), e0 = rng.float(0.01...0.06)
            let a1 = a0 + rng.float(-0.25...0.25), e1 = e0 + rng.float(-0.02...0.04)
            let period = rng.float(0.6...1.4)
            let f = ((t + rng.float(0...2)) / period).truncatingRemainder(dividingBy: 1)
            let from = skyPoint(a0, e0), to = skyPoint(a1, e1)
            sky.line(lerp(from, to, f), lerp(from, to, min(1, f + 0.12)),
                     color: j % 3 == 0 ? StoryPalette.red : StoryPalette.gold, alpha: 0.7, width: 1.2)
        }
    }

    private func drawRiftSky() {
        // The far end of the tunnel: the rift itself, torn and flickering.
        let centre = skyPoint(0, 0)
        let (u, v) = StoryScenery.basis(Vec3(0, 0, 1))
        for layer in 0..<3 {
            var r = StoryRandom(seed: 63 &+ UInt64(layer) &+ UInt64(t * 12))
            let points = (0..<22).map { i -> Vec3 in
                let a = Float(i) / 22 * 2 * .pi
                let radius = 150 * (1 - Float(layer) * 0.2) * (0.75 + 0.5 * r.unit())
                return centre + (u * cos(a) * 0.6 + v * sin(a) * 1.3) * radius
            }
            sky.polyline(points, closed: true, color: layer == 0 ? StoryPalette.white : palette.accent,
                         alpha: 0.6, width: 1.5)
        }
        sky.glow(centre, radius: 700, color: palette.accent, alpha: 0.4)
        sky.glow(centre, radius: 160, color: StoryPalette.white, alpha: 0.5)
        sky.flare(centre, length: Float(viewport.width) * 1.2, thickness: 14, color: palette.highlight, alpha: 0.35)
    }

    /// A black hole on the horizon, its disc wrapped round it. Nearer every level of
    /// the sector, and nearer as each goes on.
    private func drawBlackHole() {
        let hole = skyPoint(-0.2, 0.07)
        let radius = Self.skyRadius * 0.035 * (1 + 0.12 * Float(look.stage) + 0.15 * progress)
        sky.settings.depthSplit = sky.depth(of: hole)
        let toCamera = simd_normalize(-hole)
        sky.glow(hole - toCamera * 10, radius: radius * 6, color: palette.accent, alpha: 0.45)
        sky.disc(hole, radius: radius * 0.95, color: UIColor(red: 0.004, green: 0.004, blue: 0.012, alpha: 1))
        let tilt = rotation(0.2, Vec3(1, 0, 0.3))
        let u = tilt.act(Vec3(1, 0, 0)), v = tilt.act(Vec3(0, 0, 1))
        for ring in 0..<5 {
            let r = radius * (1.4 + Float(ring) * 0.45)
            StoryScenery.dashedRing(sky, center: hole, radius: r, u: u, v: v, phase: t * (2.4 / (1 + Float(ring) * 0.4)),
                                    dashes: 7 + ring, fill: 0.6,
                                    color: StoryPalette.mix(StoryPalette.sun, StoryPalette.ember, Float(ring) / 4),
                                    alpha: 0.9, width: 1.4)
        }
        let (pu, pv) = StoryScenery.basis(toCamera)
        sky.polyline(StoryScenery.circle(center: hole, radius: radius * 1.05, u: pu, v: pv, segments: 32),
                     color: StoryPalette.white, alpha: 0.85, width: 1.5)
        sky.settings.depthSplit = nil
        sky.flare(hole, length: Float(viewport.width) * 0.9, thickness: 10, color: StoryPalette.sun, alpha: 0.3)
    }

    private static let epicentreOuter = WireMesh.geodesic(radius: 1, subdivisions: 1)
    private static let epicentreInner = WireMesh.octahedron(radius: 1)

    /// The epicentre, bigger with every level of the last sector.
    private func drawEpicentreSky() {
        let centre = skyPoint(0, 0.13)
        let scale = Self.skyRadius * 0.12 * (1 + 0.14 * Float(look.stage) + 0.12 * progress)
        sky.mesh(Self.epicentreOuter, at: centre, rotation: rotation(t * 0.05, Vec3(0.3, 1, 0)), scale: scale,
                 color: StoryPalette.violet, alpha: 0.45, width: 1.2, backAlpha: 0.3)
        sky.mesh(Self.epicentreInner, at: centre, rotation: rotation(-t * 0.14, Vec3(1, 0.4, 0.2)), scale: scale * 0.55,
                 color: palette.highlight, alpha: 0.7, width: 1.3, backAlpha: 0.4)
        let axes = [Vec3(1, 0.2, 0), Vec3(0, 1, 0.3), Vec3(0.3, 0.1, 1)]
        for (i, axis) in axes.enumerated() {
            let q = rotation(t * (0.3 + Float(i) * 0.17), axis)
            let (u, v) = StoryScenery.basis(q.act(simd_normalize(axis)))
            StoryScenery.dashedRing(sky, center: centre, radius: scale * (1.35 + Float(i) * 0.16), u: u, v: v,
                                    phase: t * 0.4, dashes: 10, fill: 0.75,
                                    color: i == 1 ? palette.highlight : StoryPalette.cyan, alpha: 0.6, width: 1.3)
        }
        let pulse: Float = 1 + 0.12 * sin(t * 5)
        sky.glow(centre, radius: scale * 1.6, color: StoryPalette.violet, alpha: 0.35)
        sky.glow(centre, radius: scale * 0.6 * pulse, color: palette.highlight, alpha: 0.5)
        sky.glow(centre, radius: scale * 0.22 * pulse, color: StoryPalette.white, alpha: 0.9)
        sky.flare(centre, length: Float(viewport.width) * 1.1, thickness: 12, color: StoryPalette.sun, alpha: 0.45)
        var rng = StoryRandom(seed: 71)
        for bolt in 0..<3 {
            let target = Self.epicentreOuter.vertices[Int(rng.next() % UInt64(Self.epicentreOuter.vertices.count))]
            let twitch = rotation(Float(bolt) + t * 0.9, Vec3(0.2, 1, 0.4))
            StoryScenery.lightning(sky, from: centre, to: centre + twitch.act(target) * scale, t: t,
                                   seed: 700 &+ UInt64(bolt), jitter: scale * 0.1, color: StoryPalette.violet, alpha: 0.7)
        }
    }

    // MARK: - Palettes

    private struct Palette {
        var grid: UIColor
        var accent: UIColor
        var highlight: UIColor
        var horizon: UIColor
        var nebulaA: UIColor
        var nebulaB: UIColor
    }

    private static func palette(for look: BackdropLook, mood: BackdropMood) -> Palette {
        let p = StoryPalette.self
        let second = look.variant % 2 == 1
        var palette: Palette
        switch look.theme {
        case .horizon:
            palette = second
                ? Palette(grid: p.violet, accent: p.magenta, highlight: p.sun, horizon: p.magenta, nebulaA: p.blue, nebulaB: p.cyan)
                : Palette(grid: p.cyan, accent: p.ember, highlight: p.gold, horizon: p.ember, nebulaA: p.violet, nebulaB: p.blue)
        case .ruins:
            palette = second
                ? Palette(grid: p.ember, accent: p.gold, highlight: p.sun, horizon: p.ember, nebulaA: p.magenta, nebulaB: p.violet)
                : Palette(grid: p.blue, accent: p.ice, highlight: p.gold, horizon: p.cyan, nebulaA: p.blue, nebulaB: p.violet)
        case .rift:
            palette = second
                ? Palette(grid: p.magenta, accent: p.violet, highlight: p.gold, horizon: p.magenta, nebulaA: p.magenta, nebulaB: p.blue)
                : Palette(grid: p.cyan, accent: p.violet, highlight: p.gold, horizon: p.violet, nebulaA: p.violet, nebulaB: p.blue)
        case .quantum:
            palette = second
                ? Palette(grid: p.green, accent: p.cyan, highlight: p.ice, horizon: p.green, nebulaA: p.cyan, nebulaB: p.violet)
                : Palette(grid: p.violet, accent: p.magenta, highlight: p.ice, horizon: p.magenta, nebulaA: p.violet, nebulaB: p.magenta)
        case .well:
            palette = Palette(grid: p.violet, accent: p.ember, highlight: p.sun, horizon: p.violet, nebulaA: p.violet, nebulaB: p.blue)
        case .epicentre:
            palette = Palette(grid: p.violet, accent: p.gold, highlight: p.gold, horizon: p.violet, nebulaA: p.violet, nebulaB: p.magenta)
        }

        switch mood {
        case .standard:
            break
        case .dusk:
            palette.grid = p.mix(palette.grid, p.magenta, 0.35)
            palette.accent = p.mix(palette.accent, p.ember, 0.4)
            palette.horizon = p.mix(palette.horizon, p.ember, 0.6)
            palette.nebulaA = p.mix(palette.nebulaA, p.magenta, 0.4)
        case .cold:
            palette.grid = p.mix(palette.grid, p.ice, 0.35)
            palette.accent = p.mix(palette.accent, p.cyan, 0.4)
            palette.horizon = p.mix(palette.horizon, p.cyan, 0.5)
            palette.nebulaB = p.mix(palette.nebulaB, p.green, 0.4)
        case .ember:
            palette.grid = p.mix(palette.grid, p.ember, 0.65)
            palette.accent = p.mix(palette.accent, p.gold, 0.35)
            palette.horizon = p.mix(palette.horizon, p.ember, 0.7)
            palette.highlight = p.mix(palette.highlight, p.gold, 0.5)
        case .storm:
            palette.grid = p.mix(palette.grid, p.ice, 0.5)
            palette.accent = p.mix(palette.accent, p.violet, 0.3)
            palette.horizon = p.mix(palette.horizon, p.blue, 0.5)
            palette.highlight = p.mix(palette.highlight, p.ice, 0.5)
            palette.nebulaA = p.mix(palette.nebulaA, p.blue, 0.5)
        }
        return palette
    }
}
