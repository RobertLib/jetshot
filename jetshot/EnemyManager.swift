//
//  EnemyManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import SpriteKit

// Wave configuration for a level
struct EnemyWave {
    let enemies: [EnemyType]
    let spawnDelay: TimeInterval // Delay before starting this wave
    let spawnInterval: TimeInterval // Time between individual enemy spawns
    let isFormation: Bool // Whether this is a formation wave
    let formationPattern: FormationPattern? // Pattern for formation

    init(enemies: [EnemyType],
         spawnDelay: TimeInterval,
         spawnInterval: TimeInterval,
         isFormation: Bool = false,
         formationPattern: FormationPattern? = nil) {
        self.enemies = enemies
        self.spawnDelay = spawnDelay
        self.spawnInterval = spawnInterval
        self.isFormation = isFormation
        self.formationPattern = formationPattern
    }
}

class EnemyManager {

    private weak var scene: SKScene?

    // Wave system
    private var waves: [EnemyWave] = []
    private var currentWaveIndex: Int = 0
    private var enemiesSpawnedInWave: Int = 0
    private var lastSpawnTime: TimeInterval = 0
    private var waveStartTime: TimeInterval = 0
    private var hasStarted: Bool = false

    // Tracking
    private(set) var totalEnemiesSpawned: Int = 0
    private(set) var totalEnemiesToSpawn: Int = 0

    // Formation management
    private var formationManager: FormationManager?

    init(scene: SKScene, waves: [EnemyWave]) {
        self.scene = scene
        self.waves = waves
        self.formationManager = FormationManager(scene: scene)

        // Calculate total enemies
        for wave in waves {
            totalEnemiesToSpawn += wave.enemies.count
        }
    }

    func update(currentTime: TimeInterval) {
        guard scene != nil else { return }

        // Initialize start time
        if !hasStarted {
            hasStarted = true
            waveStartTime = currentTime
            lastSpawnTime = currentTime
        }

        // Update formation manager
        formationManager?.update(currentTime: currentTime)

        // Check if all waves are complete
        if currentWaveIndex >= waves.count {
            return
        }

        let currentWave = waves[currentWaveIndex]

        // Check if wave delay has passed
        if currentTime - waveStartTime < currentWave.spawnDelay {
            return
        }

        // Check if all enemies in current wave have been spawned
        if enemiesSpawnedInWave >= currentWave.enemies.count {
            // Move to next wave
            currentWaveIndex += 1
            enemiesSpawnedInWave = 0
            waveStartTime = currentTime

            // Check if this was the last wave
            if currentWaveIndex >= waves.count {
                // All waves spawned - completion will be checked in GameScene
                // when all enemies are destroyed
            }
            return
        }

        // Handle formation waves differently
        if currentWave.isFormation && enemiesSpawnedInWave == 0 {
            // Spawn entire formation at once
            let pattern = currentWave.formationPattern ?? .vShape
            formationManager?.spawnFormation(
                pattern: pattern,
                count: currentWave.enemies.count,
                attackDelay: 2.0,
                onEnemyComplete: {
                    // Enemy left the screen - no action needed
                }
            )

            enemiesSpawnedInWave = currentWave.enemies.count
            totalEnemiesSpawned += currentWave.enemies.count

            return
        }

        // Spawn next enemy if interval has passed (non-formation waves)
        if !currentWave.isFormation && currentTime - lastSpawnTime >= currentWave.spawnInterval {
            let enemyType = currentWave.enemies[enemiesSpawnedInWave]
            spawnEnemy(type: enemyType)

            enemiesSpawnedInWave += 1
            totalEnemiesSpawned += 1
            lastSpawnTime = currentTime
        }
    }

    private func spawnEnemy(type: EnemyType) {
        guard let scene = scene else { return }

        // Get GameScene to access gameContentNode
        let parentNode: SKNode
        if let gameScene = scene as? GameScene {
            parentNode = gameScene.gameContentNode
        } else {
            parentNode = scene
        }

        let enemy = Enemy(sceneSize: scene.size, scene: scene, type: type)
        parentNode.addChild(enemy)

        // Start enemy movement
        enemy.startMovement {
            // Enemy left the screen - no action needed
        }
    }

    func areAllWavesSpawned() -> Bool {
        return currentWaveIndex >= waves.count
    }

    func stopSpawning() {
        currentWaveIndex = waves.count // Mark all waves as spawned
    }
}
