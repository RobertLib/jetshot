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
    private var attackTimer: Timer?
    private var movementAction: SKAction?

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

    func addHealthBarToScene(_ scene: SKScene) {
        scene.addChild(healthBar)
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

            // Immediately hide health bar
            healthBar.removeFromParent()

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

        return false
    }

    func defeat(completion: @escaping () -> Void) {
        isActive = false
        removeAllActions()
        attackTimer?.invalidate()

        // Explosion sequence with sound
        let explosionCount = 8
        for i in 0..<explosionCount {
            let delay = Double(i) * 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.createExplosion(offset: CGPoint(
                    x: CGFloat.random(in: -self.config.size/2...self.config.size/2),
                    y: CGFloat.random(in: -self.config.size/2...self.config.size/2)
                ), playSound: true) // Play sound for each explosion
            }
        }

        // Final explosion and removal
        let finalDelay = Double(explosionCount) * 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) {
            self.createExplosion(offset: .zero, isLarge: true, playSound: true)

            let fadeOut = SKAction.fadeOut(withDuration: 0.5)
            let remove = SKAction.removeFromParent()
            self.run(SKAction.sequence([fadeOut, remove]))
            self.removeHealthBarFromScene()

            // Wait for fade out to complete before calling completion
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion()
            }
        }
    }

    private func createExplosion(offset: CGPoint, isLarge: Bool = false, playSound: Bool = true) {
        guard let scene = self.scene else { return }

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

        scene.addChild(explosion)

        // Remove emitter after particles are done
        let waitAction = SKAction.wait(forDuration: 0.8)
        let removeAction = SKAction.removeFromParent()
        explosion.run(SKAction.sequence([waitAction, removeAction]))

        // Play sound only if requested
        if playSound {
            if isLarge {
                SoundManager.shared.playBossExplosion()
            } else {
                SoundManager.shared.playExplosion()
            }
        }

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
}
