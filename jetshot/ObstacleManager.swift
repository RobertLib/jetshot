//
//  ObstacleManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 25.10.2025.
//

import SpriteKit

// Obstacle wave configuration
struct ObstacleWave {
    let obstacles: [ObstacleType]
    let spawnDelay: TimeInterval // Delay before starting this wave
    let spawnInterval: TimeInterval // Time between individual obstacle spawns
    let minSpacing: CGFloat // Minimum spacing between obstacles (to avoid clustering)
}

class ObstacleManager {

    private weak var scene: SKScene?

    // Wave system
    private var waves: [ObstacleWave] = []
    private var currentWaveIndex: Int = 0
    private var obstaclesSpawnedInWave: Int = 0
    private var lastSpawnTime: TimeInterval = 0
    private var waveStartTime: TimeInterval = 0
    private var hasStarted: Bool = false

    // Tracking last spawn positions to avoid clustering. How far apart "similar x" is
    // comes from the wave's own `minSpacing`; this used to be a fixed 150 pt here, and
    // every authored spacing (90–200) was ignored.
    //
    // Note the window is shorter than every authored `spawnInterval` (1.8 s and up), so
    // as tuned the check only bites for a wave that spawns faster than that.
    private var lastSpawnPositions: [(x: CGFloat, time: TimeInterval)] = []
    private let minTimeSpacing: TimeInterval = 1.5 // Minimum time between obstacles at similar x positions

    init(scene: SKScene, waves: [ObstacleWave]) {
        self.scene = scene
        self.waves = waves
    }

    func update(currentTime: TimeInterval) {
        guard let scene = scene else { return }

        // Initialize start time
        if !hasStarted {
            hasStarted = true
            waveStartTime = currentTime
            lastSpawnTime = currentTime
        }

        // Clean up old spawn positions (older than 5 seconds)
        lastSpawnPositions.removeAll { currentTime - $0.time > 5.0 }

        // Check if all waves are complete
        if currentWaveIndex >= waves.count {
            return
        }

        let currentWave = waves[currentWaveIndex]

        // Check if wave delay has passed
        if currentTime - waveStartTime < currentWave.spawnDelay {
            return
        }

        // Check if all obstacles in current wave have been spawned
        if obstaclesSpawnedInWave >= currentWave.obstacles.count {
            // Move to next wave
            currentWaveIndex += 1
            obstaclesSpawnedInWave = 0
            waveStartTime = currentTime
            return
        }

        // Check if enough time has passed since last spawn
        if currentTime - lastSpawnTime >= currentWave.spawnInterval {
            let obstacleType = currentWave.obstacles[obstaclesSpawnedInWave]
            spawnObstacle(type: obstacleType, scene: scene, currentTime: currentTime,
                          minSpacing: currentWave.minSpacing)
            lastSpawnTime = currentTime
            obstaclesSpawnedInWave += 1
        }
    }

    private func spawnObstacle(type: ObstacleType, scene: SKScene, currentTime: TimeInterval, minSpacing: CGFloat) {
        let sceneWidth = scene.size.width
        let sceneHeight = scene.size.height

        // Determine safe spawn area (accounting for player position at bottom)
        let minX: CGFloat = 60 // Left margin
        let maxX: CGFloat = sceneWidth - 60 // Right margin
        let spawnY: CGFloat = sceneHeight + 100 // Above screen

        // Try to find a valid spawn position (avoiding clustering)
        var spawnX: CGFloat = 0
        var attempts = 0
        let maxAttempts = 10

        repeat {
            spawnX = CGFloat.random(in: minX...maxX)
            attempts += 1

            // Check if this position is too close to recent spawns
            let tooClose = lastSpawnPositions.contains { lastPos in
                let distance = abs(spawnX - lastPos.x)
                let timeDiff = currentTime - lastPos.time
                return distance < minSpacing && timeDiff < minTimeSpacing
            }

            if !tooClose {
                break
            }
        } while attempts < maxAttempts

        // Create obstacle at calculated position
        let position = CGPoint(x: spawnX, y: spawnY)
        let obstacle = Obstacle(type: type, sceneSize: scene.size, position: position)

        // Get GameScene to access gameContentNode
        let parentNode: SKNode
        if let gameScene = scene as? GameScene {
            parentNode = gameScene.gameContentNode
        } else {
            parentNode = scene
        }

        parentNode.addChild(obstacle)

        // Record this spawn position
        lastSpawnPositions.append((x: spawnX, time: currentTime))

        // Keep only recent positions (max 10)
        if lastSpawnPositions.count > 10 {
            lastSpawnPositions.removeFirst()
        }
    }

    // No removeAllObstacles()/isComplete() here. Neither had a caller, and
    // removeAllObstacles() would not have worked if it had gained one: it swept
    // `scene` for "obstacle" nodes, but spawnObstacle parents them to
    // `gameScene.gameContentNode`, so the enumeration matched nothing.


    /// Drops whatever is still queued and starts `newWaves` from now.
    ///
    /// For endless mode, which has no authored level to draw a fixed hazard track from —
    /// `GameScene` hands over a fresh track every round so the hazards escalate with the
    /// run. This used to *append*, which queued each round's walls behind the unfinished
    /// track of the rounds before it; only a boss round's `stopSpawning()` ever cleared
    /// that backlog. Same reasoning as `AsteroidManager.replaceWaves(_:currentTime:)`.
    func replaceWaves(_ newWaves: [ObstacleWave], currentTime: TimeInterval) {
        waves = newWaves
        currentWaveIndex = 0
        obstaclesSpawnedInWave = 0
        waveStartTime = currentTime
        lastSpawnTime = currentTime
    }

    /// Waves not yet finished spawning, for `jetshotTests`.
    var queuedWaveCount: Int {
        return max(0, waves.count - currentWaveIndex)
    }

    func stopSpawning() {
        currentWaveIndex = waves.count // Mark all waves as spawned
    }
}
