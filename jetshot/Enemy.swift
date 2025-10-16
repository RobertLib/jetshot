//
//  Enemy.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import SpriteKit

class Enemy: SKShapeNode {

    // Shooting properties
    private var shootTimer: Timer?
    private let shootInterval: TimeInterval
    private var gameScene: SKScene?
    private var movementDuration: TimeInterval = 4.0 // Will be set in startMovement

    init(sceneSize: CGSize, scene: SKScene) {
        // Random shoot interval between 1.5 and 3.5 seconds
        self.shootInterval = TimeInterval.random(in: 1.5...3.5)
        self.gameScene = scene

        super.init()

        setupEnemy(sceneSize: sceneSize)
        startShooting()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        shootTimer?.invalidate()
    }

    func pauseShooting() {
        shootTimer?.invalidate()
        shootTimer = nil
    }

    func resumeShooting() {
        guard shootTimer == nil else { return }
        startShooting()
    }

    private func setupEnemy(sceneSize: CGSize) {
        // Create diamond shape
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 12))
        path.addLine(to: CGPoint(x: 10, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -12))
        path.addLine(to: CGPoint(x: -10, y: 0))
        path.closeSubpath()

        self.path = path
        self.fillColor = .red
        self.strokeColor = .white
        self.lineWidth = 2
        self.name = "enemy"

        // Random spawn position at top
        let randomX = CGFloat.random(in: 30...(sceneSize.width - 30))
        self.position = CGPoint(x: randomX, y: sceneSize.height + 20)

        // Setup physics body
        self.physicsBody = SKPhysicsBody(polygonFrom: path)
        self.physicsBody?.isDynamic = true
        self.physicsBody?.categoryBitMask = PhysicsCategory.enemy
        self.physicsBody?.contactTestBitMask = PhysicsCategory.player | PhysicsCategory.bullet
        self.physicsBody?.collisionBitMask = PhysicsCategory.none
    }

    func startMovement(completion: @escaping () -> Void) {
        // Move downwards with random duration
        movementDuration = TimeInterval.random(in: 3.0...5.0)
        let moveAction = SKAction.moveTo(y: -20, duration: movementDuration)
        let removeAction = SKAction.removeFromParent()

        run(SKAction.sequence([moveAction, removeAction])) {
            completion()
        }
    }

    private func startShooting() {
        // Schedule shooting at random intervals
        shootTimer = Timer.scheduledTimer(withTimeInterval: shootInterval, repeats: true) { [weak self] _ in
            self?.shoot()
        }
    }

    private func shoot() {
        guard let scene = gameScene, parent != nil else { return }

        // Create enemy bullet
        let bullet = SKShapeNode(circleOfRadius: 4)
        bullet.fillColor = .orange
        bullet.strokeColor = .yellow
        bullet.lineWidth = 1
        bullet.position = position
        bullet.name = "enemyBullet"

        // Setup physics for enemy bullet
        bullet.physicsBody = SKPhysicsBody(circleOfRadius: 4)
        bullet.physicsBody?.isDynamic = true
        bullet.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
        bullet.physicsBody?.contactTestBitMask = PhysicsCategory.player
        bullet.physicsBody?.collisionBitMask = PhysicsCategory.none
        bullet.physicsBody?.usesPreciseCollisionDetection = true

        scene.addChild(bullet)

        // Calculate bullet speed based on distance and constant speed
        // Bullet speed: 400 pixels per second (always faster than enemy's max ~250 px/s)
        let bulletSpeed: CGFloat = 400.0
        let distance = position.y - (-20) // Distance to bottom
        let bulletDuration = TimeInterval(distance / bulletSpeed)

        let moveAction = SKAction.moveTo(y: -20, duration: bulletDuration)
        let removeAction = SKAction.removeFromParent()
        bullet.run(SKAction.sequence([moveAction, removeAction]))

        // Play shoot sound (quieter for enemies)
        SoundManager.shared.playShoot()
    }
}
