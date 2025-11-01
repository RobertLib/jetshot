//
//  CloudStorageManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 01.11.2025.
//

import Foundation

/// Manager for iCloud Key-Value Storage synchronization
/// Ensures game progress persists across app reinstalls and devices
class CloudStorageManager {
    static let shared = CloudStorageManager()

    // MARK: - Properties
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let userDefaults = UserDefaults.standard

    // MARK: - Keys
    struct Keys {
        static let completedLevels = "completedLevels"
        static let levelScores = "levelScores"
        static let totalCoins = "gamecenter.totalcoins"
        static let totalEnemies = "gamecenter.totalenemies"
        static let levelsWithoutDamage = "gamecenter.levelswithoutdamage"
        static let bossesDefeated = "gamecenter.bossesdefeated"
        static let powerUpTypesUsed = "gamecenter.poweruptypesused"
        static let lastSyncDate = "lastSyncDate"
    }

    // MARK: - Initialization
    private init() {
        setupCloudSync()
    }

    // MARK: - Setup

    /// Setup iCloud synchronization and listeners
    private func setupCloudSync() {
        // Listen for changes from iCloud
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )

        // Synchronize on startup
        cloudStore.synchronize()

        // Merge cloud data with local data on first launch
        mergeCloudDataWithLocal()
    }

    // MARK: - Sync Handling

    @objc private func cloudStoreDidChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonForChange = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        // Only merge on external changes (from other devices or after reinstall)
        if reasonForChange == NSUbiquitousKeyValueStoreServerChange ||
           reasonForChange == NSUbiquitousKeyValueStoreInitialSyncChange {
            mergeCloudDataWithLocal()
        }
    }

    /// Merge cloud data with local data, keeping the best progress
    private func mergeCloudDataWithLocal() {
        // Merge completed levels (union of both)
        let cloudLevels = cloudStore.array(forKey: Keys.completedLevels) as? [Int] ?? []
        let localLevels = userDefaults.array(forKey: Keys.completedLevels) as? [Int] ?? []
        let mergedLevels = Array(Set(cloudLevels + localLevels)).sorted()

        if mergedLevels != localLevels {
            userDefaults.set(mergedLevels, forKey: Keys.completedLevels)
        }

        // Merge level scores (keep highest score for each level)
        let cloudScores = cloudStore.dictionary(forKey: Keys.levelScores) as? [String: Int] ?? [:]
        let localScores = userDefaults.dictionary(forKey: Keys.levelScores) as? [String: Int] ?? [:]
        var mergedScores: [String: Int] = [:]

        let allLevelKeys = Set(cloudScores.keys).union(Set(localScores.keys))
        for key in allLevelKeys {
            let cloudScore = cloudScores[key] ?? 0
            let localScore = localScores[key] ?? 0
            mergedScores[key] = max(cloudScore, localScore)
        }

        if mergedScores != localScores {
            userDefaults.set(mergedScores, forKey: Keys.levelScores)
        }

        // Merge statistics (keep highest values)
        mergeIntValue(key: Keys.totalCoins)
        mergeIntValue(key: Keys.totalEnemies)
        mergeIntValue(key: Keys.levelsWithoutDamage)
        mergeIntValue(key: Keys.bossesDefeated)

        // Merge power-up types used (union)
        let cloudPowerUps = cloudStore.array(forKey: Keys.powerUpTypesUsed) as? [String] ?? []
        let localPowerUps = userDefaults.array(forKey: Keys.powerUpTypesUsed) as? [String] ?? []
        let mergedPowerUps = Array(Set(cloudPowerUps + localPowerUps))

        if mergedPowerUps.count != localPowerUps.count {
            userDefaults.set(mergedPowerUps, forKey: Keys.powerUpTypesUsed)
        }

        userDefaults.synchronize()
    }

    private func mergeIntValue(key: String) {
        let cloudValue = Int(cloudStore.longLong(forKey: key))
        let localValue = userDefaults.integer(forKey: key)
        let mergedValue = max(cloudValue, localValue)

        if mergedValue != localValue {
            userDefaults.set(mergedValue, forKey: key)
        }
    }

    // MARK: - Save Methods

    /// Save array to both local and cloud storage
    func saveArray(_ array: [Any], forKey key: String) {
        userDefaults.set(array, forKey: key)
        cloudStore.set(array, forKey: key)
        synchronize()
    }

    /// Save dictionary to both local and cloud storage
    func saveDictionary(_ dictionary: [String: Any], forKey key: String) {
        userDefaults.set(dictionary, forKey: key)
        cloudStore.set(dictionary, forKey: key)
        synchronize()
    }

    /// Save integer to both local and cloud storage
    func saveInteger(_ value: Int, forKey key: String) {
        userDefaults.set(value, forKey: key)
        cloudStore.set(Int64(value), forKey: key)
        synchronize()
    }

    /// Save string to both local and cloud storage
    func saveString(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
        cloudStore.set(value, forKey: key)
        synchronize()
    }

    /// Remove object from both local and cloud storage
    func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
        cloudStore.removeObject(forKey: key)
        synchronize()
    }

    // MARK: - Load Methods

    /// Load array from local storage (already synced from cloud)
    func loadArray(forKey key: String) -> [Any]? {
        return userDefaults.array(forKey: key)
    }

    /// Load dictionary from local storage (already synced from cloud)
    func loadDictionary(forKey key: String) -> [String: Any]? {
        return userDefaults.dictionary(forKey: key)
    }

    /// Load integer from local storage (already synced from cloud)
    func loadInteger(forKey key: String) -> Int {
        return userDefaults.integer(forKey: key)
    }

    /// Load string from local storage (already synced from cloud)
    func loadString(forKey key: String) -> String? {
        return userDefaults.string(forKey: key)
    }

    // MARK: - Synchronization

    /// Force synchronization with iCloud
    func synchronize() {
        userDefaults.synchronize()
        cloudStore.synchronize()
    }

    /// Check if iCloud is available
    func isCloudAvailable() -> Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Debug

    /// Print current cloud storage status
    func printCloudStatus() {
        print("☁️ iCloud Status:")
        print("  Available: \(isCloudAvailable())")
        print("  Completed Levels: \(cloudStore.array(forKey: Keys.completedLevels) ?? [])")
        print("  Level Scores: \(cloudStore.dictionary(forKey: Keys.levelScores) ?? [:])")
        print("  Total Coins: \(cloudStore.longLong(forKey: Keys.totalCoins))")
        print("  Total Enemies: \(cloudStore.longLong(forKey: Keys.totalEnemies))")
    }
}
