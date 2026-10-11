//
//  Player.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import SpriteKit
import simd

/// Player spaceship with movement, shooting, and power-up capabilities.
/// Handles visual effects, animations, and power-up state management.
class Player: SKShapeNode {

    // Configuration
    private let moveSpeed: TimeInterval = GameConfiguration.playerMoveSpeed

    // PowerUp properties
    var bulletCount: Int = 1 {
        didSet {
            bulletCount = min(bulletCount, GameConfiguration.maxBulletCount)
        }
    }
    var sideMissileCount: Int = 0 {
        didSet {
            sideMissileCount = min(sideMissileCount, GameConfiguration.maxSideMissileCount)
            updateSideMissiles()
        }
    }
    var hasShield: Bool = false {
        didSet {
            updateShieldVisuals()
        }
    }
    var hasLightningWeapon: Bool = false {
        didSet {
            updateLightningVisuals()
        }
    }
    var hasRapidFire: Bool = false
    var hasMagnet: Bool = false
    var hasSlowMotion: Bool = false
    var hasScoreMultiplier: Bool = false
    var hasBarrier: Bool = false {
        didSet {
            updateBarrierVisuals()
        }
    }
    private var shieldNode: SKShapeNode?
    private var sideMissileNodes: [SKShapeNode] = []
    private var lightningIndicators: [SKShapeNode] = []
    private var barrierNodes: [SKShapeNode] = []

    // Hitbox

    /// Radius of the vulnerable core. See the note in `setupPlayer`.
    nonisolated static let hitboxRadius: CGFloat = 5.5
    /// Where the core sits on the hull: the centre of the fuselage, just under the
    /// cockpit glass.
    nonisolated static let hitboxCenter = CGPoint(x: 0, y: 1)
    /// Reach of the pickup collector.
    nonisolated static let collectorRadius: CGFloat = 26

    private var hitboxMarker: SKNode?
    private var dangerShown = false

    /// Lights the core marker while hostile fire is close, and dims it after.
    func setDangerProximity(_ near: Bool) {
        guard near != dangerShown, let marker = hitboxMarker else { return }
        dangerShown = near
        marker.removeAllActions()
        marker.run(.fadeAlpha(to: near ? 1.0 : 0.0, duration: near ? 0.08 : 0.35))
    }

    /// The gold corona an active Overdrive wraps the ship in.
    func setOverdriveAura(_ on: Bool) {
        childNode(withName: "overdriveAura")?.removeFromParent()
        guard on else { return }

        let aura = SKNode()
        aura.name = "overdriveAura"
        aura.zPosition = -4
        addChild(aura)

        let gold = ProjectileFX.overdriveBolt
        // Kept dim: it sits under the hull, and a bright one washes the ship itself out
        // at exactly the moment the player most needs to see where it is.
        let glow = NeonFX.radialGlow(radius: 40, color: gold, softness: 0.7)
        glow.alpha = 0.28
        aura.addChild(glow)
        glow.run(.repeatForever(.sequence([
            .group([.scale(to: 1.12, duration: 0.18), .fadeAlpha(to: 0.38, duration: 0.18)]),
            .group([.scale(to: 0.96, duration: 0.18), .fadeAlpha(to: 0.24, duration: 0.18)])
        ])))

        // Gyroscope rings wheeling round the hull on three axes, the way the film draws
        // the epicentre's field: reads as a field, not a halo, and makes the state
        // readable at a glance in a busy screen.
        let gyro = WireBody(extent: 34, perspective: 4) { frame in
            let axes = [Vec3(1, 0.25, 0), Vec3(0.2, 1, 0.3), Vec3(0.4, -0.3, 1)]
            for (i, axis) in axes.enumerated() {
                let q = rotation(frame.t * (2.4 + Float(i) * 0.9) * (i == 1 ? -1 : 1), axis)
                let (u, v) = StoryScenery.basis(q.act(simd_normalize(axis)))
                StoryScenery.dashedRing(frame.canvas, center: .zero, radius: 25 + Float(i) * 3.5, u: u, v: v,
                                        phase: frame.t * 3, dashes: 5, fill: 0.55,
                                        color: i == 1 ? StoryPalette.white : gold, alpha: 0.85, width: 1.3)
            }
        }
        aura.addChild(gyro)

        aura.setScale(0.4)
        aura.alpha = 0
        aura.run(.group([.scale(to: 1, duration: 0.2), .fadeIn(withDuration: 0.2)]))
    }

