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
    let totalLevels = 5

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
        // For now, all levels have same config with 60 second timer
        return LevelConfig(
            levelNumber: level,
            duration: 60.0,
            title: "Level \(level)"
        )
    }
}

// Level configuration
struct LevelConfig {
    let levelNumber: Int
    let duration: TimeInterval
    let title: String
}
