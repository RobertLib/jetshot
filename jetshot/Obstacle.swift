//
//  Obstacle.swift
//  jetshot
//
//  Created by Robert Libšanský on 25.10.2025.
//

import SpriteKit

// Obstacle types with different behaviors
enum ObstacleType {
    case wall           // Static vertical wall
    case horizontalWall // Static horizontal wall
    case rotatingBar    // Rotating bar obstacle
    case movingWall     // Wall that moves left-right
    case spinner        // Rotating cross
    case destructibleWall // Wall made of blocks that can be shot through

    var color: UIColor {
        switch self {
        case .wall: return UIColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1.0)
        case .horizontalWall: return UIColor(red: 0.5, green: 0.4, blue: 0.4, alpha: 1.0)
        case .rotatingBar: return UIColor(red: 0.6, green: 0.3, blue: 0.3, alpha: 1.0)
        case .movingWall: return UIColor(red: 0.3, green: 0.5, blue: 0.6, alpha: 1.0)
        case .spinner: return UIColor(red: 0.6, green: 0.4, blue: 0.6, alpha: 1.0)
        case .destructibleWall: return UIColor(red: 0.5, green: 0.5, blue: 0.3, alpha: 1.0)
        }
    }

    var strokeColor: UIColor {
        switch self {
        case .wall: return UIColor(red: 0.6, green: 0.6, blue: 0.7, alpha: 1.0)
        case .horizontalWall: return UIColor(red: 0.7, green: 0.6, blue: 0.6, alpha: 1.0)
        case .rotatingBar: return UIColor(red: 0.8, green: 0.5, blue: 0.5, alpha: 1.0)
        case .movingWall: return UIColor(red: 0.5, green: 0.7, blue: 0.8, alpha: 1.0)
        case .spinner: return UIColor(red: 0.8, green: 0.6, blue: 0.8, alpha: 1.0)
        case .destructibleWall: return UIColor(red: 0.7, green: 0.7, blue: 0.5, alpha: 1.0)
        }
    }

    var size: CGSize {
        switch self {
        case .wall: return CGSize(width: 20, height: 120)
        case .horizontalWall: return CGSize(width: 150, height: 20)
        case .rotatingBar: return CGSize(width: 15, height: 180)
        case .movingWall: return CGSize(width: 20, height: 100)
        case .spinner: return CGSize(width: 15, height: 150)
        case .destructibleWall: return CGSize(width: 350, height: 60) // Wide but short - shootable barrier
        }
    }
}

class Obstacle: SKNode {

    let type: ObstacleType
    private var bodyNode: SKShapeNode!
    private var sceneSize: CGSize

    // For destructible wall - store individual blocks
    private var blocks: [SKShapeNode] = []
    private let blockSize: CGFloat = 20.0
    private let blockSpacing: CGFloat = 2.0

