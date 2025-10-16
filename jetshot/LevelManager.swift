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
    private let completedLevelsKey = CloudStorageManager.Keys.completedLevels
    private let levelScoresKey = CloudStorageManager.Keys.levelScores
    private let levelStarsKey = CloudStorageManager.Keys.levelStars

    private init() {}

    // Total number of levels
    let totalLevels = 50  // Expanded to 50 levels

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
        // ============================================
        // LEVELS 1-10: Beginner levels
        // ============================================

        case 1:
            // Level 1: First steps - basic enemies only
            return [
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 4),
                    spawnDelay: 1.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                )
            ]

        case 2:
            // Level 2: Introducing fast enemies
            return [
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 5),
                    spawnDelay: 1.0,
                    spawnInterval: 1.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .fast, count: 3),
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                ),
                EnemyWave(
                    enemies: [.basic, .fast, .basic],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                )
            ]

        case 3:
            // Level 3: Introducing striker and first mix
            return [
                EnemyWave(
                    enemies: [.basic, .basic, .striker, .basic],
                    spawnDelay: 1.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .fast, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                ),
                EnemyWave(
                    enemies: [.striker, .striker, .basic],
                    spawnDelay: 2.0,
                    spawnInterval: 1.4
                )
            ]

        case 4:
            // Level 4: First formations - scouts
            return [
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 4),
                    spawnDelay: 1.0,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 3),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.fast, .striker, .fast],
                    spawnDelay: 2.0,
                    spawnInterval: 1.1
                )
            ]

        case 5:
            // Level 5: Introducing heavy and zigzag
            return [
                EnemyWave(
                    enemies: [.basic, .heavy, .basic],
                    spawnDelay: 1.0,
                    spawnInterval: 1.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .zigzag, count: 3),
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: [.fast, .fast, .striker, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                ),
                EnemyWave(
                    enemies: [.heavy, .basic, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                )
            ]

        case 6:
            // Level 6: First kamikaze attack
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 4),
                    spawnDelay: 1.0,
                    spawnInterval: 0.8
                ),
                EnemyWave(
                    enemies: [.basic, .heavy, .basic, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.zigzag, .striker, .zigzag],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                )
            ]

        case 7:
            // Level 7: Introducing sniper
            return [
                EnemyWave(
                    enemies: [.fast, .fast, .striker, .fast],
                    spawnDelay: 1.0,
                    spawnInterval: 1.0
                ),
                EnemyWave(
                    enemies: [.sniper, .basic, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .line
                ),
                EnemyWave(
                    enemies: [.heavy, .zigzag, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.4
                )
            ]

        case 8:
            // Level 8: First turret
            return [
                EnemyWave(
                    enemies: [.kamikaze, .kamikaze, .kamikaze],
                    spawnDelay: 1.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.turret],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 4),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.sniper, .heavy, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: [.basic, .fast, .striker, .fast, .basic],
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                )
            ]

        case 9:
            // Level 9: First meteor swarm
            return [
                EnemyWave(
                    enemies: [.basic, .heavy, .basic, .heavy],
                    spawnDelay: 1.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 6),
                    spawnDelay: 2.0,
                    spawnInterval: 0.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 5),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.zigzag, .striker, .zigzag, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 1.1
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 2.5
                )
            ]

        case 10:
            // Level 10: First mini-boss level - mix of everything so far
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 5),
                    spawnDelay: 1.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.turret, .heavy, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 7),
                    spawnDelay: 2.0,
                    spawnInterval: 0.35
                ),
                EnemyWave(
                    enemies: [.sniper, .heavy, .sniper, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 5),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                )
            ]

        // ============================================
        // LEVELS 11-20: Advanced beginners
        // ============================================

        case 11:
            // Level 11: First flanker attack
            return [
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 4),
                    spawnDelay: 1.0,
                    spawnInterval: 0.8
                ),
                EnemyWave(
                    enemies: [.heavy, .heavy, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 5),
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.sniper, .striker, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.6
                )
            ]

        case 12:
            // Level 12: Introducing tank
            return [
                EnemyWave(
                    enemies: [.basic, .fast, .basic, .fast],
                    spawnDelay: 1.0,
                    spawnInterval: 1.1
                ),
                EnemyWave(
                    enemies: [.tank, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 5),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.zigzag, .zigzag, .striker, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                )
            ]

        case 13:
            // Level 13: First mine
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 4),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.mine, .mine],
                    spawnDelay: 2.0,
                    spawnInterval: 3.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 7),
                    spawnDelay: 2.0,
                    spawnInterval: 0.4
                ),
                EnemyWave(
                    enemies: [.turret, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.heavy, .sniper, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                )
            ]

        case 14:
            // Level 14: Elite guard formace
            return [
                EnemyWave(
                    enemies: [.kamikaze, .kamikaze, .kamikaze, .kamikaze],
                    spawnDelay: 1.0,
                    spawnInterval: 0.6
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 5),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.tank, .basic, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 5),
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.sniper, .heavy, .sniper, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.4
                )
            ]

        case 15:
            // Level 15: Bomber formace
            return [
                EnemyWave(
                    enemies: [.fast, .striker, .fast, .striker, .fast],
                    spawnDelay: 1.0,
                    spawnInterval: 0.9
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
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 8),
                    spawnDelay: 2.0,
                    spawnInterval: 0.35
                ),
                EnemyWave(
                    enemies: [.zigzag, .zigzag, .zigzag],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                )
            ]

        case 16:
            // Level 16: Turret spiral introduction
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 4),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral],
                    spawnDelay: 2.0,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: [.tank, .heavy, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 6),
                    spawnDelay: 2.0,
                    spawnInterval: 0.6
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                )
            ]

        case 17:
            // Level 17: First ghost
            return [
                EnemyWave(
                    enemies: [.ghost, .ghost],
                    spawnDelay: 1.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 5),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .line
                ),
                EnemyWave(
                    enemies: [.heavy, .heavy, .heavy, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 5),
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.striker, .zigzag, .striker, .zigzag],
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                )
            ]

        case 18:
            // Level 18: Shield enemy
            return [
                EnemyWave(
                    enemies: [.kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze],
                    spawnDelay: 1.0,
                    spawnInterval: 0.6
                ),
                EnemyWave(
                    enemies: [.shield, .shield],
                    spawnDelay: 2.0,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 5),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.turret, .turret, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                ),
                EnemyWave(
                    enemies: [.sniper, .heavy, .sniper, .heavy, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                )
            ]

        case 19:
            // Level 19: Spinner formace
            return [
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker],
                    spawnDelay: 1.0,
                    spawnInterval: 1.1
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 9),
                    spawnDelay: 2.0,
                    spawnInterval: 0.33
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine],
                    spawnDelay: 2.5,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 6),
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                )
            ]

        case 20:
            // Level 20: Mini-boss 2 - complete challenge so far
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 6),
                    spawnDelay: 1.0,
                    spawnInterval: 0.6
                ),
                EnemyWave(
                    enemies: [.ghost, .shield, .ghost],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 6),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .heavy, .heavy],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 5),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turret, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.3
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 6),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                )
            ]

        // ============================================
        // LEVELS 21-30: Intermediate advanced
        // ============================================

        case 21:
            // Level 21: Introducing splitter
            return [
                EnemyWave(
                    enemies: [.splitter, .splitter],
                    spawnDelay: 1.0,
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
                    enemies: [.tank, .heavy, .heavy, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 6),
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.sniper, .striker, .sniper, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                )
            ]

        case 22:
            // Level 22: Commander formace
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 7),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 4),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.turret, .turret, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: [.ghost, .shield, .ghost, .shield],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.3
                )
            ]

        case 23:
            // Level 23: First laser
            return [
                EnemyWave(
                    enemies: [.laser],
                    spawnDelay: 1.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 6),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 6),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine],
                    spawnDelay: 2.5,
                    spawnInterval: 2.8
                )
            ]

        case 24:
            // Level 24: Bouncer introduction
            return [
                EnemyWave(
                    enemies: [.bouncer, .bouncer, .bouncer],
                    spawnDelay: 1.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 7),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.splitter, .ghost, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: [.heavy, .heavy, .heavy, .heavy, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                )
            ]

        case 25:
            // Level 25: Vortex introduction
            return [
                EnemyWave(
                    enemies: [.vortex],
                    spawnDelay: 1.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 8),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 5),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.tank, .sniper, .tank, .sniper],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 7),
                    spawnDelay: 2.0,
                    spawnInterval: 0.65
                ),
                EnemyWave(
                    enemies: [.shield, .shield, .shield],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                )
            ]

        case 26:
            // Level 26: Teleporter introduction
            return [
                EnemyWave(
                    enemies: [.teleporter, .teleporter],
                    spawnDelay: 1.0,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 4),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.turret, .turretSpiral, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 11),
                    spawnDelay: 2.0,
                    spawnInterval: 0.28
                ),
                EnemyWave(
                    enemies: [.ghost, .splitter, .ghost, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                )
            ]

        case 27:
            // Level 27: Mirror introduction
            return [
                EnemyWave(
                    enemies: [.mirror, .mirror],
                    spawnDelay: 1.0,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 6),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: [.laser, .laser],
                    spawnDelay: 2.5,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.bouncer, .bouncer, .bouncer, .bouncer],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                )
            ]

        case 28:
            // Level 28: Intensive mix of special enemies
            return [
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .teleporter],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 8),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.vortex, .vortex],
                    spawnDelay: 2.5,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 9),
                    spawnDelay: 2.0,
                    spawnInterval: 0.45
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.4
                )
            ]

        case 29:
            // Level 29: Complex formations and special attacks
            return [
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 5),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.mirror, .laser, .mirror],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 4),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 12),
                    spawnDelay: 2.0,
                    spawnInterval: 0.26
                ),
                EnemyWave(
                    enemies: [.bouncer, .teleporter, .bouncer, .teleporter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 8),
                    spawnDelay: 2.0,
                    spawnInterval: 0.6
                )
            ]

        case 30:
            // Level 30: Mini-boss 3 - all special enemies
            return [
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror],
                    spawnDelay: 1.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 6),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 8),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank],
                    spawnDelay: 3.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 5),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 4),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 2.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 13),
                    spawnDelay: 2.0,
                    spawnInterval: 0.25
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 2.3
                )
            ]

        // ============================================
        // LEVELS 31-40: Advanced
        // ============================================

        case 31:
            // Level 31: Intensive tanks and shields
            return [
                EnemyWave(
                    enemies: [.tank, .shield, .tank, .shield, .tank],
                    spawnDelay: 1.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 7),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.vortex, .laser, .vortex],
                    spawnDelay: 2.5,
                    spawnInterval: 2.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 14),
                    spawnDelay: 2.0,
                    spawnInterval: 0.24
                )
            ]

        case 32:
            // Level 32: Teleporters and ghosts chaos
            return [
                EnemyWave(
                    enemies: [.teleporter, .ghost, .teleporter, .ghost, .teleporter],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 8),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                ),
                EnemyWave(
                    enemies: [.splitter, .splitter, .splitter, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 9),
                    spawnDelay: 2.0,
                    spawnInterval: 0.55
                )
            ]

        case 33:
            // Level 33: Lasery a mirrors kombinace
            return [
                EnemyWave(
                    enemies: [.laser, .mirror, .laser, .mirror],
                    spawnDelay: 1.0,
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 5),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.9
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 6),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 2.2
                )
            ]

        case 34:
            // Level 34: Bouncers a vortex mayhem
            return [
                EnemyWave(
                    enemies: [.bouncer, .vortex, .bouncer, .vortex, .bouncer],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 7),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 11),
                    spawnDelay: 2.0,
                    spawnInterval: 0.38
                ),
                EnemyWave(
                    enemies: [.shield, .shield, .shield, .shield],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                )
            ]

        case 35:
            // Level 35: Massive formation attack
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 5),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 9),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 7),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 6),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 5),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.9
                )
            ]

        case 36:
            // Level 36: All special types at once
            return [
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer],
                    spawnDelay: 1.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: [.vortex, .teleporter, .mirror, .ghost, .shield],
                    spawnDelay: 2.0,
                    spawnInterval: 1.6
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 15),
                    spawnDelay: 2.0,
                    spawnInterval: 0.23
                ),
                EnemyWave(
                    enemies: [.splitter, .splitter, .splitter, .splitter, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.7
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5
                )
            ]

        case 37:
            // Level 37: Tank army
            return [
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 12),
                    spawnDelay: 2.0,
                    spawnInterval: 0.36
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 9),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.laser, .vortex, .laser, .vortex, .laser],
                    spawnDelay: 2.5,
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 2.0
                )
            ]

        case 38:
            // Level 38: Chaos of all types
            return [
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank],
                    spawnDelay: 1.0,
                    spawnInterval: 0.9
                ),
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 7),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 5),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 16),
                    spawnDelay: 2.0,
                    spawnInterval: 0.22
                )
            ]

        case 39:
            // Level 39: Extreme formation battle
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 5),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 8),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 7),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 6),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 8),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                )
            ]

        case 40:
            // Level 40: Mini-boss 4 - ultimate challenge before finale
            return [
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror],
                    spawnDelay: 1.0,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.7
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 10),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 6),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 1.9
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 13),
                    spawnDelay: 2.0,
                    spawnInterval: 0.35
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 17),
                    spawnDelay: 2.0,
                    spawnInterval: 0.21
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 7),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.laser, .vortex, .mirror, .laser, .vortex, .mirror],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 1.9
                )
            ]

        // ============================================
        // LEVELS 41-50: Expert and final challenges
        // ============================================

        case 41:
            // Level 41: Expert beginning - massive attack
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 14),
                    spawnDelay: 1.0,
                    spawnInterval: 0.33
                ),
                EnemyWave(
                    enemies: [.tank, .shield, .tank, .shield, .tank, .shield],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 8),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 18),
                    spawnDelay: 2.0,
                    spawnInterval: 0.2
                ),
                EnemyWave(
                    enemies: [.vortex, .laser, .vortex, .laser, .vortex],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                )
            ]

        case 42:
            // Level 42: Splitter apokalypsa
            return [
                EnemyWave(
                    enemies: [.splitter, .splitter, .splitter, .splitter, .splitter, .splitter],
                    spawnDelay: 1.0,
                    spawnInterval: 1.6
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 10),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 11),
                    spawnDelay: 2.0,
                    spawnInterval: 0.48
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 1.8
                )
            ]

        case 43:
            // Level 43: All formations at once
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 6),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 8),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 10),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 8),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 7),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 6),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                )
            ]

        case 44:
            // Level 44: Bouncer a mirror kombinace
            return [
                EnemyWave(
                    enemies: [.bouncer, .mirror, .bouncer, .mirror, .bouncer, .mirror, .bouncer],
                    spawnDelay: 1.0,
                    spawnInterval: 1.4
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.6
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 15),
                    spawnDelay: 2.0,
                    spawnInterval: 0.32
                ),
                EnemyWave(
                    enemies: [.laser, .vortex, .laser, .vortex, .laser, .vortex],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 19),
                    spawnDelay: 2.0,
                    spawnInterval: 0.19
                )
            ]

        case 45:
            // Level 45: Teleporter mayhem
            return [
                EnemyWave(
                    enemies: [.teleporter, .teleporter, .teleporter, .teleporter, .teleporter, .teleporter],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 6),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.ghost, .ghost, .ghost, .ghost, .ghost, .ghost],
                    spawnDelay: 2.0,
                    spawnInterval: 1.6
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: [.shield, .shield, .shield, .shield, .shield, .shield],
                    spawnDelay: 2.5,
                    spawnInterval: 1.9
                )
            ]

        case 46:
            // Level 46: Vortex a laser devastace
            return [
                EnemyWave(
                    enemies: [.vortex, .vortex, .vortex, .vortex],
                    spawnDelay: 1.0,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.laser, .laser, .laser, .laser],
                    spawnDelay: 2.5,
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 11),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 12),
                    spawnDelay: 2.0,
                    spawnInterval: 0.45
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 1.7
                )
            ]

        case 47:
            // Level 47: Complete chaos of all types
            return [
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank],
                    spawnDelay: 1.0,
                    spawnInterval: 0.8
                ),
                EnemyWave(
                    enemies: [.turret, .turretSpiral, .mine, .ghost, .shield, .splitter, .laser, .bouncer],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: [.vortex, .teleporter, .mirror, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 9),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 7),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 16),
                    spawnDelay: 2.0,
                    spawnInterval: 0.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 20),
                    spawnDelay: 2.0,
                    spawnInterval: 0.18
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 13),
                    spawnDelay: 2.0,
                    spawnInterval: 0.43
                )
            ]

        case 48:
            // Level 48: Pre-final hell
            return [
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror],
                    spawnDelay: 1.0,
                    spawnInterval: 1.1
                ),
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror],
                    spawnDelay: 2.0,
                    spawnInterval: 1.1
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 12),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 8),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 1.7
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 17),
                    spawnDelay: 2.0,
                    spawnInterval: 0.29
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 1.6
                )
            ]

        case 49:
            // Level 49: Last test before finale
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 6),
                    spawnDelay: 0.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 9),
                    spawnDelay: 1.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 12),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 9),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 8),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 7),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: [.laser, .vortex, .mirror, .laser, .vortex, .mirror, .laser, .vortex],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: [.ghost, .teleporter, .shield, .splitter, .bouncer, .ghost, .teleporter, .shield],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 21),
                    spawnDelay: 2.0,
                    spawnInterval: 0.17
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 18),
                    spawnDelay: 1.5,
                    spawnInterval: 0.28
                )
            ]

        case 50:
            // Level 50: FINAL BOSS LEVEL - Ultimate challenge
            return [
                // Wave 1: Quick warm-up
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank],
                    spawnDelay: 0.5,
                    spawnInterval: 0.7
                ),
                // Wave 2: Special enemies
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror],
                    spawnDelay: 1.5,
                    spawnInterval: 1.0
                ),
                // Wave 3: Tank army
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.4
                ),
                // Wave 4: Scout formation
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 7),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                // Wave 5: Formation mix
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 10),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                // Wave 6: Bomber army
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 13),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                // Wave 7: Elite Guard elite
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 10),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                // Wave 8: Spinner vortex
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 9),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                // Wave 9: Commander peak
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 8),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                // Wave 10: Turret hell
                EnemyWave(
                    enemies: [.turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 1.6
                ),
                // Wave 11: Kamikaze wave
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 20),
                    spawnDelay: 2.0,
                    spawnInterval: 0.26
                ),
                // Wave 12: Meteor storm
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 23),
                    spawnDelay: 2.0,
                    spawnInterval: 0.16
                ),
                // Wave 13: Flanker attack
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 15),
                    spawnDelay: 2.0,
                    spawnInterval: 0.4
                ),
                // Wave 14: Mine field
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 1.5
                ),
                // Wave 15: Special mix finale
                EnemyWave(
                    enemies: [.laser, .vortex, .mirror, .laser, .vortex, .mirror, .laser, .vortex, .mirror],
                    spawnDelay: 2.5,
                    spawnInterval: 1.7
                ),
                // Wave 16: Ghost and Teleporter chaos
                EnemyWave(
                    enemies: [.ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                // Wave 17: Shield and Splitter
                EnemyWave(
                    enemies: [.shield, .splitter, .shield, .splitter, .shield, .splitter, .shield, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                // Wave 18: Bouncer mayhem
                EnemyWave(
                    enemies: [.bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                ),
                // Wave 19: Sniper elite
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                // Wave 20: FINAL ATTACK - all at once
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank,
                             .turret, .turretSpiral, .mine, .ghost, .shield, .splitter, .laser, .bouncer,
                             .vortex, .teleporter, .mirror],
                    spawnDelay: 2.5,
                    spawnInterval: 0.65
                )
            ]

        default:
            // Fallback for other levels - basic enemies
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
        // Progressive difficulty increase for obstacles by level
        switch level {
        case 1...5:
            // Basic levels - only basic walls
            return [
                ObstacleWave(
                    obstacles: [.wall, .wall],
                    spawnDelay: TimeInterval(level) * 2.0,
                    spawnInterval: 3.0,
                    minSpacing: 150
                )
            ]

        case 6...10:
            // Adding horizontal walls
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall, .wall],
                    spawnDelay: 3.0,
                    spawnInterval: 2.8,
                    minSpacing: 140
                )
            ]

        case 11...15:
            // Rotating obstacles
            return [
                ObstacleWave(
                    obstacles: [.wall, .rotatingBar, .horizontalWall],
                    spawnDelay: 2.5,
                    spawnInterval: 2.6,
                    minSpacing: 130
                ),
                ObstacleWave(
                    obstacles: [.movingWall, .movingWall],
                    spawnDelay: 3.0,
                    spawnInterval: 3.0,
                    minSpacing: 150
                )
            ]

        case 16...20:
            // Spinners and more complex obstacles
            return [
                ObstacleWave(
                    obstacles: [.rotatingBar, .spinner, .rotatingBar],
                    spawnDelay: 2.0,
                    spawnInterval: 2.5,
                    minSpacing: 120
                ),
                ObstacleWave(
                    obstacles: [.movingWall, .horizontalWall, .movingWall],
                    spawnDelay: 2.5,
                    spawnInterval: 2.7,
                    minSpacing: 130
                )
            ]

        case 21...25:
            // New special obstacles
            return [
                ObstacleWave(
                    obstacles: [.pulsatingRing, .zigzagWall, .pulsatingRing],
                    spawnDelay: 2.0,
                    spawnInterval: 2.4,
                    minSpacing: 120
                ),
                ObstacleWave(
                    obstacles: [.spinner, .rotatingBar, .spinner],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5,
                    minSpacing: 125
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall],
                    spawnDelay: 3.0,
                    spawnInterval: 4.0,
                    minSpacing: 200
                )
            ]

        case 26...30:
            // Advanced obstacles
            return [
                ObstacleWave(
                    obstacles: [.spiralBlade, .waveWall, .spiralBlade],
                    spawnDelay: 1.8,
                    spawnInterval: 2.3,
                    minSpacing: 115
                ),
                ObstacleWave(
                    obstacles: [.triangleBarrier, .hexagonTrap, .triangleBarrier],
                    spawnDelay: 2.2,
                    spawnInterval: 2.4,
                    minSpacing: 120
                ),
                ObstacleWave(
                    obstacles: [.pulsatingRing, .pulsatingRing],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5,
                    minSpacing: 130
                )
            ]

        case 31...35:
            // Intensive obstacle mix
            return [
                ObstacleWave(
                    obstacles: [.spiralBlade, .spinner, .waveWall, .zigzagWall],
                    spawnDelay: 1.5,
                    spawnInterval: 2.2,
                    minSpacing: 110
                ),
                ObstacleWave(
                    obstacles: [.hexagonTrap, .triangleBarrier, .pulsatingRing],
                    spawnDelay: 2.0,
                    spawnInterval: 2.3,
                    minSpacing: 115
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .destructibleWall],
                    spawnDelay: 2.5,
                    spawnInterval: 3.5,
                    minSpacing: 180
                )
            ]

        case 36...40:
            // Advanced patterns
            return [
                ObstacleWave(
                    obstacles: [.spiralBlade, .spiralBlade, .spiralBlade],
                    spawnDelay: 1.5,
                    spawnInterval: 2.1,
                    minSpacing: 105
                ),
                ObstacleWave(
                    obstacles: [.hexagonTrap, .pulsatingRing, .triangleBarrier, .waveWall],
                    spawnDelay: 1.8,
                    spawnInterval: 2.2,
                    minSpacing: 110
                ),
                ObstacleWave(
                    obstacles: [.spinner, .spinner, .spinner],
                    spawnDelay: 2.2,
                    spawnInterval: 2.3,
                    minSpacing: 115
                )
            ]

        case 41...45:
            // Expert obstacles
            return [
                ObstacleWave(
                    obstacles: [.spiralBlade, .hexagonTrap, .spiralBlade, .triangleBarrier],
                    spawnDelay: 1.3,
                    spawnInterval: 2.0,
                    minSpacing: 100
                ),
                ObstacleWave(
                    obstacles: [.pulsatingRing, .waveWall, .zigzagWall, .pulsatingRing],
                    spawnDelay: 1.6,
                    spawnInterval: 2.1,
                    minSpacing: 105
                ),
                ObstacleWave(
                    obstacles: [.spinner, .rotatingBar, .spinner, .rotatingBar],
                    spawnDelay: 2.0,
                    spawnInterval: 2.2,
                    minSpacing: 110
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .destructibleWall, .destructibleWall],
                    spawnDelay: 2.5,
                    spawnInterval: 3.0,
                    minSpacing: 160
                )
            ]

        case 46...49:
            // Pre-final hell
            return [
                ObstacleWave(
                    obstacles: [.spiralBlade, .hexagonTrap, .pulsatingRing, .triangleBarrier, .waveWall],
                    spawnDelay: 1.2,
                    spawnInterval: 1.9,
                    minSpacing: 95
                ),
                ObstacleWave(
                    obstacles: [.spinner, .spinner, .spinner, .spinner],
                    spawnDelay: 1.5,
                    spawnInterval: 2.0,
                    minSpacing: 100
                ),
                ObstacleWave(
                    obstacles: [.zigzagWall, .waveWall, .movingWall, .zigzagWall],
                    spawnDelay: 1.8,
                    spawnInterval: 2.1,
                    minSpacing: 105
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall],
                    spawnDelay: 2.2,
                    spawnInterval: 2.8,
                    minSpacing: 150
                )
            ]

        case 50:
            // Final level - all obstacles
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall, .rotatingBar, .movingWall],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8,
                    minSpacing: 90
                ),
                ObstacleWave(
                    obstacles: [.spinner, .pulsatingRing, .zigzagWall, .spiralBlade],
                    spawnDelay: 1.5,
                    spawnInterval: 1.9,
                    minSpacing: 95
                ),
                ObstacleWave(
                    obstacles: [.waveWall, .triangleBarrier, .hexagonTrap],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0,
                    minSpacing: 100
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5,
                    minSpacing: 140
                ),
                ObstacleWave(
                    obstacles: [.spiralBlade, .hexagonTrap, .pulsatingRing, .spinner],
                    spawnDelay: 3.0,
                    spawnInterval: 1.9,
                    minSpacing: 95
                )
            ]

        default:
            return []
        }
    }

    // Define power-up configuration for each level
    private func getPowerUpConfigForLevel(_ level: Int) -> PowerUpSpawnConfig {
        // Progressive power-up frequency increase
        let baseInterval: TimeInterval
        let baseProbability: Double

        switch level {
        case 1...10:
            baseInterval = 15.0  // Frequent power-ups for beginners
            baseProbability = 0.7
        case 11...20:
            baseInterval = 18.0
            baseProbability = 0.65
        case 21...30:
            baseInterval = 20.0
            baseProbability = 0.6
        case 31...40:
            baseInterval = 22.0
            baseProbability = 0.55
        case 41...49:
            baseInterval = 25.0
            baseProbability = 0.5
        case 50:
            baseInterval = 12.0  // Lots of power-ups for finale
            baseProbability = 0.8
        default:
            baseInterval = 20.0
            baseProbability = 0.6
        }

        return PowerUpSpawnConfig(
            spawnInterval: baseInterval,
            spawnProbability: baseProbability,
            typeWeights: [
                .shield: 1.0,
                .multiShot: 1.0,
                .rapidFire: 1.0,
                .extraLife: 1.0
            ]
        )
    }

    // Define asteroid waves for each level
    private func getAsteroidWavesForLevel(_ level: Int) -> [AsteroidWave] {
        switch level {
        case 1...5:
            // Basic asteroids
            return [
                AsteroidWave(
                    count: 2,
                    size: .small,
                    spawnDelay: TimeInterval(level) * 2.0,
                    spawnInterval: 2.5
                )
            ]

        case 6...10:
            // More asteroids
            return [
                AsteroidWave(
                    count: 3,
                    size: .small,
                    spawnDelay: 2.0,
                    spawnInterval: 2.2
                ),
                AsteroidWave(
                    count: 2,
                    size: .medium,
                    spawnDelay: 3.0,
                    spawnInterval: 2.5
                )
            ]

        case 11...15:
            // Medium asteroids
            return [
                AsteroidWave(
                    count: 3,
                    size: .medium,
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                AsteroidWave(
                    count: 4,
                    size: .small,
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                )
            ]

        case 16...20:
            // First large asteroids
            return [
                AsteroidWave(
                    count: 2,
                    size: .large,
                    spawnDelay: 2.0,
                    spawnInterval: 3.0
                ),
                AsteroidWave(
                    count: 3,
                    size: .medium,
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                AsteroidWave(
                    count: 4,
                    size: .small,
                    spawnDelay: 3.0,
                    spawnInterval: 1.6
                )
            ]

        case 21...25:
            // Size mix
            return [
                AsteroidWave(
                    count: 3,
                    size: .large,
                    spawnDelay: 1.8,
                    spawnInterval: 2.8
                ),
                AsteroidWave(
                    count: 4,
                    size: .medium,
                    spawnDelay: 2.2,
                    spawnInterval: 1.9
                ),
                AsteroidWave(
                    count: 5,
                    size: .small,
                    spawnDelay: 2.6,
                    spawnInterval: 1.5
                )
            ]

        case 26...30:
            // More large asteroids
            return [
                AsteroidWave(
                    count: 4,
                    size: .large,
                    spawnDelay: 1.6,
                    spawnInterval: 2.6
                ),
                AsteroidWave(
                    count: 5,
                    size: .medium,
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                ),
                AsteroidWave(
                    count: 6,
                    size: .small,
                    spawnDelay: 2.4,
                    spawnInterval: 1.4
                )
            ]

        case 31...35:
            // Intensive asteroid field
            return [
                AsteroidWave(
                    count: 5,
                    size: .large,
                    spawnDelay: 1.5,
                    spawnInterval: 2.4
                ),
                AsteroidWave(
                    count: 5,
                    size: .medium,
                    spawnDelay: 1.8,
                    spawnInterval: 1.7
                ),
                AsteroidWave(
                    count: 6,
                    size: .small,
                    spawnDelay: 2.2,
                    spawnInterval: 1.3
                )
            ]

        case 36...40:
            // Dense field
            return [
                AsteroidWave(
                    count: 6,
                    size: .large,
                    spawnDelay: 1.4,
                    spawnInterval: 2.2
                ),
                AsteroidWave(
                    count: 6,
                    size: .medium,
                    spawnDelay: 1.7,
                    spawnInterval: 1.6
                ),
                AsteroidWave(
                    count: 7,
                    size: .small,
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                )
            ]

        case 41...45:
            // Extreme density
            return [
                AsteroidWave(
                    count: 7,
                    size: .large,
                    spawnDelay: 1.3,
                    spawnInterval: 2.0
                ),
                AsteroidWave(
                    count: 7,
                    size: .medium,
                    spawnDelay: 1.6,
                    spawnInterval: 1.5
                ),
                AsteroidWave(
                    count: 8,
                    size: .small,
                    spawnDelay: 1.9,
                    spawnInterval: 1.1
                )
            ]

        case 46...49:
            // Pre-final storm
            return [
                AsteroidWave(
                    count: 8,
                    size: .large,
                    spawnDelay: 1.2,
                    spawnInterval: 1.9
                ),
                AsteroidWave(
                    count: 8,
                    size: .medium,
                    spawnDelay: 1.5,
                    spawnInterval: 1.4
                ),
                AsteroidWave(
                    count: 9,
                    size: .small,
                    spawnDelay: 1.8,
                    spawnInterval: 1.0
                )
            ]

        case 50:
            // Final asteroid storm
            return [
                AsteroidWave(
                    count: 10,
                    size: .large,
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                AsteroidWave(
                    count: 10,
                    size: .medium,
                    spawnDelay: 1.3,
                    spawnInterval: 1.3
                ),
                AsteroidWave(
                    count: 10,
                    size: .small,
                    spawnDelay: 1.6,
                    spawnInterval: 0.9
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
