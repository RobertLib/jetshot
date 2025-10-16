//
//  Coin.swift
//  jetshot
//
//  Created by Robert Libšanský on 01.11.2025.
//

import SpriteKit

class Coin: SKNode {
    private var shape: SKShapeNode!
    private let size: CGFloat = 24
    let pointValue: Int = 10

    init(position: CGPoint) {
        super.init()

        self.position = position
        self.name = "coin"

        setupVisuals()
        setupPhysics()
        addAnimations()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupVisuals() {
        // Main container for star shape
        shape = SKShapeNode()

        // Create star with golden color
        let starColor = UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0) // Rich gold
        let starBorder = UIColor(red: 1.0, green: 0.95, blue: 0.3, alpha: 1.0) // Bright gold

        // Create 5-pointed star path
        let starPath = CGMutablePath()
        let radius: CGFloat = size / 2
        let innerRadius: CGFloat = radius * 0.4
        let points = 5

        for i in 0..<points * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let currentRadius = i % 2 == 0 ? radius : innerRadius
            let x = currentRadius * cos(angle)
            let y = currentRadius * sin(angle)

            if i == 0 {
                starPath.move(to: CGPoint(x: x, y: y))
            } else {
                starPath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        starPath.closeSubpath()

        // Main star
        let mainStar = SKShapeNode(path: starPath)
        mainStar.fillColor = starColor
        mainStar.strokeColor = starBorder
        mainStar.lineWidth = 2.5
        shape.addChild(mainStar)

        // Inner star for depth
        let innerStarPath = CGMutablePath()
        let innerStarRadius: CGFloat = radius * 0.6
        let innerStarInnerRadius: CGFloat = innerStarRadius * 0.4

        for i in 0..<points * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let currentRadius = i % 2 == 0 ? innerStarRadius : innerStarInnerRadius
            let x = currentRadius * cos(angle)
            let y = currentRadius * sin(angle)

            if i == 0 {
                innerStarPath.move(to: CGPoint(x: x, y: y))
            } else {
                innerStarPath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        innerStarPath.closeSubpath()

        let innerStar = SKShapeNode(path: innerStarPath)
        innerStar.fillColor = UIColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 0.5)
        innerStar.strokeColor = .clear
        shape.addChild(innerStar)

        addChild(shape)

        // Add stronger pulsing glow effect
        GlowHelper.addPulsingEnhancedGlow(
            to: mainStar,
            color: UIColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1.0),
            minIntensity: 0.8,
            maxIntensity: 1.2,
            duration: 1.0
        )
    }

    private func setupPhysics() {
        let physicsBody = SKPhysicsBody(circleOfRadius: size / 2)
        physicsBody.isDynamic = true
        physicsBody.categoryBitMask = PhysicsCategory.coin
        physicsBody.contactTestBitMask = PhysicsCategory.player
        physicsBody.collisionBitMask = PhysicsCategory.none
        physicsBody.usesPreciseCollisionDetection = true
        self.physicsBody = physicsBody
    }

    private func addAnimations() {
        // Random rotation direction (left or right)
        let rotationDirection: CGFloat = Bool.random() ? 1.0 : -1.0

        // Random rotation duration (slower = 4-8 seconds for full rotation)
        let rotationDuration = Double.random(in: 4.0...8.0)

        // Rotate with random direction and speed
        let rotate = SKAction.rotate(byAngle: .pi * 2 * rotationDirection, duration: rotationDuration)
        shape.run(SKAction.repeatForever(rotate))

        // Gentle vertical bobbing
        let moveUp = SKAction.moveBy(x: 0, y: 3, duration: 0.6)
        let moveDown = SKAction.moveBy(x: 0, y: -3, duration: 0.6)
        let bob = SKAction.sequence([moveUp, moveDown])
        shape.run(SKAction.repeatForever(bob))

        // Slow downward movement
        let moveDownScreen = SKAction.moveTo(y: -50, duration: 10.0)
        let remove = SKAction.removeFromParent()
        run(SKAction.sequence([moveDownScreen, remove]))
    }

    func collect(scorePosition: CGPoint) {
        // Immediately disable physics to prevent multiple collisions
        self.physicsBody = nil

        // Stop all existing animations
        removeAllActions()
        shape.removeAllActions()

        // Create collection sparkle effect at collection point
        createCollectionEffect()

        // Fly to score position animation
        let flyDuration: TimeInterval = 0.4
        let flyToScore = SKAction.move(to: scorePosition, duration: flyDuration)
        flyToScore.timingMode = .easeIn

        let shrink = SKAction.scale(to: 0.3, duration: flyDuration)
        let fadeOut = SKAction.fadeOut(withDuration: flyDuration * 0.7)
        fadeOut.timingMode = .easeIn

        let remove = SKAction.removeFromParent()

        run(SKAction.sequence([
            SKAction.group([flyToScore, shrink, fadeOut]),
            remove
        ]))
    }

    private func createCollectionEffect() {
        guard let parent = self.parent else { return }

        // Create sparkle particles
        let sparkle = SKEmitterNode()

        // Create small circle texture for sparkles
        let sparkleSize = CGSize(width: 8, height: 8)
        let sparkleRenderer = UIGraphicsImageRenderer(size: sparkleSize)
        let sparkleImage = sparkleRenderer.image { context in
            UIColor.white.setFill()
            let rect = CGRect(origin: .zero, size: sparkleSize)
            context.cgContext.fillEllipse(in: rect)
        }
        sparkle.particleTexture = SKTexture(image: sparkleImage)

        sparkle.particleBirthRate = 30
        sparkle.numParticlesToEmit = 20
        sparkle.particleLifetime = 0.5
        sparkle.particlePositionRange = CGVector(dx: 10, dy: 10)
        sparkle.particleSpeed = 50
        sparkle.particleSpeedRange = 30
        sparkle.emissionAngleRange = .pi * 2
        sparkle.particleAlpha = 1.0
        sparkle.particleAlphaSpeed = -2.0
        sparkle.particleScale = 0.3
        sparkle.particleScaleSpeed = -0.3
        sparkle.particleColor = UIColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1.0)
        sparkle.particleColorBlendFactor = 1.0
        sparkle.particleBlendMode = .add
        sparkle.position = self.position

        parent.addChild(sparkle)

        // Remove sparkle after animation
        sparkle.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.5),
            SKAction.removeFromParent()
        ]))
    }
}
