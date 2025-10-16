//
//  Enemy.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import SpriteKit

// Enemy types with different behaviors
enum EnemyType {
    case basic      // Standard movement, moderate shooting
    case fast       // Fast movement, less shooting
    case heavy      // Slow movement, frequent shooting
    case zigzag     // Zigzag pattern, moderate shooting
    case kamikaze   // Fast straight dive, no shooting
    case formation  // Formation flying with curved attack patterns

    // New individual enemies
    case sniper     // Slow, stops briefly, precise aimed shots at player
    case tank       // Very slow, massive, 2 HP, shoots 3-bullet spread
    case striker    // Fast horizontal movement (left-right), quick shots
    case turret     // Flies down, docks, rotates and shoots bursts in all directions, then continues down
    case turretSpiral // Flies down, docks, rotates continuously and shoots spiral pattern, then continues down
    case mine       // Slow descent, stops, countdown, explodes with shrapnel

    // New formation enemies
    case scout      // Small formations (3-4), quick pass-through attacks
    case eliteGuard // Medium formations (5-6), synchronized attacks
    case bomber     // Large formations (6-8), slow but heavy fire
    case spinner    // Medium formations (4-5), rotating formation, spiral attacks
    case commander  // Small formations (3-4), center of larger groups, wave attacks
    case meteorSwarm // Meteor swarm - chaotic group movement, no shooting, damage on collision
    case flanker    // Side attackers - fly in from left/right sides, arc across screen

    // Additional new enemies for variety
    case ghost      // Phases in/out of visibility, unpredictable movement
    case shield     // Has rotating shield, must shoot from behind
    case splitter   // When destroyed, splits into 2 smaller enemies
    case laser      // Charges and fires continuous laser beam
    case bouncer    // Bounces off screen edges like a pinball
    case vortex     // Spins and pulls player bullets toward it (absorbs some)
    case teleporter // Teleports to random positions periodically
    case mirror     // Reflects player bullets back

    var color: UIColor {
        switch self {
        case .basic: return .red
        case .fast: return .orange
        case .heavy: return .purple
        case .zigzag: return .cyan
        case .kamikaze: return .yellow
        case .formation: return UIColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 1.0)
        case .sniper: return UIColor(red: 1.0, green: 0.4, blue: 0.2, alpha: 1.0) // Orange-red
        case .tank: return UIColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1.0) // Dark blue
        case .striker: return UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0) // Electric blue
        case .turret: return UIColor(red: 0.6, green: 0.2, blue: 0.8, alpha: 1.0) // Dark purple
        case .turretSpiral: return UIColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1.0) // Cyan-blue
        case .mine: return UIColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0) // Dark gray
        case .scout: return UIColor(red: 0.5, green: 0.9, blue: 0.5, alpha: 1.0) // Light green
        case .eliteGuard: return UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0) // Gold
        case .bomber: return UIColor(red: 0.4, green: 0.2, blue: 0.5, alpha: 1.0) // Dark purple
        case .spinner: return UIColor(red: 0.9, green: 0.9, blue: 1.0, alpha: 1.0) // Rainbow white
        case .commander: return UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1.0) // Bright red
        case .meteorSwarm: return UIColor(red: 0.4, green: 0.3, blue: 0.25, alpha: 1.0) // Brown-gray rock
        case .flanker: return UIColor(red: 0.0, green: 0.9, blue: 0.7, alpha: 1.0) // Bright teal
        case .ghost: return UIColor(red: 0.7, green: 0.7, blue: 0.9, alpha: 0.6) // Translucent purple
        case .shield: return UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1.0) // Green
        case .splitter: return UIColor(red: 0.9, green: 0.5, blue: 0.0, alpha: 1.0) // Orange
        case .laser: return UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0) // Bright red
        case .bouncer: return UIColor(red: 0.9, green: 0.9, blue: 0.2, alpha: 1.0) // Yellow
        case .vortex: return UIColor(red: 0.5, green: 0.2, blue: 0.8, alpha: 1.0) // Purple
        case .teleporter: return UIColor(red: 0.2, green: 0.9, blue: 0.9, alpha: 1.0) // Cyan
        case .mirror: return UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0) // Silver
        }
    }

    var strokeColor: UIColor {
        switch self {
        case .basic: return UIColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 1.0) // Light red
        case .fast: return UIColor(red: 1.0, green: 0.8, blue: 0.5, alpha: 1.0) // Light orange
        case .heavy: return UIColor(red: 0.9, green: 0.7, blue: 1.0, alpha: 1.0) // Light purple
        case .zigzag: return UIColor(red: 0.6, green: 1.0, blue: 1.0, alpha: 1.0) // Light cyan
        case .kamikaze: return UIColor(red: 1.0, green: 1.0, blue: 0.6, alpha: 1.0) // Light yellow
        case .formation: return UIColor(red: 0.5, green: 1.0, blue: 0.7, alpha: 1.0) // Light green
        case .sniper: return UIColor(red: 1.0, green: 0.7, blue: 0.5, alpha: 1.0) // Light orange-red
        case .tank: return UIColor(red: 0.5, green: 0.6, blue: 0.9, alpha: 1.0) // Light blue
        case .striker: return UIColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 1.0) // Light electric blue
        case .turret: return UIColor(red: 0.9, green: 0.6, blue: 1.0, alpha: 1.0) // Light purple
        case .turretSpiral: return UIColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 1.0) // Light cyan-blue
        case .mine: return UIColor(red: 0.45, green: 0.45, blue: 0.5, alpha: 1.0) // Light gray
        case .scout: return UIColor(red: 0.7, green: 1.0, blue: 0.7, alpha: 1.0) // Lighter green
        case .eliteGuard: return UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1.0) // Light gold
        case .bomber: return UIColor(red: 0.7, green: 0.5, blue: 0.8, alpha: 1.0) // Light purple
        case .spinner: return UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0) // Pure white
        case .commander: return UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1.0) // Light red
        case .meteorSwarm: return UIColor(red: 0.6, green: 0.5, blue: 0.45, alpha: 1.0) // Light brown-gray
        case .flanker: return UIColor(red: 0.5, green: 1.0, blue: 0.9, alpha: 1.0) // Light teal
        case .ghost: return UIColor(red: 0.9, green: 0.9, blue: 1.0, alpha: 0.8) // Light translucent purple
        case .shield: return UIColor(red: 0.5, green: 1.0, blue: 0.6, alpha: 1.0) // Light green
        case .splitter: return UIColor(red: 1.0, green: 0.8, blue: 0.5, alpha: 1.0) // Light orange
        case .laser: return UIColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 1.0) // Light red
        case .bouncer: return UIColor(red: 1.0, green: 1.0, blue: 0.6, alpha: 1.0) // Light yellow
        case .vortex: return UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0) // Light purple
        case .teleporter: return UIColor(red: 0.6, green: 1.0, blue: 1.0, alpha: 1.0) // Light cyan
        case .mirror: return UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0) // Bright silver
        }
    }

    var shootIntervalRange: ClosedRange<TimeInterval> {
        switch self {
        case .basic: return 1.5...3.5
        case .fast: return 2.5...4.5
        case .heavy: return 0.8...1.5
        case .zigzag: return 1.8...3.2
        case .kamikaze: return 100...100 // Never shoots
        case .formation: return 2.0...4.0
        case .sniper: return 2.5...4.0 // Less often but precise
        case .tank: return 1.2...2.0 // Moderate, spread shots
        case .striker: return 1.0...1.8 // Fast shots
        case .turret: return 0.3...0.5 // Very fast bursts when docked
        case .turretSpiral: return 0.15...0.2 // Rapid fire for spiral effect
        case .mine: return 100...100 // Doesn't shoot, explodes
        case .scout: return 2.2...3.5 // Quick but not constant
        case .eliteGuard: return 1.8...3.0 // Coordinated
        case .bomber: return 0.9...1.6 // Heavy fire
        case .spinner: return 2.0...3.5 // Moderate
        case .commander: return 1.5...2.5 // Aggressive
        case .meteorSwarm: return 100...100 // Never shoots, damage on collision
        case .flanker: return 1.5...2.5 // Fast shots during pass
        case .ghost: return 2.0...3.5 // Shoots while visible
        case .shield: return 1.8...3.0 // Moderate shooting
        case .splitter: return 1.5...2.8 // Regular shots
        case .laser: return 5.0...7.0 // Rare but powerful laser
        case .bouncer: return 1.2...2.0 // Fast chaotic shots
        case .vortex: return 100...100 // Doesn't shoot, absorbs bullets
        case .teleporter: return 1.6...2.8 // Moderate shooting
        case .mirror: return 100...100 // Reflects bullets instead
        }
    }

    var movementDurationRange: ClosedRange<TimeInterval> {
        switch self {
        case .basic: return 3.0...5.0
        case .fast: return 1.5...2.5
        case .heavy: return 5.0...7.0
        case .zigzag: return 4.0...6.0
        case .kamikaze: return 1.0...1.5
        case .formation: return 2.5...3.5
        case .sniper: return 5.0...7.0 // Very slow
        case .tank: return 6.0...8.0 // Slowest
        case .striker: return 2.5...3.5 // Fast horizontal
        case .turret: return 3.0...4.0 // Medium speed for descent
        case .turretSpiral: return 3.0...4.0 // Medium speed for descent
        case .mine: return 4.0...5.0 // Slow descent before stopping
        case .scout: return 2.0...3.0 // Quick pass
        case .eliteGuard: return 2.5...3.5 // Medium
        case .bomber: return 3.5...5.0 // Slow
        case .spinner: return 2.5...3.5 // Medium
        case .commander: return 3.0...4.0 // Medium-slow
        case .meteorSwarm: return 1.8...2.8 // Fast, chaotic movement
        case .flanker: return 2.2...3.0 // Fast arc across screen
        case .ghost: return 3.5...5.0 // Slow, erratic
        case .shield: return 4.0...6.0 // Slow, defensive
        case .splitter: return 3.0...4.5 // Medium speed
        case .laser: return 4.5...6.5 // Slow, charges laser
        case .bouncer: return 2.0...3.5 // Fast, bouncy
        case .vortex: return 5.0...7.0 // Very slow
        case .teleporter: return 2.5...4.0 // Medium, teleports
        case .mirror: return 3.5...5.0 // Medium-slow
        }
    }

    var size: CGFloat {
        switch self {
        case .basic: return 1.0
        case .fast: return 0.8
        case .heavy: return 1.3
        case .zigzag: return 0.9
        case .kamikaze: return 0.85
        case .formation: return 0.95
        case .sniper: return 0.95
        case .tank: return 1.5 // Largest
        case .striker: return 0.85
        case .turret: return 1.2 // Large turret
        case .turretSpiral: return 1.2 // Large turret
        case .mine: return 1.1 // Medium mine
        case .scout: return 0.9
        case .eliteGuard: return 1.0
        case .bomber: return 1.1
        case .spinner: return 0.95
        case .commander: return 1.05
        case .meteorSwarm: return 0.75 // Smaller, swarm of many
        case .flanker: return 0.9 // Medium-small, fast mover
        case .ghost: return 0.9 // Medium-small, ethereal
        case .shield: return 1.1 // Medium-large with shield
        case .splitter: return 1.0 // Medium
        case .laser: return 1.2 // Large laser platform
        case .bouncer: return 0.85 // Small, bouncy
        case .vortex: return 1.3 // Large vortex
        case .teleporter: return 0.95 // Medium
        case .mirror: return 1.0 // Medium
        }
    }

    var points: Int {
        switch self {
        case .basic: return 10
        case .fast: return 15
        case .heavy: return 20
        case .zigzag: return 12
        case .kamikaze: return 8
        case .formation: return 25
        case .sniper: return 30
        case .tank: return 50
        case .striker: return 18
        case .turret: return 35
        case .turretSpiral: return 40
        case .mine: return 25
        case .scout: return 15
        case .eliteGuard: return 35
        case .bomber: return 25
        case .spinner: return 40
        case .commander: return 45
        case .meteorSwarm: return 12 // Low points but comes in swarms
        case .flanker: return 20 // Medium points for side attackers
        case .ghost: return 28 // Hard to hit
        case .shield: return 35 // Protected
        case .splitter: return 25 // Splits into more
        case .laser: return 40 // Powerful
        case .bouncer: return 22 // Unpredictable
        case .vortex: return 50 // Very challenging
        case .teleporter: return 32 // Evasive
        case .mirror: return 38 // Reflects bullets
        }
    }

    var maxHealth: Int {
        switch self {
        case .tank: return 2 // Only tank has 2 HP
        default: return 1
        }
    }
}

