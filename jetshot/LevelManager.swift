//
//  LevelManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import Foundation

class LevelManager {
    static let shared = LevelManager()

    private let cloudStorage = CloudStorageManager.shared
    private let completedLevelsKey = "completedLevels"
    private let levelScoresKey = "levelScores"
    private let levelStarsKey = "levelStars"

    private init() {}

    // Total number of levels
    let totalLevels = 8  // Increased from 5 to 8

    // Check if level is unlocked
    func isLevelUnlocked(_ level: Int) -> Bool {
        if level == 1 {
            return true // First level always unlocked
        }
        return isLevelCompleted(level - 1) // Unlock if previous level completed
    }

    // Check if level is completed
    func isLevelCompleted(_ level: Int) -> Bool {
        let completedLevels = getCompletedLevels()
        return completedLevels.contains(level)
    }

    // Mark level as completed with score
    func completeLevel(_ level: Int, score: Int, stars: Int = 3) {
        var completedLevels = getCompletedLevels()
        if !completedLevels.contains(level) {
            completedLevels.append(level)
            cloudStorage.saveArray(completedLevels, forKey: completedLevelsKey)
        }

        // Save score for this level (always update to allow improving score)
        saveLevelScore(level: level, score: score)

        // Save stars for this level (only update if better)
        saveLevelStars(level: level, stars: stars)

        // Submit score to Game Center
        GameCenterManager.shared.submitLevelScore(score, level: level)
    }

    // Get all completed levels
    private func getCompletedLevels() -> [Int] {
        return cloudStorage.loadArray(forKey: completedLevelsKey) as? [Int] ?? []
    }

    // Save score for a specific level
    private func saveLevelScore(level: Int, score: Int) {
        var levelScores = getLevelScores()

        // Update or add score for this level
        levelScores["\(level)"] = score

        cloudStorage.saveDictionary(levelScores, forKey: levelScoresKey)
    }

    // Get score for a specific level
    func getLevelScore(level: Int) -> Int? {
        let levelScores = getLevelScores()
        return levelScores["\(level)"]
    }

    // Get all level scores
    private func getLevelScores() -> [String: Int] {
        return cloudStorage.loadDictionary(forKey: levelScoresKey) as? [String: Int] ?? [:]
    }

    // Get total score from all completed levels
    func getTotalScore() -> Int {
        let levelScores = getLevelScores()
        return levelScores.values.reduce(0, +)
    }

    // Save stars for a specific level
    private func saveLevelStars(level: Int, stars: Int) {
        var levelStars = getLevelStarsDict()

        // Only update if new stars are better than existing
        if let existingStars = levelStars["\(level)"], existingStars >= stars {
            return
        }

        levelStars["\(level)"] = stars
        cloudStorage.saveDictionary(levelStars, forKey: levelStarsKey)
    }

    // Get stars for a specific level
    func getLevelStars(level: Int) -> Int {
        let levelStars = getLevelStarsDict()
        return levelStars["\(level)"] ?? 0
    }

    // Get all level stars
    private func getLevelStarsDict() -> [String: Int] {
        return cloudStorage.loadDictionary(forKey: levelStarsKey) as? [String: Int] ?? [:]
    }

    // Reset all progress (for testing)
    func resetProgress() {
        cloudStorage.removeObject(forKey: completedLevelsKey)
        cloudStorage.removeObject(forKey: levelScoresKey)
        cloudStorage.removeObject(forKey: levelStarsKey)

        // Also reset Game Center statistics
        GameCenterManager.shared.resetLocalTracking()
    }

    // Get level configuration
    func getLevelConfig(for level: Int) -> LevelConfig {
        let waves = getWavesForLevel(level)
        let obstacleWaves = getObstacleWavesForLevel(level)
        let powerUpConfig = getPowerUpConfigForLevel(level)
        let asteroidWaves = getAsteroidWavesForLevel(level)

        return LevelConfig(
            levelNumber: level,
            title: "Level \(level)",
            waves: waves,
            obstacleWaves: obstacleWaves,
            powerUpConfig: powerUpConfig,
            asteroidWaves: asteroidWaves
        )
    }

