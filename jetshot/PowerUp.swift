//
//  PowerUp.swift
//  jetshot
//
//  Created by Robert Libšanský on 25.10.2025.
//

import SpriteKit

enum PowerUpType {
    case extraLife    // Add extra life (max 4)
    case multiShot    // Multiple shots (max 4)
    case sideMissiles // Side missiles (max 2)
    case shield       // Temporary shield
    case lightning    // Lightning weapon

    var color: UIColor {
        switch self {
        case .extraLife:
            return UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0) // Green
        case .multiShot:
            return UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0) // Yellow
        case .sideMissiles:
            return UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0) // Orange
        case .shield:
            return UIColor(red: 0.0, green: 0.7, blue: 1.0, alpha: 1.0) // Blue
        case .lightning:
            return UIColor(red: 0.6, green: 0.3, blue: 1.0, alpha: 1.0) // Purple
        }
    }

    var icon: String {
        switch self {
        case .extraLife:
            return "+"
        case .multiShot:
            return "×"
        case .sideMissiles:
            return "⟫"
        case .shield:
            return "◆"
        case .lightning:
            return "⚡"
        }
    }

    var points: Int {
        switch self {
        case .extraLife:
            return 100
        case .multiShot:
            return 50
        case .sideMissiles:
            return 75
        case .shield:
            return 50
        case .lightning:
            return 150
        }
    }
}

class PowerUp: SKNode {
    var powerUpType: PowerUpType
    private var shape: SKShapeNode!
    private let size: CGFloat = 30

    init(type: PowerUpType, position: CGPoint) {
        self.powerUpType = type
        super.init()

        self.position = position
        self.name = "powerup"

        setupVisuals()
        setupPhysics()
        addAnimations()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupVisuals() {
        // Main container with hexagonal shape
        shape = SKShapeNode()

        // Create hexagonal border
        let hexPath = createHexagonPath(radius: size / 2)
        let hexBorder = SKShapeNode(path: hexPath)
        hexBorder.fillColor = powerUpType.color.withAlphaComponent(0.2)
        hexBorder.strokeColor = powerUpType.color
        hexBorder.lineWidth = 3.5
        shape.addChild(hexBorder)

        // Add inner glow ring
        let innerHex = SKShapeNode(path: createHexagonPath(radius: size / 2 - 6))
        innerHex.fillColor = .clear
        innerHex.strokeColor = powerUpType.color.withAlphaComponent(0.6)
        innerHex.lineWidth = 2
        shape.addChild(innerHex)

        // Add decorative corners
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3
            let x = (size / 2 - 3) * cos(angle)
            let y = (size / 2 - 3) * sin(angle)
            let corner = SKShapeNode(circleOfRadius: 2)
            corner.fillColor = powerUpType.color
            corner.strokeColor = .clear
            corner.position = CGPoint(x: x, y: y)
            shape.addChild(corner)
        }

        addChild(shape)

        // Create detailed icon based on type
        let iconNode = createIconNode()
        addChild(iconNode)

        // Add glow effect
        GlowHelper.addPulsingEnhancedGlow(
            to: shape,
            color: powerUpType.color,
            minIntensity: 0.6,
            maxIntensity: 1.0,
            duration: 1.2
        )
    }

