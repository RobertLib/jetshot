//
//  EnemyManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import SpriteKit

class EnemyManager {

    // Configuration
    private var spawnInterval: TimeInterval = 2.0
    private let minSpawnInterval: TimeInterval = 0.8
    private let difficultyIncreaseRate: TimeInterval = 0.02

    private weak var scene: SKScene?
    private var lastSpawnTime: TimeInterval = 0
    private var isPaused: Bool = false

    init(scene: SKScene) {
        self.scene = scene
    }

    func update(currentTime: TimeInterval) {
        guard scene != nil else { return }

        // Don't spawn enemies when paused
        if isPaused { return }

        // Spawn new enemy if enough time has passed
        if currentTime - lastSpawnTime > spawnInterval {
            spawnEnemy()
            lastSpawnTime = currentTime

            // Progressive difficulty increase
            spawnInterval = max(minSpawnInterval, spawnInterval - difficultyIncreaseRate)
        }
    }

    private func spawnEnemy() {
        guard let scene = scene else { return }

        let enemy = Enemy(sceneSize: scene.size, scene: scene)
        scene.addChild(enemy)

        // Start enemy movement
        enemy.startMovement {
            // Enemy reached bottom (could track this for game over condition)
        }
    }

    func reset() {
        spawnInterval = 2.0
        lastSpawnTime = 0
    }

    func pauseSpawning() {
        isPaused = true
    }

    func resumeSpawning() {
        isPaused = false
    }
}
