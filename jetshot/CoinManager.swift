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
        return formations.randomElement()!
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
        if let gameScene = scene as? GameScene {
            parentNode = gameScene.gameContentNode
        } else {
            parentNode = scene
        }

        for position in positions {
            let coin = Coin(position: position)
            parentNode.addChild(coin)
            totalCoinsSpawned += 1
        }
    }

    private func generateFormationPositions(formation: CoinFormation, sceneSize: CGSize) -> [CGPoint] {
        var positions: [CGPoint] = []

        // Random center x position (with margins)
        let centerX = CGFloat.random(in: 100...(sceneSize.width - 100))
        let y = sceneSize.height + 30
        let spacing: CGFloat = 50

        switch formation {
        case .line:
            // Horizontal line of 5-7 coins
            let count = Int.random(in: 5...7)
            let totalWidth = CGFloat(count - 1) * spacing
            let startX = max(60, min(sceneSize.width - 60, centerX - totalWidth / 2))
            for i in 0..<count {
                positions.append(CGPoint(x: startX + CGFloat(i) * spacing, y: y))
            }

        case .vShape:
            // V formation - 5 coins
            positions.append(CGPoint(x: centerX, y: y))
            positions.append(CGPoint(x: centerX - spacing, y: y + spacing))
            positions.append(CGPoint(x: centerX + spacing, y: y + spacing))
            positions.append(CGPoint(x: centerX - spacing * 2, y: y + spacing * 2))
            positions.append(CGPoint(x: centerX + spacing * 2, y: y + spacing * 2))

        case .circle:
            // Circle of 6-8 coins
            let count = Int.random(in: 6...8)
            let radius: CGFloat = 40
            for i in 0..<count {
                let angle = (CGFloat(i) / CGFloat(count)) * 2 * .pi
                let x = centerX + cos(angle) * radius
                let yPos = y + sin(angle) * radius
                positions.append(CGPoint(x: x, y: yPos))
            }

        case .wave:
            // Sine wave - 6 coins
            for i in 0..<6 {
                let x = centerX - spacing * 2.5 + CGFloat(i) * spacing
                let waveY = y + sin(CGFloat(i) * 0.8) * 30
                positions.append(CGPoint(x: x, y: waveY))
            }

        case .diagonal:
            // Diagonal line - 5 coins
            for i in 0..<5 {
                let x = centerX - spacing * 2 + CGFloat(i) * spacing
                let yPos = y + CGFloat(i) * spacing * 0.5
                positions.append(CGPoint(x: x, y: yPos))
            }

        case .cross:
            // Cross shape - 5 coins
            positions.append(CGPoint(x: centerX, y: y)) // center
            positions.append(CGPoint(x: centerX - spacing, y: y)) // left
            positions.append(CGPoint(x: centerX + spacing, y: y)) // right
            positions.append(CGPoint(x: centerX, y: y + spacing)) // top
            positions.append(CGPoint(x: centerX, y: y - spacing)) // bottom

        case .arrow:
            // Arrow pointing down - 7 coins
            positions.append(CGPoint(x: centerX, y: y)) // tip
            positions.append(CGPoint(x: centerX - spacing * 0.5, y: y + spacing))
            positions.append(CGPoint(x: centerX + spacing * 0.5, y: y + spacing))
            positions.append(CGPoint(x: centerX - spacing, y: y + spacing * 2))
            positions.append(CGPoint(x: centerX + spacing, y: y + spacing * 2))
            positions.append(CGPoint(x: centerX - spacing * 1.5, y: y + spacing * 3))
            positions.append(CGPoint(x: centerX + spacing * 1.5, y: y + spacing * 3))

        case .zigzag:
            // Zigzag - 6 coins
            for i in 0..<6 {
                let x = centerX - spacing * 2.5 + CGFloat(i) * spacing
                let offset: CGFloat = i % 2 == 0 ? 0 : spacing * 0.7
                positions.append(CGPoint(x: x, y: y + offset))
            }
        }

        return positions
    }

    private func spawnCoin(in scene: SKScene) {
        // Random x position
        let x = CGFloat.random(in: 60...(scene.size.width - 60))

        // Spawn at top of screen
        let y = scene.size.height + 30

        let coin = Coin(position: CGPoint(x: x, y: y))

        // Get GameScene to access gameContentNode
        let parentNode: SKNode
        if let gameScene = scene as? GameScene {
            parentNode = gameScene.gameContentNode
        } else {
            parentNode = scene
        }

        parentNode.addChild(coin)
        totalCoinsSpawned += 1
    }

    func setBossFight(_ active: Bool) {
        isBossFight = active
    }

    func reset() {
        lastSpawnTime = 0
        nextSpawnDelay = spawnConfig.spawnInterval
        totalCoinsSpawned = 0
        isBossFight = false
        targetCoinsForLevel = Int.random(in: spawnConfig.minCoins...spawnConfig.maxCoins)
    }

    // Get total coins that spawned in this level
    func getTotalCoinsForLevel() -> Int {
        return totalCoinsSpawned
    }
}
