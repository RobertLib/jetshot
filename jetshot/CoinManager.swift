//
//  CoinManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 01.11.2025.
//

import SpriteKit

enum CoinFormation {
    case line           // Horizontal line
    case vShape         // V formation
    case circle         // Circle
    case wave           // Sine wave
    case diagonal       // Diagonal line
    case cross          // Cross/plus shape
    case arrow          // Arrow pointing down
    case zigzag         // Zigzag pattern

    static func random() -> CoinFormation {
        let formations: [CoinFormation] = [.line, .vShape, .circle, .wave, .diagonal, .cross, .arrow, .zigzag]
        return formations.randomElement() ?? .line
    }
}

struct CoinSpawnConfig {
    let spawnInterval: TimeInterval    // Time between coin spawns
    let spawnProbability: Double       // Probability of spawning (0.0 - 1.0)
    let minCoins: Int                  // Minimum coins to spawn in a level
    let maxCoins: Int                  // Maximum coins to spawn in a level
}

class CoinManager {
    private weak var scene: SKScene?
    private var spawnConfig: CoinSpawnConfig
    private var lastSpawnTime: TimeInterval = 0
    private var nextSpawnDelay: TimeInterval = 0
    private var isBossFight: Bool = false
    private(set) var totalCoinsSpawned: Int = 0
    private var targetCoinsForLevel: Int = 0

    init(scene: SKScene, config: CoinSpawnConfig) {
        self.scene = scene
        self.spawnConfig = config

        // Determine how many coins should spawn this level
        self.targetCoinsForLevel = Int.random(in: config.minCoins...config.maxCoins)
        self.nextSpawnDelay = config.spawnInterval
    }

    func update(currentTime: TimeInterval) {
        guard let scene = scene else { return }

        // Stop spawning during boss fight or if we've reached the target
        if isBossFight || totalCoinsSpawned >= targetCoinsForLevel {
            return
        }

        // Initialize last spawn time on first update
        if lastSpawnTime == 0 {
            lastSpawnTime = currentTime
            return
        }

        // Check if it's time to spawn a coin
        let timeSinceLastSpawn = currentTime - lastSpawnTime
        if timeSinceLastSpawn >= nextSpawnDelay {
            // Randomly decide if we should spawn based on probability
            if Double.random(in: 0...1) <= spawnConfig.spawnProbability {
                spawnCoinFormation(in: scene)
            }

            // Reset timer with some randomness
            lastSpawnTime = currentTime
            nextSpawnDelay = spawnConfig.spawnInterval * Double.random(in: 0.7...1.3)
        }
    }

    private func spawnCoinFormation(in scene: SKScene) {
        let formation = CoinFormation.random()
        let positions = generateFormationPositions(formation: formation, sceneSize: scene.size)

        // Get GameScene to access gameContentNode
        let parentNode: SKNode
        let gameScene: GameScene?
        if let gs = scene as? GameScene {
            parentNode = gs.gameContentNode
            gameScene = gs
        } else {
            parentNode = scene
            gameScene = nil
        }

        for position in positions {
            let coin = Coin(position: position)
            parentNode.addChild(coin)

            // Register coin in cache for optimized magnet updates
            gameScene?.registerCoin(coin)

            totalCoinsSpawned += 1
        }
    }