class Enemy: SKShapeNode {

    // Shooting properties (optimized to use SKAction instead of Timer)
    private let shootInterval: TimeInterval
    var gameScene: GameScene?
    private var movementDuration: TimeInterval = 4.0 // Will be set in startMovement
    let enemyType: EnemyType
    private var sceneSize: CGSize

    // Health system
    var health: Int
    var maxHealth: Int

    // Movement properties for zigzag
    private var zigzagAmplitude: CGFloat = 80
    private var zigzagFrequency: CGFloat = 2.0

    // Movement properties for striker (horizontal)
    private var horizontalAmplitude: CGFloat = 120
    private var horizontalFrequency: CGFloat = 3.0

    // Formation properties
    var formationPosition: CGPoint?
    var isInFormation: Bool = false
    private var customMovementCompletion: (() -> Void)?
    private var hasCompletedMovement: Bool = false

    // Sniper properties
    private let shootActionKey = "enemyShootAction"

    // Turret properties
    private var isTurretDocked: Bool = false
    private var turretRotationNode: SKNode?
    private var turretGunBarrels: [SKShapeNode] = []
    private let turretDockDuration: TimeInterval = 4.0 // How long turret stays docked and shooting

    // Mine properties
    var isMineArmed: Bool = false
    private let mineArmingTime: TimeInterval = 2.0 // Time before mine arms
    private let mineCountdown: TimeInterval = 3.0 // Countdown before explosion

    // Ghost properties
    private var isGhostVisible: Bool = true
    private var ghostPhaseInterval: TimeInterval = 2.0

    // Shield properties
    private var shieldNode: SKShapeNode?
    private var shieldRotation: CGFloat = 0

    // Laser properties
    private var isChargingLaser: Bool = false
    private var laserBeam: SKShapeNode?

    // Bouncer properties
    private var bouncerVelocity: CGVector = CGVector(dx: 0, dy: 0)

    // Teleporter properties
    private var teleportInterval: TimeInterval = 3.0
    private var lastTeleportTime: TimeInterval = 0

    init(sceneSize: CGSize, scene: SKScene, type: EnemyType = .basic) {
        self.enemyType = type
        self.sceneSize = sceneSize
        self.shootInterval = TimeInterval.random(in: type.shootIntervalRange)
        // Accept SKScene but store a weak reference to GameScene when possible
        self.gameScene = scene as? GameScene
        self.maxHealth = type.maxHealth
        self.health = type.maxHealth

        super.init()

        setupEnemy(sceneSize: sceneSize)
        // Don't start shooting immediately for special types
        if type != .kamikaze && type != .turret && type != .turretSpiral && type != .mine &&
           type != .meteorSwarm && type != .vortex && type != .mirror {
            startShooting()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func pauseShooting() {
        removeAction(forKey: shootActionKey)
    }

    // Mark enemy as destroyed (prevents completion callback from firing)
    func markAsDestroyed() {
        hasCompletedMovement = true
        removeAllActions()
        pauseShooting()

        // Stop turret specific actions
        if enemyType == .turret || enemyType == .turretSpiral {
            stopTurretDockMode()
        }
    }

    private func setupEnemy(sceneSize: CGSize) {
        let baseSize: CGFloat = 12
        let sizeMultiplier = enemyType.size

        // Create different shapes for different enemy types
        let path = CGMutablePath()

        switch enemyType {
        case .basic:
            // Inverted triangle with wings
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier))  // Bottom point
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: -12 * sizeMultiplier, y: baseSize * sizeMultiplier))  // Left wing
            path.addLine(to: CGPoint(x: -4 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 4 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 12 * sizeMultiplier, y: baseSize * sizeMultiplier))  // Right wing
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.closeSubpath()