    // Flight feel
    private var previousX: CGFloat = 0
    private var bankAngle: CGFloat = 0
    private var enginePlumes: [SKSpriteNode] = []
    /// Frames since the last movement command, so the roll can level out when
    /// the player stops dragging (touchesMoved simply stops firing).
    private var framesSinceMove: Int = 0

    init(sceneSize: CGSize, safeAreaBottom: CGFloat = 0) {
        super.init()

        setupPlayer(sceneSize: sceneSize, safeAreaBottom: safeAreaBottom)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Deliberately does not stop actions.
        //
        // This used to walk the subtree calling `removeAllActions()`. Both pointless and
        // unsound: the player and its children are being deallocated, so SpriteKit
        // discards their action lists regardless, and `deinit` is nonisolated while
        // SKNode's methods are main-actor isolated under this project's default
        // isolation — an error in the Swift 6 language mode. GameScene.willMove(from:)
        // already sweeps the live tree before teardown, which is the point where
        // stopping repeating actions actually matters.

        // The shared particle texture is deliberately *not* dropped here. It used to
        // be, with a comment claiming it only happened for the last Player instance —
        // which the code never checked. During a scene transition the outgoing
        // player's deinit runs after the incoming scene has built its own player, so
        // clearing the cache just threw away a texture that was needed again
        // immediately. Memory pressure is handled by handleMemoryWarning() instead,
        // which now clears `ParticleTexture` — the one cache every emitter shares.
    }

    private func setupPlayer(sceneSize: CGSize, safeAreaBottom: CGFloat) {
        // Create detailed spaceship body with wings
        let path = CGMutablePath()

        // Main fuselage (center)
        path.move(to: CGPoint(x: 0, y: 18))          // Nose
        path.addLine(to: CGPoint(x: -5, y: 8))       // Upper left fuselage
        path.addLine(to: CGPoint(x: -4, y: -2))      // Lower left fuselage

        // Left wing
        path.addLine(to: CGPoint(x: -12, y: -8))     // Left wing tip
        path.addLine(to: CGPoint(x: -10, y: -12))    // Left wing back
        path.addLine(to: CGPoint(x: -5, y: -10))     // Left wing inner

        // Back left engine
        path.addLine(to: CGPoint(x: -6, y: -18))     // Left engine bottom
        path.addLine(to: CGPoint(x: -3, y: -18))     // Left engine inner
        path.addLine(to: CGPoint(x: -3, y: -10))     // Back to fuselage

        // Center back
        path.addLine(to: CGPoint(x: 0, y: -8))       // Center back top
        path.addLine(to: CGPoint(x: 3, y: -10))      // Right side

        // Back right engine
        path.addLine(to: CGPoint(x: 3, y: -18))      // Right engine inner
        path.addLine(to: CGPoint(x: 6, y: -18))      // Right engine bottom
        path.addLine(to: CGPoint(x: 5, y: -10))      // Right engine outer

        // Right wing
        path.addLine(to: CGPoint(x: 10, y: -12))     // Right wing back
        path.addLine(to: CGPoint(x: 12, y: -8))      // Right wing tip
        path.addLine(to: CGPoint(x: 4, y: -2))       // Right wing inner

        // Right fuselage
        path.addLine(to: CGPoint(x: 5, y: 8))        // Upper right fuselage

        path.closeSubpath()

        self.path = path
        // The hull is drawn in 3D by the wireframe below. The shape itself is only the
        // dark glass under it, which keeps the world's lines from showing through the
        // ship and gives the bloom its silhouette.
        self.fillColor = UIColor(red: 0.01, green: 0.04, blue: 0.09, alpha: 0.82)
        self.strokeColor = UIColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 0.22)
        self.lineWidth = 1

