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

    /// The formation the current wave spawned, while the queue may still need to wait
    /// on it. Weak: `FormationManager` drops a formation once every member is gone.
    private weak var lastFormation: Formation?
    private var lastFormationSpawnTime: TimeInterval = 0

    /// Longest the queue will wait on a formation before moving on regardless — a
    /// backstop, well past the ~8.5 s the largest formation needs to enter and attack.
    private static let maxFormationHold: TimeInterval = 12

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
            if currentWave.isFormation, isNextWaveAFormation,
               !formationHasReleasedItsSlots(at: currentTime) {
                return
            }

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
            lastFormation = formationManager?.spawnFormation(
                pattern: pattern,
                types: currentWave.enemies,
                attackDelay: 2.0,
                onEnemyComplete: {
                    // Enemy left the screen - no action needed
                }
            )
            lastFormationSpawnTime = currentTime

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

    private var isNextWaveAFormation: Bool {
        let next = currentWaveIndex + 1
        return next < waves.count && waves[next].isFormation
    }

    /// Whether the formation the current wave spawned has finished taking its slots and
    /// begun its attack, so another can fly into the same grid.
    ///
    /// Every pattern lays out on the same slots (screen centre, near the top), and a
    /// formation counts as spawned the instant it appears. A run of formation waves —
    /// levels 35, 39, 43, 49 and 50 each have five or six back to back — used to arrive
    /// one lead-in apart, under a second each after the pacing pass, while each takes
    /// 4–8 s to fly in and hold before it attacks: the whole run piled onto one grid
    /// together. Holding the next formation until this one starts its attack means it
    /// arrives as this one peels away. A formation wiped out before then holds nothing.
    ///
    /// Only formation-to-formation: loose enemies come in along the whole top edge and
    /// fly straight through, so a loose wave after a formation keeps its usual lead-in.
    private func formationHasReleasedItsSlots(at currentTime: TimeInterval) -> Bool {
        guard let formation = lastFormation else { return true }
        return formation.hasAttacked || currentTime - lastFormationSpawnTime >= Self.maxFormationHold
    }

    private func spawnEnemy(type: EnemyType) {
        guard let scene = scene else { return }

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

        let enemy = Enemy(sceneSize: scene.size, scene: scene, type: type)
        parentNode.addChild(enemy)

        // Register enemy in cache for optimized updates
        gameScene?.registerEnemy(enemy)

        // Start enemy movement
        enemy.startMovement {
            // Enemy left the screen - no action needed
        }

        spawnWingman(for: enemy, in: parentNode, gameScene: gameScene)
    }

    /// Types that may fly in pairs: the line fighters, whose behaviour is a path from
    /// wherever they spawn. Not the set-pieces (turrets, mines, the vortex, the tank),
    /// which are meant to be met one at a time, and not flankers, whose entry side is
    /// baked into their heading.
    private static func canFlyInPairs(_ type: EnemyType) -> Bool {
        switch type {
        case .basic, .fast, .zigzag, .kamikaze, .formation, .sniper, .striker,
             .scout, .eliteGuard, .bomber, .ghost, .splitter, .bouncer, .teleporter, .heavy:
            return true
        default:
            return false
        }
    }

    /// Possibly sends a second enemy of the same type down the mirrored lane. See
    /// `CombatRules.wingmanChance(forLevel:)`.
    private func spawnWingman(for lead: Enemy, in parentNode: SKNode, gameScene: GameScene?) {
        guard let scene = scene, Self.canFlyInPairs(lead.enemyType) else { return }
        let level = gameScene?.enemyHealthLevel ?? 1
        guard Double.random(in: 0..<1) < CombatRules.wingmanChance(forLevel: level) else { return }

        let width = scene.size.width
        var x = width - lead.position.x
        // A lead near the centre line would mirror onto itself: fly alongside instead.
        if abs(x - lead.position.x) < 70 {
            x = lead.position.x + (lead.position.x < width / 2 ? 80 : -80)
        }
        x = min(max(x, 30), width - 30)

        let wingman = Enemy(sceneSize: scene.size, scene: scene, type: lead.enemyType)
        wingman.position = CGPoint(x: x, y: lead.position.y)
        parentNode.addChild(wingman)
        gameScene?.registerEnemy(wingman)
        wingman.startMovement {}
        // Not counted in `totalEnemiesSpawned`. Wingmen are extra traffic on top of the
        // queue, not part of it — `totalEnemiesToSpawn` has no way to know how many will
        // roll — and counting them on one side only filled the level's progress bar
        // before the last wave had even started.
    }

    func areAllWavesSpawned() -> Bool {
        return currentWaveIndex >= waves.count
    }

    /// Adds more waves to a manager that may already have finished its queue.
    ///
    /// For endless mode, which has no authored wave list to hand the initialiser — it
    /// tops the queue up a round at a time. `update(currentTime:)` returns early once
    /// `currentWaveIndex` passes the end, so appending is enough to restart it; the only
    /// thing that has to be repaired is `waveStartTime`, which would otherwise still hold
    /// the instant the *previous* wave began and let the new one's `spawnDelay` elapse in
    /// the past.
    func appendWaves(_ newWaves: [EnemyWave], currentTime: TimeInterval) {
        guard !newWaves.isEmpty else { return }

        let hadFinished = areAllWavesSpawned()
        waves.append(contentsOf: newWaves)
        totalEnemiesToSpawn += newWaves.reduce(0) { $0 + $1.enemies.count }

        if hadFinished {
            waveStartTime = currentTime
            lastSpawnTime = currentTime
        }
    }

    func stopSpawning() {
        currentWaveIndex = waves.count // Mark all waves as spawned
    }
}
