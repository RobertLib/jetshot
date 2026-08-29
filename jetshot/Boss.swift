//
//  Boss.swift
//  jetshot
//
//  Created by Robert Libšanský on 26.10.2025.
//

import SpriteKit

// Boss shape types
enum BossShape {
    case hexagonal
    case diamond
    case triangle
    case star
    case pentagon
    case cross
    case octagon
    case arrow
}

// Boss configuration for each level
struct BossConfig {
    let maxHealth: Int
    let movementSpeed: TimeInterval
    let size: CGFloat
    let attackPatterns: [BossAttackPattern]
    let color: UIColor
    let strokeColor: UIColor
    let points: Int
    let shape: BossShape

    /// Each arm's `attackPatterns` runs lightest to heaviest, and that ordering is
    /// load-bearing rather than cosmetic: `BossPhaseRules.patternCount(forPhase:
    /// totalPatterns:)` takes a *prefix* of this list, so a boss opens with the front of
    /// its array and only earns the back of it once it is wounded. Append a heavy attack
    /// in the middle and it will show up in the opening act.
    ///
    /// The lists also differ per milestone, which they did not use to. Every arm from
    /// level 8 to level 50 declared the identical fourteen patterns, so thirty-five of
    /// the fifty bosses in the game were the same fight with a longer health bar — the
    /// single largest piece of repetition left in the game, sitting at the climax of
    /// every level. Each is now a signature of eight to fifteen patterns with a
    /// recognisable bias: level 20 hunts (aimed, homing, sweeps), level 25 floods the
    /// screen from the sides (zigzag, cascade, rain), level 30 is a laser platform, and
    /// only level 50 draws on effectively everything.
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
                points: 500,
                shape: .hexagonal
            )
        case 2:
            return BossConfig(
                maxHealth: 35,
                movementSpeed: 2.5,
                size: 90,
                attackPatterns: [.straightShot, .tripleShot, .spread],
                color: UIColor(red: 0.6, green: 0.2, blue: 0.6, alpha: 1.0),
                strokeColor: UIColor(red: 0.9, green: 0.5, blue: 0.9, alpha: 1.0),
                points: 750,
                shape: .triangle
            )
        case 3:
            return BossConfig(
                maxHealth: 50,
                movementSpeed: 2.2,
                size: 100,
                attackPatterns: [.straightShot, .tripleShot, .spread, .aimed, .circularBarrage],
                color: UIColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1.0),
                strokeColor: UIColor(red: 0.5, green: 0.6, blue: 1.0, alpha: 1.0),
                points: 1000,
                shape: .diamond
            )
        case 4:
            return BossConfig(
                maxHealth: 70,
                movementSpeed: 2.0,
                size: 110,
                attackPatterns: [.straightShot, .tripleShot, .spread, .aimed, .spiral, .cascade, .circularBarrage],
                color: UIColor(red: 0.7, green: 0.4, blue: 0.1, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.7, blue: 0.4, alpha: 1.0),
                points: 1250,
                shape: .pentagon
            )
        case 5:
            return BossConfig(
                maxHealth: 90,
                movementSpeed: 1.8,
                size: 120,
                attackPatterns: [.straightShot, .tripleShot, .spread, .aimed, .wave, .spiral, .cascade, .doubleSpiral, .circularBarrage],
                color: UIColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1.0),
                strokeColor: UIColor(red: 0.4, green: 1.0, blue: 0.6, alpha: 1.0),
                points: 1500,
                shape: .star
            )
        case 6:
            return BossConfig(
                maxHealth: 110,
                movementSpeed: 1.6,
                size: 130,
                attackPatterns: [.tripleShot, .spread, .aimed, .wave, .spiral, .burst, .cascade, .doubleSpiral, .circularBarrage, .barrageRain],
                color: UIColor(red: 0.5, green: 0.1, blue: 0.5, alpha: 1.0),
                strokeColor: UIColor(red: 0.9, green: 0.4, blue: 0.9, alpha: 1.0),
                points: 1750,
                shape: .cross
            )
        case 7:
            return BossConfig(
                maxHealth: 135,
                movementSpeed: 1.5,
                size: 140,
                attackPatterns: [.tripleShot, .spread, .aimed, .wave, .spiral, .burst, .zigzagPattern, .cascade, .homing, .doubleSpiral, .circularBarrage, .barrageRain],
                color: UIColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0),
                points: 2000,
                shape: .octagon
            )
        case 8:
            return BossConfig(
                maxHealth: 160,
                movementSpeed: 1.3,
                size: 150,
                attackPatterns: [.tripleShot, .spread, .aimed, .wave, .burst, .homing, .sectorSweep, .laser],
                color: UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
                points: 2500,
                shape: .arrow
            )
        case 10:
            return BossConfig(
                maxHealth: 200,
                movementSpeed: 1.2,
                size: 155,
                attackPatterns: [.tripleShot, .spread, .wave, .spiral, .burst, .doubleSpiral, .sectorSweep, .circularBarrage],
                color: UIColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0),
                strokeColor: UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1.0),
                points: 3000,
                shape: .star
            )
        case 15:
            return BossConfig(
                maxHealth: 250,
                movementSpeed: 1.1,
                size: 160,
                attackPatterns: [.doubleShot, .tripleShot, .spread, .wave, .burst, .cascade, .circularBarrage, .barrageRain],
                color: UIColor(red: 0.3, green: 0.0, blue: 0.5, alpha: 1.0),
                strokeColor: UIColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 1.0),
                points: 3500,
                shape: .octagon
            )
        case 20:
            return BossConfig(
                maxHealth: 300,
                movementSpeed: 1.0,
                size: 165,
                attackPatterns: [.tripleShot, .spread, .aimed, .wave, .zigzagPattern, .homing, .sectorSweep, .laser],
                color: UIColor(red: 0.5, green: 0.5, blue: 0.0, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 1.0, blue: 0.3, alpha: 1.0),
                points: 4000,
                shape: .diamond
            )
        case 25:
            return BossConfig(
                maxHealth: 350,
                movementSpeed: 1.0,
                size: 170,
                attackPatterns: [.doubleShot, .tripleShot, .spread, .wave, .zigzagPattern, .cascade, .doubleSpiral, .barrageRain],
                color: UIColor(red: 0.0, green: 0.4, blue: 0.4, alpha: 1.0),
                strokeColor: UIColor(red: 0.3, green: 1.0, blue: 1.0, alpha: 1.0),
                points: 4500,
                shape: .cross
            )
        case 30:
            return BossConfig(
                maxHealth: 400,
                movementSpeed: 1.0,
                size: 175,
                attackPatterns: [.tripleShot, .spread, .aimed, .spiral, .burst, .sectorSweep, .circularBarrage, .laser],
                color: UIColor(red: 0.5, green: 0.2, blue: 0.0, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0),
                points: 5000,
                shape: .arrow
            )
        case 35:
            return BossConfig(
                maxHealth: 450,
                movementSpeed: 1.0,
                size: 180,
                attackPatterns: [.tripleShot, .spread, .wave, .burst, .cascade, .doubleSpiral, .circularBarrage, .barrageRain],
                color: UIColor(red: 0.6, green: 0.0, blue: 0.3, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.3, blue: 0.7, alpha: 1.0),
                points: 5500,
                shape: .hexagonal
            )
        case 40:
            return BossConfig(
                maxHealth: 500,
                movementSpeed: 1.0,
                size: 185,
                attackPatterns: [.tripleShot, .spread, .aimed, .spiral, .zigzagPattern, .homing, .sectorSweep, .barrageRain, .laser],
                color: UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1.0),
                strokeColor: UIColor(red: 0.5, green: 1.0, blue: 0.5, alpha: 1.0),
                points: 6000,
                shape: .pentagon
            )
        case 45:
            return BossConfig(
                maxHealth: 550,
                movementSpeed: 1.0,
                size: 190,
                attackPatterns: [.tripleShot, .spread, .wave, .spiral, .burst, .cascade, .homing, .doubleSpiral, .circularBarrage, .laser],
                color: UIColor(red: 0.4, green: 0.0, blue: 0.6, alpha: 1.0),
                strokeColor: UIColor(red: 0.8, green: 0.4, blue: 1.0, alpha: 1.0),
                points: 6500,
                shape: .triangle
            )
        case 50:
            return BossConfig(
                maxHealth: 600,
                movementSpeed: 1.0,
                size: 200,
                attackPatterns: [.straightShot, .tripleShot, .spread, .aimed, .wave, .spiral, .burst, .zigzagPattern, .cascade, .homing, .doubleSpiral, .sectorSweep, .circularBarrage, .barrageRain, .laser],
                color: UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
                strokeColor: UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0),
                points: 7500,
                shape: .star
            )
        default:
            // Interpolate for levels between milestones
            let milestones = [1, 2, 3, 4, 5, 6, 7, 8, 10, 15, 20, 25, 30, 35, 40, 45, 50]
            let lower = milestones.last(where: { $0 <= level }) ?? 1
            return config(for: lower)
        }
    }
}