        // Position above safe area (home indicator) with padding
        let playerHeight = safeAreaBottom + GameConfiguration.playerBottomOffset
        self.position = CGPoint(x: sceneSize.width / 2, y: playerHeight)
        self.name = "player"

        // The Singularity-7 itself: the film's wireframe hull, the same mesh the
        // opening shows on its turntable, seen from above and a little behind. It rolls
        // into a turn about its own axis rather than spinning flat on the screen.
        let hull = WireBody(extent: 30, perspective: 4.2) { [weak self] frame in
            self?.drawHull(frame)
        }
        hull.name = "hull3D"
        hull.zPosition = 2
        addChild(hull)

        // Soft additive plumes under the exhaust: the bright column of light that makes
        // the ship look like it is under power.
        for x in [-4.5, 4.5] as [CGFloat] {
            let plume = NeonFX.radialGlow(radius: 10, color: UIColor(red: 0.25, green: 0.85, blue: 1.0, alpha: 1.0))
            plume.position = CGPoint(x: x, y: -21)
            plume.yScale = 1.9
            plume.xScale = 0.62
            plume.zPosition = -3
            addChild(plume)
            enginePlumes.append(plume)

            let flare = SKAction.sequence([
                .group([.scaleY(to: 2.25, duration: 0.09), .fadeAlpha(to: 1.0, duration: 0.09)]),
                .group([.scaleY(to: 1.7, duration: 0.11), .fadeAlpha(to: 0.72, duration: 0.11)])
            ])
            plume.run(.repeatForever(flare))
        }

        previousX = position.x

        // Levels the wings out once the player stops steering: touchesMoved just
        // stops firing, so without this the ship would stay locked in a tilt.
        run(.repeatForever(.customAction(withDuration: 1.0) { [weak self] _, _ in
            guard let self = self else { return }
            self.framesSinceMove += 1
            guard self.framesSinceMove > 2 else { return }
            self.bankAngle *= 0.86
            self.zRotation = self.bankAngle * Self.yawShare
            for plume in self.enginePlumes {
                plume.zRotation = -self.bankAngle * 0.55
            }
        }), withKey: "bankLevelling")

        // Setup physics body: the core, not the hull.
        //
        // The whole ship polygon used to be the hitbox, so a round that clipped a wing
        // tip — visibly off the cockpit — still cost a life. Shmups converged long ago
        // on a small core that is drawn on the ship, which is what makes dense fire
        // fair to weave through and what makes grazing (see `GrazeRules`) possible at
        // all. The generous collector below keeps pickups as easy to grab as before.
        let core = SKPhysicsBody(circleOfRadius: Self.hitboxRadius, center: Self.hitboxCenter)
        core.isDynamic = true
        core.categoryBitMask = PhysicsCategory.player
        core.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.enemyBullet | PhysicsCategory.obstacle
        core.collisionBitMask = PhysicsCategory.none
        core.usesPreciseCollisionDetection = true
        self.physicsBody = core

        // Pickup collector: coins and power-ups test against this, never the core.
        let collector = SKNode()
        collector.name = "collector"
        let collectorBody = SKPhysicsBody(circleOfRadius: Self.collectorRadius)
        collectorBody.isDynamic = true
        collectorBody.affectedByGravity = false
        collectorBody.categoryBitMask = PhysicsCategory.collector
        collectorBody.contactTestBitMask = PhysicsCategory.coin | PhysicsCategory.powerUp
        collectorBody.collisionBitMask = PhysicsCategory.none
        collector.physicsBody = collectorBody
        addChild(collector)

