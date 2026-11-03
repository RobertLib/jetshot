//
//  CloudStorageManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 01.11.2025.
//

import Foundation

extension Notification.Name {
    /// Posted on the main queue after an iCloud merge has changed this device's stored
    /// progress. Screens that summarise progress (the menu, the level select) build it
    /// once, so without this a merge that lands while one of them is on screen leaves it
    /// showing — and acting on — the pre-merge state until it is rebuilt.
    static let progressDidChange = Notification.Name("jetshot.progressDidChange")
}

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
    private let cloudStore: any ProgressKeyValueStore
    private let userDefaults: any ProgressKeyValueStore

    #if DEBUG
    /// Installed before either real store is resolved, including the startup merge.
    let testStores: (local: MemoryProgressStore, cloud: MemoryProgressStore)?
    #endif

    /// The serial queue every write and every merge is funnelled through, so that a
    /// merge and a gameplay save can never interleave on the same key. Plain reads
    /// deliberately bypass it — see `loadArray(forKey:)`.
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

        /// When the current epoch's reset happened, as seconds since 1970 (`Double`), in
        /// both stores next to `progressEpoch` and carried along whenever an epoch is
        /// adopted. Absent for epoch 0, which no reset opened, and for resets made by
        /// 1.0.8. It is what lets the merge tell a device that is merely behind on a
        /// reset from one whose progress predates it — see `reconcile(local:cloud:)`.
        ///
        /// In iCloud it carries an epoch tag like the progress keys, and only counts while
        /// that tag matches `progressEpoch`: a reset made by 1.0.8 moves the epoch on
        /// without touching this key, and the previous reset's time would otherwise pass
        /// for the new one's — dating it too early, and letting progress made between the
        /// two union back in.
        static let progressResetAt = "progressResetAt"

        /// A conservative lower bound on when this device's current progress was made,
        /// as seconds since 1970 (`Double`). Local only: it describes this device's copy,
        /// not the save, so it is never synced.
        ///
        /// Stamped by the first save to a device that holds no progress, removed by a
        /// reset, and lowered whenever a merge brings in progress from elsewhere. Absent
        /// means unknown, and unknown is treated as old — which is what every 1.0.8
        /// install's progress is.
        static let progressStartedAt = "progressStartedAt"

        /// Every key that is the player's progress: what a reset clears, and what the
        /// merge reconciles.
        static let progress = [completedLevels, levelScores, levelStars, levelWeapons, endlessRecords, levelMedals]

        /// The iCloud-only companion of a progress key: the epoch that key was last
        /// written under, as an `Int`. See `currentCloudValues(_:tags:epoch:)`.
        ///
        /// One tag per progress key, plus one for `progressResetAt`, brings iCloud to
        /// fifteen keys in all, far inside the key-value store's limit of 1024.
        static func epochTag(for key: String) -> String {
            key + ".epoch"
        }
    }

    // MARK: - Reconciling

    /// One store's copy of the player's progress: the value of each progress key it
    /// holds, the reset epoch it was written under, and when that epoch's reset happened.
    struct Snapshot {
        var values: [String: Any]
        var epoch: Int

        /// `Keys.progressResetAt`; nil when unknown.
        var resetAt: TimeInterval? = nil

        /// `Keys.progressStartedAt`, so only ever set on this device's own copy; nil
        /// when unknown. On a merge result it is the start time this device keeps.
        var startedAt: TimeInterval? = nil
    }

    /// What both stores should hold once a merge is done.
    ///
    /// Two stores in the same epoch are two devices playing one save, so they are
    /// unioned — completed levels joined, scores, stars and endless records kept at
    /// their best, medal bits combined, each arsenal slot at its best. Two stores in
    /// different epochs normally are not: the newer one was reset after the older one's
    /// progress was made, so it is taken whole, keys it lacks included. A union there is
    /// exactly what used to bring a reset save back.
    ///
    /// The exception is a device that is behind on the cloud's reset only because it
    /// had not heard of it yet — a new iPad played offline on an account that was reset
    /// months ago. Its epoch is older, but all of its progress is newer than the reset,
    /// and taking the cloud whole wiped it. So when this device's start time and the
    /// cloud epoch's reset time are both known and the start is the later of the two,
    /// the stores are unioned under the cloud's epoch instead. Either time being unknown
    /// keeps the old rule: losing progress of unknown age is the price of never undoing
    /// a reset. That covers a 1.0.8 install (no start time) and a 1.0.8 reset (no reset
    /// time) alike.
    ///
    /// Known limitation: the two times come from two devices' clocks. A skew larger
    /// than the gap between the reset and the first save on the other device can misjudge
    /// the order either way — keeping progress that predates the reset, or wiping
    /// progress that did not. That gap is normally hours or months, not minutes.
    ///
    /// Pure, so `ProgressEpochTests` can cover it without either real store.
    static func reconcile(local: Snapshot, cloud: Snapshot) -> Snapshot {
        if local.epoch == cloud.epoch {
            return union(local, cloud, epoch: cloud.epoch, resetAt: cloud.resetAt ?? local.resetAt)
        }
        if local.epoch > cloud.epoch {
            return local
        }
        if let startedAt = local.startedAt, let resetAt = cloud.resetAt, startedAt > resetAt {
            return union(local, cloud, epoch: cloud.epoch, resetAt: resetAt)
        }
        // Taken whole: everything this device now holds was made after the cloud's reset.
        return Snapshot(values: cloud.values, epoch: cloud.epoch, resetAt: cloud.resetAt, startedAt: cloud.resetAt)
    }

    /// What both stores should hold after the signed-in iCloud account changed.
    ///
    /// The cloud store now holds another Apple ID's save, whose epochs are a timeline of
    /// their own: comparing them with this device's as `reconcile` does let a higher
    /// local epoch from the previous account win whole and overwrite the new account's
    /// progress on every device. So nothing here removes anything. This device's
    /// progress is unioned into the new account's, the new account's epoch and reset
    /// time are adopted rather than pushed over, and the start time becomes unknown —
    /// the result mixes two histories.
    ///
    /// The accepted trade-off: switching accounts on one device carries that device's
    /// progress into the new account, so two Apple IDs' saves can end up mixed. The
    /// alternative is throwing one of them away.
    static func reconcileAfterAccountChange(local: Snapshot, cloud: Snapshot) -> Snapshot {
        var merged = union(local, cloud, epoch: cloud.epoch, resetAt: cloud.resetAt)
        merged.startedAt = nil
        return merged
    }

    /// The cloud's progress values with every stale write dropped.
    ///
    /// iCloud resolves conflicts per key: last writer wins. A device that has not yet
    /// received another device's reset can save after it, and its write carries the
    /// whole pre-reset collection and is newer than the reset's removal — so the server
    /// ended up holding the new epoch *and* the old progress, which every device then
    /// took for the new epoch's. Every progress key written to iCloud is therefore
    /// tagged with the epoch it was written under (`Keys.epochTag(for:)`), and a key
    /// tagged with an epoch older than the store's is such a stale write: it reads as
    /// absent, and the merge then removes it from iCloud like any other key the winning
    /// side lacks. An untagged key was written by 1.0.8 and is accepted as before.
    ///
    /// Pure, so `ProgressEpochTests` can cover it without either real store.
    static func currentCloudValues(_ values: [String: Any], tags: [String: Int], epoch: Int) -> [String: Any] {
        values.filter { key, _ in (tags[key] ?? epoch) >= epoch }
    }

    /// Both sides' progress combined, under `epoch` and `resetAt`: the same-epoch merge,
    /// and the two cross-epoch cases that union too.
    ///
    /// The start time is a bound on when *all* of the result was made. The cloud's
    /// contribution was made in its epoch, so after `resetAt`; this device's after its
    /// own start time. When the cloud added nothing, the device's bound stands. When the
    /// device held nothing, the cloud's does. Otherwise the earlier of the two — and if
    /// either is unknown (epoch 0 has no reset time, so its history is unknown), so is
    /// the result.
    private static func union(_ local: Snapshot, _ cloud: Snapshot, epoch: Int, resetAt: TimeInterval?) -> Snapshot {
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

        let cloudAddedProgress = Keys.progress.contains { !same(merged[$0], l[$0]) }
        let startedAt: TimeInterval?
        if !cloudAddedProgress {
            startedAt = local.startedAt
        } else if !holdsProgress(l) {
            startedAt = resetAt
        } else if let localStart = local.startedAt, let resetAt {
            startedAt = min(localStart, resetAt)
        } else {
            startedAt = nil
        }

        return Snapshot(values: merged, epoch: epoch, resetAt: resetAt, startedAt: startedAt)
    }

    /// Whether `values` hold any progress at all. An empty collection is no progress:
    /// 1.0.8 wrote an empty arsenal dictionary for a level finished on the default
    /// loadout.
    private static func holdsProgress(_ values: [String: Any]) -> Bool {
        values.values.contains { value in
            switch value {
            case let array as [Any]: return !array.isEmpty
            case let dictionary as [String: Any]: return !dictionary.isEmpty
            default: return true
            }
        }
    }

    // MARK: - Demo Store

    #if DEBUG
    /// Progress served entirely from memory, for any launch `DebugLaunch` stages.
    ///
    /// While this is non-nil the type is read-only: every read below answers out of it,
    /// and every write — `mutate`, `resetProgress`, the merge, the flush — returns
    /// without touching `UserDefaults` or `NSUbiquitousKeyValueStore`. That is not a
    /// convenience. `DebugLaunch.prepare()` installs it whenever a launch argument of
    /// its is present — seeded with a finished game under `-unlockall`, otherwise with
    /// a copy of the device's own save — because a staged run (`-results`, a bot-flown
    /// `-level 34 -guns 8`) would otherwise be saved as real progress and pushed to
    /// iCloud, where it would land on every other device signed into the same account.
    /// `Tools/appstore_media.sh` alone makes more than thirty such launches per run.
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
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let isTesting = environment["JETSHOT_TEST_STORAGE"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
        if isTesting {
            let local = MemoryProgressStore()
            let cloud = MemoryProgressStore()
            userDefaults = local
            cloudStore = cloud
            testStores = (local, cloud)
            return
        }
        testStores = nil
        #endif
        userDefaults = UserDefaults.standard
        cloudStore = NSUbiquitousKeyValueStore.default
        setupCloudSync()
    }

    // MARK: - Setup

    /// Setup iCloud synchronization and listeners
    private func setupCloudSync() {
        // A demo launch neither reads iCloud nor writes it. Returning before the
        // observer is registered matters as much as returning before the merge: an
        // external change arriving mid-session would otherwise call
        // `mergeCloudDataWithLocal(_:)` on the real stores behind the demo's back.
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
        // AppDelegate.didFinishLaunching, and the merge reads and may rewrite every
        // progress key plus the epoch bookkeeping in both stores — no reason to hold up
        // the first frame for it.
        queue.async { [weak self] in
            self?.mergeCloudDataWithLocal(.normal)
        }
    }

    // MARK: - Sync Handling

    /// Which reconcile rule a merge applies.
    private enum MergeMode {
        /// `reconcile(local:cloud:)`: startup, another device's change, every save.
        case normal
        /// `reconcileAfterAccountChange(local:cloud:)`.
        case accountChange
    }

    @objc private func cloudStoreDidChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonForChange = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              let mode = Self.mergeMode(forChangeReason: reasonForChange) else {
            return
        }

        // Use the dedicated serial queue to prevent race conditions
        queue.async { [weak self] in
            self?.mergeCloudDataWithLocal(mode)
        }
    }

    /// The merge a change notification calls for, or nil for none.
    ///
    /// A server change or the initial sync is this account's progress arriving from
    /// another device (or from before a reinstall): the ordinary merge. An account
    /// change is something else — the store has been replaced with another Apple ID's
    /// save — and used to be ignored, which left the next ordinary merge to compare two
    /// accounts' epochs as one timeline. A quota violation brings nothing to merge.
    private static func mergeMode(forChangeReason reason: Int) -> MergeMode? {
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange, NSUbiquitousKeyValueStoreInitialSyncChange:
            return .normal
        case NSUbiquitousKeyValueStoreAccountChange:
            return .accountChange
        default:
            return nil
        }
    }

    /// Merge cloud data with local data, keeping the best progress.
    ///
    /// Must only be called on `queue`.
    ///
    /// There is deliberately no `isCloudAvailable()` gate. With no iCloud account the
    /// key-value store still works as a local cache: `write(_:forKey:)` stores every
    /// save in it regardless, so the cloud side reads back this device's own writes,
    /// the two sides agree and the merge changes nothing — whereas the gate used to skip
    /// the merge entirely on any device with iCloud Drive switched off, which is not the
    /// same question as whether the key-value store works.
    private func mergeCloudDataWithLocal(_ mode: MergeMode) {
        // Re-entrancy guard. `isMerging` is only read and written here, on `queue`.
        if isMerging { return }
        isMerging = true
        defer { isMerging = false }

        let outcome = reconcileStoredProgress(mode)
        userDefaults.synchronize()

        // The merge is deliberately bidirectional. Before writes became unconditional
        // (see `write(_:forKey:)`), a level finished while signed out of iCloud existed
        // *only* in UserDefaults, and a cloud -> local merge alone meant that progress
        // was never uploaded and simply vanished when the player moved to another
        // device. Within an epoch `merged` is the union / element-wise max of both
        // sides, so pushing it back up can only ever add progress — this stays as a
        // repair path for records written before the account was attached. Across
        // epochs it carries a reset made on this device up to the others, or progress
        // this device made after the cloud's reset into it, and it cleans stale writes
        // off the server.
        if outcome.pushedToCloud {
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
    /// On the cloud side the epoch tag is part of what has to match. `cloud` is what
    /// iCloud actually holds, stale writes included, so a stale write is replaced or
    /// removed here. A matching value tagged with another epoch is rewritten, or other
    /// devices would read it as stale once this merge's epoch reaches them. A matching
    /// untagged value is left alone: tagging it costs a write and changes nothing about
    /// how it is read.
    ///
    /// - Returns: whether each side needed updating.
    private func propagate(
        _ merged: Any?,
        epoch: Int,
        local: Any?,
        cloud: Any?,
        cloudTag: Int?,
        forKey key: String
    ) -> (local: Bool, cloud: Bool) {
        let localChanged = !Self.same(merged, local)
        if localChanged {
            if let merged = merged {
                userDefaults.set(merged, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
            #if DEBUG
            print("☁️ Merged \(key) from iCloud")
            #endif
        }

        if let merged = merged {
            guard !Self.same(merged, cloud) || (cloudTag ?? epoch) != epoch else { return (localChanged, false) }
            setInCloud(merged, forKey: key, epoch: epoch)
        } else {
            guard cloud != nil || cloudTag != nil else { return (localChanged, false) }
            removeFromCloud(key)
        }
        return (localChanged, true)
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

    private var localEpoch: Int { (userDefaults.object(forKey: Keys.progressEpoch) as? NSNumber)?.intValue ?? 0 }

    private var cloudEpoch: Int { (cloudStore.object(forKey: Keys.progressEpoch) as? NSNumber)?.intValue ?? 0 }

    private static func time(_ object: Any?) -> TimeInterval? {
        (object as? NSNumber)?.doubleValue
    }

    /// Stores a time, or removes the key for an unknown one.
    private static func set(_ time: TimeInterval?, forKey key: String, in store: any ProgressKeyValueStore) {
        if let time {
            store.set(time, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    /// Must be called on `queue`.
    private func localSnapshot() -> Snapshot {
        var values: [String: Any] = [:]
        for key in Keys.progress {
            values[key] = userDefaults.object(forKey: key)
        }
        return Snapshot(
            values: values,
            epoch: localEpoch,
            resetAt: Self.time(userDefaults.object(forKey: Keys.progressResetAt)),
            startedAt: Self.time(userDefaults.object(forKey: Keys.progressStartedAt))
        )
    }

    /// Must be called on `queue`.
    ///
    /// `snapshot` is what the merge reconciles: stale writes already dropped. `raw` and
    /// `tags` are what iCloud actually holds, which `propagate` needs to clean them up.
    private func cloudSnapshot() -> (snapshot: Snapshot, raw: [String: Any], tags: [String: Int]) {
        var raw: [String: Any] = [:]
        var tags: [String: Int] = [:]
        for key in Keys.progress {
            raw[key] = cloudStore.object(forKey: key)
            tags[key] = (cloudStore.object(forKey: Keys.epochTag(for: key)) as? NSNumber)?.intValue
        }
        let epoch = cloudEpoch
        let resetAtTag = (cloudStore.object(forKey: Keys.epochTag(for: Keys.progressResetAt)) as? NSNumber)?.intValue
        let snapshot = Snapshot(
            values: Self.currentCloudValues(raw, tags: tags, epoch: epoch),
            epoch: epoch,
            resetAt: resetAtTag == epoch ? Self.time(cloudStore.object(forKey: Keys.progressResetAt)) : nil
        )
        return (snapshot, raw, tags)
    }

    /// What a merge changed, on each side.
    private struct MergeOutcome {
        var pushedToCloud = false
        var changedLocalProgress = false
    }

    /// Reconciles both stores. Runs at the start of every mutation as well as for every
    /// merge: a remote update may already be in the cloud store while its notification
    /// is still waiting, even when epochs match. Must be called on `queue`. Does not
    /// flush: the mutation's coalesced flush covers reconciliation too.
    ///
    /// Posts `.progressDidChange` when it changed any of this device's progress values —
    /// and only then, so a merge that found nothing new, an epoch-only change on an empty
    /// save, or the write a mutation makes after this returns never rebuilds a screen.
    @discardableResult
    private func reconcileStoredProgress(_ mode: MergeMode = .normal) -> MergeOutcome {
        let local = localSnapshot()
        let (cloud, rawCloud, cloudTags) = cloudSnapshot()
        let merged = switch mode {
        case .normal: Self.reconcile(local: local, cloud: cloud)
        case .accountChange: Self.reconcileAfterAccountChange(local: local, cloud: cloud)
        }

        var outcome = MergeOutcome()
        for key in Keys.progress {
            let changed = propagate(
                merged.values[key],
                epoch: merged.epoch,
                local: local.values[key],
                cloud: rawCloud[key],
                cloudTag: cloudTags[key],
                forKey: key
            )
            outcome.changedLocalProgress = changed.local || outcome.changedLocalProgress
            outcome.pushedToCloud = changed.cloud || outcome.pushedToCloud
        }

        if merged.epoch != local.epoch {
            userDefaults.set(merged.epoch, forKey: Keys.progressEpoch)
        }
        if merged.resetAt != local.resetAt {
            Self.set(merged.resetAt, forKey: Keys.progressResetAt, in: userDefaults)
        }
        if merged.startedAt != local.startedAt {
            Self.set(merged.startedAt, forKey: Keys.progressStartedAt, in: userDefaults)
        }
        if merged.epoch != cloud.epoch {
            cloudStore.set(Int64(merged.epoch), forKey: Keys.progressEpoch)
            outcome.pushedToCloud = true
        }
        // A reset time that is unchanged still needs a new tag if the epoch moved on.
        if merged.resetAt != cloud.resetAt || (merged.epoch != cloud.epoch && merged.resetAt != nil) {
            if let resetAt = merged.resetAt {
                setInCloud(resetAt, forKey: Keys.progressResetAt, epoch: merged.epoch)
            } else {
                removeFromCloud(Keys.progressResetAt)
            }
            outcome.pushedToCloud = true
        }

        if outcome.changedLocalProgress {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .progressDidChange, object: nil)
            }
        }
        return outcome
    }

    /// Clears the player's progress from both stores and opens a new epoch, so no other
    /// device's copy of the old progress can merge back in. See `Keys.progressEpoch`.
    ///
    /// The new epoch is one past the higher of the two sides, so a reset made on a
    /// device that is itself behind still comes out newest. Its time goes into both
    /// stores with it (`Keys.progressResetAt`), and this device's start time goes: with
    /// nothing left to date, the next save stamps a new one.
    func resetProgress() {
        guard !Self.isDemo else { return }
        queue.sync {
            let epoch = max(localEpoch, cloudEpoch) + 1
            let resetAt = Date().timeIntervalSince1970
            for key in Keys.progress {
                userDefaults.removeObject(forKey: key)
                removeFromCloud(key)
            }
            userDefaults.removeObject(forKey: Keys.progressStartedAt)
            userDefaults.set(epoch, forKey: Keys.progressEpoch)
            userDefaults.set(resetAt, forKey: Keys.progressResetAt)
            cloudStore.set(Int64(epoch), forKey: Keys.progressEpoch)
            setInCloud(resetAt, forKey: Keys.progressResetAt, epoch: epoch)
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
            let merge = reconcileStoredProgress()
            let current = userDefaults.object(forKey: key) as? [Any] ?? []
            commit(transform(current), over: current, forKey: key, after: merge)
        }
    }

    /// Reads, transforms and writes one stored dictionary as a single serial operation.
    /// See `mutate(array:_:)` for the ordering guarantee and the deadlock caveat.
    func mutate(dictionary key: String, _ transform: ([String: Any]) -> [String: Any]) {
        guard !Self.isDemo else { return }
        queue.sync {
            let merge = reconcileStoredProgress()
            let current = userDefaults.object(forKey: key) as? [String: Any] ?? [:]
            commit(transform(current), over: current, forKey: key, after: merge)
        }
    }

    /// The write half of a mutation. Must be called on `queue`.
    ///
    /// A transform that hands back what it was given — `completeLevel` on a level that
    /// is already complete, a replay that beat neither the score nor the stars — writes
    /// nothing and schedules no flush. Rewriting the unchanged value was worse than
    /// wasteful: iCloud resolves conflicts per key by the time of the write, so the
    /// rewrite could replace a value another device had improved in the meantime on the
    /// server, and from a device still behind on a reset it put the pre-reset
    /// collection back after it.
    private func commit(_ updated: Any, over current: Any, forKey key: String, after merge: MergeOutcome) {
        guard !Self.same(updated, current) else {
            // The merge in front of the transform may still have written to iCloud.
            if merge.pushedToCloud { scheduleFlush() }
            return
        }
        stampStartIfFirstProgress()
        write(updated, forKey: key)
        scheduleFlush()
    }

    /// Stamps `Keys.progressStartedAt` before a save to a device that holds no progress.
    /// Must be called on `queue`, after the merge a mutation starts with.
    ///
    /// Whenever there is no progress, not only when no start time is stored: a start
    /// time with nothing behind it bounds nothing, and keeping one — the reset time an
    /// empty epoch was adopted with, say — would date progress made today back to that
    /// reset, and a later reset this device had not heard of yet would then wipe it.
    private func stampStartIfFirstProgress() {
        guard !Self.holdsProgress(localSnapshot().values) else { return }
        userDefaults.set(Date().timeIntervalSince1970, forKey: Keys.progressStartedAt)
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
        return userDefaults.object(forKey: key) as? [Any]
    }

    /// Load dictionary from local storage (kept up to date by the merge).
    /// See `loadArray(forKey:)` for why this does not use `queue`.
    func loadDictionary(forKey key: String) -> [String: Any]? {
        #if DEBUG
        if let demo = Self.demoStore { return demo[key] as? [String: Any] }
        #endif
        return userDefaults.object(forKey: key) as? [String: Any]
    }

    /// Local-only progress preferences use the same isolated store during tests.
    func loadLocalBool(forKey key: String) -> Bool {
        (userDefaults.object(forKey: key) as? NSNumber)?.boolValue ?? false
    }

    func saveLocalBool(_ value: Bool, forKey key: String) {
        guard !Self.isDemo else { return }
        queue.sync { userDefaults.set(value, forKey: key) }
    }

    #if DEBUG
    /// Replaces only XCTest's memory stores. Pending flushes never reference real stores.
    func restoreTestStores(local: [String: Any], cloud: [String: Any]) {
        precondition(testStores != nil, "Progress tests require isolated stores")
        queue.sync {
            testStores?.local.restore(local)
            testStores?.cloud.restore(cloud)
        }
    }

    /// Runs one merge synchronously against XCTest's memory stores: the startup merge
    /// for a nil `changeReason`, otherwise what `cloudStoreDidChange` runs for that
    /// `NSUbiquitousKeyValueStoreChangeReasonKey` value. Under XCTest `init` returns
    /// before `setupCloudSync()`, so neither is wired up and this is the only way in.
    func mergeForTesting(changeReason: Int? = nil) {
        precondition(testStores != nil, "Progress tests require isolated stores")
        let mode: MergeMode?
        if let changeReason {
            mode = Self.mergeMode(forChangeReason: changeReason)
        } else {
            mode = .normal
        }
        guard let mode else { return }
        queue.sync { mergeCloudDataWithLocal(mode) }
    }
    #endif

    // MARK: - Writing

    /// Writes a progress value to both stores, tagged in iCloud with the current epoch.
    /// Must be called on `queue`, after the merge that brought both stores to one epoch.
    ///
    /// The cloud write is unconditional. It used to be gated on `isCloudAvailable()`,
    /// which reports whether iCloud *Drive* has a signed-in identity — not whether the
    /// key-value store is usable. A player with an iCloud account but Drive switched
    /// off silently got no sync at all. Writing regardless is safe: with no account the
    /// value is simply held locally by the store and uploaded if one appears.
    private func write(_ value: Any, forKey key: String) {
        userDefaults.set(value, forKey: key)
        setInCloud(value, forKey: key, epoch: localEpoch)
    }

    /// Sets a progress key — or `Keys.progressResetAt` — in iCloud together with its
    /// epoch tag (see `currentCloudValues(_:tags:epoch:)`). Must be called on `queue`.
    ///
    /// Value first and tag second here, tag first and value second in
    /// `removeFromCloud(_:)`: iCloud resolves each key on its own, so another device's
    /// writes can land between the two. Against a reset's removals this order means the
    /// only split that can survive is a tag with no value, which is harmless — never a
    /// stale value whose tag was removed, which would read as an untagged 1.0.8 write and
    /// be accepted.
    private func setInCloud(_ value: Any, forKey key: String, epoch: Int) {
        cloudStore.set(value, forKey: key)
        cloudStore.set(Int64(epoch), forKey: Keys.epochTag(for: key))
    }

    /// Removes a key and its epoch tag from iCloud, tag first — see
    /// `setInCloud(_:forKey:epoch:)`. Must be called on `queue`.
    private func removeFromCloud(_ key: String) {
        cloudStore.removeObject(forKey: Keys.epochTag(for: key))
        cloudStore.removeObject(forKey: key)
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
    /// see `write(_:forKey:)`.
    func isCloudAvailable() -> Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Debug

    #if DEBUG
    /// Print current cloud storage status
    func printCloudStatus() {
        print("☁️ iCloud Status:")
        print("  Available: \(isCloudAvailable())")
        print("  Completed Levels: \(cloudStore.object(forKey: Keys.completedLevels) as? [Int] ?? [])")
        print("  Level Scores: \(cloudStore.object(forKey: Keys.levelScores) as? [String: Int] ?? [:])")
        print("  Level Stars: \(cloudStore.object(forKey: Keys.levelStars) as? [String: Int] ?? [:])")
    }
    #endif
}
