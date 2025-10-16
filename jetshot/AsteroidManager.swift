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

    // Active asteroids tracking (for split pieces)
    var activeAsteroids: Set<ObjectIdentifier> = []

    init(scene: SKScene, waves: [AsteroidWave]) {
        self.scene = scene
        self.waves = waves

        // Calculate total asteroids (only initial spawns, not splits)
        for wave in waves {
            totalAsteroidsToSpawn += wave.count
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

        // Track this asteroid
        activeAsteroids.insert(ObjectIdentifier(asteroid))

        // Start asteroid movement
        asteroid.startMovement { [weak self] in
            // Asteroid left the screen
            self?.activeAsteroids.remove(ObjectIdentifier(asteroid))
        }
    }

    // Handle asteroid split
    func splitAsteroid(_ asteroid: Asteroid) {
        guard let scene = scene else { return }

        let splitPieces = asteroid.split()

        // Track new split pieces, add to scene, and start their movement
        for (index, piece) in splitPieces.enumerated() {
            activeAsteroids.insert(ObjectIdentifier(piece))

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

            // Calculate split velocity with stronger downward component
            let splitSpeed: CGFloat = CGFloat.random(in: 40...80) // Reduced horizontal speed
            let splitVelocityX = cos(angle) * splitSpeed
            _ = sin(angle) * splitSpeed // Negative = downward (currently unused in final calculation)

            // Calculate falling movement parameters with enhanced downward speed
            let pieceSpeed = piece.asteroidSize.speed * 1.3 // 30% faster falling for threat
            let totalDistance = scene.size.height + piece.asteroidSize.baseSize * 2
            let fallDuration = TimeInterval(totalDistance / pieceSpeed)

            // Calculate final position: combine split momentum with enhanced falling
            // Horizontal spread is limited, vertical is emphasized
            let finalX = piece.position.x + (splitVelocityX * CGFloat(fallDuration) * 0.6) // Reduce horizontal spread
            let finalY = -piece.asteroidSize.baseSize

            // Create smooth movement that combines split and fall
            let combinedMove = SKAction.move(
                to: CGPoint(x: finalX, y: finalY),
                duration: fallDuration
            )
            combinedMove.timingMode = .linear // Constant velocity, like in space

            // Add continuous rotation for more dynamic feel
            let rotationAmount = CGFloat.random(in: -(.pi * 2)...(.pi * 2))
            let rotate = SKAction.rotate(byAngle: rotationAmount, duration: fallDuration)

            // Combine movement and rotation
            let movement = SKAction.group([combinedMove, rotate])

            // Set up completion callback
            piece.movementCompletion = { [weak self, weak piece] in
                if let piece = piece {
                    self?.activeAsteroids.remove(ObjectIdentifier(piece))
                }
            }

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

        // Remove original asteroid from tracking
        activeAsteroids.remove(ObjectIdentifier(asteroid))
    }

    // Check if all asteroids are cleared
    var allAsteroidsCleared: Bool {
        return currentWaveIndex >= waves.count && activeAsteroids.isEmpty
    }

    func reset() {
        currentWaveIndex = 0
        asteroidsSpawnedInWave = 0
        totalAsteroidsSpawned = 0
        hasStarted = false
        activeAsteroids.removeAll()
    }
}
