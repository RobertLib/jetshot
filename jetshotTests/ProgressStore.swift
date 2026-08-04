//
//  ProgressStore.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// The four keys that hold everything persisted about a player's progress.
private let progressKeys = [
    CloudStorageManager.Keys.completedLevels,
    CloudStorageManager.Keys.levelScores,
    CloudStorageManager.Keys.levelStars,
    CloudStorageManager.Keys.levelWeapons
]

/// Runs `body` against a wiped progress store, then puts back whatever was there before.
///
/// Progress lives in `UserDefaults` (mirrored to iCloud), which is process-wide and
/// survives the test run — so a test that just called `resetProgress()` would silently
/// delete whatever the developer had played to in the simulator, and tests would also
/// leak state into each other in whatever order they happened to run.
///
/// `hasSeenOpeningStory` is restored too: `resetProgress()` deliberately clears it so a
/// reset replays the intro, which would otherwise come back on the next manual launch.
@MainActor
func withCleanProgress(_ body: () -> Void) {
    var snapshot: [String: Any] = [:]
    for key in progressKeys {
        if let value = UserDefaults.standard.object(forKey: key) {
            snapshot[key] = value
        }
    }
    let hadSeenStory = LevelManager.shared.hasSeenOpeningStory

    LevelManager.shared.resetProgress()

    defer {
        LevelManager.shared.resetProgress()
        for (key, value) in snapshot {
            UserDefaults.standard.set(value, forKey: key)
        }
        LevelManager.shared.hasSeenOpeningStory = hadSeenStory
    }

    body()
}

/// The raw completed-levels array, for assertions that care about duplicates rather than
/// membership — which `isLevelCompleted` cannot distinguish.
@MainActor
func storedCompletedLevels() -> [Int] {
    return CloudStorageManager.shared.loadArray(
        forKey: CloudStorageManager.Keys.completedLevels
    ) as? [Int] ?? []
}
