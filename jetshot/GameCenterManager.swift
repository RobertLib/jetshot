//
//  GameCenterManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 01.11.2025.
//

import GameKit
import UIKit

/// Manager for Game Center integration - leaderboards, achievements, and authentication
class GameCenterManager: NSObject {

    // MARK: - Singleton
    static let shared = GameCenterManager()

    // MARK: - Properties
    var isAuthenticated = false

    // MARK: - Leaderboard IDs
    // Note: These IDs must match the ones you create in App Store Connect
    struct LeaderboardID {
        static let totalScore = "com.robertlib.jetshot.totalscore"
        static let level1 = "com.robertlib.jetshot.level1"
        static let level2 = "com.robertlib.jetshot.level2"
        static let level3 = "com.robertlib.jetshot.level3"
        static let level4 = "com.robertlib.jetshot.level4"
        static let level5 = "com.robertlib.jetshot.level5"
        static let level6 = "com.robertlib.jetshot.level6"
        static let level7 = "com.robertlib.jetshot.level7"
        static let level8 = "com.robertlib.jetshot.level8"
        static let totalCoins = "com.robertlib.jetshot.totalcoins"
    }

    // MARK: - Achievement IDs
    // Note: These IDs must match the ones you create in App Store Connect
    struct AchievementID {
        // First steps
        static let firstFlight = "com.robertlib.jetshot.firstflight"
        static let survivorLevel1 = "com.robertlib.jetshot.survivor.level1"

        // Level completion
        static let levelMaster = "com.robertlib.jetshot.levelmaster"
        static let completedLevel3 = "com.robertlib.jetshot.completed.level3"
        static let completedLevel5 = "com.robertlib.jetshot.completed.level5"
        static let completedLevel8 = "com.robertlib.jetshot.completed.level8"

        // Coins
        static let coinCollector100 = "com.robertlib.jetshot.coins100"
        static let coinCollector500 = "com.robertlib.jetshot.coins500"
        static let coinCollector1000 = "com.robertlib.jetshot.coins1000"

        // Combat
        static let sharpshooter100 = "com.robertlib.jetshot.enemies100"
        static let sharpshooter500 = "com.robertlib.jetshot.enemies500"
        static let destroyer1000 = "com.robertlib.jetshot.enemies1000"

        // Boss achievements
        static let bossSlayer = "com.robertlib.jetshot.firstboss"
        static let ultimateChampion = "com.robertlib.jetshot.allbosses"

        // Perfect runs
        static let perfectRun = "com.robertlib.jetshot.perfectrun"
        static let untouchable = "com.robertlib.jetshot.untouchable3"

        // Power-ups
        static let powerUpMaster = "com.robertlib.jetshot.powerupmaster"
    }

    // MARK: - Local tracking (for incremental achievements)
    private let cloudStorage = CloudStorageManager.shared
    private let userDefaults = UserDefaults.standard
    private let totalCoinsKey = "gamecenter.totalcoins"
    private let totalEnemiesKey = "gamecenter.totalenemies"
    private let levelsWithoutDamageKey = "gamecenter.levelswithoutdamage"
    private let bossesDefeatedKey = "gamecenter.bossesdefeated"
    private let powerUpTypesUsedKey = "gamecenter.poweruptypesused"

    // MARK: - Initialization
    private override init() {
        super.init()
    }

    // MARK: - Authentication

