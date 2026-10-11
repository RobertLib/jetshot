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
    case pulsatingRing  // Ring that pulses in and out
    case zigzagWall     // Wall that moves in zigzag pattern
    case spiralBlade    // Blade that rotates and expands
    case waveWall       // Wall that moves in sine wave pattern
    case triangleBarrier // Triangular rotating barrier
    case hexagonTrap    // Hexagonal obstacle that rotates

    var color: UIColor {
        switch self {
        case .wall: return UIColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1.0)
        case .horizontalWall: return UIColor(red: 0.5, green: 0.4, blue: 0.4, alpha: 1.0)
        case .rotatingBar: return UIColor(red: 0.6, green: 0.3, blue: 0.3, alpha: 1.0)
        case .movingWall: return UIColor(red: 0.3, green: 0.5, blue: 0.6, alpha: 1.0)
        case .spinner: return UIColor(red: 0.6, green: 0.4, blue: 0.6, alpha: 1.0)
        case .destructibleWall: return UIColor(red: 0.5, green: 0.5, blue: 0.3, alpha: 1.0)
        case .pulsatingRing: return UIColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1.0)
        case .zigzagWall: return UIColor(red: 0.7, green: 0.3, blue: 0.5, alpha: 1.0)
        case .spiralBlade: return UIColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1.0)
        case .waveWall: return UIColor(red: 0.3, green: 0.7, blue: 0.4, alpha: 1.0)
        case .triangleBarrier: return UIColor(red: 0.6, green: 0.5, blue: 0.7, alpha: 1.0)
        case .hexagonTrap: return UIColor(red: 0.8, green: 0.6, blue: 0.3, alpha: 1.0)
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
        case .pulsatingRing: return UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
        case .zigzagWall: return UIColor(red: 0.9, green: 0.5, blue: 0.7, alpha: 1.0)
        case .spiralBlade: return UIColor(red: 1.0, green: 0.6, blue: 0.4, alpha: 1.0)
        case .waveWall: return UIColor(red: 0.5, green: 0.9, blue: 0.6, alpha: 1.0)
        case .triangleBarrier: return UIColor(red: 0.8, green: 0.7, blue: 0.9, alpha: 1.0)
        case .hexagonTrap: return UIColor(red: 1.0, green: 0.8, blue: 0.5, alpha: 1.0)
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
        case .pulsatingRing: return CGSize(width: 100, height: 100)
        case .zigzagWall: return CGSize(width: 20, height: 100)
        case .spiralBlade: return CGSize(width: 12, height: 140)
        case .waveWall: return CGSize(width: 25, height: 110)
        case .triangleBarrier: return CGSize(width: 120, height: 120)
        case .hexagonTrap: return CGSize(width: 90, height: 90)
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

                    // Glass bricks in a lit edge; a slight variation in the glass so the
                    // wall reads as built from pieces, which is what it is.
                    let variation = CGFloat.random(in: 0.8...1.25)
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    Enemy.glass(type.color).getRed(&r, green: &g, blue: &b, alpha: &a)
                    block.fillColor = UIColor(red: r * variation, green: g * variation, blue: b * variation, alpha: a)
                    block.strokeColor = Self.lightColor(for: type)
                    block.lineWidth = 1.2

                    let x = startX + CGFloat(col) * (blockSize + blockSpacing) + blockSize / 2
                    let y = startY + CGFloat(row) * (blockSize + blockSpacing) + blockSize / 2
                    block.position = CGPoint(x: x, y: y)

                    // Add subtle glow to each block
                    GlowHelper.addEnhancedGlow(to: block, color: Self.lightColor(for: type), intensity: 0.3)

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

        case .pulsatingRing:
            // Create ring that pulses
            let outerRadius = size.width / 2
            let innerRadius = outerRadius * 0.6

            let path = CGMutablePath()
            path.addArc(center: .zero, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            path.addArc(center: .zero, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)

            bodyNode = SKShapeNode(path: path)
            bodyNode.fillColor = type.color
            bodyNode.strokeColor = type.strokeColor
            bodyNode.lineWidth = 3.5

            // Add energy rings
            for radius in stride(from: innerRadius + 5, to: outerRadius - 5, by: 8) {
                let energyRing = SKShapeNode(circleOfRadius: radius)
                energyRing.strokeColor = type.strokeColor.withAlphaComponent(0.4)
                energyRing.fillColor = .clear
                energyRing.lineWidth = 1.5
                bodyNode.addChild(energyRing)
            }

        case .zigzagWall:
            // Vertical wall with zigzag edges
            let path = CGMutablePath()
            let zigzagCount = 8
            let height = size.height
            let width = size.width
            let zigzagWidth: CGFloat = 8

            path.move(to: CGPoint(x: -width/2, y: -height/2))

            // Left edge zigzag
            for i in 0...zigzagCount {
                let y = -height/2 + (height / CGFloat(zigzagCount)) * CGFloat(i)
                let x = -width/2 + (i % 2 == 0 ? 0 : -zigzagWidth)
                path.addLine(to: CGPoint(x: x, y: y))
            }

            // Top
            path.addLine(to: CGPoint(x: width/2, y: height/2))

            // Right edge zigzag
            for i in stride(from: zigzagCount, through: 0, by: -1) {
                let y = -height/2 + (height / CGFloat(zigzagCount)) * CGFloat(i)
                let x = width/2 + (i % 2 == 0 ? 0 : zigzagWidth)
                path.addLine(to: CGPoint(x: x, y: y))
            }

            path.closeSubpath()

            bodyNode = SKShapeNode(path: path)
            bodyNode.fillColor = type.color
            bodyNode.strokeColor = type.strokeColor
            bodyNode.lineWidth = 3

        case .spiralBlade:
            // Create spiral blade pattern
            let armCount = 3
            let armLength = size.height / 2
            let armWidth = size.width

            let path = CGMutablePath()

            for i in 0..<armCount {
                let angle = (CGFloat(i) * .pi * 2 / CGFloat(armCount))

                // Create curved blade arm
                let armPath = CGMutablePath()
                armPath.move(to: CGPoint(x: -armWidth/2, y: 0))

                // Curved blade shape
                let controlPoint1 = CGPoint(x: 0, y: armLength * 0.3)
                let controlPoint2 = CGPoint(x: armWidth/2, y: armLength * 0.6)
                let endPoint = CGPoint(x: 0, y: armLength)

                armPath.addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2)
                armPath.addLine(to: CGPoint(x: armWidth/2, y: 0))
                armPath.closeSubpath()

                var transform = CGAffineTransform(rotationAngle: angle)
                if let transformedPath = armPath.copy(using: &transform) {
                    path.addPath(transformedPath)
                }
            }

            bodyNode = SKShapeNode(path: path)
            bodyNode.fillColor = type.color
            bodyNode.strokeColor = type.strokeColor
            bodyNode.lineWidth = 3.5

            // Add center hub
            let hub = SKShapeNode(circleOfRadius: 12)
            hub.fillColor = type.strokeColor
            hub.strokeColor = type.color
            hub.lineWidth = 2
            bodyNode.addChild(hub)

        case .waveWall:
            // Wall with wavy edges
            let path = CGMutablePath()
            let waveCount = 6
            let height = size.height
            let width = size.width
            let amplitude: CGFloat = 6

            path.move(to: CGPoint(x: -width/2, y: -height/2))

            // Left wavy edge
            for i in 0...waveCount * 3 {
                let t = CGFloat(i) / CGFloat(waveCount * 3)
                let y = -height/2 + height * t
                let wave = sin(t * CGFloat.pi * CGFloat(waveCount)) * amplitude
                path.addLine(to: CGPoint(x: -width/2 + wave, y: y))
            }

            // Right wavy edge (reverse)
            for i in stride(from: waveCount * 3, through: 0, by: -1) {
                let t = CGFloat(i) / CGFloat(waveCount * 3)
                let y = -height/2 + height * t
                let wave = sin(t * CGFloat.pi * CGFloat(waveCount)) * amplitude
                path.addLine(to: CGPoint(x: width/2 + wave, y: y))
            }

            path.closeSubpath()

            bodyNode = SKShapeNode(path: path)
            bodyNode.fillColor = type.color
            bodyNode.strokeColor = type.strokeColor
            bodyNode.lineWidth = 3

        case .triangleBarrier:
            // Equilateral triangle
            let sideLength = size.width * 0.8
            let height = sideLength * sqrt(3) / 2

            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: height/2))
            path.addLine(to: CGPoint(x: -sideLength/2, y: -height/2))
            path.addLine(to: CGPoint(x: sideLength/2, y: -height/2))
            path.closeSubpath()

            bodyNode = SKShapeNode(path: path)
            bodyNode.fillColor = type.color
            bodyNode.strokeColor = type.strokeColor
            bodyNode.lineWidth = 4

            // Add inner triangles
            for scale in [0.7, 0.4] {
                let innerPath = CGMutablePath()
                innerPath.move(to: CGPoint(x: 0, y: height/2 * scale))
                innerPath.addLine(to: CGPoint(x: -sideLength/2 * scale, y: -height/2 * scale))
                innerPath.addLine(to: CGPoint(x: sideLength/2 * scale, y: -height/2 * scale))
                innerPath.closeSubpath()

                let innerTriangle = SKShapeNode(path: innerPath)
                innerTriangle.strokeColor = type.strokeColor.withAlphaComponent(0.5)
                innerTriangle.fillColor = .clear
                innerTriangle.lineWidth = 2
                bodyNode.addChild(innerTriangle)
            }

        case .hexagonTrap:
            // Regular hexagon
            let radius = size.width / 2
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

            bodyNode = SKShapeNode(path: path)
            bodyNode.fillColor = type.color
            bodyNode.strokeColor = type.strokeColor
            bodyNode.lineWidth = 4

            // Add inner hexagons
            for scale in [0.7, 0.4] {
                let innerPath = CGMutablePath()
                for i in 0..<6 {
                    let angle = CGFloat(i) * .pi / 3
                    let x = radius * scale * CGFloat(cos(angle))
                    let y = radius * scale * CGFloat(sin(angle))

                    if i == 0 {
                        innerPath.move(to: CGPoint(x: x, y: y))
                    } else {
                        innerPath.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                innerPath.closeSubpath()

                let innerHex = SKShapeNode(path: innerPath)
                innerHex.strokeColor = type.strokeColor.withAlphaComponent(0.5)
                innerHex.fillColor = .clear
                innerHex.lineWidth = 2
                bodyNode.addChild(innerHex)
            }
        }

        addChild(bodyNode)

        // Shared hard-light finish, so every obstacle reads as a constructed barrier
        // of light, the way the world around it is drawn.
        if type != .destructibleWall {
            applyHardLightFinish()
            GlowHelper.addEnhancedGlow(to: bodyNode, color: Self.lightColor(for: type), intensity: 0.5)
        }
    }

    /// A type's colour pushed to full brightness: the colour of its edges.
    static func lightColor(for type: ObstacleType) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        type.strokeColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let m = max(r, g, b, 0.01)
        // Pushed apart from grey as well as up, or the pale types all read as white.
        func lift(_ c: CGFloat) -> CGFloat { min(1, pow(c / m, 1.6)) }
        return UIColor(red: lift(r), green: lift(g), blue: lift(b), alpha: 1)
    }

    /// Dark glass inside a lit edge and a second, finer contour; slabs carry caution
    /// stripes in light and a running beacon.
    private func applyHardLightFinish() {
        let size = type.size
        let light = Self.lightColor(for: type)

        // Only glaze shapes that are actually filled; wireframe types (the ring)
        // stay open.
        if bodyNode.fillColor.cgColor.alpha > 0.05 {
            bodyNode.fillColor = Enemy.glass(type.color)
        }
        bodyNode.strokeColor = light
        bodyNode.lineWidth = min(bodyNode.lineWidth, 2.6)

        if let path = bodyNode.path {
            let box = path.boundingBoxOfPath
            if box.width > 12, box.height > 12 {
                var inset = CGAffineTransform(scaleX: (box.width - 8) / box.width, y: (box.height - 8) / box.height)
                if let inner = path.copy(using: &inset) {
                    let contour = SKShapeNode(path: inner)
                    contour.fillColor = .clear
                    contour.strokeColor = light.withAlphaComponent(0.4)
                    contour.lineWidth = 1
                    contour.blendMode = .add
                    contour.zPosition = 2
                    bodyNode.addChild(contour)
                }
            }
        }

        // Plain slab-shaped hazards get caution stripes and a running light;
        // the shaped types (spinner, blades, hexagons) already read as dangerous.
        switch type {
        case .wall, .movingWall, .horizontalWall, .zigzagWall:
            let stripes = SurfaceFX.hazardStripes(size: size, cornerRadius: 6, alpha: 0.42, stripeWidth: 3)
            (stripes as? SKSpriteNode)?.blendMode = .add
            stripes.alpha = 0.8
            bodyNode.addChild(stripes)

            let isVertical = size.height >= size.width
            let lightSize = isVertical
                ? CGSize(width: max(2.5, size.width * 0.22), height: size.height * 0.34)
                : CGSize(width: size.width * 0.34, height: max(2.5, size.height * 0.22))
            // Amber regardless of hull colour: a beacon should read as a warning,
            // and a pale hull stroke just looked like another highlight.
            bodyNode.addChild(SurfaceFX.warningLight(
                size: lightSize,
                color: UIColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 1.0)
            ))
        default:
            break
        }
    }

    private func setupPhysics() {
        // Skip physics setup for destructible wall - blocks have their own physics
        if type == .destructibleWall {
            return
        }

        let size = type.size

        switch type {
        case .wall, .horizontalWall, .movingWall, .rotatingBar, .zigzagWall, .waveWall:
            physicsBody = SKPhysicsBody(rectangleOf: size)

        case .spinner, .spiralBlade:
            // Cross/spiral shape - use two rectangles
            let verticalBody = SKPhysicsBody(rectangleOf: size)
            let horizontalBody = SKPhysicsBody(rectangleOf: CGSize(width: size.height, height: size.width))
            physicsBody = SKPhysicsBody(bodies: [verticalBody, horizontalBody])

        case .pulsatingRing:
            // Use circular physics for ring
            physicsBody = SKPhysicsBody(circleOfRadius: size.width / 2)

        case .triangleBarrier:
            // Triangle shape
            let sideLength = size.width * 0.8
            let height = sideLength * sqrt(3) / 2

            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: height/2))
            path.addLine(to: CGPoint(x: -sideLength/2, y: -height/2))
            path.addLine(to: CGPoint(x: sideLength/2, y: -height/2))
            path.closeSubpath()

            physicsBody = SKPhysicsBody(polygonFrom: path)

        case .hexagonTrap:
            // Hexagon shape
            let radius = size.width / 2
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

            physicsBody = SKPhysicsBody(polygonFrom: path)

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

        case .movingWall, .zigzagWall:
            // Move left-right while moving down
            startMovingDown()
            startHorizontalMovement()

        case .spinner:
            // Rotate continuously (faster than bar)
            let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: 2.0)
            let rotateForever = SKAction.repeatForever(rotateAction)
            run(rotateForever, withKey: "rotate")
            startMovingDown()

        case .pulsatingRing:
            // Pulse in and out
            startMovingDown()
            startPulsating()

        case .spiralBlade:
            // Rotate and slightly expand/contract
            let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: 2.5)
            let rotateForever = SKAction.repeatForever(rotateAction)
            run(rotateForever, withKey: "rotate")
            startMovingDown()
            startExpanding()

        case .waveWall:
            // Move in wave pattern
            startMovingDown()
            startWaveMovement()

        case .triangleBarrier:
            // Rotate slowly
            let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: 4.0)
            let rotateForever = SKAction.repeatForever(rotateAction)
            run(rotateForever, withKey: "rotate")
            startMovingDown()

        case .hexagonTrap:
            // Rotate and pulse
            let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: 3.5)
            let rotateForever = SKAction.repeatForever(rotateAction)
            run(rotateForever, withKey: "rotate")
            startMovingDown()
            startPulsating()
        }
    }

    private func startMovingDown() {
        // Move down the screen
        let moveDuration: TimeInterval = 8.0
        let moveAction = SKAction.moveBy(x: 0, y: -(sceneSize.height + 200), duration: moveDuration)

        // Cleanup all repeating actions before removal
        let cleanup = SKAction.run { [weak self] in
            self?.removeAction(forKey: "rotate")
            self?.removeAction(forKey: "horizontalMovement")
            self?.removeAction(forKey: "pulse")
            self?.removeAllActions()
        }
        let removeAction = SKAction.removeFromParent()
        let sequence = SKAction.sequence([moveAction, cleanup, removeAction])
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

    private func startPulsating() {
        // Scale up and down
        let scaleUp = SKAction.scale(to: 1.3, duration: 1.2)
        let scaleDown = SKAction.scale(to: 0.8, duration: 1.2)

        scaleUp.timingMode = .easeInEaseOut
        scaleDown.timingMode = .easeInEaseOut

        let sequence = SKAction.sequence([scaleUp, scaleDown])
        let forever = SKAction.repeatForever(sequence)
        bodyNode.run(forever, withKey: "pulse")
    }

    private func startExpanding() {
        // Slight expansion and contraction
        let expand = SKAction.scaleX(to: 1.15, duration: 1.0)
        let contract = SKAction.scaleX(to: 0.9, duration: 1.0)

        expand.timingMode = .easeInEaseOut
        contract.timingMode = .easeInEaseOut

        let sequence = SKAction.sequence([expand, contract])
        let forever = SKAction.repeatForever(sequence)
        bodyNode.run(forever, withKey: "expand")
    }

    private func startWaveMovement() {
        // Smooth sine wave movement
        let moveDistance: CGFloat = 120
        let moveDuration: TimeInterval = 2.5

        let moveRight = SKAction.moveBy(x: moveDistance, y: 0, duration: moveDuration)
        let moveLeft = SKAction.moveBy(x: -moveDistance, y: 0, duration: moveDuration)

        moveRight.timingMode = .easeInEaseOut
        moveLeft.timingMode = .easeInEaseOut

        let sequence = SKAction.sequence([moveRight, moveLeft])
        let forever = SKAction.repeatForever(sequence)
        run(forever, withKey: "waveMove")
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

        // Check if all blocks are destroyed. Destroyed blocks are removed from the
        // array above, so this is simply "nothing left" — the previous
        // allSatisfy { $0.parent == nil } was only ever vacuously true.
        if blocks.isEmpty {
            // Remove the entire obstacle after a short delay
            let wait = SKAction.wait(forDuration: 0.5)
            let removeObstacle = SKAction.removeFromParent()
            run(SKAction.sequence([wait, removeObstacle]))
        }

        return true
    }

    private func createBlockExplosion(at position: CGPoint, in parent: SKNode) {
        // The brick comes apart along its own edges, like everything else that breaks.
        let half = blockSize / 2
        let outline = CGPath(rect: CGRect(x: -half, y: -half, width: blockSize, height: blockSize), transform: nil)
        let pieces = ExplosionFX.shatter(path: outline, color: Self.lightColor(for: type), at: position)
        pieces.zPosition = 20
        parent.addChild(pieces)
        let flash = LightSprite.star(size: 36, color: Self.lightColor(for: type))
        flash.position = position
        flash.zPosition = 20
        parent.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 1.5, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
    }
}
