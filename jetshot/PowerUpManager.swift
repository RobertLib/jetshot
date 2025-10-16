//
//  PowerUpManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 25.10.2025.
//

import SpriteKit

struct PowerUpSpawnConfig {
    let spawnInterval: TimeInterval    // Time between powerup spawns
    let spawnProbability: Double       // Probability of spawning (0.0 - 1.0)
    let typeWeights: [PowerUpType: Double]  // Weight for each powerup type
}

class PowerUpManager {
    private weak var scene: SKScene?
    private var spawnConfig: PowerUpSpawnConfig
    private var lastSpawnTime: TimeInterval = 0
    private var nextSpawnDelay: TimeInterval = 0
    private var isPaused: Bool = false

    init(scene: SKScene, config: PowerUpSpawnConfig) {
        self.scene = scene
        self.spawnConfig = config
        self.nextSpawnDelay = config.spawnInterval
    }

    func update(currentTime: TimeInterval) {
        guard !isPaused, let scene = scene else { return }

        // Initialize last spawn time on first update
        if lastSpawnTime == 0 {
            lastSpawnTime = currentTime
            return
        }

        // Check if it's time to spawn a powerup
        let timeSinceLastSpawn = currentTime - lastSpawnTime
        if timeSinceLastSpawn >= nextSpawnDelay {
            // Randomly decide if we should spawn based on probability
            if Double.random(in: 0...1) <= spawnConfig.spawnProbability {
                spawnRandomPowerUp(in: scene)
            }

            // Reset timer with some randomness
            lastSpawnTime = currentTime
            nextSpawnDelay = spawnConfig.spawnInterval * Double.random(in: 0.8...1.2)
        }
    }

    private func spawnRandomPowerUp(in scene: SKScene) {
        // Select random powerup type based on weights
        let powerUpType = selectWeightedPowerUpType()

        // Random x position
        let x = CGFloat.random(in: 50...(scene.size.width - 50))

        // Spawn at top of screen
        let y = scene.size.height + 30

        let powerUp = PowerUp(type: powerUpType, position: CGPoint(x: x, y: y))
        scene.addChild(powerUp)
    }

    private func selectWeightedPowerUpType() -> PowerUpType {
        // Calculate total weight
        let totalWeight = spawnConfig.typeWeights.values.reduce(0, +)

        // Generate random number
        let random = Double.random(in: 0...totalWeight)

        // Select type based on cumulative weights
        var cumulativeWeight: Double = 0
        for (type, weight) in spawnConfig.typeWeights {
            cumulativeWeight += weight
            if random <= cumulativeWeight {
                return type
            }
        }

        // Fallback (should never reach here)
        return .multiShot
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func reset() {
        lastSpawnTime = 0
        nextSpawnDelay = spawnConfig.spawnInterval
    }
}
