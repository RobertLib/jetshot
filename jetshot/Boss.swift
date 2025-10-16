//
//  Boss.swift
//  jetshot
//
//  Created by Robert Libšanský on 26.10.2025.
//

import SpriteKit

// Boss configuration for each level
struct BossConfig {
    let maxHealth: Int
    let movementSpeed: TimeInterval
    let size: CGFloat
    let attackPatterns: [BossAttackPattern]
    let color: UIColor
    let strokeColor: UIColor
    let points: Int

    static func config(for level: Int) -> BossConfig {
        switch level {
        case 1:
            return BossConfig(
                maxHealth: 20,
                movementSpeed: 3.0,
                size: 80,
                attackPatterns: [.straightShot, .doubleShot],
                color: UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1.0),
                points: 500
            )
        case 2:
            return BossConfig(
                maxHealth: 35,
                movementSpeed: 2.5,
                size: 90,
                attackPatterns: [.straightShot, .tripleShot, .spread],
                color: UIColor(red: 0.6, green: 0.2, blue: 0.6, alpha: 1.0),
                strokeColor: UIColor(red: 0.9, green: 0.5, blue: 0.9, alpha: 1.0),
                points: 750
            )
        case 3:
            return BossConfig(
                maxHealth: 50,
                movementSpeed: 2.2,
                size: 100,
                attackPatterns: [.straightShot, .tripleShot, .spread, .aimed],
                color: UIColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1.0),
                strokeColor: UIColor(red: 0.5, green: 0.6, blue: 1.0, alpha: 1.0),
                points: 1000
            )
        case 4:
            return BossConfig(
                maxHealth: 70,
                movementSpeed: 2.0,
                size: 110,
                attackPatterns: [.straightShot, .tripleShot, .spread, .aimed, .spiral],
                color: UIColor(red: 0.7, green: 0.4, blue: 0.1, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.7, blue: 0.4, alpha: 1.0),
                points: 1250
            )
        case 5:
            return BossConfig(
                maxHealth: 90,
                movementSpeed: 1.8,
                size: 120,
                attackPatterns: [.straightShot, .tripleShot, .spread, .aimed, .spiral, .wave],
                color: UIColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1.0),
                strokeColor: UIColor(red: 0.4, green: 1.0, blue: 0.6, alpha: 1.0),
                points: 1500
            )
        case 6:
            return BossConfig(
                maxHealth: 110,
                movementSpeed: 1.6,
                size: 130,
                attackPatterns: [.tripleShot, .spread, .aimed, .spiral, .wave, .burst],
                color: UIColor(red: 0.5, green: 0.1, blue: 0.5, alpha: 1.0),
                strokeColor: UIColor(red: 0.9, green: 0.4, blue: 0.9, alpha: 1.0),
                points: 1750
            )
        case 7:
            return BossConfig(
                maxHealth: 135,
                movementSpeed: 1.5,
                size: 140,
                attackPatterns: [.tripleShot, .spread, .aimed, .spiral, .wave, .burst, .homing],
                color: UIColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0),
                points: 2000
            )
        case 8:
            return BossConfig(
                maxHealth: 160,
                movementSpeed: 1.3,
                size: 150,
                attackPatterns: [.tripleShot, .spread, .aimed, .spiral, .wave, .burst, .homing, .laser],
                color: UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
                points: 2500
            )
        default:
            // Fallback for any additional levels
            return BossConfig(
                maxHealth: 160 + (level - 8) * 20,
                movementSpeed: max(1.0, 1.3 - CGFloat(level - 8) * 0.1),
                size: min(180, 150 + CGFloat(level - 8) * 5),
                attackPatterns: [.tripleShot, .spread, .aimed, .spiral, .wave, .burst, .homing, .laser],
                color: UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
                points: 2500 + (level - 8) * 500
            )
        }
    }
}

// Boss attack patterns
enum BossAttackPattern {
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
}

class Boss: SKShapeNode {
    private var currentHealth: Int
    private let config: BossConfig
    private var healthBar: SKShapeNode!
    private var healthBarFill: SKShapeNode!
    private var isActive: Bool = false
    private var movementAction: SKAction?