    init(type: ObstacleType, sceneSize: CGSize, position: CGPoint) {
        self.type = type
        self.sceneSize = sceneSize
        super.init()

        self.position = position
        self.name = "obstacle"
        self.zPosition = 10

        setupBody()
        setupPhysics()
        setupBehavior()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBody() {
        let size = type.size

        switch type {
        case .wall, .movingWall:
            // Vertical wall with segments and rivets
            bodyNode = SKShapeNode(rectOf: size, cornerRadius: 6)
            bodyNode.fillColor = type.color
            bodyNode.strokeColor = type.strokeColor
            bodyNode.lineWidth = 3.5

            // Add segment lines
            for i in 1..<4 {
                let y = -size.height / 2 + (size.height / 4) * CGFloat(i)
                let segment = SKShapeNode(rectOf: CGSize(width: size.width - 4, height: 2))
                segment.fillColor = type.strokeColor.withAlphaComponent(0.6)
                segment.strokeColor = .clear
                segment.position = CGPoint(x: 0, y: y)
                bodyNode.addChild(segment)
            }

            // Add rivets
            for i in 0..<5 {
                let y = -size.height / 2 + (size.height / 5) * CGFloat(i) + size.height / 10
                for x in [-size.width / 4, size.width / 4] {
                    let rivet = SKShapeNode(circleOfRadius: 2)
                    rivet.fillColor = type.strokeColor
                    rivet.strokeColor = .clear
                    rivet.position = CGPoint(x: x, y: y)
                    bodyNode.addChild(rivet)
                }
            }

        case .horizontalWall:
            // Horizontal wall with segments
            bodyNode = SKShapeNode(rectOf: size, cornerRadius: 6)
            bodyNode.fillColor = type.color
            bodyNode.strokeColor = type.strokeColor
            bodyNode.lineWidth = 3.5

            // Add vertical segment lines
            for i in 1..<6 {
                let x = -size.width / 2 + (size.width / 6) * CGFloat(i)
                let segment = SKShapeNode(rectOf: CGSize(width: 2, height: size.height - 4))
                segment.fillColor = type.strokeColor.withAlphaComponent(0.6)
                segment.strokeColor = .clear
                segment.position = CGPoint(x: x, y: 0)
                bodyNode.addChild(segment)
            }

        case .rotatingBar:
            // Rotating bar with caps
            bodyNode = SKShapeNode(rectOf: size, cornerRadius: 7)
            bodyNode.fillColor = type.color
            bodyNode.strokeColor = type.strokeColor
            bodyNode.lineWidth = 3.5

            // Add center hub
            let hub = SKShapeNode(circleOfRadius: 12)
            hub.fillColor = type.color.withAlphaComponent(0.8)
            hub.strokeColor = type.strokeColor
            hub.lineWidth = 3
            hub.zPosition = 1
            bodyNode.addChild(hub)

            // Add danger stripes
            for i in 0..<8 {
                let stripe = SKShapeNode(rectOf: CGSize(width: size.width - 4, height: 8))
                stripe.fillColor = i % 2 == 0 ? UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.6) : .clear
                stripe.strokeColor = .clear
                let y = -size.height / 2 + (size.height / 8) * CGFloat(i) + size.height / 16
                stripe.position = CGPoint(x: 0, y: y)
                bodyNode.addChild(stripe)
            }

            // Add end caps
            for yPos in [-size.height / 2, size.height / 2] {
                let cap = SKShapeNode(circleOfRadius: size.width / 2 + 2)
                cap.fillColor = type.strokeColor
                cap.strokeColor = type.color
                cap.lineWidth = 2
                cap.position = CGPoint(x: 0, y: yPos)
                bodyNode.addChild(cap)
            }

        case .spinner:
            // Create enhanced cross shape with 4 arms
            let armWidth = size.width
            let armLength = size.height / 2

            let path = CGMutablePath()

            // Create 4 arms in cross formation
            for i in 0..<4 {
                let angle = CGFloat(i) * .pi / 2
                let armPath = CGMutablePath()

                // Arm shape (wider at base, narrow at tip)
                armPath.move(to: CGPoint(x: -armWidth / 2, y: 0))
                armPath.addLine(to: CGPoint(x: -armWidth / 3, y: armLength * 0.8))
                armPath.addLine(to: CGPoint(x: 0, y: armLength))
                armPath.addLine(to: CGPoint(x: armWidth / 3, y: armLength * 0.8))
                armPath.addLine(to: CGPoint(x: armWidth / 2, y: 0))
                armPath.closeSubpath()

                // Rotate arm to correct angle
                var transform = CGAffineTransform(rotationAngle: angle)
                if let transformedPath = armPath.copy(using: &transform) {
                    path.addPath(transformedPath)
                }
            }

            bodyNode = SKShapeNode(path: path)
            bodyNode.fillColor = type.color
            bodyNode.strokeColor = type.strokeColor
            bodyNode.lineWidth = 3.5

            // Add center core
            let core = SKShapeNode(circleOfRadius: 15)
            core.fillColor = type.color.withAlphaComponent(0.9)
            core.strokeColor = type.strokeColor
            core.lineWidth = 3
            core.zPosition = 1
            bodyNode.addChild(core)

            // Add warning pattern in center
            let warningCircle = SKShapeNode(circleOfRadius: 10)
            warningCircle.fillColor = .clear
            warningCircle.strokeColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.8)
            warningCircle.lineWidth = 2
            warningCircle.zPosition = 2
            core.addChild(warningCircle)

        case .destructibleWall:
            // Create grid of destructible blocks
            let totalWidth = type.size.width
            let totalHeight = type.size.height

            let blocksPerRow = Int(totalWidth / (blockSize + blockSpacing))
            let blocksPerColumn = Int(totalHeight / (blockSize + blockSpacing))

            // Create container node (no physics)
            bodyNode = SKShapeNode()
            bodyNode.fillColor = .clear
            bodyNode.strokeColor = .clear

            // Calculate starting position to center the grid
            let gridWidth = CGFloat(blocksPerRow) * (blockSize + blockSpacing) - blockSpacing
            let gridHeight = CGFloat(blocksPerColumn) * (blockSize + blockSpacing) - blockSpacing
            let startX = -gridWidth / 2
            let startY = -gridHeight / 2

            // Create individual blocks in a grid pattern
            for row in 0..<blocksPerColumn {
                for col in 0..<blocksPerRow {
                    let block = SKShapeNode(rectOf: CGSize(width: blockSize, height: blockSize), cornerRadius: 3)

                    // Slight color variation for visual interest
                    let variation = CGFloat.random(in: -0.05...0.05)
                    block.fillColor = UIColor(
                        red: type.color.cgColor.components![0] + variation,
                        green: type.color.cgColor.components![1] + variation,
                        blue: type.color.cgColor.components![2] + variation,
                        alpha: 1.0
                    )
                    block.strokeColor = type.strokeColor
                    block.lineWidth = 1.5

                    let x = startX + CGFloat(col) * (blockSize + blockSpacing) + blockSize / 2
                    let y = startY + CGFloat(row) * (blockSize + blockSpacing) + blockSize / 2
                    block.position = CGPoint(x: x, y: y)

                    // Add subtle glow to each block
                    GlowHelper.addEnhancedGlow(to: block, color: type.color, intensity: 0.4)

                    // Physics for each block - IMPORTANT: Set all physics properties
                    block.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: blockSize, height: blockSize))
                    block.physicsBody?.isDynamic = false
                    block.physicsBody?.categoryBitMask = PhysicsCategory.obstacle
                    block.physicsBody?.contactTestBitMask = PhysicsCategory.player | PhysicsCategory.bullet
                    block.physicsBody?.collisionBitMask = PhysicsCategory.none
                    block.physicsBody?.affectedByGravity = false

                    // Store reference and add to body
                    block.name = "destructibleBlock"
                    blocks.append(block)
                    bodyNode.addChild(block)
                }
            }
        }

        addChild(bodyNode)

        // Add enhanced glow effect (skip for destructible wall as blocks have their own glow)
        if type != .destructibleWall {
            GlowHelper.addEnhancedGlow(to: bodyNode, color: type.color, intensity: 0.7)
        }
    }

    private func setupPhysics() {
        // Skip physics setup for destructible wall - blocks have their own physics
        if type == .destructibleWall {
            return
        }

        let size = type.size

        switch type {
        case .wall, .horizontalWall, .movingWall, .rotatingBar:
            physicsBody = SKPhysicsBody(rectangleOf: size)

        case .spinner:
            // Cross shape - use two rectangles
            let verticalBody = SKPhysicsBody(rectangleOf: size)
            let horizontalBody = SKPhysicsBody(rectangleOf: CGSize(width: size.height, height: size.width))
            physicsBody = SKPhysicsBody(bodies: [verticalBody, horizontalBody])

        case .destructibleWall:
            break // Already handled above
        }

        physicsBody?.isDynamic = false
        physicsBody?.categoryBitMask = PhysicsCategory.obstacle
        physicsBody?.contactTestBitMask = PhysicsCategory.player | PhysicsCategory.bullet
        physicsBody?.collisionBitMask = PhysicsCategory.none
        physicsBody?.affectedByGravity = false
    }

    private func setupBehavior() {
        switch type {
        case .wall, .horizontalWall, .destructibleWall:
            // Static - just move down with the scene
            startMovingDown()

        case .rotatingBar:
            // Rotate continuously
            let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: 3.0)
            let rotateForever = SKAction.repeatForever(rotateAction)
            run(rotateForever, withKey: "rotate")
            startMovingDown()

        case .movingWall:
            // Move left-right while moving down
            startMovingDown()
            startHorizontalMovement()

        case .spinner:
            // Rotate continuously (faster than bar)
            let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: 2.0)
            let rotateForever = SKAction.repeatForever(rotateAction)
            run(rotateForever, withKey: "rotate")
            startMovingDown()
        }
    }

    private func startMovingDown() {
        // Move down the screen
        let moveDuration: TimeInterval = 8.0
        let moveAction = SKAction.moveBy(x: 0, y: -(sceneSize.height + 200), duration: moveDuration)
        let removeAction = SKAction.removeFromParent()
        let sequence = SKAction.sequence([moveAction, removeAction])
        run(sequence, withKey: "moveDown")
    }

    private func startHorizontalMovement() {
        // Move left-right in a wave pattern
        let moveDistance: CGFloat = 100
        let moveDuration: TimeInterval = 2.0

        let moveRight = SKAction.moveBy(x: moveDistance, y: 0, duration: moveDuration)
        let moveLeft = SKAction.moveBy(x: -moveDistance, y: 0, duration: moveDuration)

        moveRight.timingMode = .easeInEaseOut
        moveLeft.timingMode = .easeInEaseOut

        let sequence = SKAction.sequence([moveRight, moveLeft])
        let forever = SKAction.repeatForever(sequence)
        run(forever, withKey: "horizontalMove")
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    // Method to destroy a single block in destructible wall
    func destroyBlock(hitNode: SKNode?) -> Bool {
        guard type == .destructibleWall else { return false }
        guard let hitNode = hitNode else { return false }

        // Check if the hit node is one of our blocks
        guard let block = hitNode as? SKShapeNode,
              blocks.contains(block),
              block.parent != nil else {
            return false
        }

        // Create small explosion particles
        createBlockExplosion(at: block.position, in: bodyNode)

        // Fade out and fall animation
        let fadeOut = SKAction.fadeOut(withDuration: 0.2)
        let scaleDown = SKAction.scale(to: 0.3, duration: 0.2)
        let rotate = SKAction.rotate(byAngle: CGFloat.random(in: -CGFloat.pi...CGFloat.pi), duration: 0.3)
        let fall = SKAction.moveBy(x: CGFloat.random(in: -10...10), y: -30, duration: 0.3)

        let group = SKAction.group([fadeOut, scaleDown, rotate, fall])
        let remove = SKAction.removeFromParent()

        block.run(SKAction.sequence([group, remove]))

        // Remove from blocks array
        if let index = blocks.firstIndex(of: block) {
            blocks.remove(at: index)
        }

        // Check if all blocks are destroyed
        if blocks.allSatisfy({ $0.parent == nil }) {
            // Remove the entire obstacle after a short delay
            let wait = SKAction.wait(forDuration: 0.5)
            let removeObstacle = SKAction.removeFromParent()
            run(SKAction.sequence([wait, removeObstacle]))
        }

        return true
    }

    private func createBlockExplosion(at position: CGPoint, in parent: SKNode) {
        // Create small particle effect for block destruction
        for _ in 0..<6 {
            let particle = SKShapeNode(rectOf: CGSize(width: 4, height: 4))
            particle.fillColor = type.color
            particle.strokeColor = .clear
            particle.position = position
            particle.zPosition = 20

            parent.addChild(particle)

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 20...40)
            let dx = cos(angle) * speed
            let dy = sin(angle) * speed

            let move = SKAction.moveBy(x: dx, y: dy, duration: 0.3)
            let fadeOut = SKAction.fadeOut(withDuration: 0.3)
            let scale = SKAction.scale(to: 0, duration: 0.3)
            let group = SKAction.group([move, fadeOut, scale])
            let remove = SKAction.removeFromParent()

            particle.run(SKAction.sequence([group, remove]))
        }
    }
}
