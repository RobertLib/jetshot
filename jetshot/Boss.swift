//
//  Boss.swift
//  jetshot
//
//  Created by Robert Libšanský on 26.10.2025.
//

import SpriteKit
import simd

/// A piece of a boss's hardware the player can shoot off: a gun pod, a satellite, a
/// brood bay, a segment of the serpent.
///
/// It is a hit volume and a health counter, nothing more — the piece itself is drawn by
/// the boss's wireframe (`BossArt`), which also reports where it has turned to each frame
/// so the volume can follow. Every round that lands on a part still comes off the boss's
/// own health too, so taking the guns off never makes the fight longer: it only makes
/// the boss fire less.
final class BossPart: SKNode {
    weak var boss: Boss?
    let index: Int
    private(set) var health: Int

    var isDestroyed: Bool { health <= 0 }

    init(index: Int, radius: CGFloat, health: Int) {
        self.index = index
        self.health = max(1, health)
        super.init()
        name = "bossPart"

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.categoryBitMask = PhysicsCategory.enemy
        body.contactTestBitMask = PhysicsCategory.bullet
        body.collisionBitMask = PhysicsCategory.none
        body.isDynamic = false
        physicsBody = body
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Takes a hit; true if it was the one that destroyed the part.
    fileprivate func absorb(_ amount: Int) -> Bool {
        guard health > 0 else { return false }
        health -= max(1, amount)
        guard health <= 0 else { return false }
        health = 0
        physicsBody = nil
        return true
    }
}

/// The machine at the end of a level: one of the archetypes in `BossCatalog`, drawn in
/// 3D wireframe by `BossArt`, flying its archetype's path between attacks, carrying its
/// shootable hardware as `BossPart`s. `BossManager` decides what it fires and when;
/// this node owns how it looks, moves, takes damage and dies.
class Boss: SKNode {
    private var currentHealth: Int
    let config: BossConfig

    /// Health actually fought through: the authored figure scaled to the current fire
    /// rate (see `CombatRules.bossHealthScale`). Every fraction — the bar, the phases,
    /// the damage visuals — is taken against this, never against `config.maxHealth`,
    /// which stays the authored number the configs and their tests are written in.
    let maxHealthPoints: Int

    /// When the per-hit dressing (flash, debris, sparks) last ran, in real time.
    ///
    /// A full arsenal lands dozens of rounds a second on a boss. The damage itself is
    /// applied per round; the dressing is capped to a rate the eye can actually separate.
    private var lastHitDressing: CFTimeInterval = 0
    private static let hitDressingInterval: CFTimeInterval = 0.07
    private var healthBar: SKShapeNode!
    private var healthBarFill: SKShapeNode!
    /// The charge's width at full health. Kept rather than recomputed from the scene on
    /// each hit, so the charge always drains inside the frame it was built for.
    private var healthFillWidth: CGFloat = 0
    private var isActive: Bool = false
    private var damageLevel: Int = 0

    /// Everything the wireframe needs to know this frame, and what it reports back.
    /// Internal so `BossManager` can drive the parts of it its attacks animate — the
    /// mantis sweeping its arms back for a dive, the wraith fading out.
    let look: BossLook
    /// The drawn boss. Shakes, pulses and wind-ups move this rather than the boss node,
    /// so none of them disturbs the hit volumes or the flight path.
    private let hull = SKNode()
    private var wire: WireBody?
    private(set) var parts: [BossPart] = []

    /// The ship, for the eyes that follow it.
    weak var target: SKNode?

    // MARK: Flight

    /// Where the boss may fly: its sweep across the screen and its station height.
    private(set) var arena = (minX: CGFloat(0), maxX: CGFloat(0), baseY: CGFloat(0))
    private var flightClock: TimeInterval = 0
    private var lastFlightElapsed: CGFloat = 0
    private var previousX: CGFloat = 0
    /// Set while an attack is steering the boss itself — a dive, a blink.
    private(set) var isManoeuvring = false
    private var blendFrom: CGPoint?
    private var blend: CGFloat = 1
    /// The tesseract's stations and its progress between them.
    private var station = 2
    private var stationTimer: TimeInterval = 0
    /// A slide between stations. Both ends are full points: alternate stations sit at
    /// different heights, and the height has to travel with the slide.
    private var slide: (from: CGPoint, to: CGPoint)?
    /// The serpent's wake: where its head has been, oldest first.
    private var wake: [CGPoint] = []
    /// The physics body, parked while the boss is out of phase.
    private var parkedBody: SKPhysicsBody?

    init(config: BossConfig, sceneSize: CGSize) {
        self.config = config
        self.maxHealthPoints = CombatRules.bossHealth(authored: config.maxHealth)
        self.currentHealth = maxHealthPoints
        self.look = BossLook(archetype: config.archetype, tier: config.tier, palette: config.palette,
                             unit: Float(config.size / 2))

        super.init()

        self.name = "boss"
        self.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height + config.size)
        self.zPosition = 10

        buildBody()
        setupHealthBar(sceneSize: sceneSize)

