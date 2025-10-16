//
//  Player.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import SpriteKit

class Player: SKShapeNode {

    // Configuration
    private let moveSpeed: TimeInterval = 0.2

    // PowerUp properties
    var bulletCount: Int = 1 {
        didSet {
            bulletCount = min(bulletCount, 4) // Max 4 bullets
        }
    }
    var sideMissileCount: Int = 0 {
        didSet {
            sideMissileCount = min(sideMissileCount, 2) // Max 2 side missiles
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

    init(sceneSize: CGSize, safeAreaBottom: CGFloat = 0) {
        super.init()

        setupPlayer(sceneSize: sceneSize, safeAreaBottom: safeAreaBottom)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        self.fillColor = UIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0) // Bright blue
        self.strokeColor = UIColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 1.0) // Light cyan
        self.lineWidth = 2.5

        // Position above safe area (home indicator) with padding
        let playerHeight = safeAreaBottom + 60
        self.position = CGPoint(x: sceneSize.width / 2, y: playerHeight)
        self.name = "player"

        // Add cockpit detail
        let cockpit = SKShapeNode(circleOfRadius: 3)
        cockpit.fillColor = UIColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.9)
        cockpit.strokeColor = UIColor(red: 0.6, green: 1.0, blue: 1.0, alpha: 1.0)
        cockpit.lineWidth = 1.5
        cockpit.position = CGPoint(x: 0, y: 8)
        cockpit.zPosition = 1
        addChild(cockpit)

