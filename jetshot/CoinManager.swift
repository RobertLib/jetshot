//
//  CoinManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 01.11.2025.
//

import SpriteKit

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
                spawnCoin(in: scene)
            }

            // Reset timer with some randomness
            lastSpawnTime = currentTime
            nextSpawnDelay = spawnConfig.spawnInterval * Double.random(in: 0.7...1.3)
        }
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