    // Damage visual effects
    private var damageLevel: Int = 0  // 0 = no damage, 1-3 = increasing damage
    private var damageParts: [SKNode] = []
    private var cracksLayer: SKNode?
    private var lastDamageEffectHealth: Int = 0

    init(config: BossConfig, sceneSize: CGSize) {
        self.config = config
        self.currentHealth = config.maxHealth

        super.init()

        setupBossShape()
        setupHealthBar(sceneSize: sceneSize)
        self.name = "boss"

        // Position at top center
        self.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height + config.size)
        self.zPosition = 10

        // Physics
        let physicsBody = SKPhysicsBody(circleOfRadius: config.size * 0.4)
        physicsBody.categoryBitMask = PhysicsCategory.enemy
        physicsBody.contactTestBitMask = PhysicsCategory.bullet
        physicsBody.collisionBitMask = PhysicsCategory.none
        physicsBody.isDynamic = false
        self.physicsBody = physicsBody

        // Initialize cracks layer
        cracksLayer = SKNode()
        cracksLayer!.zPosition = 1
        addChild(cracksLayer!)

        lastDamageEffectHealth = config.maxHealth
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBossShape() {
        let size = config.size
        let path = CGMutablePath()

        // Create menacing boss ship shape
        // Main body (hexagonal)
        path.move(to: CGPoint(x: 0, y: size * 0.5))
        path.addLine(to: CGPoint(x: -size * 0.3, y: size * 0.2))
        path.addLine(to: CGPoint(x: -size * 0.4, y: -size * 0.2))
        path.addLine(to: CGPoint(x: -size * 0.2, y: -size * 0.5))
        path.addLine(to: CGPoint(x: size * 0.2, y: -size * 0.5))
        path.addLine(to: CGPoint(x: size * 0.4, y: -size * 0.2))
        path.addLine(to: CGPoint(x: size * 0.3, y: size * 0.2))
        path.closeSubpath()

        self.path = path
        self.fillColor = config.color
        self.strokeColor = config.strokeColor
        self.lineWidth = 3

        // Add glow effect using GlowHelper (no glowWidth)
        GlowHelper.addEnhancedGlow(to: self, color: config.color, intensity: 1.2)

        // Add details
        addBossDetails()
    }

    private func addBossDetails() {
        let size = config.size

        // Add cockpit/core
        let core = SKShapeNode(circleOfRadius: size * 0.15)
        core.fillColor = .red
        core.strokeColor = UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1.0)
        core.lineWidth = 2
        addChild(core)

        // Add glow to core
        GlowHelper.addEnhancedGlow(to: core, color: .red, intensity: 1.0)

