//
//  Asteroid.swift
//  jetshot
//
//  Created by Robert Libšanský on 1.11.2025.
//

import SpriteKit

// Asteroid sizes - each splits into smaller ones
enum AsteroidSize {
    case large   // Splits into 2-3 medium
    case medium  // Splits into 2-3 small
    case small   // Doesn't split, just destroyed

    var baseSize: CGFloat {
        switch self {
        case .large: return 40
        case .medium: return 24
        case .small: return 14
        }
    }

    var points: Int {
        switch self {
        case .large: return 20
        case .medium: return 50
        case .small: return 100
        }
    }

    var splitCount: Int {
        switch self {
        case .large: return Int.random(in: 2...3)
        case .medium: return Int.random(in: 2...3)
        case .small: return 0 // Doesn't split
        }
    }

    var nextSize: AsteroidSize? {
        switch self {
        case .large: return .medium
        case .medium: return .small
        case .small: return nil
        }
    }

    var speed: CGFloat {
        switch self {
        case .large: return 50
        case .medium: return 80
        case .small: return 120
        }
    }

    var rotationSpeed: CGFloat {
        switch self {
        case .large: return 0.5
        case .medium: return 1.0
        case .small: return 1.5
        }
    }
}

class Asteroid: SKShapeNode {

    let asteroidSize: AsteroidSize
    private var sceneSize: CGSize
    weak var gameScene: GameScene?
    var movementCompletion: (() -> Void)?
    var hasCompletedMovement: Bool = false

    // Visual properties
    private var vertexCount: Int = 0

    init(sceneSize: CGSize, scene: SKScene, size: AsteroidSize = .large, startPosition: CGPoint? = nil) {
        self.asteroidSize = size
        self.sceneSize = sceneSize
        // Accept SKScene but store a weak reference to GameScene when possible
        self.gameScene = scene as? GameScene

        super.init()

        setupAsteroid(sceneSize: sceneSize, startPosition: startPosition)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Mark asteroid as destroyed (prevents completion callback from firing)
    func markAsDestroyed() {
        hasCompletedMovement = true
        removeAllActions()
    }

    private func setupAsteroid(sceneSize: CGSize, startPosition: CGPoint?) {
        // Create irregular asteroid shape
        let baseRadius = asteroidSize.baseSize
        self.vertexCount = Int.random(in: 8...12)

        let path = CGMutablePath()
        var points: [CGPoint] = []

        for i in 0..<vertexCount {
            let angle = (CGFloat(i) / CGFloat(vertexCount)) * 2 * .pi
            // Add randomness to radius for irregular shape
            let radiusVariation = CGFloat.random(in: 0.7...1.0)
            let radius = baseRadius * radiusVariation

            let x = cos(angle) * radius
            let y = sin(angle) * radius
            points.append(CGPoint(x: x, y: y))
        }

        // Create path from points
        if let firstPoint = points.first {
            path.move(to: firstPoint)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }

        self.path = path

        // Set colors based on size (very dark gray tones - pure monochrome)
        let baseColor: UIColor
        let strokeColor: UIColor

        switch asteroidSize {
        case .large:
            baseColor = UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1.0) // Very dark gray
            strokeColor = UIColor(red: 0.38, green: 0.38, blue: 0.38, alpha: 1.0) // Dark gray
        case .medium:
            baseColor = UIColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1.0) // Very dark gray
            strokeColor = UIColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1.0) // Dark gray
        case .small:
            baseColor = UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1.0) // Dark gray
            strokeColor = UIColor(red: 0.43, green: 0.43, blue: 0.43, alpha: 1.0) // Medium gray
        }

        self.fillColor = baseColor
        self.strokeColor = strokeColor
        self.lineWidth = 2.0
        self.glowWidth = 0

        // Position at top or specific position
        if let startPos = startPosition {
            self.position = startPos
        } else {
            let randomX = CGFloat.random(in: baseRadius...sceneSize.width - baseRadius)
            self.position = CGPoint(x: randomX, y: sceneSize.height + baseRadius)
        }

        // Setup physics
        self.physicsBody = SKPhysicsBody(polygonFrom: path)
        self.physicsBody?.isDynamic = true
        self.physicsBody?.categoryBitMask = PhysicsCategory.asteroid
        self.physicsBody?.contactTestBitMask = PhysicsCategory.bullet | PhysicsCategory.player
        self.physicsBody?.collisionBitMask = PhysicsCategory.none
        self.physicsBody?.affectedByGravity = false

        // Add random rotation
        let rotationDirection = Bool.random() ? 1.0 : -1.0
        let rotateAction = SKAction.rotate(
            byAngle: .pi * 2 * rotationDirection * asteroidSize.rotationSpeed,
            duration: 3.0
        )
        self.run(SKAction.repeatForever(rotateAction))

        // Add sharp glow effect using GlowHelper
        GlowHelper.addEnhancedGlow(to: self, color: strokeColor, intensity: 0.6)

        self.name = "asteroid"
        self.zPosition = 10
    }

    func startMovement(completion: @escaping () -> Void) {
        self.movementCompletion = completion

        // Calculate movement
        let speed = asteroidSize.speed
        let distance = sceneSize.height + asteroidSize.baseSize * 2
        let duration = TimeInterval(distance / speed)

        // Add slight horizontal drift
        let horizontalDrift = CGFloat.random(in: -30...30)
        let endX = self.position.x + horizontalDrift
        let endY = -asteroidSize.baseSize

        let moveAction = SKAction.move(to: CGPoint(x: endX, y: endY), duration: duration)

        let sequence = SKAction.sequence([
            moveAction,
            SKAction.run { [weak self] in
                guard let self = self else { return }
                if !self.hasCompletedMovement {
                    self.hasCompletedMovement = true
                    self.movementCompletion?()
                    self.removeFromParent()
                }
            }
        ])

        self.run(sequence, withKey: "asteroidMovement")
    }

    // Split asteroid into smaller pieces
    func split() -> [Asteroid] {
        guard let nextSize = asteroidSize.nextSize,
              let scene = gameScene else {
            return []
        }

        var newAsteroids: [Asteroid] = []
        let splitCount = asteroidSize.splitCount

        for _ in 0..<splitCount {
            let asteroid = Asteroid(
                sceneSize: sceneSize,
                scene: scene,
                size: nextSize,
                startPosition: self.position
            )

            newAsteroids.append(asteroid)
        }

        return newAsteroids
    }

    // Create explosion effect when destroyed
    func createExplosionEffect() {
        guard let scene = gameScene else { return }

        let particleCount = asteroidSize == .small ? 8 : 15

        for _ in 0..<particleCount {
            let particle = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...4))
            particle.fillColor = self.fillColor
            particle.strokeColor = self.strokeColor
            particle.position = self.position
            particle.zPosition = 5

            scene.gameContentNode.addChild(particle)

            // Random direction
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 50...150)
            let dx = cos(angle) * speed
            let dy = sin(angle) * speed

            let moveAction = SKAction.moveBy(x: dx, y: dy, duration: 0.5)
            let fadeAction = SKAction.fadeOut(withDuration: 0.5)
            let scaleAction = SKAction.scale(to: 0.1, duration: 0.5)

            let group = SKAction.group([moveAction, fadeAction, scaleAction])

            particle.run(group) {
                particle.removeFromParent()
            }
        }
    }
}