    // Define waves for each level
    private func getWavesForLevel(_ level: Int) -> [EnemyWave] {
        switch level {
        case 1:
            // Level 1: Tutorial - Basic enemies and introducing striker
            return [
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 6),
                    spawnDelay: 1.0,
                    spawnInterval: 1.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 6),
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: [.basic, .basic, .striker, .basic, .basic],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .striker, count: 3),
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                )
            ]

        case 2:
            // Level 2: Introduce fast enemies, scouts and first formation
            return [
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 5),
                    spawnDelay: 1.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .fast, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.basic, .fast, .striker, .fast, .basic],
                    spawnDelay: 2.0,
                    spawnInterval: 1.1
                ),
                EnemyWave(
                    enemies: Array(repeating: .striker, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                )
            ]

        case 3:
            // Level 3: Heavy, zigzag, sniper, turret and basic formations
            return [
                EnemyWave(
                    enemies: [.basic, .basic, .heavy, .basic, .basic],
                    spawnDelay: 1.0,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 5),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.turret, .turret],
                    spawnDelay: 2.0,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .zigzag, count: 3),
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: [.sniper, .basic, .basic, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.fast, .striker, .fast, .striker, .fast],
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                )
            ]

        case 4:
            // Level 4: Kamikaze, Tank, Turret Spiral and Elite Guard formations
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 5),
                    spawnDelay: 1.0,
                    spawnInterval: 0.8
                ),
                EnemyWave(
                    enemies: [.heavy, .basic, .heavy, .basic],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 3.5
                ),
                EnemyWave(
                    enemies: [.mine, .mine],
                    spawnDelay: 2.0,
                    spawnInterval: 4.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 5),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.tank, .basic, .basic, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .zigzag, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .heavy, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 6),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .line
                )
            ]

        case 5:
            // Level 5: Bombers, Spinners, Turrets and mixed challenges
            return [
                EnemyWave(
                    enemies: [.fast, .fast, .striker, .striker, .fast],
                    spawnDelay: 1.0,
                    spawnInterval: 1.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 6),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.turret, .heavy, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.heavy, .heavy, .tank, .heavy],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 4),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 6),
                    spawnDelay: 2.0,
                    spawnInterval: 0.6
                ),
                EnemyWave(
                    enemies: [.turret, .turret, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine],
                    spawnDelay: 2.5,
                    spawnInterval: 3.5
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.zigzag, .zigzag, .zigzag, .zigzag],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                )
            ]

        case 6:
            // Level 6: Commanders, Turret Spirals and intense formation battles
            return [
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 6),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.tank, .heavy, .heavy, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 4),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 7),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 7),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.sniper, .striker, .sniper, .striker, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 5),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                )
            ]

        case 7:
            // Level 7: Multiple Tanks and advanced formations
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 4),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .heavy, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 6),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 4),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 8),
                    spawnDelay: 1.5,
                    spawnInterval: 0.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 5),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.zigzag, .zigzag, .striker, .striker, .zigzag],
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 8),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                )
            ]

        case 8:
            // Level 8: FINAL BOSS LEVEL - All enemy types, ultimate challenge
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 4),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .kamikaze],
                    spawnDelay: 1.5,
                    spawnInterval: 0.9
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 6),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank],
                    spawnDelay: 3.0,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 5),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .heavy, .heavy, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 4),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 10),
                    spawnDelay: 1.5,
                    spawnInterval: 0.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 8),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.striker, .striker, .zigzag, .zigzag, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 0.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 7),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.tank, .sniper, .tank, .sniper],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 6),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 4),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank],
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                )
            ]

        default:
            // Fallback for any other level
            return [
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 5),
                    spawnDelay: 1.0,
                    spawnInterval: 1.5
                )
            ]
        }
    }

    // Define obstacle waves for each level
    private func getObstacleWavesForLevel(_ level: Int) -> [ObstacleWave] {
        switch level {
        case 1:
            // Level 1: No obstacles - learning the game
            return []

        case 2:
            // Level 2: Introduce simple static walls
            return [
                ObstacleWave(
                    obstacles: [.wall, .wall],
                    spawnDelay: 8.0,
                    spawnInterval: 4.0,
                    minSpacing: 200
                )
            ]

        case 3:
            // Level 3: Add horizontal walls, destructible walls and more variety
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall],
                    spawnDelay: 5.0,
                    spawnInterval: 3.5,
                    minSpacing: 180
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall],
                    spawnDelay: 4.0,
                    spawnInterval: 5.0,
                    minSpacing: 250
                ),
                ObstacleWave(
                    obstacles: [.wall, .wall],
                    spawnDelay: 4.0,
                    spawnInterval: 3.0,
                    minSpacing: 180
                )
            ]

        case 4:
            // Level 4: Introduce rotating obstacles
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall],
                    spawnDelay: 4.0,
                    spawnInterval: 3.0,
                    minSpacing: 160
                ),
                ObstacleWave(
                    obstacles: [.rotatingBar, .movingWall],
                    spawnDelay: 3.0,
                    spawnInterval: 4.0,
                    minSpacing: 200
                ),
                ObstacleWave(
                    obstacles: [.wall, .wall],
                    spawnDelay: 3.0,
                    spawnInterval: 2.5,
                    minSpacing: 160
                )
            ]

        case 5:
            // Level 5: All obstacle types with moderate frequency
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall, .wall],
                    spawnDelay: 3.0,
                    spawnInterval: 2.8,
                    minSpacing: 160
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .destructibleWall],
                    spawnDelay: 3.0,
                    spawnInterval: 4.0,
                    minSpacing: 220
                ),
                ObstacleWave(
                    obstacles: [.rotatingBar, .spinner],
                    spawnDelay: 3.0,
                    spawnInterval: 3.5,
                    minSpacing: 180
                ),
                ObstacleWave(
                    obstacles: [.movingWall, .movingWall],
                    spawnDelay: 3.0,
                    spawnInterval: 3.0,
                    minSpacing: 170
                )
            ]

        case 6:
            // Level 6: Higher frequency, all types
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5,
                    minSpacing: 150
                ),
                ObstacleWave(
                    obstacles: [.rotatingBar, .spinner, .movingWall],
                    spawnDelay: 3.0,
                    spawnInterval: 3.0,
                    minSpacing: 170
                ),
                ObstacleWave(
                    obstacles: [.wall, .wall, .horizontalWall],
                    spawnDelay: 2.5,
                    spawnInterval: 2.3,
                    minSpacing: 150
                )
            ]

        case 7:
            // Level 7: Very high frequency and complexity
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall, .wall],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2,
                    minSpacing: 140
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .rotatingBar],
                    spawnDelay: 2.5,
                    spawnInterval: 3.5,
                    minSpacing: 180
                ),
                ObstacleWave(
                    obstacles: [.rotatingBar, .spinner],
                    spawnDelay: 2.5,
                    spawnInterval: 3.0,
                    minSpacing: 160
                ),
                ObstacleWave(
                    obstacles: [.movingWall, .movingWall, .rotatingBar],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5,
                    minSpacing: 150
                ),
                ObstacleWave(
                    obstacles: [.spinner, .wall],
                    spawnDelay: 2.5,
                    spawnInterval: 2.8,
                    minSpacing: 160
                )
            ]

        case 8:
            // Level 8: INSANE - Maximum obstacle chaos
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall, .wall],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0,
                    minSpacing: 130
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .rotatingBar],
                    spawnDelay: 2.0,
                    spawnInterval: 3.5,
                    minSpacing: 180
                ),
                ObstacleWave(
                    obstacles: [.rotatingBar, .spinner, .rotatingBar],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5,
                    minSpacing: 150
                ),
                ObstacleWave(
                    obstacles: [.movingWall, .movingWall],
                    spawnDelay: 2.0,
                    spawnInterval: 2.5,
                    minSpacing: 140
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall],
                    spawnDelay: 2.0,
                    spawnInterval: 4.0,
                    minSpacing: 200
                ),
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall, .rotatingBar],
                    spawnDelay: 2.0,
                    spawnInterval: 2.2,
                    minSpacing: 130
                ),
                ObstacleWave(
                    obstacles: [.spinner, .wall, .spinner],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5,
                    minSpacing: 140
                )
            ]

        default:
            // Fallback for other levels
            return []
        }
    }

    // Define powerup configuration for each level
    private func getPowerUpConfigForLevel(_ level: Int) -> PowerUpSpawnConfig {
        switch level {
        case 1:
            // Level 1: Lower spawn rate, mostly basic powerups
            return PowerUpSpawnConfig(
                spawnInterval: 15.0,
                spawnProbability: 0.5,
                typeWeights: [
                    .extraLife: 2.0,
                    .multiShot: 3.0,
                    .sideMissiles: 1.5,
                    .shield: 2.0,
                    .lightning: 0.5
                ]
            )

        case 2:
            // Level 2: Slightly higher spawn rate
            return PowerUpSpawnConfig(
                spawnInterval: 12.0,
                spawnProbability: 0.6,
                typeWeights: [
                    .extraLife: 2.5,
                    .multiShot: 3.5,
                    .sideMissiles: 2.0,
                    .shield: 2.5,
                    .lightning: 0.8
                ]
            )

        case 3:
            // Level 3: Balanced spawn rate
            return PowerUpSpawnConfig(
                spawnInterval: 10.0,
                spawnProbability: 0.65,
                typeWeights: [
                    .extraLife: 3.0,
                    .multiShot: 4.0,
                    .sideMissiles: 3.0,
                    .shield: 3.0,
                    .lightning: 1.0
                ]
            )

        case 4:
            // Level 4: Higher spawn rate
            return PowerUpSpawnConfig(
                spawnInterval: 9.0,
                spawnProbability: 0.7,
                typeWeights: [
                    .extraLife: 3.5,
                    .multiShot: 4.5,
                    .sideMissiles: 3.5,
                    .shield: 4.0,
                    .lightning: 1.2
                ]
            )

        case 5:
            // Level 5: Good spawn rate
            return PowerUpSpawnConfig(
                spawnInterval: 8.0,
                spawnProbability: 0.75,
                typeWeights: [
                    .extraLife: 4.0,
                    .multiShot: 5.0,
                    .sideMissiles: 4.0,
                    .shield: 5.0,
                    .lightning: 1.5
                ]
            )

        case 6:
            // Level 6: Higher spawn rate, more shields
            return PowerUpSpawnConfig(
                spawnInterval: 7.5,
                spawnProbability: 0.75,
                typeWeights: [
                    .extraLife: 4.5,
                    .multiShot: 5.5,
                    .sideMissiles: 4.5,
                    .shield: 5.5,
                    .lightning: 2.0
                ]
            )

        case 7:
            // Level 7: Very high spawn rate
            return PowerUpSpawnConfig(
                spawnInterval: 7.0,
                spawnProbability: 0.8,
                typeWeights: [
                    .extraLife: 5.0,
                    .multiShot: 6.0,
                    .sideMissiles: 5.0,
                    .shield: 6.0,
                    .lightning: 2.5
                ]
            )

        case 8:
            // Level 8: MAXIMUM spawn rate - you'll need it!
            return PowerUpSpawnConfig(
                spawnInterval: 6.0,
                spawnProbability: 0.85,
                typeWeights: [
                    .extraLife: 6.0,
                    .multiShot: 7.0,
                    .sideMissiles: 6.0,
                    .shield: 7.0,
                    .lightning: 3.0
                ]
            )

        default:
            // Fallback
            return PowerUpSpawnConfig(
                spawnInterval: 12.0,
                spawnProbability: 0.5,
                typeWeights: [
                    .extraLife: 2.0,
                    .multiShot: 3.0,
                    .sideMissiles: 1.5,
                    .shield: 2.0,
                    .lightning: 0.5
                ]
            )
        }
    }

    // Define asteroid waves for each level
    private func getAsteroidWavesForLevel(_ level: Int) -> [AsteroidWave] {
        switch level {
        case 1:
            // Level 1: No asteroids - tutorial
            return []

        case 2:
            // Level 2: Introduce asteroids with a small wave
            return [
                AsteroidWave(
                    count: 3,
                    size: .large,
                    spawnDelay: 5.0,
                    spawnInterval: 2.5
                )
            ]

        case 3:
            // Level 3: More asteroids, mixed sizes
            return [
                AsteroidWave(
                    count: 4,
                    size: .large,
                    spawnDelay: 3.0,
                    spawnInterval: 2.0
                ),
                AsteroidWave(
                    count: 3,
                    size: .medium,
                    spawnDelay: 3.0,
                    spawnInterval: 1.5
                )
            ]

        case 4:
            // Level 4: Heavy asteroid waves
            return [
                AsteroidWave(
                    count: 5,
                    size: .large,
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                AsteroidWave(
                    count: 4,
                    size: .medium,
                    spawnDelay: 3.0,
                    spawnInterval: 1.5
                ),
                AsteroidWave(
                    count: 3,
                    size: .large,
                    spawnDelay: 3.0,
                    spawnInterval: 1.8
                )
            ]

        case 5:
            // Level 5: Mixed with small asteroids
            return [
                AsteroidWave(
                    count: 4,
                    size: .large,
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                ),
                AsteroidWave(
                    count: 5,
                    size: .medium,
                    spawnDelay: 2.5,
                    spawnInterval: 1.2
                ),
                AsteroidWave(
                    count: 6,
                    size: .small,
                    spawnDelay: 2.5,
                    spawnInterval: 1.0
                )
            ]

        case 6:
            // Level 6: Intense asteroid field
            return [
                AsteroidWave(
                    count: 6,
                    size: .large,
                    spawnDelay: 1.5,
                    spawnInterval: 1.5
                ),
                AsteroidWave(
                    count: 5,
                    size: .medium,
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                ),
                AsteroidWave(
                    count: 4,
                    size: .large,
                    spawnDelay: 2.5,
                    spawnInterval: 1.5
                ),
                AsteroidWave(
                    count: 6,
                    size: .small,
                    spawnDelay: 2.0,
                    spawnInterval: 0.8
                )
            ]

        case 7:
            // Level 7: Extreme asteroid challenge
            return [
                AsteroidWave(
                    count: 8,
                    size: .large,
                    spawnDelay: 1.0,
                    spawnInterval: 1.3
                ),
                AsteroidWave(
                    count: 6,
                    size: .medium,
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                ),
                AsteroidWave(
                    count: 7,
                    size: .small,
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                ),
                AsteroidWave(
                    count: 5,
                    size: .large,
                    spawnDelay: 2.5,
                    spawnInterval: 1.2
                )
            ]

        case 8:
            // Level 8: Boss level - fewer but strategic asteroids
            return [
                AsteroidWave(
                    count: 4,
                    size: .large,
                    spawnDelay: 2.0,
                    spawnInterval: 2.5
                ),
                AsteroidWave(
                    count: 3,
                    size: .medium,
                    spawnDelay: 4.0,
                    spawnInterval: 2.0
                )
            ]

        default:
            return []
        }
    }
}

// Level configuration
struct LevelConfig {
    let levelNumber: Int
    let title: String
    let waves: [EnemyWave]
    let obstacleWaves: [ObstacleWave]
    let powerUpConfig: PowerUpSpawnConfig
    let asteroidWaves: [AsteroidWave]
}
