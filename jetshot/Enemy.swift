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
    var gameScene: SKScene?
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
    private var isSniperPaused: Bool = false
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

    init(sceneSize: CGSize, scene: SKScene, type: EnemyType = .basic) {
        self.enemyType = type
        self.sceneSize = sceneSize
        self.shootInterval = TimeInterval.random(in: type.shootIntervalRange)
        self.gameScene = scene
        self.maxHealth = type.maxHealth
        self.health = type.maxHealth

        super.init()

        setupEnemy(sceneSize: sceneSize)
        // Don't start shooting immediately for kamikaze, turret, turretSpiral and mine
        if type != .kamikaze && type != .turret && type != .turretSpiral && type != .mine {
            startShooting()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func pauseShooting() {
        removeAction(forKey: shootActionKey)
    }

    func resumeShooting() {
        guard action(forKey: shootActionKey) == nil else { return }
        startShooting()
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
        }

        self.path = path
        self.fillColor = enemyType.color
        self.strokeColor = enemyType.strokeColor
        self.lineWidth = 2.5
        self.name = "enemy"

        // Random spawn position at top
        let randomX = CGFloat.random(in: 30...(sceneSize.width - 30))
        self.position = CGPoint(x: randomX, y: sceneSize.height + 20)

        // Add cockpit/core detail
        let coreSize: CGFloat = 3 * sizeMultiplier
        let core = SKShapeNode(circleOfRadius: coreSize)
        core.fillColor = UIColor.white.withAlphaComponent(0.8)
        core.strokeColor = enemyType.strokeColor
        core.lineWidth = 1.5
        core.position = CGPoint(x: 0, y: 0)
        core.zPosition = 1
        addChild(core)

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

        scene.addChild(bullet)

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

        scene.addChild(bullet)

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

        // Play arming sound if available
        SoundManager.shared.playPowerUp()
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

        // Play explosion sound
        SoundManager.shared.playExplosion()
        HapticManager.shared.heavyTap()

        // Visual explosion effect
        createMineExplosion()

        // Spawn shrapnel bullets
        let shrapnelCount = isFullExplosion ? 12 : 6
        for i in 0..<shrapnelCount {
            let angle = CGFloat(i) * (.pi * 2 / CGFloat(shrapnelCount))
            shootShrapnel(scene: scene, angle: angle, speed: isFullExplosion ? 300 : 200)
        }

        // CRITICAL: Force remove mine immediately to prevent it from staying on screen
        // Using multiple removal methods to ensure it's gone
        let wait = SKAction.wait(forDuration: 0.05)
        let remove = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.removeFromParent()
            completion()
        }
        run(SKAction.sequence([wait, remove]), withKey: "mineRemoval")

        // Backup removal - also schedule direct removal in case action fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.removeFromParent()
        }
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

        scene.addChild(explosion)

        // Remove after emission
        let wait = SKAction.wait(forDuration: 1.0)
        let remove = SKAction.removeFromParent()
        explosion.run(SKAction.sequence([wait, remove]))
    }

    private func shootShrapnel(scene: SKScene, angle: CGFloat, speed: CGFloat) {
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

        scene.addChild(shrapnel)

        // Calculate velocity
        let velocityX = cos(angle) * speed
        let velocityY = sin(angle) * speed

        // Move shrapnel
        let moveAction = SKAction.moveBy(x: velocityX * 8, y: velocityY * 8, duration: 4.0)
        let removeAction = SKAction.removeFromParent()
        shrapnel.run(SKAction.sequence([moveAction, removeAction]))
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

        scene.addChild(bullet)

        // Calculate bullet speed based on distance and constant speed
        let bulletSpeed: CGFloat = 400.0
        let distance = position.y - (-20)
        let bulletDuration = TimeInterval(distance / bulletSpeed)

        let moveAction = SKAction.moveTo(y: -20, duration: bulletDuration)
        let removeAction = SKAction.removeFromParent()
        bullet.run(SKAction.sequence([moveAction, removeAction]))

        // Play enemy shoot sound
        SoundManager.shared.playEnemyShoot()
    }

    private func shootSpread(scene: SKScene) {
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

            scene.addChild(bullet)

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

        // Play enemy shoot sound
        SoundManager.shared.playEnemyShoot()
    }

    private func shootAimed(scene: SKScene) {
        // Sniper shoots precise bullets aimed at player
        guard let playerNode = scene.childNode(withName: "player") else {
            shootNormal(scene: scene)
            return
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

        scene.addChild(bullet)

        // Calculate angle to player
        let dx = playerNode.position.x - position.x
        let dy = playerNode.position.y - position.y
        let distance = sqrt(dx * dx + dy * dy)

        let bulletSpeed: CGFloat = 500.0 // Faster
        let bulletDuration = TimeInterval(distance / bulletSpeed)

        let moveAction = SKAction.move(to: playerNode.position, duration: bulletDuration)
        let removeAction = SKAction.removeFromParent()
        bullet.run(SKAction.sequence([moveAction, removeAction]))

        // Play enemy shoot sound
        SoundManager.shared.playEnemyShoot()
    }
}