        // Pulsing animation for core
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.5),
            SKAction.scale(to: 1.0, duration: 0.5)
        ])
        core.run(SKAction.repeatForever(pulse))

        // Add wings/cannons
        let leftCannon = createCannon()
        leftCannon.position = CGPoint(x: -size * 0.35, y: 0)
        addChild(leftCannon)

        let rightCannon = createCannon()
        rightCannon.position = CGPoint(x: size * 0.35, y: 0)
        addChild(rightCannon)
    }

    private func createCannon() -> SKShapeNode {
        let size = config.size * 0.15
        let path = CGMutablePath()

        path.move(to: CGPoint(x: -size * 0.3, y: size * 0.5))
        path.addLine(to: CGPoint(x: size * 0.3, y: size * 0.5))
        path.addLine(to: CGPoint(x: size * 0.2, y: -size * 0.5))
        path.addLine(to: CGPoint(x: -size * 0.2, y: -size * 0.5))
        path.closeSubpath()

        let cannon = SKShapeNode(path: path)
        cannon.fillColor = config.color.withAlphaComponent(0.8)
        cannon.strokeColor = config.strokeColor
        cannon.lineWidth = 1.5

        return cannon
    }

    private func setupHealthBar(sceneSize: CGSize) {
        // Health bar background
        let barWidth: CGFloat = sceneSize.width * 0.8
        let barHeight: CGFloat = 20

        // Calculate safe area top inset - use same logic as GameScene
        let safeAreaTop: CGFloat
        if let view = self.scene?.view,
           let windowScene = view.window?.windowScene {
            safeAreaTop = windowScene.windows.first?.safeAreaInsets.top ?? 0
        } else {
            safeAreaTop = 0
        }

        // Position below safe area with margin
        let topMargin = max(safeAreaTop + 20, 40)
        let barY = sceneSize.height - topMargin - 100 // 100 points below top UI (increased from 60)

        healthBar = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 5)
        healthBar.fillColor = UIColor(white: 0.2, alpha: 0.8)
        healthBar.strokeColor = .white
        healthBar.lineWidth = 2
        healthBar.position = CGPoint(x: sceneSize.width / 2, y: barY)
        healthBar.zPosition = 150

        // Health bar fill
        healthBarFill = SKShapeNode(rectOf: CGSize(width: barWidth - 4, height: barHeight - 4), cornerRadius: 4)
        healthBarFill.fillColor = .red
        healthBarFill.strokeColor = .clear
        healthBarFill.position = CGPoint(x: 0, y: 0)
        healthBar.addChild(healthBarFill)

        // Boss name label
        let bossLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        bossLabel.text = "⚡ BOSS ⚡"
        bossLabel.fontSize = 24
        bossLabel.fontColor = .yellow
        bossLabel.position = CGPoint(x: sceneSize.width / 2, y: barY + 30)
        bossLabel.zPosition = 150
        healthBar.addChild(bossLabel)
    }

    func addHealthBarToScene(_ scene: GameScene) {
        scene.gameContentNode.addChild(healthBar)
    }

    func removeHealthBarFromScene() {
        // Remove health bar only if it's still in the scene
        if healthBar.parent != nil {
            healthBar.removeFromParent()
        }
    }

    func enterScene(completion: @escaping () -> Void) {
        guard let scene = self.scene else { return }

        // Calculate safe area top inset
        let safeAreaTop: CGFloat
        if let view = scene.view,
           let windowScene = view.window?.windowScene {
            safeAreaTop = windowScene.windows.first?.safeAreaInsets.top ?? 0
        } else {
            safeAreaTop = 0
        }

        // Calculate position below safe area
        let topMargin = max(safeAreaTop + 20, 40)
        let targetY = scene.size.height - topMargin - config.size - 80 // More margin below UI (increased from 30)

        // Entrance animation
        let moveIn = SKAction.moveTo(y: targetY, duration: 2.0)
        moveIn.timingMode = .easeOut

        run(moveIn) {
            self.isActive = true
            self.startMovement()
            completion()
        }
    }

    private func startMovement() {
        guard let scene = self.scene else { return }

        let minX = config.size
        let maxX = scene.size.width - config.size

        // Create side-to-side movement
        let moveLeft = SKAction.moveTo(x: minX, duration: config.movementSpeed)
        moveLeft.timingMode = .easeInEaseOut

        let moveRight = SKAction.moveTo(x: maxX, duration: config.movementSpeed)
        moveRight.timingMode = .easeInEaseOut

        let sequence = SKAction.sequence([moveLeft, moveRight])
        movementAction = SKAction.repeatForever(sequence)

        run(movementAction!)
    }

    func takeDamage() -> Bool {
        currentHealth -= 1

        // Check if defeated first
        if currentHealth <= 0 {
            currentHealth = 0  // Ensure health doesn't go negative
            isActive = false
            removeAllActions()

            // Immediately hide health bar
            healthBar.removeFromParent()

            // Create sequence of explosion actions
            var explosionActions: [SKAction] = []
            let explosionCount = 8

            for i in 0..<explosionCount {
                let wait = SKAction.wait(forDuration: 0.2)
                let explode = SKAction.run {
                    self.createExplosion(offset: CGPoint(
                        x: CGFloat.random(in: -self.config.size/2...self.config.size/2),
                        y: CGFloat.random(in: -self.config.size/2...self.config.size/2)
                    ))
                    // Play explosion sound for each mini-explosion
                    if let scene = self.scene as? GameScene {
                        SoundManager.shared.playExplosionSound(on: scene)
                    }
                }

                if i > 0 {
                    explosionActions.append(wait)
                }
                explosionActions.append(explode)
            }

            // Final explosion and removal
            let finalWait = SKAction.wait(forDuration: 0.2)
            let finalExplosion = SKAction.run {
                self.createExplosion(offset: .zero, isLarge: true)
                self.removeHealthBarFromScene()
                // Play multiple explosion sounds for the final big explosion
                if let scene = self.scene as? GameScene {
                    SoundManager.shared.playExplosionSound(on: scene)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        SoundManager.shared.playExplosionSound(on: scene)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        SoundManager.shared.playExplosionSound(on: scene)
                    }
                }
            }

            explosionActions.append(finalWait)
            explosionActions.append(finalExplosion)

            // Fade out and remove
            let fadeOut = SKAction.fadeOut(withDuration: 0.5)
            let remove = SKAction.removeFromParent()

            explosionActions.append(fadeOut)
            explosionActions.append(remove)

            // Run the entire sequence
            run(SKAction.sequence(explosionActions), withKey: "bossDefeat")

            return true // Boss defeated
        }

        // Update health bar only if boss is still alive
        let healthPercent = CGFloat(currentHealth) / CGFloat(config.maxHealth)
        let originalWidth = (scene!.size.width * 0.8) - 4
        let newSize = CGSize(width: originalWidth * healthPercent, height: 16)

        healthBarFill.path = CGPath(
            roundedRect: CGRect(x: -newSize.width / 2, y: -newSize.height / 2, width: newSize.width, height: newSize.height),
            cornerWidth: 4,
            cornerHeight: 4,
            transform: nil
        )

        // Change color based on health
        if healthPercent > 0.6 {
            healthBarFill.fillColor = .red
        } else if healthPercent > 0.3 {
            healthBarFill.fillColor = .orange
        } else {
            healthBarFill.fillColor = .yellow
        }

        // Flash effect
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.1),
            SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        ])
        run(flash)

        // Apply visual damage effects (cracks, debris, smoke, etc.)
        applyDamageVisuals(healthPercent: healthPercent)

        // Damage sound
        if let scene = self.scene as? GameScene {
            SoundManager.shared.playHitSound(on: scene)
        }

        return false // Boss still alive
    }

    private func createExplosion(offset: CGPoint, isLarge: Bool = false) {
        guard let scene = self.scene as? GameScene else { return }

        // Use particle emitter instead of SKShapeNode for better performance
        let explosion = SKEmitterNode()
        explosion.position = CGPoint(x: position.x + offset.x, y: position.y + offset.y)
        explosion.zPosition = self.zPosition + 1

        // Create simple particle texture programmatically
        if explosion.particleTexture == nil {
            explosion.particleTexture = createParticleTexture()
        }

        // Particle configuration
        explosion.particleBirthRate = isLarge ? 800 : 400
        explosion.numParticlesToEmit = isLarge ? 150 : 80
        explosion.particleLifetime = 0.5
        explosion.particleLifetimeRange = 0.25

        // Size and scale
        explosion.particleScale = isLarge ? 0.4 : 0.25
        explosion.particleScaleRange = isLarge ? 0.2 : 0.1
        explosion.particleScaleSpeed = -0.4

        // Colors - orange/yellow gradient
        if isLarge {
            explosion.particleColor = .yellow
            explosion.particleColorBlendFactor = 1.0
            let colorSequence = SKKeyframeSequence(keyframeValues: [
                UIColor.white,
                UIColor.yellow,
                UIColor.orange,
                UIColor.red
            ], times: [0, 0.2, 0.5, 1.0])
            explosion.particleColorSequence = colorSequence
        } else {
            explosion.particleColor = .orange
            explosion.particleColorBlendFactor = 1.0
            let colorSequence = SKKeyframeSequence(keyframeValues: [
                UIColor.yellow,
                UIColor.orange,
                UIColor.red,
                UIColor(white: 0.3, alpha: 1.0)
            ], times: [0, 0.3, 0.7, 1.0])
            explosion.particleColorSequence = colorSequence
        }

        // Alpha
        explosion.particleAlpha = 1.0
        explosion.particleAlphaSpeed = -2.0

        // Movement - radial burst
        explosion.emissionAngle = 0
        explosion.emissionAngleRange = .pi * 2
        explosion.particleSpeed = isLarge ? 250 : 180
        explosion.particleSpeedRange = isLarge ? 120 : 80

        // Physics - slight gravity
        explosion.xAcceleration = 0
        explosion.yAcceleration = isLarge ? -40 : -25

        // Blend mode for glow effect
        explosion.particleBlendMode = .add

        scene.gameContentNode.addChild(explosion)

        // Remove emitter after particles are done
        let waitAction = SKAction.wait(forDuration: 0.8)
        let removeAction = SKAction.removeFromParent()
        explosion.run(SKAction.sequence([waitAction, removeAction]))

        // Haptic feedback
        if isLarge {
            HapticManager.shared.heavyTap()
        } else {
            HapticManager.shared.mediumTap()
        }
    }

    private func createParticleTexture() -> SKTexture {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(ovalIn: rect)

            // Create radial gradient
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!

            context.cgContext.saveGState()
            path.addClip()
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: size.width/2, y: size.height/2),
                startRadius: 0,
                endCenter: CGPoint(x: size.width/2, y: size.height/2),
                endRadius: size.width/2,
                options: []
            )
            context.cgContext.restoreGState()
        }
        return SKTexture(image: image)
    }

    func getPoints() -> Int {
        return config.points
    }

    func isAlive() -> Bool {
        return isActive && currentHealth > 0
    }

    func getAttackPatterns() -> [BossAttackPattern] {
        return config.attackPatterns
    }

    // MARK: - Damage Visual Effects

    private func applyDamageVisuals(healthPercent: CGFloat) {
        // Determine damage level based on health percentage
        let newDamageLevel: Int
        if healthPercent > 0.66 {
            newDamageLevel = 0  // Minor damage
        } else if healthPercent > 0.33 {
            newDamageLevel = 1  // Moderate damage
        } else {
            newDamageLevel = 2  // Heavy damage
        }

        // Only apply new visual effects if damage level increased
        if newDamageLevel > damageLevel {
            damageLevel = newDamageLevel

            switch damageLevel {
            case 1:
                applyModerateDamage()
            case 2:
                applyHeavyDamage()
            default:
                break
            }
        }

        // Random effects on every hit
        if Int.random(in: 0...2) == 0 {  // 33% chance
            createDebris()
        }

        // Add impact shake
        applyImpactShake()

        // Add random crack every few hits
        if currentHealth % 5 == 0 || healthPercent < 0.3 {
            addCrack()
        }

        // Spark effects
        createSparks()
    }

    private func applyModerateDamage() {
        // Add smoke particles
        createSmokeTrail()

        // Slight deformation
        let deform = SKAction.sequence([
            SKAction.scaleX(to: 1.05, y: 0.95, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.2)
        ])
        run(deform)

        // Make a part of the boss darker (battle damage)
        applyScorchMark(position: .random(in: 0...1))
    }

    private func applyHeavyDamage() {
        // More intense smoke
        createSmokeTrail(isHeavy: true)

        // Break off a piece
        breakOffPart()

        // More visible deformation
        let deform = SKAction.sequence([
            SKAction.scaleX(to: 1.08, y: 0.92, duration: 0.15),
            SKAction.scale(to: 1.0, duration: 0.25)
        ])
        run(deform)

        // Multiple scorch marks
        for _ in 0..<3 {
            applyScorchMark(position: .random(in: 0...1))
        }
    }

    private func applyImpactShake() {
        let shake = SKAction.sequence([
            SKAction.moveBy(x: 3, y: 2, duration: 0.05),
            SKAction.moveBy(x: -6, y: -4, duration: 0.05),
            SKAction.moveBy(x: 3, y: 2, duration: 0.05)
        ])
        run(shake)
    }

    private func createDebris() {
        guard let scene = self.scene else { return }

        let debrisCount = Int.random(in: 2...5)

        for _ in 0..<debrisCount {
            let debris = SKShapeNode(rectOf: CGSize(
                width: CGFloat.random(in: 3...8),
                height: CGFloat.random(in: 3...8)
            ))
            debris.fillColor = config.color.withAlphaComponent(0.8)
            debris.strokeColor = config.strokeColor
            debris.lineWidth = 1

            // Random position on boss
            let offsetX = CGFloat.random(in: -config.size/2...config.size/2)
            let offsetY = CGFloat.random(in: -config.size/2...config.size/2)
            debris.position = CGPoint(x: position.x + offsetX, y: position.y + offsetY)
            debris.zPosition = zPosition - 1

            scene.addChild(debris)

            // Fly away animation
            let angle = CGFloat.random(in: 0...(.pi * 2))
            let distance = CGFloat.random(in: 50...150)
            let dx = cos(angle) * distance
            let dy = sin(angle) * distance

            let flyAway = SKAction.group([
                SKAction.moveBy(x: dx, y: dy, duration: 1.5),
                SKAction.rotate(byAngle: .pi * CGFloat.random(in: 2...4), duration: 1.5),
                SKAction.fadeOut(withDuration: 1.5)
            ])

            debris.run(SKAction.sequence([
                flyAway,
                SKAction.removeFromParent()
            ]))
        }
    }

    private func breakOffPart() {
        guard let scene = self.scene else { return }

        // Create a visible chunk that breaks off
        let chunk = SKShapeNode(circleOfRadius: config.size * 0.15)
        chunk.fillColor = config.color
        chunk.strokeColor = config.strokeColor
        chunk.lineWidth = 2

        // Position on edge of boss
        let angle = CGFloat.random(in: 0...(.pi * 2))
        let offsetX = cos(angle) * config.size * 0.4
        let offsetY = sin(angle) * config.size * 0.4
        chunk.position = CGPoint(x: position.x + offsetX, y: position.y + offsetY)
        chunk.zPosition = zPosition

        scene.addChild(chunk)
        damageParts.append(chunk)

        // Small explosion at break point
        createSmallExplosion(at: chunk.position)

        // Fly off animation
        let flyDirection = CGPoint(x: offsetX * 3, y: offsetY * 3)
        let flyOff = SKAction.group([
            SKAction.moveBy(x: flyDirection.x, y: flyDirection.y, duration: 2.0),
            SKAction.rotate(byAngle: .pi * 4, duration: 2.0),
            SKAction.fadeOut(withDuration: 2.0)
        ])

        chunk.run(SKAction.sequence([
            flyOff,
            SKAction.removeFromParent()
        ]))

        HapticManager.shared.mediumTap()
    }

    private func addCrack() {
        guard let cracksLayer = cracksLayer else { return }

        let path = CGMutablePath()
        let startX = CGFloat.random(in: -config.size/3...config.size/3)
        let startY = CGFloat.random(in: -config.size/3...config.size/3)
        path.move(to: CGPoint(x: startX, y: startY))

        // Create jagged crack line
        let segments = Int.random(in: 3...6)
        for _ in 0..<segments {
            let endX = startX + CGFloat.random(in: -config.size/4...config.size/4)
            let endY = startY + CGFloat.random(in: -config.size/4...config.size/4)
            path.addLine(to: CGPoint(x: endX, y: endY))
        }

        let crack = SKShapeNode(path: path)
        crack.strokeColor = UIColor.black.withAlphaComponent(0.6)
        crack.lineWidth = 2
        crack.lineCap = .round
        crack.alpha = 0

        cracksLayer.addChild(crack)

        // Fade in crack
        crack.run(SKAction.fadeIn(withDuration: 0.2))
    }

    private func applyScorchMark(position: CGFloat) {
        let scorch = SKShapeNode(circleOfRadius: config.size * CGFloat.random(in: 0.1...0.2))
        scorch.fillColor = UIColor.black.withAlphaComponent(0.4)
        scorch.strokeColor = .clear

        let angle = position * .pi * 2
        let distance = config.size * CGFloat.random(in: 0.2...0.4)
        scorch.position = CGPoint(
            x: cos(angle) * distance,
            y: sin(angle) * distance
        )
        scorch.zPosition = 0.5
        scorch.alpha = 0

        addChild(scorch)
        damageParts.append(scorch)

        scorch.run(SKAction.fadeAlpha(to: 0.6, duration: 0.3))
    }

    private func createSmokeTrail(isHeavy: Bool = false) {
        guard let scene = self.scene as? GameScene else { return }

        let smoke = SKEmitterNode()
        smoke.position = position
        smoke.zPosition = zPosition - 1

        if smoke.particleTexture == nil {
            smoke.particleTexture = createParticleTexture()
        }

        smoke.particleBirthRate = isHeavy ? 40 : 20
        smoke.numParticlesToEmit = isHeavy ? 30 : 15
        smoke.particleLifetime = 1.5
        smoke.particleLifetimeRange = 0.5

        smoke.particleScale = 0.3
        smoke.particleScaleRange = 0.1
        smoke.particleScaleSpeed = 0.2

        smoke.particleColor = UIColor.gray
        smoke.particleColorBlendFactor = 1.0
        smoke.particleAlpha = 0.6
        smoke.particleAlphaSpeed = -0.4

        smoke.emissionAngle = .pi / 2
        smoke.emissionAngleRange = .pi / 4
        smoke.particleSpeed = 30
        smoke.particleSpeedRange = 20

        smoke.yAcceleration = 20

        scene.gameContentNode.addChild(smoke)

        let waitAction = SKAction.wait(forDuration: 2.0)
        let removeAction = SKAction.removeFromParent()
        smoke.run(SKAction.sequence([waitAction, removeAction]))
    }

    private func createSparks() {
        guard let scene = self.scene as? GameScene else { return }

        let sparks = SKEmitterNode()
        let sparkX = position.x + CGFloat.random(in: -config.size/2...config.size/2)
        let sparkY = position.y + CGFloat.random(in: -config.size/2...config.size/2)
        sparks.position = CGPoint(x: sparkX, y: sparkY)
        sparks.zPosition = zPosition + 1

        if sparks.particleTexture == nil {
            sparks.particleTexture = createParticleTexture()
        }

        sparks.particleBirthRate = 200
        sparks.numParticlesToEmit = 10
        sparks.particleLifetime = 0.3
        sparks.particleLifetimeRange = 0.1

        sparks.particleScale = 0.08
        sparks.particleScaleRange = 0.04
        sparks.particleScaleSpeed = -0.2

        sparks.particleColor = .yellow
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

        let waitAction = SKAction.wait(forDuration: 0.5)
        let removeAction = SKAction.removeFromParent()
        sparks.run(SKAction.sequence([waitAction, removeAction]))
    }

    private func createSmallExplosion(at position: CGPoint) {
        guard let scene = self.scene as? GameScene else { return }

        // Play explosion sound when parts break off
        SoundManager.shared.playExplosionSound(on: scene)

        let explosion = SKEmitterNode()
        explosion.position = position
        explosion.zPosition = zPosition + 1

        if explosion.particleTexture == nil {
            explosion.particleTexture = createParticleTexture()
        }

        explosion.particleBirthRate = 300
        explosion.numParticlesToEmit = 30
        explosion.particleLifetime = 0.4
        explosion.particleLifetimeRange = 0.15

        explosion.particleScale = 0.2
        explosion.particleScaleRange = 0.1
        explosion.particleScaleSpeed = -0.3

        explosion.particleColor = .orange
        explosion.particleColorBlendFactor = 1.0
        explosion.particleAlpha = 1.0
        explosion.particleAlphaSpeed = -2.5

        explosion.emissionAngle = 0
        explosion.emissionAngleRange = .pi * 2
        explosion.particleSpeed = 120
        explosion.particleSpeedRange = 60

        explosion.yAcceleration = -30
        explosion.particleBlendMode = .add

        scene.gameContentNode.addChild(explosion)

        let waitAction = SKAction.wait(forDuration: 0.6)
        let removeAction = SKAction.removeFromParent()
        explosion.run(SKAction.sequence([waitAction, removeAction]))
    }
}