    /// Authenticate the local player with Game Center
    /// Call this when the app launches (in AppDelegate or initial view controller)
    func authenticatePlayer(from viewController: UIViewController? = nil) {
        let player = GKLocalPlayer.local

        player.authenticateHandler = { [weak self] gcAuthViewController, error in
            guard let self = self else { return }

            if let gcAuthViewController = gcAuthViewController {
                // Player needs to sign in - present the Game Center view controller
                if let vc = viewController {
                    vc.present(gcAuthViewController, animated: true)
                } else {
                    // Try to get the root view controller from the active window scene
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(gcAuthViewController, animated: true)
                    }
                }
            } else if player.isAuthenticated {
                // Player is authenticated
                self.isAuthenticated = true
                print("✅ Game Center: Player authenticated - \(player.displayName)")

                // Load any cached achievements
                self.loadAchievements()
            } else {
                // Player is not authenticated (they may have cancelled)
                self.isAuthenticated = false
                if let error = error {
                    print("⚠️ Game Center: Authentication failed - \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Leaderboards

    /// Submit score to a specific leaderboard
    func submitScore(_ score: Int, to leaderboardID: String) {
        guard isAuthenticated else {
            print("⚠️ Game Center: Cannot submit score - player not authenticated")
            return
        }

        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        ) { error in
            if let error = error {
                print("❌ Game Center: Failed to submit score to \(leaderboardID) - \(error.localizedDescription)")
            } else {
                print("✅ Game Center: Score \(score) submitted to \(leaderboardID)")
            }
        }
    }

    /// Submit level score (automatically submits to both level-specific and total score leaderboards)
    func submitLevelScore(_ score: Int, level: Int) {
        // Submit to level-specific leaderboard
        let levelLeaderboardID = getLevelLeaderboardID(for: level)
        submitScore(score, to: levelLeaderboardID)

        // Submit total score (sum of all levels)
        let totalScore = LevelManager.shared.getTotalScore()
        submitScore(totalScore, to: LeaderboardID.totalScore)
    }

    /// Submit total coins collected
    func submitTotalCoins(_ coins: Int) {
        submitScore(coins, to: LeaderboardID.totalCoins)

        // Update local tracking
        cloudStorage.saveInteger(coins, forKey: totalCoinsKey)

        // Check coin achievements
        checkCoinAchievements(coins)
    }

    /// Get leaderboard ID for a specific level
    private func getLevelLeaderboardID(for level: Int) -> String {
        switch level {
        case 1: return LeaderboardID.level1
        case 2: return LeaderboardID.level2
        case 3: return LeaderboardID.level3
        case 4: return LeaderboardID.level4
        case 5: return LeaderboardID.level5
        case 6: return LeaderboardID.level6
        case 7: return LeaderboardID.level7
        case 8: return LeaderboardID.level8
        default: return LeaderboardID.totalScore
        }
    }

    /// Show the Game Center leaderboard view controller
    func showLeaderboard(from viewController: UIViewController, leaderboardID: String? = nil) {
        guard isAuthenticated else {
            print("⚠️ Game Center: Cannot show leaderboard - player not authenticated")
            return
        }

        GKAccessPoint.shared.isActive = false

        Task { @MainActor in
            do {
                if let leaderboardID = leaderboardID {
                    let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboardID])
                    if let leaderboard = leaderboards.first {
                        let vc = GKGameCenterViewController(leaderboard: leaderboard, playerScope: .global)
                        vc.gameCenterDelegate = self
                        viewController.present(vc, animated: true)
                    }
                } else {
                    let vc = GKGameCenterViewController(state: .leaderboards)
                    vc.gameCenterDelegate = self
                    viewController.present(vc, animated: true)
                }
            } catch {
                print("❌ Game Center: Failed to show leaderboard - \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Achievements

    /// Report an achievement with a specific percentage (0-100)
    func reportAchievement(_ identifier: String, percentComplete: Double = 100.0, showBanner: Bool = true) {
        guard isAuthenticated else {
            print("⚠️ Game Center: Cannot report achievement - player not authenticated")
            return
        }

        let achievement = GKAchievement(identifier: identifier)
        achievement.percentComplete = percentComplete
        achievement.showsCompletionBanner = showBanner

        GKAchievement.report([achievement]) { error in
            if let error = error {
                print("❌ Game Center: Failed to report achievement \(identifier) - \(error.localizedDescription)")
            } else {
                print("✅ Game Center: Achievement \(identifier) reported (\(percentComplete)%)")
            }
        }
    }

    /// Load current achievement progress from Game Center
    private func loadAchievements() {
        GKAchievement.loadAchievements { achievements, error in
            if let error = error {
                print("❌ Game Center: Failed to load achievements - \(error.localizedDescription)")
                return
            }

            if let achievements = achievements {
                print("✅ Game Center: Loaded \(achievements.count) achievements")
                // You can cache these if needed
            }
        }
    }

    /// Show the Game Center achievements view controller
    func showAchievements(from viewController: UIViewController) {
        guard isAuthenticated else {
            print("⚠️ Game Center: Cannot show achievements - player not authenticated")
            return
        }

        GKAccessPoint.shared.isActive = false

        Task { @MainActor in
            let vc = GKGameCenterViewController(state: .achievements)
            vc.gameCenterDelegate = self
            viewController.present(vc, animated: true)
        }
    }

    /// Reset all achievements (use only for testing!)
    func resetAchievements() {
        GKAchievement.resetAchievements { error in
            if let error = error {
                print("❌ Game Center: Failed to reset achievements - \(error.localizedDescription)")
            } else {
                print("✅ Game Center: All achievements reset")
            }
        }
    }

    // MARK: - Achievement Tracking Helpers

    /// Track level completion and check related achievements
    func trackLevelCompletion(level: Int, withPerfectHealth: Bool = false) {
        // First flight achievement
        if level == 1 {
            reportAchievement(AchievementID.firstFlight)

            if withPerfectHealth {
                reportAchievement(AchievementID.survivorLevel1)
            }
        }

        // Level milestones
        if level == 3 {
            reportAchievement(AchievementID.completedLevel3)
        }
        if level == 5 {
            reportAchievement(AchievementID.completedLevel5)
        }
        if level == 8 {
            reportAchievement(AchievementID.completedLevel8)
        }

        // Check if all levels completed
        let completedLevels = LevelManager.shared.totalLevels
        var allCompleted = true
        for i in 1...completedLevels {
            if !LevelManager.shared.isLevelCompleted(i) {
                allCompleted = false
                break
            }
        }
        if allCompleted {
            reportAchievement(AchievementID.levelMaster)
        }

        // Track levels without damage
        if withPerfectHealth {
            var levelsNoDamage = cloudStorage.loadInteger(forKey: levelsWithoutDamageKey)
            levelsNoDamage += 1
            cloudStorage.saveInteger(levelsNoDamage, forKey: levelsWithoutDamageKey)

            if levelsNoDamage >= 3 {
                reportAchievement(AchievementID.untouchable)
            }
        }
    }

    /// Track coins collected
    func trackCoinsCollected(_ amount: Int) {
        var totalCoins = cloudStorage.loadInteger(forKey: totalCoinsKey)
        totalCoins += amount
        cloudStorage.saveInteger(totalCoins, forKey: totalCoinsKey)

        checkCoinAchievements(totalCoins)

        // Also update leaderboard
        submitTotalCoins(totalCoins)
    }

    /// Check coin milestones
    private func checkCoinAchievements(_ totalCoins: Int) {
        if totalCoins >= 100 {
            reportAchievement(AchievementID.coinCollector100)
        }
        if totalCoins >= 500 {
            reportAchievement(AchievementID.coinCollector500)
        }
        if totalCoins >= 1000 {
            reportAchievement(AchievementID.coinCollector1000)
        }
    }

    /// Track enemies destroyed
    func trackEnemyDestroyed() {
        var totalEnemies = cloudStorage.loadInteger(forKey: totalEnemiesKey)
        totalEnemies += 1
        cloudStorage.saveInteger(totalEnemies, forKey: totalEnemiesKey)

        if totalEnemies >= 100 {
            reportAchievement(AchievementID.sharpshooter100)
        }
        if totalEnemies >= 500 {
            reportAchievement(AchievementID.sharpshooter500)
        }
        if totalEnemies >= 1000 {
            reportAchievement(AchievementID.destroyer1000)
        }
    }

    /// Track boss defeated
    func trackBossDefeated(isFirstBoss: Bool = false) {
        var bossesDefeated = cloudStorage.loadInteger(forKey: bossesDefeatedKey)
        bossesDefeated += 1
        cloudStorage.saveInteger(bossesDefeated, forKey: bossesDefeatedKey)

        if isFirstBoss {
            reportAchievement(AchievementID.bossSlayer)
        }

        // Assuming 8 levels = 8 bosses (or adjust based on your game)
        if bossesDefeated >= LevelManager.shared.totalLevels {
            reportAchievement(AchievementID.ultimateChampion)
        }
    }

    /// Track power-up usage by type
    func trackPowerUpUsed(type: String) {
        var powerUpTypes = cloudStorage.loadArray(forKey: powerUpTypesUsedKey) as? [String] ?? []

        if !powerUpTypes.contains(type) {
            powerUpTypes.append(type)
            cloudStorage.saveArray(powerUpTypes, forKey: powerUpTypesUsedKey)

            // Assuming 3-4 different power-up types (adjust based on your game)
            if powerUpTypes.count >= 3 {
                reportAchievement(AchievementID.powerUpMaster)
            }
        }
    }

    /// Track perfect run (level completed with maximum possible score)
    func trackPerfectRun() {
        reportAchievement(AchievementID.perfectRun)
    }

    // MARK: - Helper Methods

    /// Get total coins from local tracking
    func getTotalCoins() -> Int {
        return userDefaults.integer(forKey: totalCoinsKey)
    }

    /// Get total enemies destroyed from local tracking
    func getTotalEnemiesDestroyed() -> Int {
        return userDefaults.integer(forKey: totalEnemiesKey)
    }

    /// Reset local tracking (for testing)
    func resetLocalTracking() {
        cloudStorage.removeObject(forKey: totalCoinsKey)
        cloudStorage.removeObject(forKey: totalEnemiesKey)
        cloudStorage.removeObject(forKey: levelsWithoutDamageKey)
        cloudStorage.removeObject(forKey: bossesDefeatedKey)
        cloudStorage.removeObject(forKey: powerUpTypesUsedKey)
    }
}

// MARK: - GKGameCenterControllerDelegate

extension GameCenterManager: GKGameCenterControllerDelegate {
    @available(iOS, introduced: 14.0, deprecated: 26.0, message: "Use newer Game Center APIs when available")
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
