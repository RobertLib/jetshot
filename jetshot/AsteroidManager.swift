//
//  AsteroidManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 1.11.2025.
//

import SpriteKit

// Asteroid wave configuration
struct AsteroidWave {
    let count: Int // Number of asteroids to spawn
    let size: AsteroidSize // Size of asteroids in this wave
    let spawnDelay: TimeInterval // Delay before starting this wave
    let spawnInterval: TimeInterval // Time between individual asteroid spawns

    init(count: Int,
         size: AsteroidSize = .large,
         spawnDelay: TimeInterval = 0,
         spawnInterval: TimeInterval = 1.0) {
        self.count = count
        self.size = size
        self.spawnDelay = spawnDelay
        self.spawnInterval = spawnInterval
    }
}

class AsteroidManager {

    private weak var scene: SKScene?

    // Wave system
    private var waves: [AsteroidWave] = []
    private var currentWaveIndex: Int = 0
    private var asteroidsSpawnedInWave: Int = 0
    private var lastSpawnTime: TimeInterval = 0
    private var waveStartTime: TimeInterval = 0
    private var hasStarted: Bool = false

    // Tracking
    private(set) var totalAsteroidsSpawned: Int = 0
    private(set) var totalAsteroidsToSpawn: Int = 0

    init(scene: SKScene, waves: [AsteroidWave]) {
        self.scene = scene
        self.waves = waves

        // Calculate total asteroids (only initial spawns, not splits)
        for wave in waves {
            totalAsteroidsToSpawn += wave.count
        }
    }


    /// Drops whatever is still queued and starts `newWaves` from now.
    ///
    /// For endless mode, which has no authored level to draw a fixed hazard track from —
    /// `GameScene` hands over a fresh track every round so the hazards escalate with the
    /// run. This used to *append*, but a borrowed track runs far longer than a round (a
    /// level 50 set is ~84 s against rounds of 15–30 s), so each round queued behind a
    /// growing backlog and a deep run was still flying asteroids from many rounds back.
    func replaceWaves(_ newWaves: [AsteroidWave], currentTime: TimeInterval) {
        waves = newWaves
        currentWaveIndex = 0
        asteroidsSpawnedInWave = 0
        totalAsteroidsToSpawn = totalAsteroidsSpawned + newWaves.reduce(0) { $0 + $1.count }
        waveStartTime = currentTime
        lastSpawnTime = currentTime
    }

    func update(currentTime: TimeInterval) {
        guard scene != nil else { return }

        // Initialize start time
        if !hasStarted {
            hasStarted = true
            waveStartTime = currentTime
            lastSpawnTime = currentTime
        }

        // Check if all waves are complete
        if currentWaveIndex >= waves.count {
            return
        }

        let currentWave = waves[currentWaveIndex]

        // Check if wave delay has passed
        if currentTime - waveStartTime < currentWave.spawnDelay {
            return
        }

        // Check if all asteroids in current wave have been spawned
        if asteroidsSpawnedInWave >= currentWave.count {
            // Move to next wave
            currentWaveIndex += 1
            asteroidsSpawnedInWave = 0
            waveStartTime = currentTime

            // Check if this was the last wave
            if currentWaveIndex >= waves.count {
                // All waves spawned
            }
            return
        }

        // Spawn next asteroid if interval has passed
        if currentTime - lastSpawnTime >= currentWave.spawnInterval {
            spawnAsteroid(size: currentWave.size)

            asteroidsSpawnedInWave += 1
            totalAsteroidsSpawned += 1
            lastSpawnTime = currentTime
        }
    }

    private func spawnAsteroid(size: AsteroidSize, at position: CGPoint? = nil) {
        guard let scene = scene else { return }

        let asteroid = Asteroid(sceneSize: scene.size, scene: scene, size: size, startPosition: position)

        // Get GameScene to access gameContentNode
        let parentNode: SKNode
        if let gameScene = scene as? GameScene {
            parentNode = gameScene.gameContentNode
        } else {
            parentNode = scene
        }

        parentNode.addChild(asteroid)

        // Start asteroid movement
        asteroid.startMovement {
            // Asteroid left the screen - no action needed
        }
    }

