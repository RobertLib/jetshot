//
//  LevelManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import Foundation

class LevelManager {
    static let shared = LevelManager()

    private let userDefaults = UserDefaults.standard
    private let completedLevelsKey = "completedLevels"

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

    // Mark level as completed
    func completeLevel(_ level: Int) {
        var completedLevels = getCompletedLevels()
        if !completedLevels.contains(level) {
            completedLevels.append(level)
            userDefaults.set(completedLevels, forKey: completedLevelsKey)
            userDefaults.synchronize()
        }
    }

    // Get all completed levels
    private func getCompletedLevels() -> [Int] {
        return userDefaults.array(forKey: completedLevelsKey) as? [Int] ?? []
    }

    // Reset all progress (for testing)
    func resetProgress() {
        userDefaults.removeObject(forKey: completedLevelsKey)
        userDefaults.synchronize()
    }

    // Get level configuration
    func getLevelConfig(for level: Int) -> LevelConfig {
        let waves = getWavesForLevel(level)
        let obstacleWaves = getObstacleWavesForLevel(level)
        let powerUpConfig = getPowerUpConfigForLevel(level)

        return LevelConfig(
            levelNumber: level,
            title: "Level \(level)",
            waves: waves,
            obstacleWaves: obstacleWaves,
            powerUpConfig: powerUpConfig
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
            // Level 3: Heavy, zigzag, sniper and basic formations
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
            // Level 4: Kamikaze, Tank and Elite Guard formations
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
            // Level 5: Bombers, Spinners and mixed challenges
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
            // Level 6: Commanders and intense formation battles
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
            // Level 3: Add horizontal walls and more variety
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall],
                    spawnDelay: 5.0,
                    spawnInterval: 3.5,
                    minSpacing: 180
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
                    .shield: 2.0
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
                    .shield: 2.5
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
                    .shield: 3.0
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
                    .shield: 4.0
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
                    .shield: 5.0
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
                    .shield: 5.5
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
                    .shield: 6.0
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
                    .shield: 7.0
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
                    .shield: 2.0
                ]
            )
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
}
