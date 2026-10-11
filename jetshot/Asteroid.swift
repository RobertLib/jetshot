//
//  Asteroid.swift
//  jetshot
//
//  Created by Robert Libšanský on 1.11.2025.
//

import SpriteKit
import simd

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

        // The polygon is the physics outline only. What is drawn is a rock in real 3D,
        // tumbling on its own axis in the films' light-tube wireframe, over a dark body
        // that keeps the world's lines from showing through it.
        let strokeColor = Self.rockColor
        self.fillColor = .clear
        self.strokeColor = .clear
        self.lineWidth = 0
        self.glowWidth = 0

        let body = SKSpriteNode(texture: WireCanvas.discTexture,
                                size: CGSize(width: baseRadius * 1.7, height: baseRadius * 1.7))
        body.color = UIColor(red: 0.03, green: 0.02, blue: 0.02, alpha: 1)
        body.colorBlendFactor = 1
        body.alpha = 0.85
        body.zPosition = -0.5
        addChild(body)

        let mesh = WireMesh.rock(radius: Float(baseRadius) * 0.92, seed: UInt64.random(in: 0...UInt64.max),
                                 roughness: 0.34, subdivisions: asteroidSize == .small ? 0 : 1)
        let axis = simd_normalize(Vec3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) + Vec3(0, 0, 0.01))
        let tumble = Float.random(in: 0.5...1.1) * Float(asteroidSize.rotationSpeed) * 2
        let glow = Self.emberColor
        let rock = WireBody(extent: baseRadius * 1.05, perspective: 4.5, interval: 1.0 / 30,
                            seed: Float.random(in: 0...50)) { frame in
            let c = frame.canvas
            c.glow(.zero, radius: Float(baseRadius) * 0.7, color: glow, alpha: 0.18)
            c.mesh(mesh, rotation: rotation(frame.t * tumble, axis), color: strokeColor, alpha: 0.78,
                   width: 1.0, backAlpha: 0.2)
        }
        rock.zPosition = 1
        addChild(rock)

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

        // Only a faint halo: rock is not a light source.
        GlowHelper.addEnhancedGlow(to: self, color: strokeColor, intensity: 0.16)

        self.name = "asteroid"
        self.zPosition = 10
    }

    /// Sunlit stone, as light: warm enough to tell from every hostile's red and
    /// every pickup's gold.
    static let rockColor = UIColor(red: 0.9, green: 0.7, blue: 0.5, alpha: 1)
    static let emberColor = UIColor(red: 1.0, green: 0.46, blue: 0.22, alpha: 1)

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

        // The rock comes apart into lines of itself, tumbling outwards.
        let count = asteroidSize == .small ? 7 : 12
        let reach = asteroidSize.baseSize
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2 + CGFloat.random(in: -0.3...0.3)
            let length = CGFloat.random(in: 0.25...0.5) * reach
            let shard = LightSprite.tube(from: CGPoint(x: -length / 2, y: 0), to: CGPoint(x: length / 2, y: 0),
                                         width: 1.3, color: i % 3 == 0 ? Self.emberColor : Self.rockColor)
            shard.position = CGPoint(x: position.x + cos(angle) * reach * 0.4, y: position.y + sin(angle) * reach * 0.4)
            shard.zRotation = CGFloat.random(in: 0...(.pi))
            shard.zPosition = 5
            scene.gameContentNode.addChild(shard)

            let speed = CGFloat.random(in: 60...160)
            let move = SKAction.moveBy(x: cos(angle) * speed * 0.6, y: sin(angle) * speed * 0.6, duration: 0.6)
            move.timingMode = .easeOut
            let spin = SKAction.rotate(byAngle: CGFloat.random(in: -6...6), duration: 0.6)
            shard.run(.sequence([.group([move, spin, .fadeOut(withDuration: 0.6), .scaleX(to: 0.3, duration: 0.6)]),
                                 .removeFromParent()]))
        }
        let dust = LightSprite.star(size: reach * 3, color: Self.emberColor)
        dust.position = position
        dust.zPosition = 4
        dust.alpha = 0.6
        scene.gameContentNode.addChild(dust)
        dust.run(.sequence([.group([.scale(to: 1.6, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
    }
}