        // The core, drawn: a white dot in a thin ring. Quiet until hostile fire is
        // near, then lit (see `setDangerProximity`), so it is there when the player is
        // threading rounds and out of the way when they are not.
        let marker = SKNode()
        marker.position = Self.hitboxCenter
        marker.zPosition = 6
        let ring = SKShapeNode(circleOfRadius: Self.hitboxRadius + 1)
        ring.strokeColor = UIColor(red: 1.0, green: 0.55, blue: 0.8, alpha: 1.0)
        ring.fillColor = UIColor(white: 0, alpha: 0.35)
        ring.lineWidth = 1.4
        marker.addChild(ring)
        let dot = SKShapeNode(circleOfRadius: 2.2)
        dot.fillColor = .white
        dot.strokeColor = .clear
        marker.addChild(dot)
        marker.alpha = 0.0
        addChild(marker)
        hitboxMarker = marker

        // A soft breathing halo behind the wireframe.
        GlowHelper.addPulsingEnhancedGlow(to: self, color: UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1.0), minIntensity: 0.4, maxIntensity: 0.6, duration: 1.2)
    }

    /// How much of the bank shows as a flat turn of the sprite; the rest is the hull's
    /// 3D roll. A little yaw keeps the nose pointing into the turn.
    private static let yawShare: CGFloat = 0.3

    /// Fraction of a second since the last shot, for the engines' kick.
    private var recoilGlow: Float = 0

    /// The film's hull without its nacelle rings: at gameplay size those forty edges
    /// merge into a white blur over the engines.
    private static let hullMesh: WireMesh = {
        let full = WireMesh.ship
        // Outline top and bottom (36 vertices) and the canopy (5) come first; the
        // nacelle rings are everything after.
        let nacelles = 41
        return WireMesh(vertices: full.vertices, edges: full.edges.filter { $0.0 < nacelles && $0.1 < nacelles })
    }()

    private static let hullColor = UIColor(red: 0.55, green: 0.93, blue: 1.0, alpha: 1)

    private func drawHull(_ frame: WireBody.Frame) {
        let c = frame.canvas
        let t = frame.t
        // Lie the film's mesh (forward -Z, up +Y) flat on the screen with the nose up,
        // tip it back so the camera sits above and behind, then roll it.
        let tilt = rotation(.pi / 2 - 0.42, Vec3(1, 0, 0))
        let q = tilt * rotation(Float(bankAngle) * 1.9, Vec3(0, 0, 1))
        let centre = Vec3(0, 1, 0)
        let scale: Float = 1.08
        c.mesh(Self.hullMesh, at: centre, rotation: q, scale: scale, color: Self.hullColor, alpha: 0.95,
               width: 1.05, backAlpha: 0.3)

        recoilGlow = max(0, recoilGlow - 0.08)
        let engine: Float = 0.85 + recoilGlow
        let back = q.act(Vec3(0, 0, 1))
        for (i, nozzle) in WireMesh.shipNozzles.enumerated() {
            let p = centre + q.act(nozzle * scale)
            let flicker = 0.85 + 0.15 * sin(t * 47 + Float(i) * 2.1)
            c.glow(p, radius: 5.5 * engine * flicker, color: StoryPalette.cyan, alpha: 0.9)
            c.glow(p, radius: 2.3 * engine, color: StoryPalette.white, alpha: 1)
            // Exhaust: a fan of lines trailing from the nozzle, lengths flickering.
            for k in 0..<4 {
                let a = Float(k) / 4 * 2 * .pi + t * 9
                let side = q.act(Vec3(cos(a), sin(a), 0)) * 0.9
                let length = (9 + 5 * sin(t * 31 + Float(k * 3 + i))) * engine
                c.line(p + side, p + back * length, color: StoryPalette.blue, alpha: 0.55 * engine, width: 1)
            }
        }
    }

    func moveTo(x: CGFloat, y: CGFloat, sceneWidth: CGFloat, sceneHeight: CGFloat, safeAreaBottom: CGFloat) {
        // Clamp X position to screen bounds
        let targetX = max(10, min(sceneWidth - 10, x))

        // Offset so the player appears above the thumb
        let touchYOffset: CGFloat = 50

        // Allow limited upward movement - player can move up to 50% of screen height
        let minY = safeAreaBottom + 15  // Minimum Y (starting position)
        let maxY = minY + (sceneHeight * 0.5)  // Can move up by 50% of screen height
        let targetY = max(minY, min(maxY, y + touchYOffset))

        // Bank into the jump. Tap-to-move animates the position, so there are no
        // per-frame deltas for `updateBanking` to read; kick the roll here and
        // let the levelling action ease it back out.
        let dx = targetX - position.x
        bankAngle = max(-0.38, min(0.38, -dx * 0.012))
        zRotation = bankAngle * Self.yawShare
        framesSinceMove = 0

        let moveAction = SKAction.move(to: CGPoint(x: targetX, y: targetY), duration: moveSpeed)
        run(moveAction)
        previousX = targetX
    }

    /// Where the ship may fly. Shared by every way of moving it.
    static func flightBounds(sceneWidth: CGFloat, sceneHeight: CGFloat, safeAreaBottom: CGFloat) -> CGRect {
        let minY = safeAreaBottom + 15
        let maxY = minY + sceneHeight * 0.55
        return CGRect(x: 10, y: minY, width: max(0, sceneWidth - 20), height: maxY - minY)
    }

    /// Moves the ship by a drag delta, clamped to the flight area. The relative-drag
    /// path; see `GameScene`'s touch handling.
    func steer(by delta: CGVector, sceneWidth: CGFloat, sceneHeight: CGFloat, safeAreaBottom: CGFloat) {
        let bounds = Self.flightBounds(sceneWidth: sceneWidth, sceneHeight: sceneHeight, safeAreaBottom: safeAreaBottom)
        position.x = min(max(position.x + delta.dx, bounds.minX), bounds.maxX)
        position.y = min(max(position.y + delta.dy, bounds.minY), bounds.maxY)
        updateBanking()
    }

    func moveToInstant(x: CGFloat, y: CGFloat, sceneWidth: CGFloat, sceneHeight: CGFloat, safeAreaBottom: CGFloat) {
        // Clamp X position to screen bounds
        let targetX = max(10, min(sceneWidth - 10, x))

        // Offset so the player appears above the thumb
        let touchYOffset: CGFloat = 50

        // Allow limited upward movement - player can move up to 50% of screen height
        let minY = safeAreaBottom + 15  // Minimum Y (starting position)
        let maxY = minY + (sceneHeight * 0.5)  // Can move up by 50% of screen height
        let targetY = max(minY, min(maxY, y + touchYOffset))

        // Direct position update for smooth dragging
        position.x = targetX
        position.y = targetY

        updateBanking()
    }

    /// Rolls the hull into the turn and leans the engine plumes the other way.
    ///
    /// A fighter that slides sideways without banking is the clearest tell of a
    /// 2D sprite; the roll costs nothing and makes the ship feel like it has mass.
    private func updateBanking() {
        let dx = position.x - previousX
        previousX = position.x
        framesSinceMove = 0

        // Smoothed, so a jittery finger doesn't make the ship twitch.
        let maxBank: CGFloat = 0.38
        let target = max(-maxBank, min(maxBank, -dx * 0.055))
        bankAngle += (target - bankAngle) * 0.25
        zRotation = bankAngle * Self.yawShare

        // Counter-rotate the plumes slightly: thrust keeps pointing more or less
        // down-range while the airframe rolls.
        for plume in enginePlumes {
            plume.zRotation = -bankAngle * 0.55
        }
    }

    /// Brief squash on the hull when a shot goes out. Sub-100ms so it registers
    /// as kick rather than as the ship wobbling.
    func applyRecoil() {
        recoilGlow = 0.35
        removeAction(forKey: "recoil")
        let dip = SKAction.scaleY(to: 0.9, duration: 0.045)
        dip.timingMode = .easeOut
        let back = SKAction.scaleY(to: 1.0, duration: 0.085)
        back.timingMode = .easeOut
        run(.sequence([dip, back]), withKey: "recoil")
    }

    /// One volley: the bolts for every barrel, ready to be flown.
    ///
    /// Each round carries its angle (0 is straight up, positive leans right) in
    /// `zRotation`, so the scene flies it along whatever it is pointing at. With
    /// `overdrive`, every bolt is a gold, double-damage round and two extra bolts fan out
    /// from the nose — the visible difference between the normal guns and the burst the
    /// player saved up for.
    func shoot(overdrive: Bool = false) -> [PlayerRound] {
        var rounds: [PlayerRound] = []

        // Bullets 1-4 shoot straight forward
        let straightBulletCount = min(bulletCount, 4)
        let spacing: CGFloat = 15
        let totalWidth = CGFloat(straightBulletCount - 1) * spacing
        let startX = self.position.x - totalWidth / 2

        for i in 0..<straightBulletCount {
            let round = ProjectileFX.playerRound(overdrive: overdrive)
            round.position = CGPoint(x: startX + CGFloat(i) * spacing, y: self.position.y + 22)
            rounds.append(round)
        }

        // Bullets 5-8 shoot at angles
        var angles: [CGFloat] = []
        if bulletCount > 4 {
            let angledBulletCount = min(bulletCount - 4, 4) // Max 4 angled bullets (5-8)
            angles.append(contentsOf: [15, -15, 25, -25].prefix(angledBulletCount))
        }
        if overdrive {
            angles.append(contentsOf: [8, -8])
        }
        for angle in angles {
            let round = ProjectileFX.playerRound(overdrive: overdrive)
            round.position = CGPoint(x: self.position.x, y: self.position.y + 22)
            round.zRotation = -angle * .pi / 180
            rounds.append(round)
        }

        return rounds
    }

    func shootMissile(side: Int) -> PlayerRound {
        let missile = ProjectileFX.missile(homing: false)
        // Position based on side (-1 for left, 1 for right)
        let offsetX: CGFloat = CGFloat(side) * 20
        missile.position = CGPoint(x: self.position.x + offsetX, y: self.position.y + 20)
        return missile
    }

    private func updateSideMissiles() {
        // Remove old missile visuals efficiently
        for node in sideMissileNodes {
            node.removeFromParent()
        }
        sideMissileNodes.removeAll(keepingCapacity: true)

        // Add new missile visuals
        for i in 0..<sideMissileCount {
            let side = i == 0 ? -1 : 1 // Left first, then right
            let missileVisual = createMissileVisual()
            missileVisual.position = CGPoint(x: CGFloat(side) * 15, y: -8)
            addChild(missileVisual)
            sideMissileNodes.append(missileVisual)
        }
    }

    private func createMissileVisual() -> SKShapeNode {
        // A launcher pod on the wing: dark glass in an amber edge, the warhead lit.
        let missile = SKShapeNode(rectOf: CGSize(width: 4.5, height: 12), cornerRadius: 2.2)
        missile.fillColor = UIColor(red: 0.12, green: 0.04, blue: 0.0, alpha: 0.9)
        missile.strokeColor = UIColor(red: 1.0, green: 0.58, blue: 0.18, alpha: 1.0)
        missile.lineWidth = 1.2
        missile.zPosition = -1

        let warhead = LightSprite.star(size: 9, color: UIColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 1.0))
        warhead.position = CGPoint(x: 0, y: 5)
        missile.addChild(warhead)

        return missile
    }

    private func updateShieldVisuals() {
        if hasShield {
            guard shieldNode == nil else { return }
            let cyan = UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1.0)
            let shieldContainer = SKNode()
            shieldContainer.name = "shieldContainer"
            shieldContainer.zPosition = -1
            addChild(shieldContainer)

            // A geodesic bubble turning round the ship, its far side faint behind the
            // near — the film's wireframe, not a flat ring.
            let sphere = VectorFX3D.createShieldSphere(radius: 35, color: cyan, persistent: true)
            sphere.zPosition = 3
            shieldContainer.addChild(sphere)

            // A faint glass skin and rim, for the bloom and for a silhouette that reads
            // at a glance in a busy screen.
            let shield = SKShapeNode(circleOfRadius: 35)
            shield.fillColor = UIColor(red: 0.0, green: 0.7, blue: 1.0, alpha: 0.06)
            shield.strokeColor = cyan.withAlphaComponent(0.45)
            shield.lineWidth = 1.2
            shield.zPosition = 1
            shieldContainer.addChild(shield)
            shieldNode = shield

            shield.run(.repeatForever(.sequence([.scale(to: 1.05, duration: 0.6), .scale(to: 1.0, duration: 0.6)])))
            GlowHelper.addPulsingEnhancedGlow(to: shield, color: cyan, minIntensity: 0.35, maxIntensity: 0.6, duration: 1.2)

            // Raised with a flash of the bubble expanding through.
            let flash = VectorFX3D.createShieldSphere(radius: 35, color: .white, persistent: false)
            flash.zPosition = 4
            shieldContainer.addChild(flash)
        } else {
            // Remove shield (remove parent container)
            if let container = childNode(withName: "shieldContainer") {
                container.removeFromParent()
            }
            shieldNode?.removeFromParent()
            shieldNode = nil
        }
    }

    func hasAnyPowerUps() -> Bool {
        // Check if player has any powerups (used to determine if we should degrade or lose life)
        return hasShield || hasBarrier || hasLightningWeapon || hasRapidFire ||
               sideMissileCount > 0 || bulletCount > 1 ||
               hasMagnet || hasSlowMotion || hasScoreMultiplier
    }

    func degradePowerUps() {
        // Gradually reduce powerups when player loses a life (instead of removing all at once)

        // Priority system - lose powerups in this order:
        // 1. Temporary powerups (shield, barrier, lightning, rapid fire)
        // 2. Side missiles (reduce by 1)
        // 3. Multi shot (reduce by 1)
        // 4. Other powerups (magnet, slow motion, score multiplier)

        // First, try to remove temporary powerups
        if hasShield {
            hasShield = false
            return
        }

        if hasBarrier {
            hasBarrier = false
            return
        }

        if hasLightningWeapon {
            hasLightningWeapon = false
            return
        }

        if hasRapidFire {
            hasRapidFire = false
            return
        }

        // Next, reduce side missiles
        if sideMissileCount > 0 {
            sideMissileCount -= 1
            return
        }

        // Then reduce multi shot
        if bulletCount > 1 {
            bulletCount -= 1
            return
        }

        // Finally, remove utility powerups
        if hasMagnet {
            hasMagnet = false
            return
        }

        if hasSlowMotion {
            hasSlowMotion = false
            return
        }

        if hasScoreMultiplier {
            hasScoreMultiplier = false
            return
        }

        // If no powerups, nothing to remove
    }

    // No resetPowerUps() here. It had no callers: a life lost goes through
    // degradePowerUps(), and a new level builds a fresh Player from the arsenal
    // GameScene hands it, so there is never a live ship whose power-ups need clearing.

    func updateBounds(sceneSize: CGSize, safeAreaBottom: CGFloat) {
        // Update player position to stay within new bounds
        let playerHeight = safeAreaBottom + GameConfiguration.playerBottomOffset
        let clampedX = max(30, min(sceneSize.width - 30, position.x))
        position = CGPoint(x: clampedX, y: playerHeight)
    }

    private func updateLightningVisuals() {
        // Remove old lightning indicators
        lightningIndicators.forEach { $0.removeFromParent() }
        lightningIndicators.removeAll(keepingCapacity: true)

        if hasLightningWeapon {
            // Add electric arcs around the ship
            for i in 0..<4 {
                let side = i < 2 ? -1.0 : 1.0
                let yPos = i % 2 == 0 ? 5.0 : -5.0

                let arc = createElectricArc()
                arc.position = CGPoint(x: side * 12, y: yPos)
                arc.zPosition = 2
                addChild(arc)
                lightningIndicators.append(arc)

                // Pulsing animation
                let pulse = SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.5, duration: 0.15),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.15)
                ])
                arc.run(SKAction.repeatForever(pulse))

                // Add glow
                GlowHelper.addEnhancedGlow(
                    to: arc,
                    color: UIColor(red: 0.7, green: 0.4, blue: 1.0, alpha: 1.0),
                    intensity: 1.2
                )
            }
        }
    }

    private func createElectricArc() -> SKShapeNode {
        // Create small electric arc visual
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -3))
        path.addLine(to: CGPoint(x: 2, y: 0))
        path.addLine(to: CGPoint(x: -1, y: 0))
        path.addLine(to: CGPoint(x: 1, y: 3))

        let arc = SKShapeNode(path: path)
        arc.strokeColor = UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0)
        arc.lineWidth = 2
        arc.lineCap = .round
        arc.lineJoin = .round
        arc.fillColor = .clear

        return arc
    }

    private func updateBarrierVisuals() {
        // Remove old barrier nodes
        barrierNodes.forEach { $0.removeFromParent() }
        barrierNodes.removeAll(keepingCapacity: true)

        if hasBarrier {
            // Create 4 rotating barrier segments
            let radius: CGFloat = 35
            for i in 0..<4 {
                let angle = CGFloat(i) * .pi / 2

                // Create hexagonal barrier segment
                let segment = SKShapeNode(circleOfRadius: 8)
                segment.fillColor = UIColor(red: 0.02, green: 0.12, blue: 0.1, alpha: 0.7)
                segment.strokeColor = UIColor(red: 0.4, green: 1.0, blue: 0.9, alpha: 0.5)
                segment.lineWidth = 1
                // A turning crystal in each, the barrier's light.
                let crystal = VectorFX3D.createCore(radius: 8, shape: .octahedron,
                                                    color: UIColor(red: 0.4, green: 1.0, blue: 0.85, alpha: 1.0))
                crystal.zPosition = 1
                segment.addChild(crystal)
                segment.position = CGPoint(
                    x: cos(angle) * radius,
                    y: sin(angle) * radius
                )
                segment.zPosition = -1
                segment.name = "barrierSegment"
                addChild(segment)
                barrierNodes.append(segment)

                // Add glow effect
                GlowHelper.addEnhancedGlow(
                    to: segment,
                    color: UIColor(red: 0.2, green: 0.9, blue: 0.7, alpha: 1.0),
                    intensity: 1.0
                )

                // Orbit the segment around the ship.
                //
                // This used to be `rotate(byAngle:)`, which spins a node about its own
                // centre — invisible on a circle, so the "rotating barrier" sat
                // perfectly still. Driving the position instead makes the ring actually
                // sweep, which also means the gaps between segments move rather than
                // leaving four permanently open approach lanes. The segments stay direct
                // children of the ship so GameScene's non-recursive lookup for
                // "barrierSegment" (where their physics bodies get attached) still
                // finds them.
                let orbitDuration: TimeInterval = 3.0
                let baseAngle = angle
                let orbit = SKAction.customAction(withDuration: orbitDuration) { node, elapsed in
                    let progress = CGFloat(elapsed) / CGFloat(orbitDuration)
                    let current = baseAngle + progress * .pi * 2
                    node.position = CGPoint(x: cos(current) * radius, y: sin(current) * radius)
                }
                segment.run(SKAction.repeatForever(orbit))
            }
        }
    }
}
