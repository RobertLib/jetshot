//
//  ParallaxBackgroundHelper.swift
//  jetshot
//
//  Created by Robert Libšanský on 17.01.2026.
//

import SpriteKit

/// Parallax background types
enum ParallaxBackgroundType {
    case grid           // Grid pattern
    case shipPanels     // Spaceship panels
    case techPlates     // Technical plates with details
    case circuitBoard   // Electronic circuits
}

/// Background segment definition
struct BackgroundSegment {
    let startDelay: TimeInterval  // When to spawn (seconds from level start)
    let duration: TimeInterval     // How long it lasts
    let type: ParallaxBackgroundType
}

/// Helper for creating different types of parallax backgrounds
class ParallaxBackgroundHelper {

    private static var activeSegments: [SKNode] = []
    private static var scheduledTimers: [Timer] = []
    private static var prerenderedTextures: [String: SKTexture] = [:]

    /// Adds parallax background segments to scene based on level
    static func addParallaxBackground(to scene: SKScene, parentNode: SKNode, levelNumber: Int) {
        // Clear any existing segments
        removeParallaxBackground(from: parentNode)
        activeSegments.removeAll()
        scheduledTimers.forEach { $0.invalidate() }
        scheduledTimers.removeAll()

        // Get segments for this level (deterministic)
        let segments = getBackgroundSegments(for: levelNumber)

        // Pre-render textures asynchronously in background
        DispatchQueue.global(qos: .userInitiated).async {
            for segment in segments {
                let cacheKey = "\(levelNumber)_\(segment.type)_\(Int(Date().timeIntervalSince1970))"
                if prerenderedTextures[cacheKey] == nil {
                    // Pre-render texture in background thread
                    var generator = SeededRandomGenerator(seed: UInt64(levelNumber * 1000 + Int(segment.startDelay)))
                    let tempNode = SKNode()
                    let tileSize = CGSize(width: scene.size.width, height: 512)

                    switch segment.type {
                    case .grid:
                        addGridPattern(to: tempNode, size: tileSize, generator: &generator)
                    case .shipPanels:
                        addShipPanels(to: tempNode, size: tileSize, generator: &generator)
                    case .techPlates:
                        addTechPlates(to: tempNode, size: tileSize, generator: &generator)
                    case .circuitBoard:
                        addCircuitBoard(to: tempNode, size: tileSize, generator: &generator)
                    }

                    let texture = renderNodeToTexture(node: tempNode, size: tileSize)

                    DispatchQueue.main.async {
                        prerenderedTextures[cacheKey] = texture
                    }
                }
            }
        }

        // Schedule each segment
        for segment in segments {
            let timer = Timer.scheduledTimer(withTimeInterval: segment.startDelay, repeats: false) { _ in
                let segmentNode = createBackgroundSegment(type: segment.type, scene: scene, parentNode: parentNode, levelNumber: levelNumber)
                activeSegments.append(segmentNode)

                // Schedule removal after duration
                Timer.scheduledTimer(withTimeInterval: segment.duration, repeats: false) { _ in
                    fadeOutAndRemove(node: segmentNode)
                    activeSegments.removeAll { $0 == segmentNode }
                }
            }
            scheduledTimers.append(timer)
        }
    }

    /// Get background segments for a specific level (deterministic)
    private static func getBackgroundSegments(for level: Int) -> [BackgroundSegment] {
        // Use level number as seed for deterministic randomness
        var generator = SeededRandomGenerator(seed: UInt64(level))

        // Determine if level has background (every 2nd level has it)
        let hasBackground = level % 2 == 0
        guard hasBackground else { return [] }

        // Select background type based on level
        let backgroundTypes: [ParallaxBackgroundType] = [.grid, .shipPanels, .techPlates, .circuitBoard]
        let typeIndex = (level / 2) % backgroundTypes.count
        let backgroundType = backgroundTypes[typeIndex]

        // Create 2-4 segments throughout the level
        var segments: [BackgroundSegment] = []
        let segmentCount = generator.next(min: 2, max: 4)

        for i in 0..<segmentCount {
            let startDelay = TimeInterval(5 + i * 15 + generator.next(min: 0, max: 10))
            let duration = TimeInterval(generator.next(min: 8, max: 20))

            segments.append(BackgroundSegment(
                startDelay: startDelay,
                duration: duration,
                type: backgroundType
            ))
        }

        return segments
    }