    // Handle asteroid split
    func splitAsteroid(_ asteroid: Asteroid) {
        guard let scene = scene else { return }

        let splitPieces = asteroid.split()

        // Add split pieces to the scene and start their movement
        for (index, piece) in splitPieces.enumerated() {
            // Get GameScene to access gameContentNode
            let parentNode: SKNode
            if let gameScene = scene as? GameScene {
                parentNode = gameScene.gameContentNode
            } else {
                parentNode = scene
            }

            // Add to scene
            parentNode.addChild(piece)

            // Calculate direction for split - favor downward direction to threaten player
            // Instead of full circle, use lower hemisphere (π to 2π) which means downward angles
            let angleRange: CGFloat = .pi // 180 degrees range
            let angleStart: CGFloat = .pi * 0.75 // Start from lower-left
            let angleStep = angleRange / CGFloat(max(splitPieces.count - 1, 1))
            let baseAngle = angleStart + (angleStep * CGFloat(index))
            let randomOffset = CGFloat.random(in: -0.3...0.3)
            let angle = baseAngle + randomOffset

            // Calculate split velocity. Only the horizontal component is used: the
            // downward travel comes from the fall below, which is deliberately
            // stronger than the split impulse would be.
            let splitSpeed: CGFloat = CGFloat.random(in: 40...80) // Reduced horizontal speed
            let splitVelocityX = cos(angle) * splitSpeed

            let fall = Self.pieceFall(from: piece.position, size: piece.asteroidSize, splitVelocityX: splitVelocityX)
            let fallDuration = fall.duration

            // Create smooth movement that combines split and fall
            let combinedMove = SKAction.move(to: fall.destination, duration: fallDuration)
            combinedMove.timingMode = .linear // Constant velocity, like in space

            // Add continuous rotation for more dynamic feel
            let rotationAmount = CGFloat.random(in: -(.pi * 2)...(.pi * 2))
            let rotate = SKAction.rotate(byAngle: rotationAmount, duration: fallDuration)

            // Combine movement and rotation
            let movement = SKAction.group([combinedMove, rotate])

            // Start the combined movement
            let sequence = SKAction.sequence([
                movement,
                SKAction.run { [weak piece] in
                    guard let piece = piece else { return }
                    if !piece.hasCompletedMovement {
                        piece.hasCompletedMovement = true
                        piece.movementCompletion?()
                        piece.removeFromParent()
                    }
                }
            ])

            piece.run(sequence, withKey: "asteroidMovement")
        }
    }

    /// Where a split piece falls to, and how long it takes: from where the rock broke
    /// to just below the bottom edge, 30% faster than a whole rock of its size so the
    /// pieces are a threat. The split's sideways momentum, damped to 60%, carries on
    /// for the same time.
    ///
    /// The duration used to be a full-screen drop — screen height over speed — whatever
    /// the height the rock was broken at. A piece only has the rest of the screen left
    /// to fall, so one broken low crawled out at a fraction of the intended speed
    /// (a medium broken 150 pt up fell at ~20 pt/s instead of 104), and the drift, scaled
    /// by that inflated duration, slid it hundreds of points sideways.
    static func pieceFall(
        from start: CGPoint,
        size: AsteroidSize,
        splitVelocityX: CGFloat
    ) -> (destination: CGPoint, duration: TimeInterval) {
        let speed = size.speed * 1.3
        let finalY = -size.baseSize
        let duration = TimeInterval(max(0, start.y - finalY) / speed)
        let finalX = start.x + splitVelocityX * 0.6 * CGFloat(duration)
        return (CGPoint(x: finalX, y: finalY), duration)
    }
}
