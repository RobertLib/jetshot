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
        static let levelStars = "levelStars"
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

        // Merge level stars (keep highest stars for each level)
        let cloudStars = cloudStore.dictionary(forKey: Keys.levelStars) as? [String: Int] ?? [:]
        let localStars = userDefaults.dictionary(forKey: Keys.levelStars) as? [String: Int] ?? [:]
        var mergedStars: [String: Int] = [:]

        let allStarLevelKeys = Set(cloudStars.keys).union(Set(localStars.keys))
        for key in allStarLevelKeys {
            let cloudStar = cloudStars[key] ?? 0
            let localStar = localStars[key] ?? 0
            mergedStars[key] = max(cloudStar, localStar)
        }

        if mergedStars != localStars {
            userDefaults.set(mergedStars, forKey: Keys.levelStars)
        }

        userDefaults.synchronize()
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
        print("  Level Stars: \(cloudStore.dictionary(forKey: Keys.levelStars) ?? [:])")
    }
}