        case .fast:
            // Sleek dart shape
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.2))  // Sharp nose
            path.addLine(to: CGPoint(x: -6 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: -10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: -4 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.4))
            path.addLine(to: CGPoint(x: 4 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: 10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: 6 * sizeMultiplier, y: 0))
            path.closeSubpath()

        case .heavy:
            // Bulky rectangular shape with angles
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: -6 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.4))
            path.addLine(to: CGPoint(x: -11 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: -13 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 13 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: 11 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: 6 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.4))
            path.closeSubpath()

        case .zigzag:
            // Curved organic shape
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: -7 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -11 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -7 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: 7 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 11 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: 7 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.3))
            path.closeSubpath()

        case .kamikaze:
            // Sharp aggressive V-shape
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.3))
            path.addLine(to: CGPoint(x: -5 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -9 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: -4 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: 4 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: 9 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 5 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.closeSubpath()

        case .formation:
            // Diamond with extended wings
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: -7 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: -13 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.4))
            path.addLine(to: CGPoint(x: -7 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 7 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: 13 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.4))
            path.addLine(to: CGPoint(x: 7 * sizeMultiplier, y: 0))
            path.closeSubpath()

        case .sniper:
            // Long barrel shape with scope
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.3))  // Long barrel
            path.addLine(to: CGPoint(x: -3 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: -11 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: -6 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: 6 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 11 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: 3 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.5))
            path.closeSubpath()

        case .tank:
            // Large, boxy, armored shape
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: -7 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: -12 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: -14 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -12 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: -6 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.9))
            path.addLine(to: CGPoint(x: 6 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 12 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 14 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: 12 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: 7 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.5))
            path.closeSubpath()

        case .striker:
            // Streamlined horizontal shape with fins
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.1))
            path.addLine(to: CGPoint(x: -5 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: -12 * sizeMultiplier, y: 0))  // Wide fins
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.4))
            path.addLine(to: CGPoint(x: -3 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: 3 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.4))
            path.addLine(to: CGPoint(x: 12 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: 5 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.closeSubpath()

        case .turret:
            // Octagonal turret platform with gun barrels
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.1))
            path.addLine(to: CGPoint(x: -5 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: -10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: -3 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 3 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: 5 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.7))
            path.closeSubpath()

        case .turretSpiral:
            // Octagonal turret platform (similar to turret but slightly different proportions)
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.1))
            path.addLine(to: CGPoint(x: -5 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: -10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: -3 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 3 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: 5 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.7))
            path.closeSubpath()

        case .mine:
            // Perfect 8-pointed star mine shape
            let outerRadius = baseSize * sizeMultiplier * 1.0
            let innerRadius = baseSize * sizeMultiplier * 0.45
            let points = 8

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

        case .scout:
            // Small, agile triangular shape
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.1))
            path.addLine(to: CGPoint(x: -6 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: -5 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: 5 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: 6 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.closeSubpath()

        case .eliteGuard:
            // Elegant symmetrical shape with sharp edges
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.2))
            path.addLine(to: CGPoint(x: -5 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.4))
            path.addLine(to: CGPoint(x: -9 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: -12 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: -7 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.9))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 7 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.9))
            path.addLine(to: CGPoint(x: 12 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: 9 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: 5 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.4))
            path.closeSubpath()

        case .bomber:
            // Large, heavy bomber shape
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -13 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: -11 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: -5 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.9))
            path.addLine(to: CGPoint(x: 5 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 11 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: 13 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.3))
            path.closeSubpath()

        case .spinner:
            // Circular with protruding blades
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.2))
            path.addLine(to: CGPoint(x: -4 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: -10 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -11 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: -7 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 7 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.7))
            path.addLine(to: CGPoint(x: 11 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: 10 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: 4 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.6))
            path.closeSubpath()

        case .commander:
            // Command ship with star-like center
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.3))
            path.addLine(to: CGPoint(x: -4 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: -10 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -13 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: -6 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 6 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 13 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: 10 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: 4 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.5))
            path.closeSubpath()

        case .meteorSwarm:
            // Irregular rocky meteor shape
            let points = 8
            let radius = baseSize * sizeMultiplier
            var firstPoint = true
            for i in 0..<points {
                let angle = (CGFloat(i) / CGFloat(points)) * .pi * 2
                // Random variation for irregular shape
                let variation = CGFloat.random(in: 0.7...1.3)
                let x = cos(angle) * radius * variation
                let y = sin(angle) * radius * variation
                if firstPoint {
                    path.move(to: CGPoint(x: x, y: y))
                    firstPoint = false
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()

        case .flanker:
            // Sleek arrow-like shape pointing horizontally (for side attacks)
            path.move(to: CGPoint(x: baseSize * sizeMultiplier * 1.4, y: 0)) // Sharp nose
            path.addLine(to: CGPoint(x: -baseSize * sizeMultiplier * 0.3, y: -8 * sizeMultiplier))
            path.addLine(to: CGPoint(x: -baseSize * sizeMultiplier * 0.8, y: -6 * sizeMultiplier))
            path.addLine(to: CGPoint(x: -baseSize * sizeMultiplier * 0.8, y: -2 * sizeMultiplier))
            path.addLine(to: CGPoint(x: -baseSize * sizeMultiplier * 1.2, y: 0)) // Tail
            path.addLine(to: CGPoint(x: -baseSize * sizeMultiplier * 0.8, y: 2 * sizeMultiplier))
            path.addLine(to: CGPoint(x: -baseSize * sizeMultiplier * 0.8, y: 6 * sizeMultiplier))
            path.addLine(to: CGPoint(x: -baseSize * sizeMultiplier * 0.3, y: 8 * sizeMultiplier))
            path.closeSubpath()

        case .ghost:
            // Wavy ghost-like shape
            let radius = baseSize * sizeMultiplier
            path.move(to: CGPoint(x: 0, y: -radius * 1.2))
            path.addLine(to: CGPoint(x: -radius * 0.7, y: -radius * 0.4))
            path.addLine(to: CGPoint(x: -radius, y: radius * 0.2))
            // Wavy bottom
            path.addLine(to: CGPoint(x: -radius * 0.7, y: radius))
            path.addLine(to: CGPoint(x: -radius * 0.4, y: radius * 0.7))
            path.addLine(to: CGPoint(x: 0, y: radius))
            path.addLine(to: CGPoint(x: radius * 0.4, y: radius * 0.7))
            path.addLine(to: CGPoint(x: radius * 0.7, y: radius))
            path.addLine(to: CGPoint(x: radius, y: radius * 0.2))
            path.addLine(to: CGPoint(x: radius * 0.7, y: -radius * 0.4))
            path.closeSubpath()

        case .shield:
            // Hexagonal shape with shield
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.1))
            path.addLine(to: CGPoint(x: -7 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: -9 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: -7 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 7 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: 9 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: 7 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.6))
            path.closeSubpath()

        case .splitter:
            // Y-shaped craft that looks like it could split
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.3))
            path.addLine(to: CGPoint(x: -4 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: -7 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.9))
            path.addLine(to: CGPoint(x: -2 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.4))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: 2 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.4))
            path.addLine(to: CGPoint(x: 7 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.9))
            path.addLine(to: CGPoint(x: 10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.5))
            path.addLine(to: CGPoint(x: 4 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.3))
            path.closeSubpath()

        case .laser:
            // Long rectangular shape with laser emitter
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.4))
            path.addLine(to: CGPoint(x: -6 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: -4 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.8))
            path.addLine(to: CGPoint(x: 4 * sizeMultiplier, y: baseSize * sizeMultiplier))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.2))
            path.addLine(to: CGPoint(x: 6 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.8))
            path.closeSubpath()

        case .bouncer:
            // Round bouncy ball shape with segments
            let radius = baseSize * sizeMultiplier
            let segments = 12
            for i in 0..<segments {
                let angle = (CGFloat(i) / CGFloat(segments)) * .pi * 2
                let x = cos(angle) * radius
                let y = sin(angle) * radius
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()

        case .vortex:
            // Spiral vortex shape
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.2))
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4
                let radius = baseSize * sizeMultiplier * (1.2 - CGFloat(i) * 0.1)
                let x = cos(angle) * radius
                let y = sin(angle) * radius
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: 0, y: 0))

            // Second spiral arm
            for i in 0..<8 {
                let angle = .pi + CGFloat(i) * .pi / 4
                let radius = baseSize * sizeMultiplier * (0.3 + CGFloat(i) * 0.1)
                let x = cos(angle) * radius
                let y = sin(angle) * radius
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.closeSubpath()

        case .teleporter:
            // Geometric teleporter with portals
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.1))
            path.addLine(to: CGPoint(x: -8 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.4))
            path.addLine(to: CGPoint(x: -10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: -5 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.9))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 0.6))
            path.addLine(to: CGPoint(x: 5 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.9))
            path.addLine(to: CGPoint(x: 10 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.3))
            path.addLine(to: CGPoint(x: 8 * sizeMultiplier, y: -baseSize * sizeMultiplier * 0.4))
            path.closeSubpath()

        case .mirror:
            // Reflective diamond shape
            path.move(to: CGPoint(x: 0, y: -baseSize * sizeMultiplier * 1.3))
            path.addLine(to: CGPoint(x: -9 * sizeMultiplier, y: 0))
            path.addLine(to: CGPoint(x: 0, y: baseSize * sizeMultiplier * 1.3))
            path.addLine(to: CGPoint(x: 9 * sizeMultiplier, y: 0))
            path.closeSubpath()
        }

        self.path = path
        self.fillColor = enemyType.color
        self.strokeColor = enemyType.strokeColor
        self.lineWidth = 2.5
        self.name = "enemy"

        // Spawn position - flankers come from sides, others from top
        if enemyType == .flanker {
            // Spawn from left or right side
            let fromLeft = Bool.random()
            let randomY = CGFloat.random(in: (sceneSize.height * 0.3)...(sceneSize.height * 0.7))
            if fromLeft {
                self.position = CGPoint(x: -20, y: randomY)
                // Face right when coming from left
                self.zRotation = 0
            } else {
                self.position = CGPoint(x: sceneSize.width + 20, y: randomY)
                // Face left when coming from right (flip 180 degrees)
                self.zRotation = .pi
            }
        } else {
            // Random spawn position at top
            let randomX = CGFloat.random(in: 30...(sceneSize.width - 30))
            self.position = CGPoint(x: randomX, y: sceneSize.height + 20)
        }

        // Add cockpit/core detail (skip for meteor swarm, flanker, ghost, vortex, mirror)
        if enemyType != .meteorSwarm && enemyType != .flanker && enemyType != .ghost &&
           enemyType != .vortex && enemyType != .mirror {
            let coreSize: CGFloat = 3 * sizeMultiplier
            let core = SKShapeNode(circleOfRadius: coreSize)
            core.fillColor = UIColor.white.withAlphaComponent(0.8)
            core.strokeColor = enemyType.strokeColor
            core.lineWidth = 1.5
            core.position = CGPoint(x: 0, y: 0)
            core.zPosition = 1
            addChild(core)
        } else {
            // Add rocky texture details for meteors
            for _ in 0..<3 {
                let craterSize = CGFloat.random(in: 1.5...3.0) * sizeMultiplier
                let crater = SKShapeNode(circleOfRadius: craterSize)
                crater.fillColor = UIColor(red: 0.25, green: 0.18, blue: 0.15, alpha: 1.0)
                crater.strokeColor = .clear
                crater.position = CGPoint(
                    x: CGFloat.random(in: -4...4) * sizeMultiplier,
                    y: CGFloat.random(in: -4...4) * sizeMultiplier
                )
                crater.zPosition = 1
                addChild(crater)
            }
        }

        // Add engine glows for certain types
        if enemyType == .fast || enemyType == .kamikaze || enemyType == .striker || enemyType == .scout {
            let leftEngine = SKShapeNode(circleOfRadius: 2 * sizeMultiplier)
            leftEngine.fillColor = UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.7)
            leftEngine.strokeColor = .clear
            leftEngine.position = CGPoint(x: -5 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6)
            leftEngine.zPosition = -1
            addChild(leftEngine)

            let rightEngine = SKShapeNode(circleOfRadius: 2 * sizeMultiplier)
            rightEngine.fillColor = UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.7)
            rightEngine.strokeColor = .clear
            rightEngine.position = CGPoint(x: 5 * sizeMultiplier, y: baseSize * sizeMultiplier * 0.6)
            rightEngine.zPosition = -1
            addChild(rightEngine)

            // Engine flicker
            let flicker = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.4, duration: 0.1),
                SKAction.fadeAlpha(to: 0.8, duration: 0.1)
            ])
            leftEngine.run(SKAction.repeatForever(flicker))
            rightEngine.run(SKAction.repeatForever(flicker))
        }

        // Add special details for new enemy types
        if enemyType == .sniper {
            // Add scope/targeting laser
            let scope = SKShapeNode(rectOf: CGSize(width: 2, height: 4 * sizeMultiplier))
            scope.fillColor = UIColor.red.withAlphaComponent(0.6)
            scope.strokeColor = .clear
            scope.position = CGPoint(x: 0, y: -baseSize * sizeMultiplier * 0.8)
            scope.zPosition = 1
            addChild(scope)

            let scopePulse = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.3, duration: 0.3),
                SKAction.fadeAlpha(to: 0.9, duration: 0.3)
            ])
            scope.run(SKAction.repeatForever(scopePulse))
        }

        if enemyType == .tank {
            // Add armor plates
            let leftArmor = SKShapeNode(rectOf: CGSize(width: 4 * sizeMultiplier, height: 6 * sizeMultiplier))
            leftArmor.fillColor = enemyType.strokeColor.withAlphaComponent(0.5)
            leftArmor.strokeColor = .clear
            leftArmor.position = CGPoint(x: -8 * sizeMultiplier, y: 0)
            leftArmor.zPosition = 2
            addChild(leftArmor)

            let rightArmor = SKShapeNode(rectOf: CGSize(width: 4 * sizeMultiplier, height: 6 * sizeMultiplier))
            rightArmor.fillColor = enemyType.strokeColor.withAlphaComponent(0.5)
            rightArmor.strokeColor = .clear
            rightArmor.position = CGPoint(x: 8 * sizeMultiplier, y: 0)
            rightArmor.zPosition = 2
            addChild(rightArmor)
        }

        if enemyType == .turret || enemyType == .turretSpiral {
            // Create rotating gun mount
            let rotationNode = SKNode()
            rotationNode.position = CGPoint(x: 0, y: 0)
            rotationNode.zPosition = 3
            addChild(rotationNode)
            self.turretRotationNode = rotationNode

            if enemyType == .turret {
                // Add 4 gun barrels in cross pattern for standard turret
                let barrelLength: CGFloat = 8 * sizeMultiplier
                let barrelWidth: CGFloat = 2 * sizeMultiplier

                for i in 0..<4 {
                    let angle = CGFloat(i) * .pi / 2
                    let barrel = SKShapeNode(rectOf: CGSize(width: barrelWidth, height: barrelLength), cornerRadius: 1)
                    barrel.fillColor = UIColor(red: 0.8, green: 0.3, blue: 1.0, alpha: 1.0)
                    barrel.strokeColor = UIColor.white.withAlphaComponent(0.7)
                    barrel.lineWidth = 1
                    barrel.position = CGPoint(
                        x: cos(angle) * barrelLength / 2,
                        y: sin(angle) * barrelLength / 2
                    )
                    barrel.zRotation = angle + .pi / 2
                    rotationNode.addChild(barrel)
                    turretGunBarrels.append(barrel)
                }

                // Add central hub
                let hub = SKShapeNode(circleOfRadius: 4 * sizeMultiplier)
                hub.fillColor = UIColor(red: 0.4, green: 0.1, blue: 0.6, alpha: 1.0)
                hub.strokeColor = UIColor.white
                hub.lineWidth = 1.5
                rotationNode.addChild(hub)
            } else {
                // turretSpiral - single rotating barrel
                let barrelLength: CGFloat = 12 * sizeMultiplier
                let barrelWidth: CGFloat = 3 * sizeMultiplier

                let barrel = SKShapeNode(rectOf: CGSize(width: barrelWidth, height: barrelLength), cornerRadius: 1.5)
                barrel.fillColor = UIColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 1.0)
                barrel.strokeColor = UIColor.white.withAlphaComponent(0.9)
                barrel.lineWidth = 1.5
                barrel.position = CGPoint(x: 0, y: barrelLength / 2)
                rotationNode.addChild(barrel)
                turretGunBarrels.append(barrel)

                // Add muzzle flash indicator
                let muzzle = SKShapeNode(circleOfRadius: 2.5 * sizeMultiplier)
                muzzle.fillColor = UIColor.cyan.withAlphaComponent(0.8)
                muzzle.strokeColor = UIColor.white
                muzzle.lineWidth = 1
                muzzle.position = CGPoint(x: 0, y: barrelLength)
                barrel.addChild(muzzle)

                // Add central hub
                let hub = SKShapeNode(circleOfRadius: 5 * sizeMultiplier)
                hub.fillColor = UIColor(red: 0.1, green: 0.4, blue: 0.6, alpha: 1.0)
                hub.strokeColor = UIColor.white
                hub.lineWidth = 1.5
                rotationNode.addChild(hub)
            }
        }

        if enemyType == .mine {
            // Add central warning indicator
            let warningCore = SKShapeNode(circleOfRadius: baseSize * sizeMultiplier * 0.3)
            warningCore.fillColor = UIColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 0.8)
            warningCore.strokeColor = .clear
            warningCore.position = CGPoint(x: 0, y: 0)
            warningCore.zPosition = 1
            warningCore.name = "mineCore"
            addChild(warningCore)
        }

        if enemyType == .commander {
            // Add star symbol
            let starSize: CGFloat = 4 * sizeMultiplier
            let star = createStarPath(size: starSize)
            let starNode = SKShapeNode(path: star)
            starNode.fillColor = UIColor.yellow.withAlphaComponent(0.9)
            starNode.strokeColor = UIColor.white
            starNode.lineWidth = 1
            starNode.position = CGPoint(x: 0, y: -baseSize * sizeMultiplier * 0.3)
            starNode.zPosition = 2
            addChild(starNode)

            let starRotate = SKAction.rotate(byAngle: .pi * 2, duration: 3.0)
            starNode.run(SKAction.repeatForever(starRotate))
        }

        if enemyType == .spinner {
            // Add spinning blades effect
            for i in 0..<4 {
                let angle = CGFloat(i) * .pi / 2
                let blade = SKShapeNode(rectOf: CGSize(width: 2, height: 8 * sizeMultiplier))
                blade.fillColor = enemyType.strokeColor.withAlphaComponent(0.7)
                blade.strokeColor = .clear
                blade.position = CGPoint(
                    x: cos(angle) * 6 * sizeMultiplier,
                    y: sin(angle) * 6 * sizeMultiplier
                )
                blade.zRotation = angle
                blade.zPosition = -1
                addChild(blade)
            }
        }

        // Add special effects for new enemy types
        if enemyType == .ghost {
            // Add ethereal glow
            self.alpha = 0.7
            let fadeAction = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.3, duration: ghostPhaseInterval),
                SKAction.fadeAlpha(to: 0.7, duration: ghostPhaseInterval)
            ])
            run(SKAction.repeatForever(fadeAction), withKey: "ghostFade")
        }

        if enemyType == .shield {
            // Create rotating shield
            let shieldRadius = baseSize * sizeMultiplier * 1.5
            let shieldPath = CGMutablePath()
            shieldPath.addArc(center: .zero, radius: shieldRadius,
                             startAngle: -.pi / 3, endAngle: .pi / 3, clockwise: false)

            let shield = SKShapeNode(path: shieldPath)
            shield.strokeColor = UIColor(red: 0.2, green: 1.0, blue: 0.3, alpha: 0.8)
            shield.fillColor = UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.3)
            shield.lineWidth = 3
            shield.zPosition = 5
            shield.name = "shield"
            addChild(shield)
            shieldNode = shield

            // Rotate shield
            let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: 2.0)
            shield.run(SKAction.repeatForever(rotateAction))
        }

        if enemyType == .laser {
            // Add laser charging indicator
            let chargeIndicator = SKShapeNode(rectOf: CGSize(width: 4, height: 10 * sizeMultiplier))
            chargeIndicator.fillColor = UIColor.red.withAlphaComponent(0.3)
            chargeIndicator.strokeColor = .clear
            chargeIndicator.position = CGPoint(x: 0, y: -baseSize * sizeMultiplier * 0.9)
            chargeIndicator.zPosition = 1
            chargeIndicator.name = "chargeIndicator"
            addChild(chargeIndicator)
        }

        if enemyType == .bouncer {
            // Add bouncy trail effect
            for i in 0..<3 {
                let trail = SKShapeNode(circleOfRadius: (3 - CGFloat(i)) * sizeMultiplier)
                trail.fillColor = .clear
                trail.strokeColor = enemyType.strokeColor.withAlphaComponent(0.5 - CGFloat(i) * 0.15)
                trail.lineWidth = 2
                trail.position = .zero
                trail.zPosition = -1
                addChild(trail)

                let pulse = SKAction.sequence([
                    SKAction.scale(to: 1.3, duration: 0.3),
                    SKAction.scale(to: 1.0, duration: 0.3)
                ])
                trail.run(SKAction.repeatForever(pulse))
            }
        }

        if enemyType == .vortex {
            // Add swirling particles effect
            let vortexCore = SKShapeNode(circleOfRadius: baseSize * sizeMultiplier * 0.4)
            vortexCore.fillColor = UIColor(red: 0.3, green: 0.1, blue: 0.5, alpha: 0.9)
            vortexCore.strokeColor = UIColor.white.withAlphaComponent(0.8)
            vortexCore.lineWidth = 2
            vortexCore.zPosition = 2
            addChild(vortexCore)

            let spin = SKAction.rotate(byAngle: .pi * 2, duration: 1.0)
            run(SKAction.repeatForever(spin))
        }

        if enemyType == .teleporter {
            // Add teleport rings
            for i in 1...3 {
                let ring = SKShapeNode(circleOfRadius: CGFloat(i) * 4 * sizeMultiplier)
                ring.fillColor = .clear
                ring.strokeColor = UIColor.cyan.withAlphaComponent(0.6 - CGFloat(i) * 0.15)
                ring.lineWidth = 2
                ring.zPosition = -1
                addChild(ring)

                let pulse = SKAction.sequence([
                    SKAction.scale(to: 1.2, duration: 0.5),
                    SKAction.fadeOut(withDuration: 0.5),
                    SKAction.group([
                        SKAction.scale(to: 1.0, duration: 0.01),
                        SKAction.fadeIn(withDuration: 0.01)
                    ])
                ])
                ring.run(SKAction.repeatForever(pulse))
            }
        }

        if enemyType == .mirror {
            // Add reflective shine
            let shine = SKShapeNode(rectOf: CGSize(width: 3, height: 12 * sizeMultiplier))
            shine.fillColor = UIColor.white.withAlphaComponent(0.7)
            shine.strokeColor = .clear
            shine.position = CGPoint(x: -3 * sizeMultiplier, y: 0)
            shine.zPosition = 3
            addChild(shine)

            let shimmer = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.3, duration: 0.8),
                SKAction.fadeAlpha(to: 0.9, duration: 0.8)
            ])
            shine.run(SKAction.repeatForever(shimmer))
        }

        if enemyType == .splitter {
            // Add split line indicator
            let splitLine = SKShapeNode(rectOf: CGSize(width: 1, height: baseSize * sizeMultiplier * 2))
            splitLine.strokeColor = UIColor.yellow.withAlphaComponent(0.6)
            splitLine.fillColor = .clear
            splitLine.lineWidth = 1.5
            splitLine.zPosition = 2
            addChild(splitLine)

            let glow = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.3, duration: 0.5),
                SKAction.fadeAlpha(to: 0.8, duration: 0.5)
            ])
            splitLine.run(SKAction.repeatForever(glow))
        }

        // Setup physics body
        self.physicsBody = SKPhysicsBody(polygonFrom: path)
        self.physicsBody?.isDynamic = true
        self.physicsBody?.categoryBitMask = PhysicsCategory.enemy
        self.physicsBody?.contactTestBitMask = PhysicsCategory.player | PhysicsCategory.bullet
        self.physicsBody?.collisionBitMask = PhysicsCategory.none

        // Add glow effect to enemy based on type
        switch enemyType {
        case .kamikaze:
            GlowHelper.addPulsingEnhancedGlow(to: self, color: enemyType.color, minIntensity: 0.7, maxIntensity: 1.0, duration: 0.4)
        case .heavy, .tank:
            GlowHelper.addEnhancedGlow(to: self, color: enemyType.color, intensity: 1.1)
        case .sniper:
            GlowHelper.addPulsingEnhancedGlow(to: self, color: enemyType.color, minIntensity: 0.6, maxIntensity: 0.9, duration: 0.8)
        case .commander, .eliteGuard:
            GlowHelper.addEnhancedGlow(to: self, color: enemyType.color, intensity: 1.0)
        case .spinner:
            GlowHelper.addPulsingEnhancedGlow(to: self, color: enemyType.color, minIntensity: 0.8, maxIntensity: 1.2, duration: 0.5)
        case .ghost:
            GlowHelper.addPulsingEnhancedGlow(to: self, color: enemyType.color, minIntensity: 0.4, maxIntensity: 0.7, duration: 1.5)
        case .shield:
            GlowHelper.addEnhancedGlow(to: self, color: enemyType.color, intensity: 0.8)
        case .laser:
            GlowHelper.addPulsingEnhancedGlow(to: self, color: enemyType.color, minIntensity: 0.7, maxIntensity: 1.3, duration: 1.0)
        case .vortex:
            GlowHelper.addPulsingEnhancedGlow(to: self, color: enemyType.color, minIntensity: 0.9, maxIntensity: 1.4, duration: 0.6)
        case .teleporter:
            GlowHelper.addPulsingEnhancedGlow(to: self, color: enemyType.color, minIntensity: 0.5, maxIntensity: 1.0, duration: 1.2)
        case .mirror:
            GlowHelper.addEnhancedGlow(to: self, color: UIColor.white, intensity: 0.9)
        case .bouncer:
            GlowHelper.addPulsingEnhancedGlow(to: self, color: enemyType.color, minIntensity: 0.7, maxIntensity: 1.1, duration: 0.4)
        case .splitter:
            GlowHelper.addEnhancedGlow(to: self, color: enemyType.color, intensity: 0.9)
        default:
            GlowHelper.addEnhancedGlow(to: self, color: enemyType.color, intensity: 0.9)
        }
    }

    // Helper function to create a star path
    private func createStarPath(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let points = 5
        let outerRadius = size
        let innerRadius = size * 0.4

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
        return path
    }

    func startMovement(completion: @escaping () -> Void) {
        customMovementCompletion = completion
        movementDuration = TimeInterval.random(in: enemyType.movementDurationRange)

        switch enemyType {
        case .basic, .fast, .heavy, .kamikaze:
            // Straight downward movement
            let moveAction = SKAction.moveTo(y: -20, duration: movementDuration)
            let removeAction = SKAction.run { [weak self] in
                guard let self = self, !self.hasCompletedMovement else { return }
                self.hasCompletedMovement = true
                self.removeFromParent()
                completion()
            }
            run(SKAction.sequence([moveAction, removeAction]))

        case .zigzag:
            // Zigzag movement pattern
            performZigzagMovement(completion: completion)

        case .sniper:
            // Sniper: slow movement with pauses
            performSniperMovement(completion: completion)

        case .tank:
            // Tank: very slow straight movement
            let moveAction = SKAction.moveTo(y: -20, duration: movementDuration)
            let removeAction = SKAction.run { [weak self] in
                guard let self = self, !self.hasCompletedMovement else { return }
                self.hasCompletedMovement = true
                self.removeFromParent()
                completion()
            }
            run(SKAction.sequence([moveAction, removeAction]))

        case .striker:
            // Striker: fast horizontal zigzag
            performStrikerMovement(completion: completion)

        case .turret:
            // Turret: flies down, docks, shoots, then continues down
            performTurretMovement(completion: completion)

        case .turretSpiral:
            // Turret Spiral: flies down, docks, rotates and shoots spiral pattern, then continues down
            performTurretSpiralMovement(completion: completion)

        case .mine:
            // Mine: descends slowly, stops, arms, counts down, then explodes
            performMineMovement(completion: completion)

        case .meteorSwarm:
            // Meteor Swarm: chaotic diagonal movement with rotation
            performMeteorSwarmMovement(completion: completion)

        case .flanker:
            // Flanker: arc across screen from side to side
            performFlankerMovement(completion: completion)

        case .ghost:
            // Ghost: phases in and out while moving down
            performGhostMovement(completion: completion)

        case .shield:
            // Shield: moves down with rotating shield
            let moveAction = SKAction.moveTo(y: -20, duration: movementDuration)
            let removeAction = SKAction.run { [weak self] in
                guard let self = self, !self.hasCompletedMovement else { return }
                self.hasCompletedMovement = true
                self.removeFromParent()
                completion()
            }
            run(SKAction.sequence([moveAction, removeAction]))

        case .splitter:
            // Splitter: moves down normally (splits on death)
            let moveAction = SKAction.moveTo(y: -20, duration: movementDuration)
            let removeAction = SKAction.run { [weak self] in
                guard let self = self, !self.hasCompletedMovement else { return }
                self.hasCompletedMovement = true
                self.removeFromParent()
                completion()
            }
            run(SKAction.sequence([moveAction, removeAction]))

        case .laser:
            // Laser: moves down while charging beam attacks
            let moveAction = SKAction.moveTo(y: -20, duration: movementDuration)
            let removeAction = SKAction.run { [weak self] in
                guard let self = self, !self.hasCompletedMovement else { return }
                self.hasCompletedMovement = true
                self.removeFromParent()
                completion()
            }
            run(SKAction.sequence([moveAction, removeAction]))

        case .bouncer:
            // Bouncer: bounces off screen edges
            performBouncerMovement(completion: completion)

        case .vortex:
            // Vortex: moves down while absorbing bullets
            let moveAction = SKAction.moveTo(y: -20, duration: movementDuration)
            let removeAction = SKAction.run { [weak self] in
                guard let self = self, !self.hasCompletedMovement else { return }
                self.hasCompletedMovement = true
                self.removeFromParent()
                completion()
            }
            run(SKAction.sequence([moveAction, removeAction]))

        case .teleporter:
            // Teleporter: teleports periodically while moving down
            performTeleporterMovement(completion: completion)

        case .mirror:
            // Mirror: moves down and reflects bullets
            let moveAction = SKAction.moveTo(y: -20, duration: movementDuration)
            let removeAction = SKAction.run { [weak self] in
                guard let self = self, !self.hasCompletedMovement else { return }
                self.hasCompletedMovement = true
                self.removeFromParent()
                completion()
            }
            run(SKAction.sequence([moveAction, removeAction]))

        case .formation, .scout, .eliteGuard, .bomber, .spinner, .commander:
            // Formation enemies start with no movement - controlled by FormationManager
            break
        }
    }

    // Move along a bezier curve path (for formation attacks)
    func moveAlongPath(_ path: [CGPoint], duration: TimeInterval, completion: @escaping () -> Void) {
        guard path.count >= 2 else {
            if !hasCompletedMovement {
                hasCompletedMovement = true
                completion()
            }
            return
        }

        // Create a CGPath from the points for smooth movement
        let cgPath = CGMutablePath()
        cgPath.move(to: path[0])

        // Use quadratic curves between points for smoother movement
        for i in 1..<path.count {
            cgPath.addLine(to: path[i])
        }

        // Follow the path with constant speed
        let followPath = SKAction.follow(cgPath, asOffset: false, orientToPath: false, duration: duration)
        let removeAction = SKAction.run { [weak self] in
            guard let self = self, !self.hasCompletedMovement else { return }
            self.hasCompletedMovement = true
            self.removeFromParent()
            completion()
        }

        run(SKAction.sequence([followPath, removeAction]))
    }

    // Move to formation position
    func moveToFormation(_ targetPosition: CGPoint, duration: TimeInterval) {
        isInFormation = false
        let moveAction = SKAction.move(to: targetPosition, duration: duration)

        run(moveAction) { [weak self] in
            self?.isInFormation = true
        }
    }

    // Attack from formation with curved path
    func attackFromFormation(path: [CGPoint], duration: TimeInterval, completion: @escaping () -> Void) {
        isInFormation = false

        // CRITICAL: Stop all running actions to prevent "tearing" effect
        removeAllActions()

        moveAlongPath(path, duration: duration, completion: completion)
    }

    private func performSniperMovement(completion: @escaping () -> Void) {
        let startY = position.y
        let endY: CGFloat = -20
        let totalDistance = startY - endY
        let segments = 4 // Number of movement segments with pauses
        let segmentDistance = totalDistance / CGFloat(segments)

        var actions: [SKAction] = []

        for i in 0..<segments {
            let targetY = startY - segmentDistance * CGFloat(i + 1)
            let moveTime = movementDuration / TimeInterval(segments * 2) // Half time for moving
            let pauseTime = movementDuration / TimeInterval(segments * 2) // Half time for pausing

            actions.append(SKAction.moveTo(y: targetY, duration: moveTime))
            actions.append(SKAction.wait(forDuration: pauseTime))
        }

        let removeAction = SKAction.run { [weak self] in
            guard let self = self, !self.hasCompletedMovement else { return }
            self.hasCompletedMovement = true
            self.removeFromParent()
            completion()
        }
        actions.append(removeAction)

        run(SKAction.sequence(actions))
    }

    private func performStrikerMovement(completion: @escaping () -> Void) {
        let startX = position.x
        let startY = position.y
        let endY: CGFloat = -20
        let totalDistance = startY - endY
        let steps = 50

        var pathPoints: [CGPoint] = []
        for i in 0...steps {
            let progress = CGFloat(i) / CGFloat(steps)
            let y = startY - (totalDistance * progress)
            // Stronger horizontal movement
            let x = startX + sin(progress * .pi * horizontalFrequency) * horizontalAmplitude
            let clampedX = max(30, min(sceneSize.width - 30, x))
            pathPoints.append(CGPoint(x: clampedX, y: y))
        }

        var actions: [SKAction] = []
        let timePerStep = movementDuration / TimeInterval(steps)

        for point in pathPoints {
            actions.append(SKAction.move(to: point, duration: timePerStep))
        }

        let removeAction = SKAction.run { [weak self] in
            guard let self = self, !self.hasCompletedMovement else { return }
            self.hasCompletedMovement = true
            self.removeFromParent()
            completion()
        }
        actions.append(removeAction)

        run(SKAction.sequence(actions))
    }

    private func performTurretMovement(completion: @escaping () -> Void) {
        let dockY = sceneSize.height * 0.65 // Dock at ~65% from bottom
        let endY: CGFloat = -20

        // Phase 1: Fly down to docking position
        let descendDuration = movementDuration * 0.3
        let descendAction = SKAction.moveTo(y: dockY, duration: descendDuration)
        descendAction.timingMode = .easeOut

        // Phase 2: Dock and start shooting
        let dockAction = SKAction.run { [weak self] in
            self?.startTurretDockMode()
        }

        // Phase 3: Stay docked and shoot
        let dockWaitAction = SKAction.wait(forDuration: turretDockDuration)

        // Phase 4: Stop shooting and undock
        let undockAction = SKAction.run { [weak self] in
            self?.stopTurretDockMode()
        }

        // Phase 5: Continue down
        let continueDuration = movementDuration * 0.4
        let continueAction = SKAction.moveTo(y: endY, duration: continueDuration)
        continueAction.timingMode = .easeIn

        let removeAction = SKAction.run { [weak self] in
            guard let self = self, !self.hasCompletedMovement else { return }
            self.hasCompletedMovement = true
            self.removeFromParent()
            completion()
        }

        let sequence = SKAction.sequence([
            descendAction,
            dockAction,
            dockWaitAction,
            undockAction,
            continueAction,
            removeAction
        ])

        run(sequence)
    }

    private func performTurretSpiralMovement(completion: @escaping () -> Void) {
        let dockY = sceneSize.height * 0.65 // Dock at ~65% from bottom
        let endY: CGFloat = -20

        // Phase 1: Fly down to docking position
        let descendDuration = movementDuration * 0.3
        let descendAction = SKAction.moveTo(y: dockY, duration: descendDuration)
        descendAction.timingMode = .easeOut

        // Phase 2: Dock and start shooting spiral
        let dockAction = SKAction.run { [weak self] in
            self?.startTurretSpiralDockMode()
        }

        // Phase 3: Stay docked and shoot spiral
        let dockWaitAction = SKAction.wait(forDuration: turretDockDuration)

        // Phase 4: Stop shooting and undock
        let undockAction = SKAction.run { [weak self] in
            self?.stopTurretSpiralDockMode()
        }

        // Phase 5: Continue down
        let continueDuration = movementDuration * 0.4
        let continueAction = SKAction.moveTo(y: endY, duration: continueDuration)
        continueAction.timingMode = .easeIn

        let removeAction = SKAction.run { [weak self] in
            guard let self = self, !self.hasCompletedMovement else { return }
            self.hasCompletedMovement = true
            self.removeFromParent()
            completion()
        }

        let sequence = SKAction.sequence([
            descendAction,
            dockAction,
            dockWaitAction,
            undockAction,
            continueAction,
            removeAction
        ])

        run(sequence)
    }

    private func startTurretSpiralDockMode() {
        isTurretDocked = true

        // Start rotating the turret continuously
        if let rotationNode = turretRotationNode {
            let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: 3.0)
            let repeatRotation = SKAction.repeatForever(rotateAction)
            rotationNode.run(repeatRotation, withKey: "turretRotation")
        }

        // Add docking visual effect
        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 0.25),
            SKAction.fadeAlpha(to: 1.0, duration: 0.25)
        ])
        run(SKAction.repeatForever(glowPulse), withKey: "dockGlow")

        // Start spiral shooting pattern
        startTurretSpiralShooting()
    }

    private func stopTurretSpiralDockMode() {
        isTurretDocked = false

        // Stop rotating
        turretRotationNode?.removeAction(forKey: "turretRotation")

        // Stop visual effects
        removeAction(forKey: "dockGlow")

        // Stop shooting
        removeAction(forKey: "turretSpiralShoot")
    }

    private func startTurretSpiralShooting() {
        var shotCount = 0
        let shotsPerBurst = 10
        let burstInterval: TimeInterval = 1.5 // Pause between bursts

        let shootAction = SKAction.run { [weak self] in
            guard let self = self else { return }

            if shotCount < shotsPerBurst {
                // Shoot based on current rotation
                self.shootTurretSpiralBullet()
                shotCount += 1
            } else {
                // Reset counter for next burst (will happen after pause)
                shotCount = 0
            }
        }

        let rapidWait = SKAction.wait(forDuration: shootInterval)
        let rapidSequence = SKAction.sequence([shootAction, rapidWait])
        let rapidBurst = SKAction.repeat(rapidSequence, count: shotsPerBurst)

        let burstPause = SKAction.wait(forDuration: burstInterval)

        let fullSequence = SKAction.sequence([rapidBurst, burstPause])
        let repeatAction = SKAction.repeatForever(fullSequence)

        run(repeatAction, withKey: "turretSpiralShoot")
    }

    private func shootTurretSpiralBullet() {
        guard let scene = gameScene, parent != nil, isTurretDocked else { return }
        guard let rotationNode = turretRotationNode else { return }

        // Play enemy shoot sound
        SoundManager.shared.playEnemyShootSound(on: scene)

        // Shoot in the direction the turret is currently facing
        let angle = rotationNode.zRotation

        // Create turret bullet
        let bullet = SKShapeNode(circleOfRadius: 4)
        bullet.fillColor = UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1.0)  // Cyan
        bullet.strokeColor = UIColor(red: 0.6, green: 1.0, blue: 1.0, alpha: 1.0)  // Light cyan
        bullet.lineWidth = 2
        bullet.position = position
        bullet.name = "enemyBullet"

        // Add energy core
        let core = SKShapeNode(circleOfRadius: 2)
        core.fillColor = UIColor.white.withAlphaComponent(0.9)
        core.strokeColor = .clear
        core.zPosition = 1
        bullet.addChild(core)

        // Setup physics
        bullet.physicsBody = SKPhysicsBody(circleOfRadius: 4)
        bullet.physicsBody?.isDynamic = true
        bullet.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
        bullet.physicsBody?.contactTestBitMask = PhysicsCategory.player
        bullet.physicsBody?.collisionBitMask = PhysicsCategory.none
        bullet.physicsBody?.usesPreciseCollisionDetection = true

        // Add glow
        GlowHelper.addEnhancedGlow(to: bullet, color: UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1.0), intensity: 1.0)

        scene.gameContentNode.addChild(bullet)

        // Calculate velocity based on rotation angle
        let speed: CGFloat = 180 // Slower than burst turret
        let velocityX = cos(angle) * speed
        let velocityY = sin(angle) * speed

        // Move bullet
        let moveAction = SKAction.moveBy(x: velocityX * 10, y: velocityY * 10, duration: 6.0)
        let removeAction = SKAction.removeFromParent()
        bullet.run(SKAction.sequence([moveAction, removeAction]))
    }

    private func startTurretDockMode() {
        isTurretDocked = true

        // Start rotating the turret
        if let rotationNode = turretRotationNode {
            let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: 2.0)
            let repeatRotation = SKAction.repeatForever(rotateAction)
            rotationNode.run(repeatRotation, withKey: "turretRotation")
        }

        // Add docking visual effect
        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 0.3),
            SKAction.fadeAlpha(to: 1.0, duration: 0.3)
        ])
        run(SKAction.repeatForever(glowPulse), withKey: "dockGlow")

        // Start burst shooting
        startTurretBurstShooting()
    }

    private func stopTurretDockMode() {
        isTurretDocked = false

        // Stop rotating
        turretRotationNode?.removeAction(forKey: "turretRotation")

        // Stop visual effects
        removeAction(forKey: "dockGlow")

        // Stop shooting
        removeAction(forKey: "turretBurstShoot")
    }

    private func startTurretBurstShooting() {
        let burstAction = SKAction.run { [weak self] in
            self?.shootTurretBurst()
        }

        let waitAction = SKAction.wait(forDuration: shootInterval)
        let sequence = SKAction.sequence([burstAction, waitAction])
        let repeatAction = SKAction.repeatForever(sequence)

        run(repeatAction, withKey: "turretBurstShoot")
    }

    private func shootTurretBurst() {
        guard let scene = gameScene, parent != nil, isTurretDocked else { return }

        // Play enemy shoot sound
        SoundManager.shared.playEnemyShootSound(on: scene)

        // Shoot in 8 directions (every 45 degrees)
        let directions = 8
        for i in 0..<directions {
            let angle = CGFloat(i) * (.pi * 2 / CGFloat(directions))
            shootTurretBullet(scene: scene, angle: angle)
        }
    }

    private func shootTurretBullet(scene: SKScene, angle: CGFloat) {
        // Create turret bullet
        let bullet = SKShapeNode(circleOfRadius: 4)
        bullet.fillColor = UIColor(red: 0.8, green: 0.2, blue: 1.0, alpha: 1.0)  // Purple
        bullet.strokeColor = UIColor(red: 1.0, green: 0.6, blue: 1.0, alpha: 1.0)  // Light purple
        bullet.lineWidth = 2
        bullet.position = position
        bullet.name = "enemyBullet"

        // Add energy core
        let core = SKShapeNode(circleOfRadius: 2)
        core.fillColor = UIColor.white.withAlphaComponent(0.9)
        core.strokeColor = .clear
        core.zPosition = 1
        bullet.addChild(core)

        // Setup physics
        bullet.physicsBody = SKPhysicsBody(circleOfRadius: 4)
        bullet.physicsBody?.isDynamic = true
        bullet.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
        bullet.physicsBody?.contactTestBitMask = PhysicsCategory.player
        bullet.physicsBody?.collisionBitMask = PhysicsCategory.none
        bullet.physicsBody?.usesPreciseCollisionDetection = true

        // Add glow
        GlowHelper.addEnhancedGlow(to: bullet, color: UIColor(red: 0.8, green: 0.2, blue: 1.0, alpha: 1.0), intensity: 1.0)

        // Add bullet to game content node
        if let gameScene = scene as? GameScene {
            gameScene.gameContentNode.addChild(bullet)
        } else {
            scene.addChild(bullet)
        }

        // Calculate velocity
        let speed: CGFloat = 250
        let velocityX = cos(angle) * speed
        let velocityY = sin(angle) * speed

        // Move bullet
        let moveAction = SKAction.moveBy(x: velocityX * 10, y: velocityY * 10, duration: 5.0)
        let removeAction = SKAction.removeFromParent()
        bullet.run(SKAction.sequence([moveAction, removeAction]))
    }

    // MARK: - Mine Movement and Behavior

    private func performMineMovement(completion: @escaping () -> Void) {
        let stopY = sceneSize.height * 0.60 // Stop at 60% from bottom

        // Phase 1: Descend slowly to stop position
        let descendDuration = movementDuration * 0.5
        let descendAction = SKAction.moveTo(y: stopY, duration: descendDuration)
        descendAction.timingMode = .easeOut

        // Phase 2: Stop and arm the mine
        let armAction = SKAction.run { [weak self] in
            self?.armMine()
        }

        // Phase 3: Wait for arming time
        let armWaitAction = SKAction.wait(forDuration: mineArmingTime)

        // Phase 4: Start countdown
        let countdownStartAction = SKAction.run { [weak self] in
            self?.startMineCountdown(completion: completion)
        }

        let sequence = SKAction.sequence([
            descendAction,
            armAction,
            armWaitAction,
            countdownStartAction
        ])

        run(sequence)
    }

    private func armMine() {
        isMineArmed = true

        // Change mine color to orange to indicate arming
        fillColor = UIColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
        strokeColor = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)

        // Update core color
        if let core = childNode(withName: "mineCore") as? SKShapeNode {
            core.fillColor = UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.9)
        }

        // Add gentle pulsing effect
        let armPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.8, duration: 0.3),
            SKAction.fadeAlpha(to: 1.0, duration: 0.3)
        ])
        run(SKAction.repeatForever(armPulse), withKey: "armingPulse")
    }

    private func startMineCountdown(completion: @escaping () -> Void) {
        var timeRemaining = Int(mineCountdown)

        // Stop the arming pulse and start countdown pulse
        removeAction(forKey: "armingPulse")

        let updateAction = SKAction.run { [weak self] in
            guard let self = self else { return }

            // Gradually change color from orange to red during countdown
            let progress = 1.0 - CGFloat(timeRemaining) / CGFloat(self.mineCountdown)

            // Interpolate from orange to red
            let red = 0.8 + (0.2 * progress)  // 0.8 -> 1.0
            let green = 0.4 - (0.4 * progress) // 0.4 -> 0.0

            self.fillColor = UIColor(red: red, green: green, blue: 0.0, alpha: 1.0)
            self.strokeColor = UIColor(red: 1.0, green: 0.6 * (1.0 - progress), blue: 0.0, alpha: 1.0)

            // Update core color
            if let core = self.childNode(withName: "mineCore") as? SKShapeNode {
                core.fillColor = UIColor(red: 1.0, green: 0.5 * (1.0 - progress), blue: 0.0, alpha: 0.9)
            }

            // Faster pulsing as time runs out
            let pulseDuration = 0.5 / (4.0 - CGFloat(timeRemaining))
            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.15, duration: pulseDuration),
                SKAction.scale(to: 1.0, duration: pulseDuration)
            ])
            self.run(pulse)

            timeRemaining -= 1
        }

        let waitAction = SKAction.wait(forDuration: 1.0)
        let countSequence = SKAction.sequence([updateAction, waitAction])
        let repeatCount = SKAction.repeat(countSequence, count: Int(mineCountdown))

        let explodeAction = SKAction.run { [weak self] in
            self?.explodeMine(isFullExplosion: true, completion: completion)
        }

        let fullSequence = SKAction.sequence([repeatCount, explodeAction])
        run(fullSequence, withKey: "mineCountdown")
    }

    func explodeMine(isFullExplosion: Bool, completion: @escaping () -> Void) {
        guard !hasCompletedMovement, let scene = gameScene else { return }

        // Mark as completed FIRST to prevent any other callbacks
        hasCompletedMovement = true

        // Stop all movement and shooting actions (but don't call markAsDestroyed yet)
        removeAllActions()
        pauseShooting()

        HapticManager.shared.heavyTap()

        // Play explosion sound
        SoundManager.shared.playExplosionSound(on: scene)

        // Visual explosion effect
        createMineExplosion()

        // Spawn shrapnel bullets
        let shrapnelCount = isFullExplosion ? 12 : 6
        for i in 0..<shrapnelCount {
            let angle = CGFloat(i) * (.pi * 2 / CGFloat(shrapnelCount))
            shootShrapnel(scene: scene, angle: angle, speed: isFullExplosion ? 300 : 200)
        }

        // Force remove mine immediately to prevent it from staying on screen
        let wait = SKAction.wait(forDuration: 0.05)
        let remove = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.removeFromParent()
            completion()
        }
        run(SKAction.sequence([wait, remove]), withKey: "mineRemoval")
    }

    private func createMineExplosion() {
        guard let scene = gameScene else { return }

        // Create particle explosion
        let explosion = SKEmitterNode()
        explosion.particleTexture = SKTexture(imageNamed: "spark") // Fallback to programmatic if needed
        explosion.particleBirthRate = 600
        explosion.numParticlesToEmit = 120
        explosion.particleLifetime = 0.6
        explosion.emissionAngle = 0
        explosion.emissionAngleRange = .pi * 2
        explosion.particleSpeed = 250
        explosion.particleSpeedRange = 100
        explosion.particleAlpha = 1.0
        explosion.particleAlphaRange = 0.3
        explosion.particleAlphaSpeed = -1.5
        explosion.particleScale = 0.3
        explosion.particleScaleRange = 0.2
        explosion.particleScaleSpeed = -0.3
        explosion.particleColorBlendFactor = 1.0
        explosion.particleColor = UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0)
        explosion.particleBlendMode = .add
        explosion.position = position
        explosion.zPosition = 100

        scene.gameContentNode.addChild(explosion)

        // Remove after emission
        let wait = SKAction.wait(forDuration: 1.0)
        let remove = SKAction.removeFromParent()
        explosion.run(SKAction.sequence([wait, remove]))
    }

    private func shootShrapnel(scene: SKScene, angle: CGFloat, speed: CGFloat) {
        // Play enemy shoot sound (only once per explosion, not for each shrapnel piece)
        // This is handled in the mineExplode function

        // Create shrapnel bullet
        let shrapnel = SKShapeNode(circleOfRadius: 3)
        shrapnel.fillColor = UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0)  // Orange
        shrapnel.strokeColor = UIColor(red: 1.0, green: 0.7, blue: 0.0, alpha: 1.0)  // Yellow-orange
        shrapnel.lineWidth = 1.5
        shrapnel.position = position
        shrapnel.name = "enemyBullet"

        // Setup physics
        shrapnel.physicsBody = SKPhysicsBody(circleOfRadius: 3)
        shrapnel.physicsBody?.isDynamic = true
        shrapnel.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
        shrapnel.physicsBody?.contactTestBitMask = PhysicsCategory.player
        shrapnel.physicsBody?.collisionBitMask = PhysicsCategory.none
        shrapnel.physicsBody?.usesPreciseCollisionDetection = true

        // Add glow
        GlowHelper.addEnhancedGlow(to: shrapnel, color: UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0), intensity: 0.8)

        // Add shrapnel to game content node
        if let gameScene = scene as? GameScene {
            gameScene.gameContentNode.addChild(shrapnel)
        } else {
            scene.addChild(shrapnel)
        }

        // Calculate velocity
        let velocityX = cos(angle) * speed
        let velocityY = sin(angle) * speed

        // Move shrapnel
        let moveAction = SKAction.moveBy(x: velocityX * 8, y: velocityY * 8, duration: 4.0)
        let removeAction = SKAction.removeFromParent()
        shrapnel.run(SKAction.sequence([moveAction, removeAction]))
    }

    private func performMeteorSwarmMovement(completion: @escaping () -> Void) {
        // Meteors move in realistic diagonal paths like shooting stars
        let startX = position.x
        let startY = position.y
        let endY: CGFloat = -20

        // Random diagonal angle (roughly 30-60 degrees from vertical)
        let angleVariation = CGFloat.random(in: -0.3...0.3) // Small variation
        let baseAngle: CGFloat = .pi * 1.35 // ~245 degrees (diagonal down-left to down-right)
        let meteorAngle = baseAngle + angleVariation

        // Calculate horizontal movement based on angle and distance
        let totalDistance = startY - endY
        let horizontalDistance = cos(meteorAngle) * totalDistance * 0.6

        // Create smooth diagonal path with very slight wobble for realism
        let steps = 30
        var pathPoints: [CGPoint] = []
        for i in 0...steps {
            let progress = CGFloat(i) / CGFloat(steps)
            let y = startY - (totalDistance * progress)
            // Minimal wobble - just slight atmospheric disturbance
            let wobble = sin(progress * .pi * 4) * 3.0 // Very subtle
            let x = startX + (horizontalDistance * progress) + wobble
            pathPoints.append(CGPoint(x: x, y: y))
        }

        // Create path
        let bezierPath = UIBezierPath()
        bezierPath.move(to: pathPoints[0])
        for i in 1..<pathPoints.count {
            bezierPath.addLine(to: pathPoints[i])
        }

        // Follow path
        let followAction = SKAction.follow(bezierPath.cgPath, asOffset: false, orientToPath: false, duration: movementDuration)

        // Moderate rotation for tumbling effect (less chaotic)
        let rotationAmount = CGFloat.random(in: 2...4) * .pi * (Bool.random() ? 1 : -1)
        let rotateAction = SKAction.rotate(byAngle: rotationAmount, duration: movementDuration)

        // Group movement and rotation
        let groupAction = SKAction.group([followAction, rotateAction])

        let removeAction = SKAction.run { [weak self] in
            guard let self = self, !self.hasCompletedMovement else { return }
            self.hasCompletedMovement = true
            self.removeFromParent()
            completion()
        }

        run(SKAction.sequence([groupAction, removeAction]))

        // Add dust trail particle effect for meteors
        addMeteorTrail()
    }

    private func addMeteorTrail() {
        let trail = SKEmitterNode()
        trail.particleBirthRate = 15
        trail.particleLifetime = 0.5
        trail.particleLifetimeRange = 0.3
        trail.emissionAngle = .pi / 2 // Upward
        trail.emissionAngleRange = .pi / 4
        trail.particleSpeed = 30
        trail.particleSpeedRange = 20
        trail.particleAlpha = 0.6
        trail.particleAlphaRange = 0.3
        trail.particleAlphaSpeed = -1.2
        trail.particleScale = 0.15
        trail.particleScaleRange = 0.1
        trail.particleScaleSpeed = -0.2
        trail.particleColor = UIColor(red: 0.5, green: 0.35, blue: 0.25, alpha: 1.0)
        trail.particleColorBlendFactor = 1.0
        trail.particleBlendMode = .alpha
        trail.position = CGPoint(x: 0, y: 0)
        trail.zPosition = -1
        trail.name = "meteorTrail"

        // Create simple particle texture
        let size = CGSize(width: 4, height: 4)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        trail.particleTexture = SKTexture(image: image)

        addChild(trail)
    }

    private func performFlankerMovement(completion: @escaping () -> Void) {
        // Flankers arc across the screen from one side to the other
        let startX = position.x
        let startY = position.y

        // Determine if coming from left or right based on spawn position
        let fromLeft = startX < sceneSize.width / 2

        // Target position on opposite side
        let endX: CGFloat = fromLeft ? sceneSize.width + 20 : -20

        // Arc through the middle of the screen with slight dip/rise
        let midY = startY + CGFloat.random(in: -80...80) // Slight vertical variation

        // Create smooth arc path
        let bezierPath = UIBezierPath()
        bezierPath.move(to: CGPoint(x: startX, y: startY))

        // Use quadratic curve for smooth arc
        let controlPoint = CGPoint(x: sceneSize.width / 2, y: midY)
        let endPoint = CGPoint(x: endX, y: startY + CGFloat.random(in: -40...40))

        bezierPath.addQuadCurve(to: endPoint, controlPoint: controlPoint)

        // Follow the arc path
        let followAction = SKAction.follow(bezierPath.cgPath, asOffset: false, orientToPath: false, duration: movementDuration)

        let removeAction = SKAction.run { [weak self] in
            guard let self = self, !self.hasCompletedMovement else { return }
            self.hasCompletedMovement = true
            self.removeFromParent()
            completion()
        }

        run(SKAction.sequence([followAction, removeAction]))

        // Add energy trail
        addFlankerTrail(fromLeft: fromLeft)
    }

    private func addFlankerTrail(fromLeft: Bool) {
        let trail = SKEmitterNode()
        trail.particleBirthRate = 20
        trail.particleLifetime = 0.4
        trail.particleLifetimeRange = 0.2
        // Trail points backward relative to movement direction
        trail.emissionAngle = fromLeft ? .pi : 0
        trail.emissionAngleRange = .pi / 6
        trail.particleSpeed = 40
        trail.particleSpeedRange = 20
        trail.particleAlpha = 0.7
        trail.particleAlphaRange = 0.3
        trail.particleAlphaSpeed = -1.8
        trail.particleScale = 0.2
        trail.particleScaleRange = 0.1
        trail.particleScaleSpeed = -0.3
        trail.particleColor = UIColor(red: 0.0, green: 0.9, blue: 0.7, alpha: 1.0)
        trail.particleColorBlendFactor = 1.0
        trail.particleBlendMode = .add // Glowing effect
        trail.position = CGPoint(x: fromLeft ? -5 : 5, y: 0) // Trail from back
        trail.zPosition = -1
        trail.name = "flankerTrail"

        // Create simple particle texture
        let size = CGSize(width: 4, height: 4)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        trail.particleTexture = SKTexture(image: image)

        addChild(trail)
    }

    private func performZigzagMovement(completion: @escaping () -> Void) {
        let startX = position.x
        let startY = position.y
        let endY: CGFloat = -20
        let totalDistance = startY - endY
        let steps = 50 // Number of points in the zigzag path

        var pathPoints: [CGPoint] = []
        for i in 0...steps {
            let progress = CGFloat(i) / CGFloat(steps)
            let y = startY - (totalDistance * progress)
            let x = startX + sin(progress * .pi * zigzagFrequency) * zigzagAmplitude
            // Keep within screen bounds
            let clampedX = max(30, min(sceneSize.width - 30, x))
            pathPoints.append(CGPoint(x: clampedX, y: y))
        }

        // Create sequence of move actions
        var actions: [SKAction] = []
        let timePerStep = movementDuration / TimeInterval(steps)

        for point in pathPoints {
            actions.append(SKAction.move(to: point, duration: timePerStep))
        }

        let removeAction = SKAction.run { [weak self] in
            guard let self = self, !self.hasCompletedMovement else { return }
            self.hasCompletedMovement = true
            self.removeFromParent()
            completion()
        }
        actions.append(removeAction)

        run(SKAction.sequence(actions))
    }

    private func startShooting() {
        // Use SKAction instead of Timer for better performance and synchronization
        let shootAction = SKAction.run { [weak self] in
            self?.shoot()
        }

        let waitAction = SKAction.wait(forDuration: shootInterval)
        let sequence = SKAction.sequence([waitAction, shootAction])
        let repeatAction = SKAction.repeatForever(sequence)

        run(repeatAction, withKey: shootActionKey)
    }

    private func shoot() {
        guard let scene = gameScene, parent != nil else { return }

        // Different shooting patterns for different enemy types
        switch enemyType {
        case .tank:
            shootSpread(scene: scene)
        case .sniper:
            shootAimed(scene: scene)
        default:
            shootNormal(scene: scene)
        }
    }

    private func shootNormal(scene: SKScene) {
        // Play enemy shoot sound
        if let gameScene = gameScene {
            SoundManager.shared.playEnemyShootSound(on: gameScene)
        }

        // Create enemy plasma bullet with energy effect
        let bullet = SKShapeNode(circleOfRadius: 5)
        bullet.fillColor = UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0)  // Orange-red
        bullet.strokeColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)  // Lighter orange
        bullet.lineWidth = 2
        bullet.position = position
        bullet.name = "enemyBullet"

        // Add energy core
        let core = SKShapeNode(circleOfRadius: 2.5)
        core.fillColor = UIColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 1.0)
        core.strokeColor = .clear
        core.zPosition = 1
        bullet.addChild(core)

        // Add pulsing animation to core
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.2),
            SKAction.scale(to: 1.0, duration: 0.2)
        ])
        core.run(SKAction.repeatForever(pulse))

        // Setup physics for enemy bullet
        bullet.physicsBody = SKPhysicsBody(circleOfRadius: 5)
        bullet.physicsBody?.isDynamic = true
        bullet.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
        bullet.physicsBody?.contactTestBitMask = PhysicsCategory.player
        bullet.physicsBody?.collisionBitMask = PhysicsCategory.none
        bullet.physicsBody?.usesPreciseCollisionDetection = true

        // Add enhanced glow effect to enemy bullet
        GlowHelper.addEnhancedGlow(to: bullet, color: UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0), intensity: 0.9)

        // Add bullet to game content node
        if let gameScene = scene as? GameScene {
            gameScene.gameContentNode.addChild(bullet)
        } else {
            scene.addChild(bullet)
        }

        // Calculate bullet speed based on distance and constant speed
        let bulletSpeed: CGFloat = 400.0
        let distance = position.y - (-20)
        let bulletDuration = TimeInterval(distance / bulletSpeed)

        let moveAction = SKAction.moveTo(y: -20, duration: bulletDuration)
        let removeAction = SKAction.removeFromParent()
        bullet.run(SKAction.sequence([moveAction, removeAction]))
    }

    private func shootSpread(scene: SKScene) {
        // Play enemy shoot sound
        if let gameScene = gameScene {
            SoundManager.shared.playEnemyShootSound(on: gameScene)
        }

        // Tank shoots 3 bullets in a spread pattern
        let angles: [CGFloat] = [-0.3, 0, 0.3] // Spread angles in radians

        for angle in angles {
            let bullet = SKShapeNode(circleOfRadius: 6)
            bullet.fillColor = UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)  // Blue for tank
            bullet.strokeColor = UIColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 1.0)
            bullet.lineWidth = 2
            bullet.position = position
            bullet.name = "enemyBullet"

            let core = SKShapeNode(circleOfRadius: 3)
            core.fillColor = UIColor.white.withAlphaComponent(0.8)
            core.strokeColor = .clear
            core.zPosition = 1
            bullet.addChild(core)

            bullet.physicsBody = SKPhysicsBody(circleOfRadius: 6)
            bullet.physicsBody?.isDynamic = true
            bullet.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
            bullet.physicsBody?.contactTestBitMask = PhysicsCategory.player
            bullet.physicsBody?.collisionBitMask = PhysicsCategory.none
            bullet.physicsBody?.usesPreciseCollisionDetection = true

            GlowHelper.addEnhancedGlow(to: bullet, color: UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0), intensity: 1.0)

            // Add bullet to game content node
            if let gameScene = scene as? GameScene {
                gameScene.gameContentNode.addChild(bullet)
            } else {
                scene.addChild(bullet)
            }

            // Calculate trajectory with angle
            let bulletSpeed: CGFloat = 350.0
            let distance = position.y - (-20)
            let bulletDuration = TimeInterval(distance / bulletSpeed)

            let horizontalOffset = sin(angle) * distance
            let targetX = position.x + horizontalOffset
            let targetY: CGFloat = -20

            let moveAction = SKAction.move(to: CGPoint(x: targetX, y: targetY), duration: bulletDuration)
            let removeAction = SKAction.removeFromParent()
            bullet.run(SKAction.sequence([moveAction, removeAction]))
        }
    }

    private func shootAimed(scene: SKScene) {
        // Sniper shoots precise bullets aimed at player
        guard let playerNode = scene.childNode(withName: "player") else {
            shootNormal(scene: scene)
            return
        }

        // Play enemy shoot sound
        if let gameScene = gameScene {
            SoundManager.shared.playEnemyShootSound(on: gameScene)
        }

        let bullet = SKShapeNode(circleOfRadius: 4)
        bullet.fillColor = UIColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 1.0)  // Bright red
        bullet.strokeColor = UIColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1.0)
        bullet.lineWidth = 3
        bullet.position = position
        bullet.name = "enemyBullet"

        let core = SKShapeNode(circleOfRadius: 2)
        core.fillColor = UIColor.white
        core.strokeColor = .clear
        core.zPosition = 1
        bullet.addChild(core)

        bullet.physicsBody = SKPhysicsBody(circleOfRadius: 4)
        bullet.physicsBody?.isDynamic = true
        bullet.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
        bullet.physicsBody?.contactTestBitMask = PhysicsCategory.player
        bullet.physicsBody?.collisionBitMask = PhysicsCategory.none
        bullet.physicsBody?.usesPreciseCollisionDetection = true

        GlowHelper.addEnhancedGlow(to: bullet, color: UIColor.red, intensity: 1.2)

        // Add bullet to game content node
        if let gameScene = scene as? GameScene {
            gameScene.gameContentNode.addChild(bullet)
        } else {
            scene.addChild(bullet)
        }

        // Calculate angle to player
        let dx = playerNode.position.x - position.x
        let dy = playerNode.position.y - position.y
        let distance = sqrt(dx * dx + dy * dy)

        let bulletSpeed: CGFloat = 500.0 // Faster
        let bulletDuration = TimeInterval(distance / bulletSpeed)

        let moveAction = SKAction.move(to: playerNode.position, duration: bulletDuration)
        let removeAction = SKAction.removeFromParent()
        bullet.run(SKAction.sequence([moveAction, removeAction]))
    }

    func freeze(duration: TimeInterval) {
        // Pause all actions
        isPaused = true

        // Visual effect - add blue tint
        let freezeOverlay = SKShapeNode(rectOf: CGSize(width: 50, height: 50))
        freezeOverlay.fillColor = UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 0.4)
        freezeOverlay.strokeColor = .clear
        freezeOverlay.name = "freezeOverlay"
        freezeOverlay.zPosition = 10
        addChild(freezeOverlay)

        // Unfreeze after duration
        let wait = SKAction.wait(forDuration: duration)
        let unfreeze = SKAction.run { [weak self] in
            self?.isPaused = false
            self?.childNode(withName: "freezeOverlay")?.removeFromParent()
        }
        run(SKAction.sequence([wait, unfreeze]))
    }

    private func performGhostMovement(completion: @escaping () -> Void) {
        // Ghost phases in and out while moving down
        let moveAction = SKAction.moveTo(y: -20, duration: movementDuration)

        // Create phase effect - alternate between visible and semi-transparent
        let fadeOut = SKAction.fadeAlpha(to: 0.3, duration: 0.5)
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        let phaseSequence = SKAction.sequence([fadeOut, fadeIn])
        let phaseLoop = SKAction.repeatForever(phaseSequence)

        let removeAction = SKAction.run { [weak self] in
            guard let self = self, !self.hasCompletedMovement else { return }
            self.hasCompletedMovement = true
            self.removeFromParent()
            completion()
        }

        run(phaseLoop, withKey: "phasing")
        run(SKAction.sequence([moveAction, removeAction]))
    }

    private func performBouncerMovement(completion: @escaping () -> Void) {
        // Bouncer moves diagonally and bounces off screen edges
        var currentVelocity = CGVector(dx: CGFloat.random(in: -150...150), dy: -200)
        let updateInterval: TimeInterval = 0.016 // ~60fps

        let updateAction = SKAction.run { [weak self] in
            guard let self = self else { return }

            // Update position
            let newX = self.position.x + currentVelocity.dx * CGFloat(updateInterval)
            let newY = self.position.y + currentVelocity.dy * CGFloat(updateInterval)

            // Bounce off left/right edges
            if newX < 30 || newX > self.sceneSize.width - 30 {
                currentVelocity.dx = -currentVelocity.dx
            }

            self.position = CGPoint(
                x: max(30, min(self.sceneSize.width - 30, newX)),
                y: newY
            )

            // Check if off screen
            if self.position.y < -20 {
                if !self.hasCompletedMovement {
                    self.hasCompletedMovement = true
                    self.removeFromParent()
                    completion()
                }
            }
        }

        let wait = SKAction.wait(forDuration: updateInterval)
        let sequence = SKAction.sequence([updateAction, wait])
        run(SKAction.repeatForever(sequence), withKey: "bouncing")
    }

    private func performTeleporterMovement(completion: @escaping () -> Void) {
        // Teleporter moves down and teleports to random positions periodically
        let teleportInterval: TimeInterval = 1.5

        let moveAction = SKAction.moveTo(y: -20, duration: movementDuration)

        let teleportAction = SKAction.run { [weak self] in
            guard let self = self else { return }

            // Teleport effect - fade out
            let fadeOut = SKAction.fadeOut(withDuration: 0.2)
            let teleport = SKAction.run {
                // Random new X position
                let newX = CGFloat.random(in: 50...(self.sceneSize.width - 50))
                self.position.x = newX
            }
            let fadeIn = SKAction.fadeIn(withDuration: 0.2)

            self.run(SKAction.sequence([fadeOut, teleport, fadeIn]))
        }

        let wait = SKAction.wait(forDuration: teleportInterval)
        let teleportSequence = SKAction.sequence([teleportAction, wait])
        let teleportLoop = SKAction.repeatForever(teleportSequence)

        let removeAction = SKAction.run { [weak self] in
            guard let self = self, !self.hasCompletedMovement else { return }
            self.hasCompletedMovement = true
            self.removeFromParent()
            completion()
        }

        run(teleportLoop, withKey: "teleporting")
        run(SKAction.sequence([moveAction, removeAction]))
    }
}
