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

    init(sceneSize: CGSize, safeAreaBottom: CGFloat = 0) {
        super.init()

        setupPlayer(sceneSize: sceneSize, safeAreaBottom: safeAreaBottom)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPlayer(sceneSize: CGSize, safeAreaBottom: CGFloat) {
        // Create triangle shape
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 15))
        path.addLine(to: CGPoint(x: -10, y: -15))
        path.addLine(to: CGPoint(x: 10, y: -15))
        path.closeSubpath()

        self.path = path
        self.fillColor = .cyan
        self.strokeColor = .white
        self.lineWidth = 2

        // Position above safe area (home indicator) with padding
        let playerHeight = safeAreaBottom + 60
        self.position = CGPoint(x: sceneSize.width / 2, y: playerHeight)
        self.name = "player"

        // Setup physics body
        self.physicsBody = SKPhysicsBody(polygonFrom: path)
        self.physicsBody?.isDynamic = true
        self.physicsBody?.categoryBitMask = PhysicsCategory.player
        self.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.enemyBullet
        self.physicsBody?.collisionBitMask = PhysicsCategory.none
        self.physicsBody?.usesPreciseCollisionDetection = true
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

    func shoot() -> SKShapeNode {
        // Create bullet
        let bullet = SKShapeNode(rectOf: CGSize(width: 4, height: 12), cornerRadius: 2)
        bullet.fillColor = .yellow
        bullet.strokeColor = .orange
        bullet.position = CGPoint(x: self.position.x, y: self.position.y + 20)
        bullet.name = "bullet"

        // Setup physics body
        bullet.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 4, height: 12))
        bullet.physicsBody?.isDynamic = true
        bullet.physicsBody?.categoryBitMask = PhysicsCategory.bullet
        bullet.physicsBody?.contactTestBitMask = PhysicsCategory.enemy
        bullet.physicsBody?.collisionBitMask = PhysicsCategory.none
        bullet.physicsBody?.usesPreciseCollisionDetection = true

        return bullet
    }

    func playHitAnimation() {
        // Blink animation when hit
        let blinkAction = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.1),
            SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        ])
        run(SKAction.repeat(blinkAction, count: 3))
    }
}