    /// Creates a background segment with parallax layers
    private static func createBackgroundSegment(type: ParallaxBackgroundType, scene: SKScene, parentNode: SKNode, levelNumber: Int) -> SKNode {
        let segmentContainer = SKNode()
        segmentContainer.name = "backgroundSegment"
        segmentContainer.alpha = 0

        var generator = SeededRandomGenerator(seed: UInt64(levelNumber * 1000 + Int(Date().timeIntervalSince1970)))

        // Create 2-3 layers with different speeds for parallax effect
        let layerSpeeds: [CGFloat] = [20, 35, 50]
        let layerAlphas: [CGFloat] = [0.12, 0.18, 0.25]

        // Create or get cached texture ONCE for all tiles
        let tileHeight: CGFloat = 512
        let tileSize = CGSize(width: scene.size.width, height: tileHeight)
        let cacheKey = "\(type)_\(Int(scene.size.width))_\(Int(tileHeight))"

        let sharedTexture: SKTexture
        if let cachedTexture = prerenderedTextures[cacheKey] {
            sharedTexture = cachedTexture
        } else {
            // Create texture only once
            sharedTexture = createBackgroundTexture(type: type, size: tileSize, generator: &generator)
            prerenderedTextures[cacheKey] = sharedTexture
        }

        for (index, speed) in layerSpeeds.enumerated() {
            let layerNode = SKNode()
            layerNode.name = "parallaxLayer_\(index)"
            layerNode.zPosition = -15 + CGFloat(index) * 0.5

            // Create tiles for continuous scrolling - reuse same texture
            // We need tiles both vertically and horizontally to cover the entire screen
            let tilesNeededVertical = Int(ceil(scene.size.height / tileHeight)) + 2
            let tilesNeededHorizontal = Int(ceil(scene.size.width / tileSize.width)) + 2

            for i in 0..<tilesNeededVertical {
                for j in 0..<tilesNeededHorizontal {
                    // Create sprite directly from cached texture
                    let tile = SKSpriteNode(texture: sharedTexture)
                    tile.size = tileSize
                    tile.position = CGPoint(
                        x: CGFloat(j) * tileSize.width,
                        y: CGFloat(i) * tileHeight
                    )
                    tile.alpha = layerAlphas[index]
                    tile.name = "tile_\(i)_\(j)"
                    layerNode.addChild(tile)
                }
            }

            segmentContainer.addChild(layerNode)

            // Animate scrolling
            animateParallaxLayer(layerNode, speed: speed, tileHeight: tileHeight, scene: scene)
        }

        parentNode.addChild(segmentContainer)

        // Fade in
        segmentContainer.run(SKAction.fadeIn(withDuration: 2.0))

        return segmentContainer
    }