    private func createHexagonPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3
            let x = radius * cos(angle)
            let y = radius * sin(angle)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }

    private func createIconNode() -> SKNode {
        let container = SKNode()

        switch powerUpType {
        case .extraLife:
            // Heart icon
            let heartPath = CGMutablePath()
            heartPath.move(to: CGPoint(x: 0, y: -6))
            heartPath.addCurve(to: CGPoint(x: -8, y: 2), control1: CGPoint(x: -4, y: -8), control2: CGPoint(x: -8, y: -2))
            heartPath.addCurve(to: CGPoint(x: 0, y: 8), control1: CGPoint(x: -8, y: 6), control2: CGPoint(x: -3, y: 8))
            heartPath.addCurve(to: CGPoint(x: 8, y: 2), control1: CGPoint(x: 3, y: 8), control2: CGPoint(x: 8, y: 6))
            heartPath.addCurve(to: CGPoint(x: 0, y: -6), control1: CGPoint(x: 8, y: -2), control2: CGPoint(x: 4, y: -8))

            let heart = SKShapeNode(path: heartPath)
            heart.fillColor = powerUpType.color
            heart.strokeColor = powerUpType.color.withAlphaComponent(0.8)
            heart.lineWidth = 2
            container.addChild(heart)

        case .multiShot:
            // Triple bullet icon
            for i in -1...1 {
                let bullet = SKShapeNode(rectOf: CGSize(width: 3, height: 10), cornerRadius: 1.5)
                bullet.fillColor = powerUpType.color
                bullet.strokeColor = .clear
                bullet.position = CGPoint(x: CGFloat(i) * 6, y: 0)
                container.addChild(bullet)
            }

        case .sideMissiles:
            // Angled missiles icon
            let leftMissile = SKShapeNode(rectOf: CGSize(width: 4, height: 12), cornerRadius: 2)
            leftMissile.fillColor = powerUpType.color
            leftMissile.strokeColor = .clear
            leftMissile.position = CGPoint(x: -6, y: 0)
            leftMissile.zRotation = -.pi / 6
            container.addChild(leftMissile)

            let rightMissile = SKShapeNode(rectOf: CGSize(width: 4, height: 12), cornerRadius: 2)
            rightMissile.fillColor = powerUpType.color
            rightMissile.strokeColor = .clear
            rightMissile.position = CGPoint(x: 6, y: 0)
            rightMissile.zRotation = .pi / 6
            container.addChild(rightMissile)

            // Add center indicator
            let center = SKShapeNode(circleOfRadius: 3)
            center.fillColor = powerUpType.color
            center.strokeColor = .clear
            container.addChild(center)

        case .shield:
            // Shield icon with segments
            let shieldPath = CGMutablePath()
            shieldPath.move(to: CGPoint(x: 0, y: -8))
            shieldPath.addLine(to: CGPoint(x: -8, y: -4))
            shieldPath.addLine(to: CGPoint(x: -8, y: 4))
            shieldPath.addLine(to: CGPoint(x: 0, y: 8))
            shieldPath.addLine(to: CGPoint(x: 8, y: 4))
            shieldPath.addLine(to: CGPoint(x: 8, y: -4))
            shieldPath.closeSubpath()

            let shield = SKShapeNode(path: shieldPath)
            shield.fillColor = powerUpType.color.withAlphaComponent(0.7)
            shield.strokeColor = powerUpType.color
            shield.lineWidth = 2.5
            container.addChild(shield)

            // Add cross pattern
            let vLine = SKShapeNode(rectOf: CGSize(width: 2, height: 14))
            vLine.fillColor = powerUpType.color
            vLine.strokeColor = .clear
            container.addChild(vLine)

            let hLine = SKShapeNode(rectOf: CGSize(width: 14, height: 2))
            hLine.fillColor = powerUpType.color
            hLine.strokeColor = .clear
            container.addChild(hLine)

        case .lightning:
            // Lightning bolt icon
            let boltPath = CGMutablePath()
            boltPath.move(to: CGPoint(x: 2, y: 8))
            boltPath.addLine(to: CGPoint(x: -4, y: 2))
            boltPath.addLine(to: CGPoint(x: 0, y: 2))
            boltPath.addLine(to: CGPoint(x: -2, y: -8))
            boltPath.addLine(to: CGPoint(x: 4, y: -2))
            boltPath.addLine(to: CGPoint(x: 0, y: -2))
            boltPath.closeSubpath()

            let bolt = SKShapeNode(path: boltPath)
            bolt.fillColor = powerUpType.color
            bolt.strokeColor = UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0)
            bolt.lineWidth = 2
            container.addChild(bolt)

            // Add energy sparks around the bolt
            for i in 0..<3 {
                let angle = CGFloat(i) * .pi * 2 / 3
                let radius: CGFloat = 8
                let spark = SKShapeNode(circleOfRadius: 1.5)
                spark.fillColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9)
                spark.strokeColor = .clear
                spark.position = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
                container.addChild(spark)

                // Spark animation
                let pulse = SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.3, duration: 0.15),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.15)
                ])
                spark.run(SKAction.repeatForever(pulse))
            }
        }

        return container
    }

    private func setupPhysics() {
        let physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size, height: size))
        physicsBody.isDynamic = true
        physicsBody.categoryBitMask = PhysicsCategory.powerUp
        physicsBody.contactTestBitMask = PhysicsCategory.player
        physicsBody.collisionBitMask = PhysicsCategory.none
        physicsBody.usesPreciseCollisionDetection = true
        self.physicsBody = physicsBody
    }

    private func addAnimations() {
        // Gentle rotation
        let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 3.0)
        shape.run(SKAction.repeatForever(rotate))

        // Pulsing size
        let scaleUp = SKAction.scale(to: 1.1, duration: 0.8)
        let scaleDown = SKAction.scale(to: 0.9, duration: 0.8)
        let pulse = SKAction.sequence([scaleUp, scaleDown])
        shape.run(SKAction.repeatForever(pulse))

        // Slow downward movement
        let moveDown = SKAction.moveTo(y: -50, duration: 8.0)
        let remove = SKAction.removeFromParent()
        run(SKAction.sequence([moveDown, remove]))
    }

    func collect() {
        // Immediately disable physics to prevent multiple collisions
        self.physicsBody = nil

        // Collection animation
        let fadeOut = SKAction.fadeOut(withDuration: 0.2)
        let scaleUp = SKAction.scale(to: 1.5, duration: 0.2)
        let remove = SKAction.removeFromParent()

        run(SKAction.sequence([
            SKAction.group([fadeOut, scaleUp]),
            remove
        ]))
    }
}