        // Add engine glow effects
        let leftEngine = SKShapeNode(rectOf: CGSize(width: 2.5, height: 6), cornerRadius: 1)
        leftEngine.fillColor = UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.8)
        leftEngine.strokeColor = .clear
        leftEngine.position = CGPoint(x: -4.5, y: -15)
        leftEngine.zPosition = -1
        addChild(leftEngine)

        let rightEngine = SKShapeNode(rectOf: CGSize(width: 2.5, height: 6), cornerRadius: 1)
        rightEngine.fillColor = UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.8)
        rightEngine.strokeColor = .clear
        rightEngine.position = CGPoint(x: 4.5, y: -15)
        rightEngine.zPosition = -1
        addChild(rightEngine)

        // Engine flame animation
        let engineFlicker = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 0.1),
            SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        ])
        leftEngine.run(SKAction.repeatForever(engineFlicker))
        rightEngine.run(SKAction.repeatForever(engineFlicker))

        // Add particle effects for engine thrusters
        addEngineThrusterParticles(at: CGPoint(x: -4.5, y: -18))
        addEngineThrusterParticles(at: CGPoint(x: 4.5, y: -18))

        // Setup physics body
        self.physicsBody = SKPhysicsBody(polygonFrom: path)
        self.physicsBody?.isDynamic = true
        self.physicsBody?.categoryBitMask = PhysicsCategory.player
        self.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.enemyBullet | PhysicsCategory.obstacle
        self.physicsBody?.collisionBitMask = PhysicsCategory.none
        self.physicsBody?.usesPreciseCollisionDetection = true

        // Add subtle pulsing glow effect to player
        GlowHelper.addPulsingEnhancedGlow(to: self, color: UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1.0), minIntensity: 0.6, maxIntensity: 0.9, duration: 1.2)
    }

    // Cached particle texture for better performance
    private static var cachedParticleTexture: SKTexture?

    private func addEngineThrusterParticles(at position: CGPoint) {
        // Create particle emitter for engine thruster effect
        let thrusterEmitter = SKEmitterNode()
        thrusterEmitter.position = position
        thrusterEmitter.zPosition = -2

        // Use cached texture or create if needed
        if Player.cachedParticleTexture == nil {
            Player.cachedParticleTexture = createParticleTexture()
        }
        thrusterEmitter.particleTexture = Player.cachedParticleTexture

        // Particle properties (optimized from 150 to 80 for better performance)
        thrusterEmitter.particleBirthRate = 80
        thrusterEmitter.numParticlesToEmit = 0 // Continuous emission

        // Particle lifetime
        thrusterEmitter.particleLifetime = 0.5
        thrusterEmitter.particleLifetimeRange = 0.25

        // Particle appearance
        thrusterEmitter.particleScale = 0.2
        thrusterEmitter.particleScaleRange = 0.075
        thrusterEmitter.particleScaleSpeed = -0.28

        // Particle colors - bright cyan to blue gradient
        thrusterEmitter.particleColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        thrusterEmitter.particleColorBlendFactor = 1.0
        thrusterEmitter.particleColorSequence = nil

        // Color ramp for gradient effect
        let colorKeyframe1 = SKKeyframeSequence(keyframeValues: [
            UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0),
            UIColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 0.8),
            UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 0.4),
            UIColor(red: 0.4, green: 0.4, blue: 0.9, alpha: 0.0)
        ], times: [0, 0.3, 0.6, 1.0])
        thrusterEmitter.particleColorSequence = colorKeyframe1

        // Particle alpha
        thrusterEmitter.particleAlpha = 0.9
        thrusterEmitter.particleAlphaRange = 0.2
        thrusterEmitter.particleAlphaSpeed = -2.0

        // Particle movement
        thrusterEmitter.emissionAngle = .pi * 1.5 // Downward
        thrusterEmitter.emissionAngleRange = .pi * 0.18
        thrusterEmitter.particleSpeed = 70
        thrusterEmitter.particleSpeedRange = 35

        // Particle acceleration (slight upward drift to simulate turbulence)
        thrusterEmitter.xAcceleration = 0
        thrusterEmitter.yAcceleration = 20

        // Blend mode for glowing effect
        thrusterEmitter.particleBlendMode = .add

        addChild(thrusterEmitter)
    }

    private func createParticleTexture() -> SKTexture {
        // Create a simple circular gradient texture for particles
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Create radial gradient
            let colors = [
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0.5).cgColor,
                UIColor.clear.cgColor
            ] as CFArray

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.5, 1])!

            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: size.width / 2,
                options: []
            )
        }

        return SKTexture(image: image)
    }

    func moveTo(x: CGFloat, sceneWidth: CGFloat) {
        // Clamp position to screen bounds
        let targetX = max(30, min(sceneWidth - 30, x))
        let moveAction = SKAction.moveTo(x: targetX, duration: moveSpeed)
        run(moveAction)
    }

    func moveToInstant(x: CGFloat, sceneWidth: CGFloat) {
        // Clamp position to screen bounds
        let targetX = max(30, min(sceneWidth - 30, x))
        // Direct position update for smooth dragging
        position.x = targetX
    }

    func shoot() -> [SKShapeNode] {
        var bullets: [SKShapeNode] = []

        // Calculate spacing between bullets based on count
        let spacing: CGFloat = 15
        let totalWidth = CGFloat(bulletCount - 1) * spacing
        let startX = self.position.x - totalWidth / 2

        // Create bullets based on bulletCount
        for i in 0..<bulletCount {
            // Create laser bullet with gradient effect
            let bullet = SKShapeNode(rectOf: CGSize(width: 5, height: 16), cornerRadius: 2.5)
            bullet.fillColor = UIColor(red: 0.0, green: 1.0, blue: 0.8, alpha: 1.0) // Cyan-green
            bullet.strokeColor = UIColor(red: 0.5, green: 1.0, blue: 1.0, alpha: 1.0)
            bullet.lineWidth = 1.5
            bullet.position = CGPoint(x: startX + CGFloat(i) * spacing, y: self.position.y + 20)
            bullet.name = "bullet"

            // Add bullet core
            let core = SKShapeNode(rectOf: CGSize(width: 2, height: 14), cornerRadius: 1)
            core.fillColor = UIColor(red: 0.8, green: 1.0, blue: 1.0, alpha: 1.0)
            core.strokeColor = .clear
            core.zPosition = 1
            bullet.addChild(core)

            // Setup physics body
            bullet.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 5, height: 16))
            bullet.physicsBody?.isDynamic = true
            bullet.physicsBody?.categoryBitMask = PhysicsCategory.bullet
            bullet.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.obstacle
            bullet.physicsBody?.collisionBitMask = PhysicsCategory.none
            bullet.physicsBody?.usesPreciseCollisionDetection = true

            // Add enhanced glow effect to bullet
            GlowHelper.addEnhancedGlow(to: bullet, color: UIColor(red: 0.0, green: 1.0, blue: 0.9, alpha: 1.0), intensity: 1.0)

            bullets.append(bullet)
        }

        return bullets
    }

    func shootMissile(side: Int) -> SKShapeNode {
        // Create missile body (larger than regular bullet)
        let missile = SKShapeNode(rectOf: CGSize(width: 10, height: 24), cornerRadius: 5)
        missile.fillColor = UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0) // Bright orange-red
        missile.strokeColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        missile.lineWidth = 2

        // Position based on side (-1 for left, 1 for right)
        let offsetX: CGFloat = CGFloat(side) * 20
        missile.position = CGPoint(x: self.position.x + offsetX, y: self.position.y + 20)
        missile.name = "missile"

        // Add missile warhead
        let warhead = SKShapeNode(circleOfRadius: 3)
        warhead.fillColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
        warhead.strokeColor = UIColor(red: 1.0, green: 1.0, blue: 0.5, alpha: 1.0)
        warhead.lineWidth = 1.5
        warhead.position = CGPoint(x: 0, y: 10)
        warhead.zPosition = 1
        missile.addChild(warhead)

        // Add fins
        let leftFin = SKShapeNode(path: {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -5, y: -5))
            path.addLine(to: CGPoint(x: -8, y: -8))
            path.addLine(to: CGPoint(x: -5, y: -10))
            path.closeSubpath()
            return path
        }())
        leftFin.fillColor = UIColor(red: 0.8, green: 0.2, blue: 0.0, alpha: 1.0)
        leftFin.strokeColor = UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0)
        leftFin.lineWidth = 1
        missile.addChild(leftFin)

        let rightFin = SKShapeNode(path: {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 5, y: -5))
            path.addLine(to: CGPoint(x: 8, y: -8))
            path.addLine(to: CGPoint(x: 5, y: -10))
            path.closeSubpath()
            return path
        }())
        rightFin.fillColor = UIColor(red: 0.8, green: 0.2, blue: 0.0, alpha: 1.0)
        rightFin.strokeColor = UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0)
        rightFin.lineWidth = 1
        missile.addChild(rightFin)

        // Add engine trail
        let trail = SKShapeNode(rectOf: CGSize(width: 4, height: 8), cornerRadius: 2)
        trail.fillColor = UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.8)
        trail.strokeColor = .clear
        trail.position = CGPoint(x: 0, y: -14)
        trail.zPosition = -1
        missile.addChild(trail)

        // Trail flicker animation
        let flicker = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.4, duration: 0.1),
            SKAction.fadeAlpha(to: 0.9, duration: 0.1)
        ])
        trail.run(SKAction.repeatForever(flicker))

        // Setup physics body
        missile.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 24))
        missile.physicsBody?.isDynamic = true
        missile.physicsBody?.categoryBitMask = PhysicsCategory.bullet
        missile.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.obstacle
        missile.physicsBody?.collisionBitMask = PhysicsCategory.none
        missile.physicsBody?.usesPreciseCollisionDetection = true

        // Add glow effect to missile
        GlowHelper.addEnhancedGlow(to: missile, color: UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0), intensity: 1.2)

        return missile
    }

    private func updateSideMissiles() {
        // Remove old missile visuals
        sideMissileNodes.forEach { $0.removeFromParent() }
        sideMissileNodes.removeAll()

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
        // Small visual representation of side missiles mounted on wings
        let missile = SKShapeNode(rectOf: CGSize(width: 5, height: 12), cornerRadius: 2.5)
        missile.fillColor = UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0)
        missile.strokeColor = UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)
        missile.lineWidth = 1.5
        missile.zPosition = -1

        // Add small warhead detail
        let warhead = SKShapeNode(circleOfRadius: 1.5)
        warhead.fillColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
        warhead.strokeColor = .clear
        warhead.position = CGPoint(x: 0, y: 5)
        missile.addChild(warhead)

        return missile
    }

    private func updateShieldVisuals() {
        if hasShield {
            // Create shield if it doesn't exist
            if shieldNode == nil {
                let shield = SKShapeNode(circleOfRadius: 35)
                shield.fillColor = UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.15)
                shield.strokeColor = UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 0.9)
                shield.lineWidth = 3.5
                shield.zPosition = -1
                addChild(shield)
                shieldNode = shield

                // Add hexagonal pattern overlay
                let hexPattern = createHexagonalPattern()
                hexPattern.zPosition = 1
                shield.addChild(hexPattern)

                // Pulsing animation
                let pulse = SKAction.sequence([
                    SKAction.scale(to: 1.08, duration: 0.6),
                    SKAction.scale(to: 1.0, duration: 0.6)
                ])
                shield.run(SKAction.repeatForever(pulse))

                // Rotation animation for pattern
                let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 8.0)
                hexPattern.run(SKAction.repeatForever(rotate))

                // Glow effect
                GlowHelper.addPulsingEnhancedGlow(
                    to: shield,
                    color: UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1.0),
                    minIntensity: 0.6,
                    maxIntensity: 1.0,
                    duration: 1.2
                )
            }
        } else {
            // Remove shield
            shieldNode?.removeFromParent()
            shieldNode = nil
        }
    }

    private func createHexagonalPattern() -> SKShapeNode {
        let pattern = SKShapeNode()
        let radius: CGFloat = 8
        let positions: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: -14, y: 8), CGPoint(x: 14, y: 8),
            CGPoint(x: -14, y: -8), CGPoint(x: 14, y: -8),
            CGPoint(x: 0, y: 16), CGPoint(x: 0, y: -16)
        ]

        for position in positions {
            let hex = createHexagon(radius: radius)
            hex.position = position
            hex.strokeColor = UIColor(red: 0.4, green: 1.0, blue: 1.0, alpha: 0.4)
            hex.lineWidth = 1.5
            hex.fillColor = .clear
            pattern.addChild(hex)
        }

        return pattern
    }

    private func createHexagon(radius: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3
            let x = radius * cos(angle)
            let y = radius * sin(angle)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return SKShapeNode(path: path)
    }

    func resetPowerUps() {
        // Reset all powerups to default state (called when player loses a life)
        bulletCount = 1
        sideMissileCount = 0
        hasShield = false
        hasLightningWeapon = false
        hasRapidFire = false
        hasMagnet = false
        hasSlowMotion = false
        hasScoreMultiplier = false
        hasBarrier = false
    }

    func playHitAnimation() {
        // Blink animation when hit
        let blinkAction = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.1),
            SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        ])
        run(SKAction.repeat(blinkAction, count: 3))
    }

    func updateBounds(sceneSize: CGSize, safeAreaBottom: CGFloat) {
        // Update player position to stay within new bounds
        let playerHeight = safeAreaBottom + 60
        let clampedX = max(30, min(sceneSize.width - 30, position.x))
        position = CGPoint(x: clampedX, y: playerHeight)
    }

    private func updateLightningVisuals() {
        // Remove old lightning indicators
        lightningIndicators.forEach { $0.removeFromParent() }
        lightningIndicators.removeAll()

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
        barrierNodes.removeAll()

        if hasBarrier {
            // Create 4 rotating barrier segments
            let radius: CGFloat = 35
            for i in 0..<4 {
                let angle = CGFloat(i) * .pi / 2

                // Create hexagonal barrier segment
                let segment = SKShapeNode(circleOfRadius: 8)
                segment.fillColor = UIColor(red: 0.2, green: 0.9, blue: 0.7, alpha: 0.6)
                segment.strokeColor = UIColor(red: 0.4, green: 1.0, blue: 0.9, alpha: 1.0)
                segment.lineWidth = 2.5
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
            }

            // Rotate all barrier segments together
            let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 3.0)
            let repeatRotate = SKAction.repeatForever(rotate)
            barrierNodes.forEach { $0.run(repeatRotate) }
        }
    }
}