    /// Fade out and remove segment
    private static func fadeOutAndRemove(node: SKNode) {
        node.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 2.0),
            SKAction.removeFromParent()
        ]))
    }

    /// Creates background texture based on type (called once per type and cached)
    private static func createBackgroundTexture(type: ParallaxBackgroundType, size: CGSize, generator: inout SeededRandomGenerator) -> SKTexture {
        // Create a temporary node to draw into
        let tempNode = SKNode()

        switch type {
        case .grid:
            addGridPattern(to: tempNode, size: size, generator: &generator)
        case .shipPanels:
            addShipPanels(to: tempNode, size: size, generator: &generator)
        case .techPlates:
            addTechPlates(to: tempNode, size: size, generator: &generator)
        case .circuitBoard:
            addCircuitBoard(to: tempNode, size: size, generator: &generator)
        }

        // Render to texture using Core Graphics
        return renderNodeToTexture(node: tempNode, size: size)
    }

    /// Renders a node hierarchy into a single texture using Core Graphics
    private static func renderNodeToTexture(node: SKNode, size: CGSize) -> SKTexture {
        // Use standard retina scale (2.0 for most devices, 3.0 for plus/pro models)
        let scale: CGFloat = 2.0

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return SKTexture()
        }

        // Clear background
        context.clear(CGRect(origin: .zero, size: size))

        // Render node hierarchy manually
        renderNode(node, in: context, offset: CGPoint(x: size.width / 2, y: size.height / 2))

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = image?.cgImage else {
            return SKTexture()
        }

        return SKTexture(cgImage: cgImage)
    }

    /// Recursively renders a node and its children to a Core Graphics context
    private static func renderNode(_ node: SKNode, in context: CGContext, offset: CGPoint) {
        context.saveGState()

        let position = CGPoint(x: offset.x + node.position.x, y: offset.y + node.position.y)

        // Handle SKShapeNode rendering
        if let shapeNode = node as? SKShapeNode {
            context.translateBy(x: position.x, y: position.y)
            context.rotate(by: node.zRotation)

            // Apply alpha
            context.setAlpha(node.alpha)

            // Set blend mode (SKShapeNode has blendMode property)
            if let shapeNode = node as? SKShapeNode {
                switch shapeNode.blendMode {
                case .add:
                    context.setBlendMode(.plusLighter)
                case .alpha:
                    context.setBlendMode(.normal)
                default:
                    context.setBlendMode(.normal)
                }
            } else {
                context.setBlendMode(.normal)
            }

            // Draw the shape
            if let path = shapeNode.path {
                // Fill
                if shapeNode.fillColor != .clear {
                    context.setFillColor(shapeNode.fillColor.cgColor)
                    context.addPath(path)
                    context.fillPath()
                }

                // Stroke
                if shapeNode.strokeColor != .clear && shapeNode.lineWidth > 0 {
                    context.setStrokeColor(shapeNode.strokeColor.cgColor)
                    context.setLineWidth(shapeNode.lineWidth)
                    context.addPath(path)
                    context.strokePath()
                }
            }
        }

        context.restoreGState()

        // Render children
        for child in node.children {
            renderNode(child, in: context, offset: position)
        }
    }

    // MARK: - Grid Pattern

    private static func addGridPattern(to node: SKNode, size: CGSize, generator: inout SeededRandomGenerator) {
        let gridSpacing: CGFloat = 60
        let lineWidth: CGFloat = 1.5

        // Vertical lines
        let verticalCount = Int(size.width / gridSpacing) + 1
        for i in 0..<verticalCount {
            let x = CGFloat(i) * gridSpacing - size.width / 2
            let line = SKShapeNode(rectOf: CGSize(width: lineWidth, height: size.height))
            line.position = CGPoint(x: x, y: 0)
            line.fillColor = UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)
            line.strokeColor = .clear
            line.blendMode = .add
            node.addChild(line)
        }

        // Horizontal lines
        let horizontalCount = Int(size.height / gridSpacing) + 1
        for i in 0..<horizontalCount {
            let y = CGFloat(i) * gridSpacing - size.height / 2
            let line = SKShapeNode(rectOf: CGSize(width: size.width, height: lineWidth))
            line.position = CGPoint(x: 0, y: y)
            line.fillColor = UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)
            line.strokeColor = .clear
            line.blendMode = .add
            node.addChild(line)

            // Occasionally add dots at intersections
            if i % 2 == 0 {
                for j in 0..<verticalCount where j % 2 == 0 {
                    let x = CGFloat(j) * gridSpacing - size.width / 2
                    let dot = SKShapeNode(circleOfRadius: 2)
                    dot.position = CGPoint(x: x, y: y)
                    dot.fillColor = UIColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1.0)
                    dot.strokeColor = .clear
                    dot.blendMode = .add
                    node.addChild(dot)
                }
            }
        }
    }

    // MARK: - Ship Panels

    private static func addShipPanels(to node: SKNode, size: CGSize, generator: inout SeededRandomGenerator) {
        let panelWidth: CGFloat = size.width / 3
        let panelHeight: CGFloat = 200

        // Create panels in multiple rows
        let rows = Int(size.height / panelHeight) + 1

        for row in 0..<rows {
            for col in 0..<3 {
                // Randomly skip some panels (create holes)
                if generator.nextDouble() < 0.4 { continue }

                let panel = createShipPanel(size: CGSize(width: panelWidth - 4, height: panelHeight - 4), generator: &generator)
                panel.position = CGPoint(
                    x: CGFloat(col) * panelWidth - size.width / 2 + panelWidth / 2,
                    y: CGFloat(row) * panelHeight - size.height / 2 + panelHeight / 2
                )
                node.addChild(panel)
            }
        }
    }

    private static func createShipPanel(size: CGSize, generator: inout SeededRandomGenerator) -> SKNode {
        let panel = SKNode()

        // Main panel
        let rect = SKShapeNode(rectOf: size, cornerRadius: 8)
        rect.fillColor = UIColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 1.0)
        rect.strokeColor = UIColor(red: 0.25, green: 0.35, blue: 0.5, alpha: 1.0)
        rect.lineWidth = 2
        rect.blendMode = .alpha
        panel.addChild(rect)

        // Add details - horizontal stripes
        for i in 0..<3 {
            let stripe = SKShapeNode(rectOf: CGSize(width: size.width - 20, height: 2))
            stripe.position = CGPoint(x: 0, y: CGFloat(i - 1) * 30)
            stripe.fillColor = UIColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 1.0)
            stripe.strokeColor = .clear
            stripe.blendMode = .add
            panel.addChild(stripe)
        }

        // Add corners
        for xOffset in [-size.width/2 + 10, size.width/2 - 10] {
            for yOffset in [-size.height/2 + 10, size.height/2 - 10] {
                let corner = SKShapeNode(rectOf: CGSize(width: 8, height: 8))
                corner.position = CGPoint(x: xOffset, y: yOffset)
                corner.fillColor = UIColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1.0)
                corner.strokeColor = .clear
                corner.blendMode = .add
                panel.addChild(corner)
            }
        }

        return panel
    }

    // MARK: - Tech Plates

    private static func addTechPlates(to node: SKNode, size: CGSize, generator: inout SeededRandomGenerator) {
        let plateSize: CGFloat = 150

        let cols = Int(size.width / plateSize) + 1
        let rows = Int(size.height / plateSize) + 1

        for row in 0..<rows {
            for col in 0..<cols {
                // Randomly skip some plates (create holes)
                if generator.nextDouble() < 0.35 { continue }

                let plate = createTechPlate(size: plateSize, generator: &generator)
                plate.position = CGPoint(
                    x: CGFloat(col) * plateSize - size.width / 2 + plateSize / 2,
                    y: CGFloat(row) * plateSize - size.height / 2 + plateSize / 2
                )
                node.addChild(plate)
            }
        }
    }

    private static func createTechPlate(size: CGFloat, generator: inout SeededRandomGenerator) -> SKNode {
        let plate = SKNode()

        // Hexagonal or square plate
        let isHex = generator.nextBool()

        if isHex {
            // Hexagon
            let hexPath = createHexagonPath(size: size * 0.8)
            let hex = SKShapeNode(path: hexPath)
            hex.fillColor = UIColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 1.0)
            hex.strokeColor = UIColor(red: 0.25, green: 0.35, blue: 0.45, alpha: 1.0)
            hex.lineWidth = 1.5
            hex.blendMode = .alpha
            plate.addChild(hex)
        } else {
            // Square
            let square = SKShapeNode(rectOf: CGSize(width: size * 0.9, height: size * 0.9), cornerRadius: 6)
            square.fillColor = UIColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 1.0)
            square.strokeColor = UIColor(red: 0.25, green: 0.35, blue: 0.45, alpha: 1.0)
            square.lineWidth = 1.5
            square.blendMode = .alpha
            plate.addChild(square)
        }

        // Add central point or detail
        if generator.nextDouble() < 0.5 {
            let center = SKShapeNode(circleOfRadius: 4)
            center.fillColor = UIColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1.0)
            center.strokeColor = .clear
            center.blendMode = .add
            plate.addChild(center)
        }

        return plate
    }

    private static func createHexagonPath(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let radius = size / 2

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

    // MARK: - Circuit Board

    private static func addCircuitBoard(to node: SKNode, size: CGSize, generator: inout SeededRandomGenerator) {
        // Create random circuits
        let circuitCount = generator.next(min: 15, max: 25)

        for _ in 0..<circuitCount {
            let startX = generator.nextDouble(min: -size.width/2, max: size.width/2)
            let startY = generator.nextDouble(min: -size.height/2, max: size.height/2)

            let circuit = createCircuitPath(from: CGPoint(x: startX, y: startY), maxLength: 150, generator: &generator)
            node.addChild(circuit)
        }

        // Add chips/components
        let componentCount = generator.next(min: 8, max: 15)
        for _ in 0..<componentCount {
            let component = createCircuitComponent(generator: &generator)
            component.position = CGPoint(
                x: generator.nextDouble(min: -size.width/2, max: size.width/2),
                y: generator.nextDouble(min: -size.height/2, max: size.height/2)
            )
            node.addChild(component)
        }
    }

    private static func createCircuitPath(from start: CGPoint, maxLength: CGFloat, generator: inout SeededRandomGenerator) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: start)

        var current = start
        var remainingLength = maxLength

        // Create random path with right-angle movements
        while remainingLength > 0 {
            let segmentLength = generator.nextDouble(min: 20, max: 50)
            let isHorizontal = generator.nextBool()

            let next: CGPoint
            if isHorizontal {
                next = CGPoint(x: current.x + (generator.nextBool() ? segmentLength : -segmentLength), y: current.y)
            } else {
                next = CGPoint(x: current.x, y: current.y + (generator.nextBool() ? segmentLength : -segmentLength))
            }

            path.addLine(to: next)
            current = next
            remainingLength -= segmentLength
        }

        let circuit = SKShapeNode(path: path)
        circuit.strokeColor = UIColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1.0)
        circuit.lineWidth = 1.5
        circuit.blendMode = .add

        // Occasionally add blinking
        if generator.nextDouble() < 0.3 {
            let pulse = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.3, duration: 1.0),
                SKAction.fadeAlpha(to: 1.0, duration: 1.0)
            ])
            circuit.run(SKAction.repeatForever(pulse))
        }

        return circuit
    }

    private static func createCircuitComponent(generator: inout SeededRandomGenerator) -> SKNode {
        let component = SKNode()

        let componentTypes = ["square", "rect", "circle"]
        let type = componentTypes[generator.next(min: 0, max: 2)]

        let shape: SKShapeNode
        switch type {
        case "square":
            shape = SKShapeNode(rectOf: CGSize(width: 12, height: 12))
        case "rect":
            shape = SKShapeNode(rectOf: CGSize(width: 20, height: 10))
        case "circle":
            shape = SKShapeNode(circleOfRadius: 6)
        default:
            shape = SKShapeNode(rectOf: CGSize(width: 12, height: 12))
        }

        shape.fillColor = UIColor(red: 0.15, green: 0.2, blue: 0.25, alpha: 1.0)
        shape.strokeColor = UIColor(red: 0.3, green: 0.5, blue: 0.4, alpha: 1.0)
        shape.lineWidth = 1.5
        shape.blendMode = .alpha
        component.addChild(shape)

        // Add pins
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            let pin = SKShapeNode(rectOf: CGSize(width: 2, height: 6))
            pin.position = CGPoint(x: cos(angle) * 10, y: sin(angle) * 10)
            pin.zRotation = angle
            pin.fillColor = UIColor(red: 0.4, green: 0.6, blue: 0.5, alpha: 1.0)
            pin.strokeColor = .clear
            pin.blendMode = .add
            component.addChild(pin)
        }

        return component
    }

    // MARK: - Animation

    private static func animateParallaxLayer(_ layer: SKNode, speed: CGFloat, tileHeight: CGFloat, scene: SKScene) {
        let moveDown = SKAction.moveBy(x: 0, y: -tileHeight, duration: TimeInterval(tileHeight / speed))

        let resetPosition = SKAction.run {
            // When tile moves by its height, reset position
            for tile in layer.children {
                if tile.position.y < -tileHeight {
                    tile.position.y += tileHeight * CGFloat(layer.children.count)
                }
            }
        }

        let sequence = SKAction.sequence([moveDown, resetPosition])
        layer.run(SKAction.repeatForever(sequence))
    }

    /// Removes parallax background from scene
    static func removeParallaxBackground(from parentNode: SKNode) {
        scheduledTimers.forEach { $0.invalidate() }
        scheduledTimers.removeAll()
        activeSegments.forEach { $0.removeFromParent() }
        activeSegments.removeAll()
        parentNode.children.filter { $0.name == "backgroundSegment" }.forEach { $0.removeFromParent() }
    }
}

// MARK: - Seeded Random Generator

/// Deterministic random number generator using a seed
struct SeededRandomGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // Linear congruential generator
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func next(min: Int, max: Int) -> Int {
        let range = UInt64(max - min + 1)
        return Int(next() % range) + min
    }

    mutating func nextDouble() -> Double {
        return Double(next()) / Double(UInt64.max)
    }

    mutating func nextDouble(min: CGFloat, max: CGFloat) -> CGFloat {
        return CGFloat(nextDouble()) * (max - min) + min
    }

    mutating func nextBool() -> Bool {
        return next() % 2 == 0
    }
}
