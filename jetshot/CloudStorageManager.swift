//
//  CloudStorageManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 01.11.2025.
//

import Foundation

/// Manages iCloud key-value storage for game progress synchronization.
/// Handles level completion, scores, and star ratings across devices.
/// Ensures game progress persists across app reinstalls and devices.
///
/// Explicitly `nonisolated`, because this type genuinely does not live on the main
/// actor: the merge runs on `queue`, and the change notification from iCloud can
/// arrive on any thread. The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// which would otherwise infer `@MainActor` for the whole class — a claim the code then
/// broke on every merge.
///
/// Every **mutation** goes through the single serial `queue`. That is what makes the
/// read-modify-write patterns in `LevelManager` safe: `mutate(array:)` and
/// `mutate(dictionary:)` run the caller's transform *inside* the same serial queue as
/// the merge, so the two can no longer interleave. They used to be separate steps on
/// separate threads — `loadArray()` on the main thread, then `saveArray()` — while the
/// merge read and rewrote the same key on `mergeQueue`. That lost progress: the merge
/// could read `[1,2,3,4]`, the player could finish level 5 and save `[1,2,3,4,5]`, and
/// the merge would then write its stale union back over the top.
///
/// Plain reads (`loadArray`, `loadDictionary`) deliberately bypass the queue and hit
/// `UserDefaults` directly — see `loadArray(forKey:)` for the argument.
///
/// `@unchecked Sendable` rather than plain `Sendable`, because the safety argument is
/// one the compiler cannot check: every stored property is either a `let` (`cloudStore`,
/// `userDefaults`, `queue`) or is only touched on `queue` (`isMerging`,
/// `flushScheduled`).
nonisolated final class CloudStorageManager: @unchecked Sendable {
    static let shared = CloudStorageManager()

    // MARK: - Properties
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let userDefaults = UserDefaults.standard

    /// The one serial queue every read and write is funnelled through, so that a
    /// merge and a gameplay save can never interleave on the same key.
    private let queue = DispatchQueue(label: "com.jetshot.cloudStorage", qos: .utility)

    /// Only ever touched on `queue`, so it needs no lock of its own.
    private var isMerging = false

    /// Set while a coalesced flush is already pending. Only touched on `queue`.
    private var flushScheduled = false

    /// How long a write waits for other writes to join it before the store is flushed.
    private let flushDelay: TimeInterval = 1.0

    // MARK: - Keys
    //
    // These four are the whole store. A `lastSyncDate` key used to sit here too, which
    // nothing ever read or wrote — `resetProgress()` does not clear it either, so it was
    // never a key at all, just a name.
    struct Keys {
        static let completedLevels = "completedLevels"
        static let levelScores = "levelScores"
        static let levelStars = "levelStars"
        static let levelWeapons = "levelWeapons"
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

        // Merge cloud data with local data on first launch.
        // Runs on the queue rather than inline: this is reached from
        // AppDelegate.didFinishLaunching, and the merge touches iCloud plus four
        // UserDefaults collections — no reason to hold up the first frame for it.
        queue.async { [weak self] in
            self?.mergeCloudDataWithLocal()
        }
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
            // Use the dedicated serial queue to prevent race conditions
            queue.async { [weak self] in
                self?.mergeCloudDataWithLocal()
            }
        }
    }

    /// Merge cloud data with local data, keeping the best progress.
    ///
    /// Must only be called on `queue`.
    ///
    /// There is deliberately no `isCloudAvailable()` gate. With no iCloud account the
    /// cloud side simply reads back empty, so every `merged` value collapses to the
    /// local one and the writes are no-ops — whereas the gate used to skip the merge
    /// entirely on any device with iCloud Drive switched off, which is not the same
    /// question as whether the key-value store works.
    private func mergeCloudDataWithLocal() {
        // Re-entrancy guard. `isMerging` is only read and written here, on `queue`.
        if isMerging { return }
        isMerging = true
        defer { isMerging = false }

        // Set when any collection had to be written back up to iCloud, so the whole
        // merge needs only a single synchronize() at the end.
        var didPushToCloud = false

        // Completed levels: union of both sides.
        let cloudLevels = cloudStore.array(forKey: Keys.completedLevels) as? [Int] ?? []
        let localLevels = userDefaults.array(forKey: Keys.completedLevels) as? [Int] ?? []
        didPushToCloud = propagate(
            Array(Set(cloudLevels + localLevels)).sorted(),
            local: localLevels,
            cloud: cloudLevels.sorted(),
            forKey: Keys.completedLevels,
            label: "completed levels"
        ) || didPushToCloud

        // Scores and stars: element-wise max per level.
        for key in [Keys.levelScores, Keys.levelStars] {
            let cloud = cloudStore.dictionary(forKey: key) as? [String: Int] ?? [:]
            let local = userDefaults.dictionary(forKey: key) as? [String: Int] ?? [:]
            var merged: [String: Int] = [:]
            for level in Set(cloud.keys).union(local.keys) {
                merged[level] = max(cloud[level] ?? 0, local[level] ?? 0)
            }
            didPushToCloud = propagate(
                merged, local: local, cloud: cloud, forKey: key, label: key
            ) || didPushToCloud
        }

        // Weapons: element-wise max of each arsenal slot.
        let cloudWeapons = cloudStore.dictionary(forKey: Keys.levelWeapons) as? [String: [String: Int]] ?? [:]
        let localWeapons = userDefaults.dictionary(forKey: Keys.levelWeapons) as? [String: [String: Int]] ?? [:]
        var mergedWeapons: [String: [String: Int]] = [:]
        for level in Set(cloudWeapons.keys).union(localWeapons.keys) {
            let cloud = cloudWeapons[level] ?? [:]
            let local = localWeapons[level] ?? [:]
            mergedWeapons[level] = [
                "bulletCount": max(cloud["bulletCount"] ?? 1, local["bulletCount"] ?? 1),
                "sideMissileCount": max(cloud["sideMissileCount"] ?? 0, local["sideMissileCount"] ?? 0)
            ]
        }
        didPushToCloud = propagate(
            mergedWeapons,
            local: localWeapons,
            cloud: cloudWeapons,
            forKey: Keys.levelWeapons,
            label: "level weapons"
        ) || didPushToCloud

        userDefaults.synchronize()

        // The merge is deliberately bidirectional. Before writes became unconditional
        // (see `write(array:forKey:)`), a level finished while signed out of iCloud
        // existed *only* in UserDefaults, and a cloud -> local merge alone meant that
        // progress was never uploaded and simply vanished when the player moved to
        // another device. Because `merged` is the union / element-wise max of both
        // sides, pushing it back up can only ever add progress — so this stays as a
        // repair path for records written before the account was attached.
        if didPushToCloud {
            #if DEBUG
            print("☁️ Pushed merged local progress up to iCloud")
            #endif
            flush()
        }
    }

    /// Writes a merged value to whichever side is out of date.
    ///
    /// Comparison is on *contents*, not on key counts: another device improving a
    /// value for a level both sides already know about leaves the count unchanged, and
    /// a count-based check used to throw that merge away.
    ///
    /// - Returns: `true` if the cloud side needed updating.
    private func propagate<T: Equatable>(
        _ merged: T,
        local: T,
        cloud: T,
        forKey key: String,
        label: String
    ) -> Bool {
        if merged != local {
            userDefaults.set(merged, forKey: key)
            #if DEBUG
            print("☁️ Merged \(label) from iCloud")
            #endif
        }
        guard merged != cloud else { return false }
        cloudStore.set(merged, forKey: key)
        return true
    }

    // MARK: - Atomic Access

    /// Reads, transforms and writes one stored array as a single serial operation.
    ///
    /// The transform runs on `queue`, the same queue the merge runs on, so a merge
    /// cannot slip between the read and the write. Callers must not call back into
    /// this type from inside `transform` — it would deadlock on the serial queue.
    ///
    /// `sync` rather than `async` on purpose: callers read the value straight back and
    /// have to see the write. `ProgressPersistenceTests` asserts on `isLevelCompleted`
    /// on the line after `completeLevel`, and `LevelCompleteScene` reads back the
    /// arsenal it just saved via `getLevelWeapons` when the player advances. Since the
    /// reads bypass `queue` entirely (see `loadArray(forKey:)`), only a synchronous write
    /// orders them correctly. What the caller does *not* wait for is the flush — see
    /// `scheduleFlush()`.
    func mutate(array key: String, _ transform: ([Any]) -> [Any]) {
        queue.sync {
            let current = userDefaults.array(forKey: key) ?? []
            let updated = transform(current)
            write(array: updated, forKey: key)
            scheduleFlush()
        }
    }

    /// Reads, transforms and writes one stored dictionary as a single serial operation.
    /// See `mutate(array:_:)` for the ordering guarantee and the deadlock caveat.
    func mutate(dictionary key: String, _ transform: ([String: Any]) -> [String: Any]) {
        queue.sync {
            let current = userDefaults.dictionary(forKey: key) ?? [:]
            let updated = transform(current)
            write(dictionary: updated, forKey: key)
            scheduleFlush()
        }
    }

    /// Remove a key from both local and cloud storage.
    func removeObject(forKey key: String) {
        queue.sync {
            userDefaults.removeObject(forKey: key)
            cloudStore.removeObject(forKey: key)
            scheduleFlush()
        }
    }

    // MARK: - Load Methods

    /// Load array from local storage (kept up to date by the merge).
    ///
    /// Deliberately *not* routed through `queue`. These are plain reads, and hopping onto
    /// a `.utility` serial queue to make one meant the calling thread — always the main
    /// thread in practice — blocked behind whatever else was queued, including a merge
    /// doing iCloud I/O and two `synchronize()` calls. `LevelSelectScene.loadPage` alone
    /// does two or three of these per level button, so building one page of twelve was
    /// ~30 synchronous hops onto a lower-priority queue during a scene transition.
    ///
    /// Dropping the hop is safe because the queue was never what made these correct:
    /// `UserDefaults` is documented thread-safe and its per-key writes are atomic, so a
    /// reader sees either the pre-merge or the post-merge value for a key, never a torn
    /// one. The ordering guarantee that actually matters — that a read-modify-write
    /// cannot interleave with the merge — belongs to `mutate(array:_:)` and
    /// `mutate(dictionary:_:)`, which still run their whole transform on `queue`.
    func loadArray(forKey key: String) -> [Any]? {
        return userDefaults.array(forKey: key)
    }

    /// Load dictionary from local storage (kept up to date by the merge).
    /// See `loadArray(forKey:)` for why this does not use `queue`.
    func loadDictionary(forKey key: String) -> [String: Any]? {
        return userDefaults.dictionary(forKey: key)
    }

    // MARK: - Writing

    /// Writes to both stores. Must be called on `queue`.
    ///
    /// The cloud write is unconditional. It used to be gated on `isCloudAvailable()`,
    /// which reports whether iCloud *Drive* has a signed-in identity — not whether the
    /// key-value store is usable. A player with an iCloud account but Drive switched
    /// off silently got no sync at all. Writing regardless is safe: with no account the
    /// value is simply held locally by the store and uploaded if one appears.
    private func write(array: [Any], forKey key: String) {
        userDefaults.set(array, forKey: key)
        cloudStore.set(array, forKey: key)
    }

    /// Writes to both stores. Must be called on `queue`. See `write(array:forKey:)`.
    private func write(dictionary: [String: Any], forKey key: String) {
        userDefaults.set(dictionary, forKey: key)
        cloudStore.set(dictionary, forKey: key)
    }

    // MARK: - Synchronization

    /// Queues one flush to cover a burst of writes, without the writer waiting for it.
    ///
    /// Must be called on `queue`.
    ///
    /// This used to be a *throttle* — each write called `synchronize()` inline unless
    /// one had run within the last second. That put the flush inside the writer's
    /// `queue.sync` block, so `LevelManager.completeLevel` — four `mutate` calls in a
    /// row, from the main thread, at the level-complete transition — held the main
    /// thread across a `NSUbiquitousKeyValueStore.synchronize()`. Collapsing four
    /// flushes into one did not help the frame that was waiting on the first.
    ///
    /// Debouncing instead means the writer only ever waits for two setter calls, and
    /// the four writes coalesce into a single flush that happens `flushDelay` later on
    /// the queue. Deferring it is safe: `cloudStore.set` has already recorded the value
    /// and `synchronize()` only asks for the upload to be scheduled sooner, so the worst
    /// case for an app killed inside the window is that iCloud uploads on its own
    /// schedule instead.
    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + flushDelay) { [weak self] in
            guard let self = self else { return }
            self.flushScheduled = false
            self.flush()
        }
    }

    /// Flush both stores. Must be called on `queue`.
    private func flush() {
        userDefaults.synchronize()
        cloudStore.synchronize()
    }

    /// Whether iCloud Drive has a signed-in identity.
    ///
    /// Reported for diagnostics only. It is deliberately *not* used to gate writes —
    /// see `write(array:forKey:)`.
    func isCloudAvailable() -> Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Debug

    #if DEBUG
    /// Print current cloud storage status
    func printCloudStatus() {
        print("☁️ iCloud Status:")
        print("  Available: \(isCloudAvailable())")
        print("  Completed Levels: \(cloudStore.array(forKey: Keys.completedLevels) ?? [])")
        print("  Level Scores: \(cloudStore.dictionary(forKey: Keys.levelScores) ?? [:])")
        print("  Level Stars: \(cloudStore.dictionary(forKey: Keys.levelStars) ?? [:])")
    }
    #endif
}