        // The core, fitted to the hull (see `BossArt.coreVolume`). Hardware outside it is
        // hit through its own `BossPart`s.
        let unit = config.size / 2
        let shapes = BossArt.coreVolume(for: config.archetype, tier: config.tier).map {
            SKPhysicsBody(circleOfRadius: $0.radius * unit,
                          center: CGPoint(x: $0.center.x * unit, y: $0.center.y * unit))
        }
        let physicsBody = shapes.count == 1 ? shapes[0] : SKPhysicsBody(bodies: shapes)
        physicsBody.categoryBitMask = PhysicsCategory.enemy
        physicsBody.contactTestBitMask = PhysicsCategory.bullet
        physicsBody.collisionBitMask = PhysicsCategory.none
        physicsBody.isDynamic = false
        self.physicsBody = physicsBody

        let count = look.partAlive.count
        let partHealth = BossPhaseRules.partHealth(bossHealth: maxHealthPoints, partCount: count)
        for i in 0..<count {
            let radius = BossArt.partRadius(for: config.archetype, index: i, count: count) * config.size / 2
            let part = BossPart(index: i, radius: radius, health: partHealth)
            part.boss = self
            part.position = look.partPoints[i]
            addChild(part)
            parts.append(part)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildBody() {
        let size = config.size

        // A pool of shadow under the hull so the world's lines do not run through it,
        // and a faint wash of its own light around it.
        let shadow = NeonFX.radialGlow(radius: size * 0.66, color: .black, softness: 0.8, additive: false)
        shadow.alpha = 0.75
        shadow.zPosition = -10
        addChild(shadow)

        let aura = NeonFX.radialGlow(radius: size * 0.72, color: config.palette.hull, softness: 0.6)
        aura.alpha = 0.14
        aura.zPosition = -9
        addChild(aura)
        aura.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 1.4),
            .fadeAlpha(to: 0.11, duration: 1.4)
        ])))

        addChild(hull)
        let extent = size / 2 * BossArt.extent(for: config.archetype)
        let body = WireBody(extent: extent, perspective: 4.5) { [weak self] frame in
            self?.drawFrame(frame)
        }
        look.cameraDistance = body.distance
        hull.addChild(body)
        wire = body
    }

    private func drawFrame(_ frame: WireBody.Frame) {
        look.health = Float(healthFraction)
        if let target = target, target.parent === parent {
            let d = SIMD2<Float>(Float(target.position.x - position.x), Float(target.position.y - position.y))
            let length = simd_length(d)
            if length > 1 {
                let blended = look.gaze + (d / length - look.gaze) * 0.12
                let l = simd_length(blended)
                if l > 1e-3 { look.gaze = blended / l }
            }
        }
        if config.archetype == .serpent { look.trail = trailOffsets() }

        BossArt.render(look, frame.canvas, t: frame.t)

        for part in parts where part.index < look.partPoints.count {
            part.position = look.partPoints[part.index]
        }
    }

    // MARK: - Muzzles

    private func toContent(_ local: CGPoint) -> CGPoint {
        CGPoint(x: position.x + hull.position.x + local.x * hull.xScale,
                y: position.y + hull.position.y + local.y * hull.yScale)
    }

    /// Where shots leave the boss when nothing else does: its eye, its emitter, the
    /// lip of its hole. In the coordinates of the boss's parent.
    var coreMuzzle: CGPoint { toContent(look.corePoint) }

    /// How many weapon muzzles the archetype has, destroyed ones included, so an
    /// attack can address them by index.
    var muzzleCount: Int { look.muzzlePoints.count }

    /// A weapon muzzle, or nil if the hardware carrying it has been shot off.
    func muzzle(_ index: Int) -> CGPoint? {
        guard index >= 0, index < look.muzzlePoints.count, look.muzzleAlive[index] else { return nil }
        return toContent(look.muzzlePoints[index])
    }

    /// The indices of the weapon muzzles still able to fire, left to right.
    func liveMuzzles() -> [Int] {
        look.muzzlePoints.indices
            .filter { look.muzzleAlive[$0] }
            .sorted { look.muzzlePoints[$0].x < look.muzzlePoints[$1].x }
    }

    // MARK: - Health bar

    /// How far below the HUD margin the health bar hangs.
    ///
    /// Not private so `jetshotTests` can assert the placement without restating the
    /// number. The point of that test is that the bar is measured down from
    /// `GameConfiguration.topMargin(in:)`, and a test carrying its own copy of the drop
    /// would keep passing if the margin fell out of the formula again — which is exactly
    /// what went wrong here.
    /// Moved down from 100 when the chain meter was moved off the pause button: the
    /// meter's panel bottom sits at the HUD margin less 97, and the bar's right end runs
    /// underneath it at the same x, so leaving this at 100 would have overlapped them.
    /// `HUDLayoutTests` pins the resulting clearance.
    static let healthBarDropBelowHUD: CGFloat = 114

    /// Builds the health bar. Its *position* is set later, by `layoutHealthBar(in:)`.
    ///
    /// The split is forced by the safe-area inset. This runs from `init`, where the boss
    /// is not in a scene yet, so it has no view to ask — the lookup that used to sit here
    /// read `self.scene?.view` and could therefore only ever return nil, pinning the
    /// margin to `minTopMargin` on every device.
    private func setupHealthBar(sceneSize: CGSize) {
        let barWidth: CGFloat = sceneSize.width * 0.8
        let barHeight: CGFloat = 20

        // A gauge in the films' instrument style: dark glass in a thin lit frame, the
        // charge a bar of light, tick marks every tenth like the dial in the opening.
        healthBar = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        healthBar.fillColor = UIColor(red: 0.03, green: 0.0, blue: 0.02, alpha: 0.75)
        healthBar.strokeColor = UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 0.55)
        healthBar.lineWidth = 1
        healthBar.zPosition = 150

        healthFillWidth = barWidth - 4
        healthBarFill = SKShapeNode(rectOf: CGSize(width: healthFillWidth, height: barHeight - 4), cornerRadius: 2)
        healthBarFill.fillColor = Self.gaugeColor(for: 1)
        healthBarFill.strokeColor = .clear
        healthBarFill.blendMode = .add
        healthBarFill.position = CGPoint(x: 0, y: 0)
        healthBar.addChild(healthBarFill)

        for tick in 1..<10 {
            let x = -barWidth / 2 + barWidth * CGFloat(tick) / 10
            let mark = SKSpriteNode(color: .black, size: CGSize(width: 1.5, height: barHeight - 4))
            mark.alpha = 0.55
            mark.position = CGPoint(x: x, y: 0)
            mark.zPosition = 1
            healthBar.addChild(mark)
        }
        // Where the next act begins: a brighter notch through the frame at each phase
        // threshold, so the player can see how far there is to go before it changes.
        // The charge drains from both ends towards the middle, so each threshold is a
        // pair of notches, one where each end of the charge will be when it is crossed.
        for x in Self.phaseNotchOffsets(fillWidth: barWidth - 4) {
            let notch = LightSprite.tube(from: CGPoint(x: x, y: -barHeight / 2 - 4),
                                         to: CGPoint(x: x, y: barHeight / 2 + 4),
                                         width: 1.2, color: StoryPalette.sun)
            notch.name = Self.phaseNotchName
            notch.zPosition = 2
            notch.alpha = 0.8
            healthBar.addChild(notch)
        }
        for side: CGFloat in [-1, 1] {
            let cap = LightSprite.tube(from: CGPoint(x: side * (barWidth / 2 + 4), y: -barHeight / 2 - 3),
                                       to: CGPoint(x: side * (barWidth / 2 + 4), y: barHeight / 2 + 3),
                                       width: 1.2, color: StoryPalette.red)
            healthBar.addChild(cap)
        }

        // The boss's name, parented to the bar. Its own floor for the shrink-to-fit:
        // under the default of 24 a 20 pt name could never shrink at all, so any name
        // longer than the bar ran past both ends of it.
        let bossLabel = Cinematic.title("⚡ \(config.displayName) ⚡", fontSize: 20,
                                        color: UIColor(red: 1.0, green: 0.55, blue: 0.5, alpha: 1.0),
                                        glow: StoryPalette.red, tracking: 6, maxWidth: barWidth, minimumSize: 12)
        bossLabel.name = Self.nameplateName
        bossLabel.position = CGPoint(x: 0, y: 26)
        bossLabel.zPosition = 1
        healthBar.addChild(bossLabel)
    }

    private static let phaseNotchName = "bossPhaseNotch"
    private static let nameplateName = "bossNameplate"

    /// How wide the boss's name over the bar came out, and the bar itself, for
    /// `jetshotTests`.
    var nameplateWidth: CGFloat { healthBar.childNode(withName: Self.nameplateName)?.frame.width ?? 0 }
    var healthBarWidth: CGFloat { healthBar.path?.boundingBox.width ?? 0 }

    /// Where the phase notches sit across the middle of a health bar whose charge is
    /// `fillWidth` wide at full health: both ends of the charge at each threshold.
    static func phaseNotchOffsets(fillWidth: CGFloat) -> [CGFloat] {
        BossPhaseRules.thresholds.flatMap { [-fillWidth * $0 / 2, fillWidth * $0 / 2] }
    }

    /// The x of each phase notch, relative to the middle of the bar, for `jetshotTests`.
    var phaseNotchXs: [CGFloat] {
        healthBar.children.filter { $0.name == Self.phaseNotchName }.map { $0.position.x }
    }

    /// Half the width of the charge left in the bar, for `jetshotTests`: where each end
    /// of it sits, measured from the middle.
    var healthBarFillHalfWidth: CGFloat {
        (healthBarFill.path?.boundingBox.width ?? 0) / 2
    }

    /// The gauge's light: red at full strength, burning down through ember to gold, one
    /// colour per act. Keyed to `BossPhaseRules` itself — it used to change at 0.6 and
    /// 0.3, a beat after the notches and the phase change it should announce. Internal
    /// for `jetshotTests`.
    static func gaugeColor(for fraction: CGFloat) -> UIColor {
        let colors = [StoryPalette.red, StoryPalette.ember, StoryPalette.gold]
        return colors[min(BossPhaseRules.phase(forHealthFraction: fraction), colors.count - 1)]
    }

    func addHealthBarToScene(_ scene: GameScene) {
        layoutHealthBar(in: scene)
        scene.gameContentNode.addChild(healthBar)
    }

    /// Places the health bar under the HUD.
    ///
    /// Separate from `addHealthBarToScene(_:)` so `GameScene.didChangeSize(_:)` can call
    /// it too. Position only — the bar's width is baked into its shape path in
    /// `setupHealthBar(sceneSize:)` and a resize would need the path rebuilt.
    func layoutHealthBar(in scene: GameScene) {
        healthBar.position = CGPoint(
            x: scene.size.width / 2,
            y: scene.size.height - GameConfiguration.topMargin(in: scene.view) - Self.healthBarDropBelowHUD
        )
    }

    func removeHealthBarFromScene() {
        if healthBar.parent != nil {
            healthBar.removeFromParent()
        }
    }

    /// Whether the health bar is currently in the scene, for `jetshotTests`.
    ///
    /// The bar is attached and detached independently of the boss node — `die()`
    /// drops it the instant the boss dies, well before the explosion sequence removes
    /// the boss itself — so "is the boss on screen" does not answer this.
    var isHealthBarAttached: Bool {
        return healthBar.parent != nil
    }

    /// The health bar's Y in scene coordinates, for `jetshotTests`.
    var healthBarY: CGFloat {
        return healthBar.position.y
    }

    // MARK: - Entrance and flight

    func enterScene(completion: @escaping () -> Void) {
        guard let scene = self.scene else { return }

        // Station height: right under the health bar, whatever the boss's size, so the
        // big ones do not hang down into the ship's half of the screen and the small
        // ones do not hover far below their own name.
        let topMargin = GameConfiguration.topMargin(in: scene.view)
        let targetY = scene.size.height - topMargin - Self.healthBarDropBelowHUD - 22 - config.size * 0.48

        // Margin is the boss's *half* width, not `config.size`: `config.size` is the
        // full silhouette, and insetting each edge by all of it collapsed the sweep of
        // the late bosses to nothing. Clamped so a boss wider than the screen centres
        // instead of inverting.
        let margin = config.size * 0.5 + 8
        let centre = scene.size.width / 2
        arena = (minX: min(margin, centre), maxX: max(scene.size.width - margin, centre), baseY: targetY)

        // The hull is lit by a scan line running down it as it arrives.
        let reveal = SKAction.customAction(withDuration: 1.6) { node, elapsed in
            (node as? Boss)?.look.reveal = Float(elapsed / 1.6)
        }
        run(reveal, withKey: "bossReveal")

        let moveIn = SKAction.moveTo(y: targetY, duration: 2.0)
        moveIn.timingMode = .easeOut

        // Weak, like the explosion closures in die(): SpriteKit holds the action
        // on this node, so a strong capture makes node -> action -> closure -> node.
        run(moveIn) { [weak self] in
            guard let self = self else { return }
            self.look.reveal = 1
            self.isActive = true
            self.startFlight()
            completion()
        }
    }

    private func startFlight() {
        flightClock = 0
        lastFlightElapsed = 0
        previousX = position.x
        station = 2
        stationTimer = 0
        // Ease onto the path from wherever the entrance left the boss. Several paths do
        // not start at the station height — the serpent's figure of eight is 40 points
        // below it — and taking the first point literally was a visible jump.
        blendFrom = position
        blend = 0
        run(.repeatForever(.customAction(withDuration: 60) { node, elapsed in
            (node as? Boss)?.flightTick(elapsed: elapsed)
        }), withKey: "bossFlight")
    }

    private func flightTick(elapsed: CGFloat) {
        var dt = TimeInterval(elapsed - lastFlightElapsed)
        if elapsed < lastFlightElapsed { dt = TimeInterval(elapsed) }
        lastFlightElapsed = elapsed
        dt = min(max(dt, 0), 0.1)

        if config.archetype == .serpent { recordWake() }

        // Lean into the direction of travel.
        let vx = dt > 0 ? (position.x - previousX) / CGFloat(dt) : 0
        previousX = position.x
        let lean = Float(max(-0.5, min(0.5, -vx * 0.004)))
        look.bank += (lean - look.bank) * Float(min(1, dt * 6))

        guard !isManoeuvring else { return }
        flightClock += dt
        var target = flightTarget(dt: dt)
        if blend < 1, let from = blendFrom {
            blend = min(1, blend + CGFloat(dt / 0.6))
            let e = blend * blend * (3 - 2 * blend)
            target = CGPoint(x: from.x + (target.x - from.x) * e, y: from.y + (target.y - from.y) * e)
        }
        position = target
    }

    /// Where the flight path puts the boss now. Every style stays at or below the
    /// station height, so nothing ever rises into the health bar.
    private func flightTarget(dt: TimeInterval) -> CGPoint {
        let cx = (arena.minX + arena.maxX) / 2
        let range = (arena.maxX - arena.minX) / 2
        let leg = max(0.6, config.movementSpeed)
        let t = flightClock
        let y0 = arena.baseY

        switch config.archetype.flight {
        case .patrol:
            let w = Double.pi / leg
            return CGPoint(x: cx + range * CGFloat(sin(w * t)), y: y0 - 5 + 5 * CGFloat(sin(t * 1.3)))
        case .weave:
            let w = Double.pi / leg
            return CGPoint(x: cx + range * CGFloat(sin(w * t)), y: y0 - 16 + 16 * CGFloat(cos(2 * w * t)))
        case .orbit:
            let w = Double.pi / (leg * 1.6)
            return CGPoint(x: cx + range * CGFloat(sin(w * t)), y: y0 - 22 + 22 * CGFloat(cos(2 * w * t)))
        case .drift:
            let w = Double.pi / (leg * 1.3)
            return CGPoint(x: cx + range * 0.8 * CGFloat(sin(w * t)), y: y0 - 10 + 10 * CGFloat(sin(t * 0.8)))
        case .snake:
            // A figure of eight: at each end of the sweep the head is still moving
            // vertically, so the body behind it loops round instead of folding back
            // onto itself.
            let w = Double.pi / leg
            return CGPoint(x: cx + range * CGFloat(sin(w * t)), y: y0 - 40 + 40 * CGFloat(sin(2 * w * t)))
        case .haunt:
            let w = Double.pi / (leg * 1.4)
            return CGPoint(x: cx + range * 0.75 * CGFloat(sin(w * t)), y: y0 - 14 + 14 * CGFloat(sin(t * 1.7)))
        case .shift:
            return shiftTarget(dt: dt)
        }
    }

    /// The stations the tesseract snaps between, left to right.
    private var stations: [CGFloat] {
        let count = arena.maxX - arena.minX > 120 ? 5 : 3
        return (0..<count).map { arena.minX + (arena.maxX - arena.minX) * CGFloat($0) / CGFloat(count - 1) }
    }

    /// Where the tesseract holds at station `index`: alternate stations sit a little lower.
    private func stationPoint(_ index: Int, of stops: [CGFloat]) -> CGPoint {
        CGPoint(x: stops[index], y: arena.baseY - (index % 2 == 0 ? 0 : 18))
    }

    private func shiftTarget(dt: TimeInterval) -> CGPoint {
        let stops = stations
        station = min(max(station, 0), stops.count - 1)
        stationTimer += dt

        if let slide = slide {
            let f = CGFloat(min(1, stationTimer / 0.32))
            let e = f * f * (3 - 2 * f)
            if f >= 1 {
                self.slide = nil
                stationTimer = 0
            }
            return CGPoint(x: slide.from.x + (slide.to.x - slide.from.x) * e,
                           y: slide.from.y + (slide.to.y - slide.from.y) * e)
        }
        let hold = max(0.9, 1.6 - 0.12 * Double(config.tier))
        if stationTimer >= hold {
            var next = Int.random(in: 0..<stops.count)
            if next == station { next = (next + 2) % stops.count }
            let from = position
            slide = (from: from, to: stationPoint(next, of: stops))
            station = next
            stationTimer = 0
            return from
        }
        return stationPoint(station, of: stops)
    }

    /// A station for the tesseract to fold across to: away from where it is.
    func distantStation() -> CGPoint {
        let stops = stations
        let far = stops.indices.filter { abs(stops[$0] - position.x) > (arena.maxX - arena.minX) * 0.3 }
        let index = far.randomElement() ?? (station + 2) % stops.count
        return stationPoint(index, of: stops)
    }

    /// Hands the controls to an attack.
    func beginManoeuvre() {
        isManoeuvring = true
        removeAction(forKey: "bossManoeuvre")
    }

    /// Takes the controls back after an attack has moved the boss, picking the flight
    /// path up from wherever it was left rather than snapping back to where it was.
    func endManoeuvre() {
        guard isManoeuvring else { return }
        isManoeuvring = false
        let cx = (arena.minX + arena.maxX) / 2
        let range = max(1, (arena.maxX - arena.minX) / 2)
        let leg = max(0.6, config.movementSpeed)
        let share = Double(max(-1, min(1, (position.x - cx) / range)))
        switch config.archetype.flight {
        case .patrol, .weave, .snake:
            flightClock = asin(share) / (Double.pi / leg)
        case .orbit:
            flightClock = asin(share) / (Double.pi / (leg * 1.6))
        case .drift:
            flightClock = asin(max(-1, min(1, share / 0.8))) / (Double.pi / (leg * 1.3))
        case .haunt:
            flightClock = asin(max(-1, min(1, share / 0.75))) / (Double.pi / (leg * 1.4))
        case .shift:
            let stops = stations
            station = stops.indices.min { abs(stops[$0] - position.x) < abs(stops[$1] - position.x) } ?? 0
            stationTimer = 0
            slide = nil
        }
        blendFrom = position
        blend = 0
    }

    /// Undoes whatever an interrupted attack left half-done: the controls, a fade, a
    /// sweep, a parked hit volume.
    func cancelManoeuvre() {
        removeAction(forKey: "bossManoeuvre")
        removeAction(forKey: "bossCharge")
        removeAction(forKey: "bossSpin")
        look.fade = 1
        look.sweep = 0
        look.spin = 1
        look.charge = 0
        setTangible(true)
        endManoeuvre()
    }

    /// Takes the core's hit volume away while the boss is out of phase, and puts it back.
    func setTangible(_ tangible: Bool) {
        if tangible {
            if let body = parkedBody, physicsBody == nil { physicsBody = body }
            parkedBody = nil
        } else if let body = physicsBody {
            parkedBody = body
            physicsBody = nil
        }
    }

    // MARK: - Serpent

    private func recordWake() {
        if let last = wake.last, hypot(last.x - position.x, last.y - position.y) < 2 { return }
        wake.append(position)
        if wake.count > 700 { wake.removeFirst(wake.count - 700) }
    }

    /// Each segment's offset from the head, spaced along the path the head has flown.
    private func trailOffsets() -> [CGPoint] {
        let count = look.partAlive.count
        let spacing = config.size / 2 * 0.62
        var result: [CGPoint] = []
        result.reserveCapacity(count)
        var goal = spacing
        var travelled: CGFloat = 0
        var previous = position
        var i = wake.count - 1
        while result.count < count {
            if i >= 0 {
                let p = wake[i]
                let d = hypot(p.x - previous.x, p.y - previous.y)
                if travelled + d >= goal, d > 0 {
                    let f = (goal - travelled) / d
                    result.append(CGPoint(x: previous.x + (p.x - previous.x) * f - position.x,
                                          y: previous.y + (p.y - previous.y) * f - position.y))
                    goal += spacing
                    continue
                }
                travelled += d
                previous = p
                i -= 1
            } else {
                let last = result.last ?? .zero
                result.append(CGPoint(x: last.x, y: last.y + spacing))
            }
        }
        return result
    }

    // MARK: - Fighting

    /// Takes a hit; true if it was the one that killed the boss.
    ///
    /// A boss that is not fightable — still flying in, or already dead — takes nothing.
    /// That used to be left to every caller to check, and a caller that forgot would have
    /// run `die()` a second time and been told "defeated" again: the bounty paid twice
    /// and the explosion sequence restarted over the first.
    func takeDamage(amount: Int = 1) -> Bool {
        guard isAlive() else { return false }
        currentHealth -= max(1, amount)

        if currentHealth <= 0 {
            currentHealth = 0
            isActive = false
            die()
            return true
        }

        // Update health bar only if boss is still alive
        let healthPercent = CGFloat(currentHealth) / CGFloat(maxHealthPoints)
        guard scene != nil else { return false }
        let newSize = CGSize(width: healthFillWidth * healthPercent, height: 16)

        healthBarFill.path = CGPath(
            roundedRect: CGRect(x: -newSize.width / 2, y: -newSize.height / 2, width: newSize.width, height: newSize.height),
            cornerWidth: min(2, newSize.width / 2),
            cornerHeight: 2,
            transform: nil
        )
        healthBarFill.fillColor = Self.gaugeColor(for: healthPercent)

        let now = CACurrentMediaTime()
        guard now - lastHitDressing >= Self.hitDressingInterval else { return false }
        lastHitDressing = now

        // Armour taking a round goes white hot for a moment.
        look.hitFlash = 1
        applyDamageVisuals(healthPercent: healthPercent)

        // No sound here: `GameScene` plays the boss-hit cue for the same impact.
        return false
    }

    /// A round landing on a part. Returns true if it destroyed the part. The boss's own
    /// health is taken separately, by `takeDamage(amount:)`.
    func damagePart(_ part: BossPart, amount: Int) -> Bool {
        guard part.boss === self, isActive, part.absorb(amount) else { return false }
        guard part.index < look.partAlive.count else { return true }
        look.partAlive[part.index] = false
        partExplosion(at: toContent(part.position))
        return true
    }

    private func partExplosion(at point: CGPoint) {
        guard let scene = scene as? GameScene, let content = scene.gameContentNode else { return }
        let multiplier = GameConfiguration.particleMultiplier(for: UIDevice.current.userInterfaceIdiom)
        let burst = ExplosionFX.burst(size: .large, particleMultiplier: multiplier, tint: config.palette.accent)
        burst.position = point
        content.addChild(burst)
        let ring = LightRing.wave(from: 6, to: config.size * 0.7, width: 2, color: config.palette.accent, duration: 0.45)
        ring.position = point
        ring.zPosition = 510
        content.addChild(ring)
        splinters(at: point, count: 6, reach: 90)
        SoundManager.shared.playExplosionSound(on: scene)
        HapticManager.shared.heavyTap()
        hull.removeAction(forKey: "bossPhaseFlash")
        hull.run(.sequence([.scale(to: 1.06, duration: 0.06), .scale(to: 1.0, duration: 0.18)]), withKey: "bossPhaseFlash")
    }

    private func die() {
        removeAllActions()
        isManoeuvring = true
        // Killed mid-blink or mid-fold, it must still be seen to come apart.
        look.charge = 0
        look.fade = 1
        look.sweep = 0
        look.spin = 1
        healthBar.removeFromParent()
        for part in parts { part.physicsBody = nil }

        // The hull comes apart over the length of the explosions.
        run(.customAction(withDuration: 1.7) { node, elapsed in
            (node as? Boss)?.look.dying = Float(elapsed / 1.7)
        }, withKey: "bossDying")

        var explosionActions: [SKAction] = []
        let explosionCount = 8
        for i in 0..<explosionCount {
            let explode = SKAction.run { [weak self] in
                guard let self = self else { return }
                let spread = self.config.size / 2
                self.createExplosion(offset: CGPoint(x: CGFloat.random(in: -spread...spread),
                                                     y: CGFloat.random(in: -spread...spread)))
                if let scene = self.scene as? GameScene {
                    SoundManager.shared.playExplosionSound(on: scene)
                }
            }
            if i > 0 { explosionActions.append(.wait(forDuration: 0.2)) }
            explosionActions.append(explode)
        }

        let finalExplosion = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.createExplosion(offset: .zero, isLarge: true)
            self.removeHealthBarFromScene()
            if let scene = self.scene as? GameScene {
                SoundManager.shared.playExplosionSound(on: scene)
            }
        }

        // Additional explosion sounds using SKAction to respect pause state
        for (delay, key) in [(0.1, "bossExplosionSound2"), (0.2, "bossExplosionSound3")] {
            run(.sequence([.wait(forDuration: delay), .run { [weak self] in
                if let scene = self?.scene as? GameScene {
                    SoundManager.shared.playExplosionSound(on: scene)
                }
            }]), withKey: key)
        }

        explosionActions.append(.wait(forDuration: 0.2))
        explosionActions.append(finalExplosion)
        explosionActions.append(.fadeOut(withDuration: 0.5))
        explosionActions.append(.removeFromParent())
        run(.sequence(explosionActions), withKey: "bossDefeat")
    }

    private func createExplosion(offset: CGPoint, isLarge: Bool = false) {
        guard let scene = self.scene as? GameScene, let content = scene.gameContentNode else { return }
        let multiplier = GameConfiguration.particleMultiplier(for: UIDevice.current.userInterfaceIdiom)
        let tint = isLarge ? StoryPalette.sun : (Bool.random() ? config.palette.hull : config.palette.accent)
        let burst = ExplosionFX.burst(size: isLarge ? .huge : .large, particleMultiplier: multiplier, tint: tint)
        burst.position = CGPoint(x: position.x + offset.x, y: position.y + offset.y)
        content.addChild(burst)
        splinters(at: burst.position, count: isLarge ? 12 : 5, reach: isLarge ? 220 : 120)

        if isLarge {
            HapticManager.shared.heavyTap()
        } else {
            HapticManager.shared.mediumTap()
        }
    }

    func getPoints() -> Int {
        return config.points
    }

    func isAlive() -> Bool {
        return isActive && currentHealth > 0
    }

    /// Remaining health as a fraction of the boss's maximum, 0...1.
    var healthFraction: CGFloat {
        guard maxHealthPoints > 0 else { return 0 }
        return CGFloat(currentHealth) / CGFloat(maxHealthPoints)
    }

    /// Which act of the fight the boss is currently in. See `BossPhaseRules`.
    var currentPhase: Int {
        return BossPhaseRules.phase(forHealthFraction: healthFraction)
    }

    /// The attacks available to the boss right now: those of the acts its current
    /// health has reached.
    func availableAttackPatterns() -> [BossAttackPattern] {
        let count = BossPhaseRules.patternCount(forPhase: currentPhase, acts: config.patternActs)
        return Array(config.attackPatterns.prefix(count))
    }

    /// The boss's own size and accent colour, for effects `BossManager` and
    /// `GameScene` build around it.
    var bossSize: CGFloat { config.size }
    var telegraphColor: UIColor { config.palette.accent }

    /// The wind-up: the hull swells and every muzzle gathers light.
    func windUp(duration: TimeInterval) {
        hull.removeAction(forKey: "bossTelegraph")
        hull.run(.sequence([
            .scale(to: 1.06, duration: duration * 0.75),
            .scale(to: 1.0, duration: duration * 0.25)
        ]), withKey: "bossTelegraph")
        run(.sequence([
            .customAction(withDuration: duration) { node, elapsed in
                (node as? Boss)?.look.charge = Float(elapsed / CGFloat(max(0.01, duration)))
            },
            .customAction(withDuration: 0.3) { node, elapsed in
                (node as? Boss)?.look.charge = Float(1 - elapsed / 0.3)
            }
        ]), withKey: "bossCharge")
    }

    func cancelWindUp() {
        hull.removeAction(forKey: "bossTelegraph")
        hull.setScale(1)
        removeAction(forKey: "bossCharge")
        look.charge = 0
    }

    /// Marks a phase change on the boss itself: a lurch outward, the hull flaring white,
    /// and a ring of light thrown off it.
    ///
    /// Loud on purpose. The transition is the one moment in a fight that tells the player
    /// they are actually getting somewhere.
    func playPhaseTransitionEffect() {
        hull.removeAction(forKey: "bossPhaseFlash")
        hull.run(.sequence([
            .scale(to: 1.18, duration: 0.14),
            .scale(to: 1.0, duration: 0.22)
        ]), withKey: "bossPhaseFlash")
        look.hitFlash = 1

        for (i, color) in [config.palette.accent, config.palette.hull].enumerated() {
            let ring = LightRing.wave(from: config.size * 0.4, to: config.size * (1.3 + CGFloat(i) * 0.4),
                                      width: 3 - CGFloat(i), color: color, duration: 0.5 + Double(i) * 0.15)
            ring.zPosition = -1
            addChild(ring)
        }
    }

    // MARK: - Damage visuals

    private func applyDamageVisuals(healthPercent: CGFloat) {
        let newDamageLevel = healthPercent > 0.66 ? 0 : (healthPercent > 0.33 ? 1 : 2)
        if newDamageLevel > damageLevel {
            damageLevel = newDamageLevel
            createSmokeTrail(isHeavy: damageLevel == 2)
            splinters(at: position, count: damageLevel == 2 ? 10 : 6, reach: config.size)
            HapticManager.shared.mediumTap()
        }

        if Int.random(in: 0...2) == 0 {
            splinters(at: CGPoint(x: position.x + CGFloat.random(in: -config.size / 3...config.size / 3),
                                  y: position.y + CGFloat.random(in: -config.size / 3...config.size / 3)),
                      count: Int.random(in: 1...3), reach: 70)
        }
        applyImpactShake()
        createSparks()
    }

    private func applyImpactShake() {
        guard hull.action(forKey: "hitShake") == nil else { return }
        hull.run(.sequence([
            .moveBy(x: 3, y: 2, duration: 0.05),
            .moveBy(x: -6, y: -4, duration: 0.05),
            .moveBy(x: 3, y: 2, duration: 0.05)
        ]), withKey: "hitShake")
    }

    /// Splinters of the wireframe flying off: short lines of the hull's light, tumbling
    /// and fading. `gameContentNode`, so they freeze with the pause menu.
    private func splinters(at point: CGPoint, count: Int, reach: CGFloat) {
        guard let scene = scene as? GameScene, let content = scene.gameContentNode else { return }
        for _ in 0..<count {
            let length = CGFloat.random(in: 6...16)
            let color = Bool.random() ? config.palette.hull : config.palette.accent
            let splinter = LightSprite.tube(from: CGPoint(x: -length / 2, y: 0), to: CGPoint(x: length / 2, y: 0),
                                            width: 1.2, color: color)
            splinter.position = point
            splinter.zRotation = CGFloat.random(in: 0...(.pi * 2))
            splinter.zPosition = zPosition + 1
            content.addChild(splinter)

            let angle = CGFloat.random(in: 0...(.pi * 2))
            let distance = CGFloat.random(in: reach * 0.4...reach)
            let duration = Double.random(in: 0.6...1.1)
            let fly = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: duration)
            fly.timingMode = .easeOut
            splinter.run(.sequence([
                .group([fly, .rotate(byAngle: .pi * CGFloat.random(in: 2...5), duration: duration),
                        .fadeOut(withDuration: duration)]),
                .removeFromParent()
            ]))
        }
    }

    private func createSmokeTrail(isHeavy: Bool = false) {
        guard let scene = self.scene as? GameScene else { return }

        let smoke = SKEmitterNode()
        smoke.position = position
        smoke.zPosition = zPosition - 1
        smoke.particleTexture = ParticleTexture.softCircle(diameter: 32)
        smoke.particleBirthRate = isHeavy ? 40 : 20
        smoke.numParticlesToEmit = isHeavy ? 30 : 15
        smoke.particleLifetime = 1.5
        smoke.particleLifetimeRange = 0.5
        smoke.particleScale = 0.3
        smoke.particleScaleRange = 0.1
        smoke.particleScaleSpeed = 0.2
        smoke.particleColor = UIColor(white: 0.35, alpha: 1)
        smoke.particleColorBlendFactor = 1.0
        smoke.particleAlpha = 0.5
        smoke.particleAlphaSpeed = -0.35
        smoke.emissionAngle = .pi / 2
        smoke.emissionAngleRange = .pi / 4
        smoke.particleSpeed = 30
        smoke.particleSpeedRange = 20
        smoke.yAcceleration = 20

        scene.gameContentNode.addChild(smoke)
        smoke.run(.sequence([.wait(forDuration: 2.0), .removeFromParent()]))
    }

    private func createSparks() {
        guard let scene = self.scene as? GameScene else { return }

        let sparks = SKEmitterNode()
        let sparkX = position.x + CGFloat.random(in: -config.size / 2...config.size / 2)
        let sparkY = position.y + CGFloat.random(in: -config.size / 2...config.size / 2)
        sparks.position = CGPoint(x: sparkX, y: sparkY)
        sparks.zPosition = zPosition + 1
        sparks.particleTexture = ParticleTexture.softCircle(diameter: 32)
        sparks.particleBirthRate = 200
        sparks.numParticlesToEmit = 10
        sparks.particleLifetime = 0.3
        sparks.particleLifetimeRange = 0.1
        sparks.particleScale = 0.08
        sparks.particleScaleRange = 0.04
        sparks.particleScaleSpeed = -0.2
        sparks.particleColor = StoryPalette.mix(config.palette.accent, .white, 0.4)
        sparks.particleColorBlendFactor = 1.0
        sparks.particleAlpha = 1.0
        sparks.particleAlphaSpeed = -3.0
        sparks.emissionAngle = 0
        sparks.emissionAngleRange = .pi * 2
        sparks.particleSpeed = 80
        sparks.particleSpeedRange = 40
        sparks.yAcceleration = -150
        sparks.particleBlendMode = .add

        scene.gameContentNode.addChild(sparks)
        sparks.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
    }
}
