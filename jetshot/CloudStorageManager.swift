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
    // These are the whole store. A `lastSyncDate` key used to sit here too, which
    // nothing ever read or wrote — `resetProgress()` does not clear it either, so it was
    // never a key at all, just a name.
    struct Keys {
        static let completedLevels = "completedLevels"
        static let levelScores = "levelScores"
        static let levelStars = "levelStars"
        static let levelWeapons = "levelWeapons"

        /// The endless run's records, as `["bestScore": Int, "bestRound": Int]`.
        ///
        /// A dictionary rather than two scalars so it can ride the element-wise `max`
        /// merge below with the other `[String: Int]` collections, which is exactly the
        /// semantics a personal best wants across two devices.
        static let endlessRecords = "endlessRecords"

        /// Medals per level, as `["<level>": MedalSet.rawValue]`.
        ///
        /// Merged with a bitwise OR rather than the `max` the other per-level
        /// dictionaries use: medals are a set, not a score. Two devices that each earned
        /// a different medal on the same level hold 0b001 and 0b010, and `max` would keep
        /// only one of them.
        static let levelMedals = "levelMedals"

        /// How many times progress has been reset, as an `Int`; absent means 0.
        ///
        /// The merge below only ever adds — a union, a max, an OR — which is right for
        /// two devices playing the same save, and wrong the moment one of them resets
        /// it: the other still holds the old progress, pushes it back up on its next
        /// merge, and the reset comes undone everywhere. Every reset opens a new epoch,
        /// and the merge only unions stores that share one. See `reconcile(local:cloud:)`.
        static let progressEpoch = "progressEpoch"

        /// Every key that is the player's progress: what a reset clears, and what the
        /// merge reconciles.
        static let progress = [completedLevels, levelScores, levelStars, levelWeapons, endlessRecords, levelMedals]
    }

    // MARK: - Reconciling

    /// One store's copy of the player's progress: the value of each progress key it
    /// holds, and the reset epoch it was written under.
    struct Snapshot {
        var values: [String: Any]
        var epoch: Int
    }

    /// What both stores should hold once a merge is done.
    ///
    /// Two stores in the same epoch are two devices playing one save, so they are
    /// unioned — completed levels joined, scores, stars and endless records kept at
    /// their best, medal bits combined, each arsenal slot at its best. Two stores in
    /// different epochs are not: the newer one was reset after the older one's progress
    /// was made, so it is taken whole, keys it lacks included. A union there is exactly
    /// what used to bring a reset save back.
    ///
    /// Pure, so `ProgressEpochTests` can cover it without either real store.
    static func reconcile(local: Snapshot, cloud: Snapshot) -> Snapshot {
        if local.epoch != cloud.epoch {
            return local.epoch > cloud.epoch ? local : cloud
        }

        var merged: [String: Any] = [:]
        let l = local.values, c = cloud.values

        // A key neither side holds stays absent: there is nothing to write.
        func eitherHolds(_ key: String) -> Bool { l[key] != nil || c[key] != nil }

        // Completed levels: union of both sides.
        if eitherHolds(Keys.completedLevels) {
            let levels = (c[Keys.completedLevels] as? [Int] ?? []) + (l[Keys.completedLevels] as? [Int] ?? [])
            merged[Keys.completedLevels] = Array(Set(levels)).sorted()
        }

        // Scores, stars and endless records: element-wise max per key.
        for key in [Keys.levelScores, Keys.levelStars, Keys.endlessRecords] where eitherHolds(key) {
            let cloud = c[key] as? [String: Int] ?? [:]
            let local = l[key] as? [String: Int] ?? [:]
            merged[key] = cloud.merging(local) { max($0, $1) }
        }

        // Medals: element-wise union of the bit sets.
        if eitherHolds(Keys.levelMedals) {
            let cloud = c[Keys.levelMedals] as? [String: Int] ?? [:]
            let local = l[Keys.levelMedals] as? [String: Int] ?? [:]
            merged[Keys.levelMedals] = cloud.merging(local) { $0 | $1 }
        }

        // Weapons: element-wise max of each arsenal slot.
        if eitherHolds(Keys.levelWeapons) {
            let cloudWeapons = c[Keys.levelWeapons] as? [String: [String: Int]] ?? [:]
            let localWeapons = l[Keys.levelWeapons] as? [String: [String: Int]] ?? [:]
            var weapons: [String: [String: Int]] = [:]
            for level in Set(cloudWeapons.keys).union(localWeapons.keys) {
                let cloud = cloudWeapons[level] ?? [:]
                let local = localWeapons[level] ?? [:]
                weapons[level] = [
                    "bulletCount": max(cloud["bulletCount"] ?? 1, local["bulletCount"] ?? 1),
                    "sideMissileCount": max(cloud["sideMissileCount"] ?? 0, local["sideMissileCount"] ?? 0)
                ]
            }
            merged[Keys.levelWeapons] = weapons
        }

        return Snapshot(values: merged, epoch: local.epoch)
    }

    // MARK: - Demo Store

    #if DEBUG
    /// Progress served entirely from memory, for the App Store media pipeline.
    ///
    /// While this is non-nil the type is read-only: every read below answers out of it,
    /// and every write — `mutate`, `resetProgress`, the merge, the flush — returns
    /// without touching `UserDefaults` or `NSUbiquitousKeyValueStore`. That is not a
    /// convenience. `Tools/appstore_media.sh` launches the game with `-unlockall` more
    /// than thirty times per run, and without this the first of those launches would
    /// write a fabricated fifty-level save to disk and then push it to iCloud, where it
    /// would land on every other device signed into the same account.
    ///
    /// `nonisolated(unsafe)` on the same terms the class itself is `@unchecked
    /// Sendable`: it is assigned exactly once, from `DebugLaunch.prepare()` in
    /// `application(_:didFinishLaunchingWithOptions:)`, before `shared` has been
    /// resolved and therefore before any other thread in this type exists. Everything
    /// after that point is a read.
    nonisolated(unsafe) private static var demoStore: [String: Any]?

    /// Switches the whole type into the read-only demo mode described above.
    ///
    /// Deliberately `static`: touching an instance member here would resolve `shared`,
    /// and resolving `shared` runs `setupCloudSync()` — the very merge this is meant to
    /// get in front of.
    static func installDemoStore(_ values: [String: Any]) {
        demoStore = values
    }

    private static var isDemo: Bool { demoStore != nil }
    #else
    private static var isDemo: Bool { false }
    #endif

    // MARK: - Initialization
    private init() {
        setupCloudSync()
    }

    // MARK: - Setup

    /// Setup iCloud synchronization and listeners
    private func setupCloudSync() {
        // A demo launch neither reads iCloud nor writes it. Returning before the
        // observer is registered matters as much as returning before the merge: an
        // external change arriving mid-session would otherwise call
        // `mergeCloudDataWithLocal()` on the real stores behind the demo's back.
        guard !Self.isDemo else { return }

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

        let local = localSnapshot()
        let cloud = cloudSnapshot()
        let merged = Self.reconcile(local: local, cloud: cloud)

        for key in Keys.progress {
            didPushToCloud = propagate(
                merged.values[key], local: local.values[key], cloud: cloud.values[key],
                forKey: key, label: key
            ) || didPushToCloud
        }

        // The epoch travels with the data it describes: a side that adopted the other's
        // progress adopts its epoch too, or the next merge would see them disagree again.
        if merged.epoch != local.epoch {
            userDefaults.set(merged.epoch, forKey: Keys.progressEpoch)
        }
        if merged.epoch != cloud.epoch {
            cloudStore.set(Int64(merged.epoch), forKey: Keys.progressEpoch)
            didPushToCloud = true
        }

        userDefaults.synchronize()

        // The merge is deliberately bidirectional. Before writes became unconditional
        // (see `write(array:forKey:)`), a level finished while signed out of iCloud
        // existed *only* in UserDefaults, and a cloud -> local merge alone meant that
        // progress was never uploaded and simply vanished when the player moved to
        // another device. Within an epoch `merged` is the union / element-wise max of
        // both sides, so pushing it back up can only ever add progress — this stays as
        // a repair path for records written before the account was attached. Across
        // epochs it carries a reset made on this device up to the others.
        if didPushToCloud {
            #if DEBUG
            print("☁️ Pushed merged local progress up to iCloud")
            #endif
            flush()
        }
    }

    /// Writes a merged value to whichever side is out of date. A nil `merged` — a key
    /// the winning side of an epoch change does not hold — removes it.
    ///
    /// Comparison is on *contents*, not on key counts: another device improving a
    /// value for a level both sides already know about leaves the count unchanged, and
    /// a count-based check used to throw that merge away.
    ///
    /// - Returns: `true` if the cloud side needed updating.
    private func propagate(
        _ merged: Any?,
        local: Any?,
        cloud: Any?,
        forKey key: String,
        label: String
    ) -> Bool {
        if !Self.same(merged, local) {
            if let merged = merged {
                userDefaults.set(merged, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
            #if DEBUG
            print("☁️ Merged \(label) from iCloud")
            #endif
        }
        guard !Self.same(merged, cloud) else { return false }
        if let merged = merged {
            cloudStore.set(merged, forKey: key)
        } else {
            cloudStore.removeObject(forKey: key)
        }
        return true
    }

    /// Property-list equality: what the stores themselves would consider unchanged.
    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as AnyObject).isEqual(b)
        default: return false
        }
    }

    // MARK: - Epochs

    private var localEpoch: Int { userDefaults.integer(forKey: Keys.progressEpoch) }

    private var cloudEpoch: Int { Int(cloudStore.longLong(forKey: Keys.progressEpoch)) }

    /// Must be called on `queue`.
    private func localSnapshot() -> Snapshot {
        var values: [String: Any] = [:]
        for key in Keys.progress {
            values[key] = userDefaults.object(forKey: key)
        }
        return Snapshot(values: values, epoch: localEpoch)
    }

    /// Must be called on `queue`.
    private func cloudSnapshot() -> Snapshot {
        var values: [String: Any] = [:]
        for key in Keys.progress {
            values[key] = cloudStore.object(forKey: key)
        }
        return Snapshot(values: values, epoch: cloudEpoch)
    }

    /// Settles an epoch disagreement before a write lands on top of it. Must be called
    /// on `queue`.
    ///
    /// A device that has not yet merged another's reset still holds the old progress.
    /// Without this, its next finished level would write that whole old collection up
    /// to iCloud under the new epoch — the reset undone by an ordinary save rather than
    /// by a merge. Adopting the newer side first means the write lands on the reset.
    private func reconcileEpochsBeforeWriting() {
        guard localEpoch != cloudEpoch else { return }
        mergeCloudDataWithLocal()
    }

    /// Clears the player's progress from both stores and opens a new epoch, so no other
    /// device's copy of the old progress can merge back in. See `Keys.progressEpoch`.
    ///
    /// The new epoch is one past the higher of the two sides, so a reset made on a
    /// device that is itself behind still comes out newest.
    func resetProgress() {
        guard !Self.isDemo else { return }
        queue.sync {
            let epoch = max(localEpoch, cloudEpoch) + 1
            for key in Keys.progress {
                userDefaults.removeObject(forKey: key)
                cloudStore.removeObject(forKey: key)
            }
            userDefaults.set(epoch, forKey: Keys.progressEpoch)
            cloudStore.set(Int64(epoch), forKey: Keys.progressEpoch)
            scheduleFlush()
        }
    }

    /// The reset epoch this device's progress belongs to. Read-only, for
    /// `jetshotTests`; a plain read for the reason `loadArray(forKey:)` gives.
    var currentEpoch: Int {
        localEpoch
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
        guard !Self.isDemo else { return }
        queue.sync {
            reconcileEpochsBeforeWriting()
            let current = userDefaults.array(forKey: key) ?? []
            let updated = transform(current)
            write(array: updated, forKey: key)
            scheduleFlush()
        }
    }

    /// Reads, transforms and writes one stored dictionary as a single serial operation.
    /// See `mutate(array:_:)` for the ordering guarantee and the deadlock caveat.
    func mutate(dictionary key: String, _ transform: ([String: Any]) -> [String: Any]) {
        guard !Self.isDemo else { return }
        queue.sync {
            reconcileEpochsBeforeWriting()
            let current = userDefaults.dictionary(forKey: key) ?? [:]
            let updated = transform(current)
            write(dictionary: updated, forKey: key)
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
        #if DEBUG
        if let demo = Self.demoStore { return demo[key] as? [Any] }
        #endif
        return userDefaults.array(forKey: key)
    }

    /// Load dictionary from local storage (kept up to date by the merge).
    /// See `loadArray(forKey:)` for why this does not use `queue`.
    func loadDictionary(forKey key: String) -> [String: Any]? {
        #if DEBUG
        if let demo = Self.demoStore { return demo[key] as? [String: Any] }
        #endif
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