    /// Builds a coin formation, laid out around x = 0 and then placed so that every coin
    /// is reachable.
    ///
    /// The layout below is deliberately relative. Picking an absolute centre up front
    /// (the previous approach: `centerX = random(100 ... width - 100)`) ignored how wide
    /// each shape actually is, so the wider ones put coins past the screen edge — a
    /// `.wave` or `.zigzag` spans ±125pt, which on a 375pt phone reaches x = -25 or
    /// x = 400. Coins fall straight down at a fixed x, so those were unreachable, and
    /// because they still counted towards the level's coin total they quietly cost the
    /// player stars. Only `.line` clamped itself.
    func generateFormationPositions(formation: CoinFormation, sceneSize: CGSize) -> [CGPoint] {
        var positions: [CGPoint] = []

        let spacing: CGFloat = 50
        let y: CGFloat = 0

        switch formation {
        case .line:
            // Horizontal line of 5-7 coins
            let count = Int.random(in: 5...7)
            let totalWidth = CGFloat(count - 1) * spacing
            for i in 0..<count {
                positions.append(CGPoint(x: -totalWidth / 2 + CGFloat(i) * spacing, y: y))
            }

        case .vShape:
            // V formation - 5 coins
            positions.append(CGPoint(x: 0, y: y))
            positions.append(CGPoint(x: -spacing, y: y + spacing))
            positions.append(CGPoint(x: spacing, y: y + spacing))
            positions.append(CGPoint(x: -spacing * 2, y: y + spacing * 2))
            positions.append(CGPoint(x: spacing * 2, y: y + spacing * 2))

        case .circle:
            // Circle of 6-8 coins
            let count = Int.random(in: 6...8)
            let radius: CGFloat = 40
            for i in 0..<count {
                let angle = (CGFloat(i) / CGFloat(count)) * 2 * .pi
                positions.append(CGPoint(x: cos(angle) * radius, y: y + sin(angle) * radius))
            }

        case .wave:
            // Sine wave - 6 coins
            for i in 0..<6 {
                let x = -spacing * 2.5 + CGFloat(i) * spacing
                positions.append(CGPoint(x: x, y: y + sin(CGFloat(i) * 0.8) * 30))
            }

        case .diagonal:
            // Diagonal line - 5 coins
            for i in 0..<5 {
                let x = -spacing * 2 + CGFloat(i) * spacing
                positions.append(CGPoint(x: x, y: y + CGFloat(i) * spacing * 0.5))
            }

        case .cross:
            // Cross shape - 5 coins
            positions.append(CGPoint(x: 0, y: y)) // center
            positions.append(CGPoint(x: -spacing, y: y)) // left
            positions.append(CGPoint(x: spacing, y: y)) // right
            positions.append(CGPoint(x: 0, y: y + spacing)) // top
            positions.append(CGPoint(x: 0, y: y - spacing)) // bottom

        case .arrow:
            // Arrow pointing down - 7 coins
            positions.append(CGPoint(x: 0, y: y)) // tip
            positions.append(CGPoint(x: -spacing * 0.5, y: y + spacing))
            positions.append(CGPoint(x: spacing * 0.5, y: y + spacing))
            positions.append(CGPoint(x: -spacing, y: y + spacing * 2))
            positions.append(CGPoint(x: spacing, y: y + spacing * 2))
            positions.append(CGPoint(x: -spacing * 1.5, y: y + spacing * 3))
            positions.append(CGPoint(x: spacing * 1.5, y: y + spacing * 3))

        case .zigzag:
            // Zigzag - 6 coins
            for i in 0..<6 {
                let x = -spacing * 2.5 + CGFloat(i) * spacing
                let offset: CGFloat = i % 2 == 0 ? 0 : spacing * 0.7
                positions.append(CGPoint(x: x, y: y + offset))
            }
        }

        return Self.place(positions, in: sceneSize)
    }

    /// Slides a relative formation to a random horizontal position that keeps all of it
    /// on screen, and lifts it above the top edge so nothing pops into view mid-fall.
    static func place(_ positions: [CGPoint], in sceneSize: CGSize) -> [CGPoint] {
        guard let minX = positions.map(\.x).min(),
              let maxX = positions.map(\.x).max(),
              let minY = positions.map(\.y).min() else { return positions }

        // Half a coin plus a little breathing room, so the sprite is fully inside.
        let margin: CGFloat = 30

        let lowerBound = margin - minX
        let upperBound = sceneSize.width - margin - maxX
        let offsetX: CGFloat = lowerBound <= upperBound
            ? CGFloat.random(in: lowerBound...upperBound)
            : (sceneSize.width - minX - maxX) / 2 // Wider than the screen: centre it.

        // `.cross` reaches below its own origin, which used to spawn its bottom coin
        // already on screen.
        let offsetY = sceneSize.height + 30 - minY

        return positions.map { CGPoint(x: $0.x + offsetX, y: $0.y + offsetY) }
    }

    func setBossFight(_ active: Bool) {
        isBossFight = active
    }

    // Get total coins that spawned in this level
    func getTotalCoinsForLevel() -> Int {
        return totalCoinsSpawned
    }
}