// Boss attack patterns.
//
// `nonisolated` like `PhysicsCategory` and `ExplosionSize`: a bare enum of cases carries
// no state and has no business on the main actor. `BossPhaseRules` slices these lists per
// phase and is pure, so it cannot see a main-actor type — and nor can `jetshotTests`.
//
// The order of the cases is not load-bearing, but the order *within each config's
// `attackPatterns` array* is: see `BossPhaseRules.patternCount(forPhase:totalPatterns:)`,
// which takes a prefix and so expects each list to run lightest to heaviest.
nonisolated enum BossAttackPattern {
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

    // NEW HARDER ATTACK PATTERNS
    case circularBarrage // Dense circle of bullets around boss
    case cascade         // Cascading bullets falling down from left to right
    case doubleSpiral    // Two spirals rotating in opposite directions
    case barrageRain     // Dense rain of bullets across screen width
    case zigzagPattern   // Zigzag pattern of bullets
    case sectorSweep     // Sweeping sector fire (rotating barrage)
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
    // No `damageParts` array here on purpose. It used to collect every chunk and scorch
    // mark and was never read back — write-only state that just held strong references.
    // Both kinds of node already retire themselves: chunks end their fly-off with
    // removeFromParent(), and scorch marks are children of the boss.
    private var cracksLayer: SKNode?
    // No `lastDamageEffectHealth` either, for the same reason: it was set once in init
    // and never read. Re-application of the damage visuals is already gated by
    // `damageLevel` in `applyDamageVisuals(healthPercent:)`.

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
        let cracks = SKNode()
        cracks.zPosition = 1
        cracksLayer = cracks
        addChild(cracks)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createShapePath(for shape: BossShape, size: CGFloat) -> CGMutablePath {
        let path = CGMutablePath()

        switch shape {
        case .hexagonal:
            path.move(to: CGPoint(x: 0, y: size * 0.5))
            path.addLine(to: CGPoint(x: -size * 0.3, y: size * 0.2))
            path.addLine(to: CGPoint(x: -size * 0.4, y: -size * 0.2))
            path.addLine(to: CGPoint(x: -size * 0.2, y: -size * 0.5))
            path.addLine(to: CGPoint(x: size * 0.2, y: -size * 0.5))
            path.addLine(to: CGPoint(x: size * 0.4, y: -size * 0.2))
            path.addLine(to: CGPoint(x: size * 0.3, y: size * 0.2))
            path.closeSubpath()

        case .diamond:
            path.move(to: CGPoint(x: 0, y: size * 0.5))
            path.addLine(to: CGPoint(x: -size * 0.45, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -size * 0.5))
            path.addLine(to: CGPoint(x: size * 0.45, y: 0))
            path.closeSubpath()

        case .triangle:
            path.move(to: CGPoint(x: 0, y: size * 0.5))
            path.addLine(to: CGPoint(x: -size * 0.5, y: -size * 0.4))
            path.addLine(to: CGPoint(x: size * 0.5, y: -size * 0.4))
            path.closeSubpath()

        case .star:
            let points = 5
            let outerRadius = size * 0.5
            let innerRadius = size * 0.2
            for i in 0..<(points * 2) {
                let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
                let radius = i % 2 == 0 ? outerRadius : innerRadius
                let x = cos(angle) * radius
                let y = sin(angle) * radius
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()

        case .pentagon:
            let points = 5
            let radius = size * 0.5
            for i in 0..<points {
                let angle = CGFloat(i) * 2 * .pi / CGFloat(points) - .pi / 2
                let x = cos(angle) * radius
                let y = sin(angle) * radius
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()

        case .cross:
            let thickness = size * 0.2
            let length = size * 0.5
            // Vertical bar
            path.move(to: CGPoint(x: -thickness, y: length))
            path.addLine(to: CGPoint(x: thickness, y: length))
            path.addLine(to: CGPoint(x: thickness, y: thickness))
            path.addLine(to: CGPoint(x: length, y: thickness))
            path.addLine(to: CGPoint(x: length, y: -thickness))
            path.addLine(to: CGPoint(x: thickness, y: -thickness))
            path.addLine(to: CGPoint(x: thickness, y: -length))
            path.addLine(to: CGPoint(x: -thickness, y: -length))
            path.addLine(to: CGPoint(x: -thickness, y: -thickness))
            path.addLine(to: CGPoint(x: -length, y: -thickness))
            path.addLine(to: CGPoint(x: -length, y: thickness))
            path.addLine(to: CGPoint(x: -thickness, y: thickness))
            path.closeSubpath()

        case .octagon:
            let points = 8
            let radius = size * 0.5
            for i in 0..<points {
                let angle = CGFloat(i) * 2 * .pi / CGFloat(points) - .pi / 2
                let x = cos(angle) * radius
                let y = sin(angle) * radius
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()

        case .arrow:
            path.move(to: CGPoint(x: 0, y: size * 0.5))
            path.addLine(to: CGPoint(x: -size * 0.4, y: size * 0.1))
            path.addLine(to: CGPoint(x: -size * 0.2, y: size * 0.1))
            path.addLine(to: CGPoint(x: -size * 0.2, y: -size * 0.5))
            path.addLine(to: CGPoint(x: size * 0.2, y: -size * 0.5))
            path.addLine(to: CGPoint(x: size * 0.2, y: size * 0.1))
            path.addLine(to: CGPoint(x: size * 0.4, y: size * 0.1))
            path.closeSubpath()
        }

        return path
    }

    private func setupBossShape() {
        let size = config.size
        let path = createShapePath(for: config.shape, size: size)

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

        // Add 3D vector effects based on boss configuration
        add3DVectorEffects()
    }

    /// Adds pseudo-3D vector effects to boss
    private func add3DVectorEffects() {
        let size = config.size
        let level = getCurrentLevel()

        // Energy core for all bosses (gets more complex with levels)
        let coreRadius = size * 0.25
        let coreLayers = min(3 + level / 3, 6) // More layers for higher levels
        let energyCore = VectorFX3D.createEnergyCore(
            radius: coreRadius,
            color: config.strokeColor,
            layers: coreLayers
        )
        energyCore.zPosition = -2
        addChild(energyCore)

        // Force field for levels 3+
        if level >= 3 {
            let forceField = VectorFX3D.createForceField(
                radius: size * 0.6,
                color: config.color.withAlphaComponent(0.6)
            )
            forceField.zPosition = -3
            addChild(forceField)
        }

        // Rotating cannons for levels 4+
        if level >= 4 {
            let cannonCount = min(4 + (level - 4), 8)
            let cannons = VectorFX3D.createRotatingCannons(
                count: cannonCount,
                radius: size * 0.45,
                color: config.strokeColor
            )
            cannons.zPosition = -1
            addChild(cannons)
        }

        // Orbital defense for levels 5+
        if level >= 5 {
            let orbitalDefense = VectorFX3D.createOrbitalDefense(
                count: 6,
                radius: size * 0.7,
                color: config.strokeColor.withAlphaComponent(0.8)
            )
            orbitalDefense.zPosition = -4
            addChild(orbitalDefense)
        }

        // Radar sweep for levels 7+
        if level >= 7 {
            let radar = VectorFX3D.createRadarSweep(
                radius: size * 0.8,
                color: UIColor.red.withAlphaComponent(0.5)
            )
            radar.zPosition = -5
            addChild(radar)
        }

        // Massive shield sphere for final bosses (level 15+)
        if level >= 15 {
            let shield = VectorFX3D.createShieldSphere(
                radius: size * 0.9,
                color: config.color.withAlphaComponent(0.4),
                persistent: true
            )
            shield.zPosition = -6
            addChild(shield)
        }
    }

    /// Gets current level from config
    private func getCurrentLevel() -> Int {
        // Determine level based on boss health/points
        switch config.maxHealth {
        case 20: return 1
        case 35: return 2
        case 50: return 3
        case 70: return 4
        case 90: return 5
        case 110: return 6
        case 135: return 7
        case 160: return 8
        case 200: return 10
        case 250: return 15
        case 300: return 20
        default: return max(1, config.maxHealth / 20)
        }
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

    /// How far below the HUD margin the health bar hangs.
    ///
    /// Not private so `jetshotTests` can assert the placement without restating the
    /// number. The point of that test is that the bar is measured down from
    /// `GameConfiguration.topMargin(in:)`, and a test carrying its own copy of the drop
    /// would keep passing if the margin fell out of the formula again — which is exactly
    /// what went wrong here.
    static let healthBarDropBelowHUD: CGFloat = 100

    /// Builds the health bar. Its *position* is set later, by `layoutHealthBar(in:)`.
    ///
    /// The split is forced by the safe-area inset. This runs from `init`, where the boss
    /// is not in a scene yet, so it has no view to ask — the lookup that used to sit here
    /// read `self.scene?.view` and could therefore only ever return nil, pinning the
    /// margin to `minTopMargin` on every device. On a notched iPhone that pulled the bar
    /// ~40pt up into the HUD band and took the "⚡ BOSS ⚡" label with it, right under the
    /// score and lives.
    private func setupHealthBar(sceneSize: CGSize) {
        // Health bar background
        let barWidth: CGFloat = sceneSize.width * 0.8
        let barHeight: CGFloat = 20

        healthBar = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 5)
        healthBar.fillColor = UIColor(white: 0.2, alpha: 0.8)
        healthBar.strokeColor = .white
        healthBar.lineWidth = 2
        healthBar.zPosition = 150

        // Health bar fill
        healthBarFill = SKShapeNode(rectOf: CGSize(width: barWidth - 4, height: barHeight - 4), cornerRadius: 4)
        healthBarFill.fillColor = .red
        healthBarFill.strokeColor = .clear
        healthBarFill.position = CGPoint(x: 0, y: 0)
        healthBar.addChild(healthBarFill)

        // Boss name label.
        //
        // Positioned relative to healthBar, which is what it is parented to. It used to
        // be given the same scene-space coordinates as the bar itself, so it landed at
        // (sceneWidth, 2 * barY + 30) — off the right edge and far above the top of the
        // screen, i.e. never visible at all.
        let bossLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        bossLabel.text = L10n.HUD.boss
        bossLabel.fontSize = 24
        bossLabel.fontColor = .yellow
        bossLabel.position = CGPoint(x: 0, y: 30)
        bossLabel.zPosition = 1
        healthBar.addChild(bossLabel)
    }

    func addHealthBarToScene(_ scene: GameScene) {
        layoutHealthBar(in: scene)
        scene.gameContentNode.addChild(healthBar)
    }

    /// Places the health bar under the HUD.
    ///
    /// Separate from `addHealthBarToScene(_:)` so `GameScene.didChangeSize(_:)` can call
    /// it too: the bar was placed for whatever the scene measured when the boss spawned,
    /// and nothing re-flowed it afterwards. Portrait-only plus `UIRequiresFullScreen`
    /// makes a mid-fight resize hard to reach today, but every other HUD element in that
    /// method is already re-flowed and this one was the exception.
    ///
    /// Position only — the bar's width is baked into its shape path in
    /// `setupHealthBar(sceneSize:)` and a resize would need the path rebuilt.
    func layoutHealthBar(in scene: GameScene) {
        healthBar.position = CGPoint(
            x: scene.size.width / 2,
            y: scene.size.height - GameConfiguration.topMargin(in: scene.view) - Self.healthBarDropBelowHUD
        )
    }

    func removeHealthBarFromScene() {
        // Remove health bar only if it's still in the scene
        if healthBar.parent != nil {
            healthBar.removeFromParent()
        }
    }

    /// Whether the health bar is currently in the scene, for `jetshotTests`.
    ///
    /// The bar is attached and detached independently of the boss node — `takeDamage()`
    /// drops it the instant the boss dies, well before the explosion sequence removes
    /// the boss itself — so "is the boss on screen" does not answer this.
    var isHealthBarAttached: Bool {
        return healthBar.parent != nil
    }

    /// The health bar's Y in scene coordinates, for `jetshotTests`.
    ///
    /// The bar itself stays private and is unnamed, so there is no other way to reach it.
    /// Its placement is what regressed: computed in `init`, where the node has no view to
    /// read a safe-area inset from and no scene whose height it can measure against.
    var healthBarY: CGFloat {
        return healthBar.position.y
    }

    func enterScene(completion: @escaping () -> Void) {
        guard let scene = self.scene else { return }

        // Position below the HUD. Through `GameConfiguration` rather than the inline
        // `max(safeAreaTop + 20, 40)` this used to carry: that duplicated
        // `topMargin(safeAreaTop:)` with its constants copied out, so a change to
        // `minTopMargin` or `safeAreaTopSpacing` would move the HUD and leave the boss
        // behind.
        let topMargin = GameConfiguration.topMargin(in: scene.view)
        let targetY = scene.size.height - topMargin - config.size - 80 // More margin below UI (increased from 30)

        // Entrance animation
        let moveIn = SKAction.moveTo(y: targetY, duration: 2.0)
        moveIn.timingMode = .easeOut

        // Weak, like the explosion closures in takeDamage(): SpriteKit holds the action
        // on this node, so a strong capture makes node -> action -> closure -> node.
        run(moveIn) { [weak self] in
            guard let self = self else { return }
            self.isActive = true
            self.startMovement()
            completion()
        }
    }

    private func startMovement() {
        guard let scene = self.scene else { return }

        // Margin is the boss's *half* width, not `config.size`.
        //
        // `config.size` is the full silhouette — `createShapePath` spans -size/2 to
        // +size/2 — so insetting each edge by the whole diameter reserved twice the
        // room needed and collapsed the patrol it is supposed to define. It never
        // crashed, because `moveTo` accepts any coordinate, so the late-game bosses
        // simply stopped moving: on a 402pt iPhone the level 50 boss (size 200) swept
        // between x=200 and x=202, two points, and on a 375pt screen the range
        // inverted outright (200 -> 175) and parked it right of centre.
        let margin = config.size * 0.5 + 8

        // Clamped so a boss wider than the screen centres instead of inverting, the
        // same fallback `CoinManager.place` uses for over-wide formations.
        let centre = scene.size.width / 2
        let minX = min(margin, centre)
        let maxX = max(scene.size.width - margin, centre)

        // Create side-to-side movement
        let moveLeft = SKAction.moveTo(x: minX, duration: config.movementSpeed)
        moveLeft.timingMode = .easeInEaseOut

        let moveRight = SKAction.moveTo(x: maxX, duration: config.movementSpeed)
        moveRight.timingMode = .easeInEaseOut

        let sequence = SKAction.sequence([moveLeft, moveRight])
        movementAction = SKAction.repeatForever(sequence)

        if let movement = movementAction {
            run(movement)
        }
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
                let explode = SKAction.run { [weak self] in
                    guard let self = self else { return }
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
            let finalExplosion = SKAction.run { [weak self] in
                guard let self = self else { return }
                self.createExplosion(offset: .zero, isLarge: true)
                self.removeHealthBarFromScene()
                // Play multiple explosion sounds for the final big explosion
                if let scene = self.scene as? GameScene {
                    SoundManager.shared.playExplosionSound(on: scene)
                }
            }

            // Additional explosion sounds using SKAction to respect pause state
            let secondExplosion = SKAction.sequence([
                SKAction.wait(forDuration: 0.1),
                SKAction.run { [weak self] in
                    if let scene = self?.scene as? GameScene {
                        SoundManager.shared.playExplosionSound(on: scene)
                    }
                }
            ])
            let thirdExplosion = SKAction.sequence([
                SKAction.wait(forDuration: 0.2),
                SKAction.run { [weak self] in
                    if let scene = self?.scene as? GameScene {
                        SoundManager.shared.playExplosionSound(on: scene)
                    }
                }
            ])

            explosionActions.append(finalWait)
            explosionActions.append(finalExplosion)

            // Run additional sound effects in parallel
            run(secondExplosion, withKey: "bossExplosionSound2")
            run(thirdExplosion, withKey: "bossExplosionSound3")

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
        guard let scene = scene else { return false }
        let originalWidth = (scene.size.width * 0.8) - 4
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
            explosion.particleTexture = ParticleTexture.softCircle(diameter: 32)
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


    func getPoints() -> Int {
        return config.points
    }

    func isAlive() -> Bool {
        return isActive && currentHealth > 0
    }

    func getAttackPatterns() -> [BossAttackPattern] {
        return config.attackPatterns
    }

    /// Remaining health as a fraction of the boss's maximum, 0...1.
    var healthFraction: CGFloat {
        guard config.maxHealth > 0 else { return 0 }
        return CGFloat(currentHealth) / CGFloat(config.maxHealth)
    }

    /// Which act of the fight the boss is currently in. See `BossPhaseRules`.
    var currentPhase: Int {
        return BossPhaseRules.phase(forHealthFraction: healthFraction)
    }

    /// The attacks available to the boss right now — the prefix of its authored list that
    /// its current health has unlocked.
    func availableAttackPatterns() -> [BossAttackPattern] {
        let all = config.attackPatterns
        let count = BossPhaseRules.patternCount(
            forPhase: currentPhase,
            totalPatterns: all.count
        )
        return Array(all.prefix(count))
    }

    /// The boss's own size and stroke colour, for effects `BossManager` builds around it.
    var bossSize: CGFloat { config.size }
    var telegraphColor: UIColor { config.strokeColor }

    /// Marks a phase change on the boss itself: a lurch outward and a ring thrown off the
    /// silhouette.
    ///
    /// Loud on purpose. The transition is the one moment in a fight that tells the player
    /// they are actually getting somewhere, and against a 600 hit point level 50 boss
    /// that readout is most of what stops the fight feeling like a wall.
    ///
    /// Deliberately no alpha animation: `takeDamage()` runs an unkeyed alpha flash on
    /// every single hit, and a second, longer one from here would be fighting it for the
    /// same property throughout the transition.
    func playPhaseTransitionEffect() {
        removeAction(forKey: "bossPhaseFlash")

        let flash = SKAction.sequence([
            SKAction.scale(to: 1.18, duration: 0.14),
            SKAction.scale(to: 1.0, duration: 0.22)
        ])
        run(flash, withKey: "bossPhaseFlash")

        let ring = SKShapeNode(circleOfRadius: config.size * 0.5)
        ring.strokeColor = config.strokeColor
        ring.fillColor = .clear
        ring.lineWidth = 5
        ring.zPosition = -1
        ring.blendMode = .add
        addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.4, duration: 0.5),
                SKAction.fadeOut(withDuration: 0.5)
            ]),
            SKAction.removeFromParent()
        ]))
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
        // `gameContentNode`, not the scene: the scene keeps ticking while the game is
        // paused, so debris used to keep tumbling behind the pause menu. It also means
        // the positions below — computed from `position`, which is in gameContentNode's
        // space — land in the space they were measured in rather than working by
        // coincidence because that node happens to sit at the origin unscaled.
        guard let scene = self.scene as? GameScene else { return }
        let debrisParent = scene.gameContentNode ?? scene

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

            debrisParent.addChild(debris)

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
        // See createDebris() for why this is gameContentNode rather than the scene.
        guard let scene = self.scene as? GameScene else { return }
        let chunkParent = scene.gameContentNode ?? scene

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

        chunkParent.addChild(chunk)

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

        scorch.run(SKAction.fadeAlpha(to: 0.6, duration: 0.3))
    }

    private func createSmokeTrail(isHeavy: Bool = false) {
        guard let scene = self.scene as? GameScene else { return }

        let smoke = SKEmitterNode()
        smoke.position = position
        smoke.zPosition = zPosition - 1

        if smoke.particleTexture == nil {
            smoke.particleTexture = ParticleTexture.softCircle(diameter: 32)
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
            sparks.particleTexture = ParticleTexture.softCircle(diameter: 32)
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
            explosion.particleTexture = ParticleTexture.softCircle(diameter: 32)
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
