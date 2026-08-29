//
//  LevelManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import Foundation

/// Manages level progression, completion status, scoring, and star ratings.
/// Integrates with CloudStorageManager for iCloud synchronization.
class LevelManager {
    static let shared = LevelManager()

    private let cloudStorage = CloudStorageManager.shared
    private let completedLevelsKey = CloudStorageManager.Keys.completedLevels
    private let levelScoresKey = CloudStorageManager.Keys.levelScores
    private let levelStarsKey = CloudStorageManager.Keys.levelStars
    private let levelWeaponsKey = CloudStorageManager.Keys.levelWeapons

    private init() {}

    // Total number of levels
    let totalLevels = GameConfiguration.totalLevels

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

    // Mark level as completed with score and weapon arsenal
    //
    // Each of the four writes below is a read-modify-write, and each one goes through
    // `CloudStorageManager.mutate` so it is serialised against the iCloud merge. Doing
    // the read and the write as separate steps (load..., then save...) let the merge
    // interleave and overwrite a freshly finished level with its own stale union.
    func completeLevel(_ level: Int, score: Int, stars: Int = 3, bulletCount: Int = 1, sideMissileCount: Int = 0) {
        cloudStorage.mutate(array: completedLevelsKey) { current in
            var levels = current as? [Int] ?? []
            guard !levels.contains(level) else { return current }
            levels.append(level)
            return levels.sorted()
        }

        saveLevelScore(level: level, score: score)
        saveLevelStars(level: level, stars: stars)
        saveLevelWeapons(level: level, bulletCount: bulletCount, sideMissileCount: sideMissileCount)
    }

    // Get all completed levels
    private func getCompletedLevels() -> [Int] {
        return cloudStorage.loadArray(forKey: completedLevelsKey) as? [Int] ?? []
    }

    // Save score for a specific level (keeps the personal best)
    private func saveLevelScore(level: Int, score: Int) {
        cloudStorage.mutate(dictionary: levelScoresKey) { current in
            var scores = current as? [String: Int] ?? [:]
            // Only record an improvement. Overwriting unconditionally meant replaying a
            // level with a worse run lowered the stored score and shrank
            // getTotalScore(), and it disagreed with the iCloud merge — which keeps
            // max() — so the value flip-flopped between devices on every sync.
            guard score > (scores["\(level)"] ?? Int.min) else { return current }
            scores["\(level)"] = score
            return scores
        }
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
        cloudStorage.mutate(dictionary: levelStarsKey) { current in
            var levelStars = current as? [String: Int] ?? [:]
            // Only update if new stars are better than existing
            guard stars > (levelStars["\(level)"] ?? Int.min) else { return current }
            levelStars["\(level)"] = stars
            return levelStars
        }
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
        cloudStorage.removeObject(forKey: levelWeaponsKey)
        cloudStorage.removeObject(forKey: CloudStorageManager.Keys.endlessRecords)

        // A full reset should feel like a fresh install, so the intro plays again.
        hasSeenOpeningStory = false
    }

    // MARK: - Endless Records

    /// Best score and deepest round reached in endless, or zeros if it has never been
    /// played. Both are kept as personal bests, the same way level scores are.
    func getEndlessRecords() -> (bestScore: Int, bestRound: Int) {
        let records = cloudStorage.loadDictionary(forKey: CloudStorageManager.Keys.endlessRecords) as? [String: Int] ?? [:]
        return (records["bestScore"] ?? 0, records["bestRound"] ?? 0)
    }

    /// Records the outcome of an endless run, keeping the better of each field.
    ///
    /// Read-modify-write through `mutate` for the reason `completeLevel` documents: doing
    /// the load and the save as separate steps lets the iCloud merge interleave and
    /// overwrite a fresh record with its own stale copy.
    @discardableResult
    func recordEndlessRun(score: Int, round: Int) -> Bool {
        let previous = getEndlessRecords()

        cloudStorage.mutate(dictionary: CloudStorageManager.Keys.endlessRecords) { current in
            var records = current as? [String: Int] ?? [:]
            records["bestScore"] = max(score, records["bestScore"] ?? 0)
            records["bestRound"] = max(round, records["bestRound"] ?? 0)
            return records
        }

        return score > previous.bestScore
    }

    // MARK: - Story Playback

    private var hasSeenOpeningStoryKey: String { "hasSeenOpeningStory" }

    /// Whether the opening story has already been shown.
    ///
    /// Deliberately local rather than iCloud-backed: this is a presentation flag for
    /// this device, not progress worth syncing or merging. Without it, entering level 1
    /// from the level select replayed the whole intro crawl on every single attempt —
    /// skippable, but a skip you had to perform every retry.
    var hasSeenOpeningStory: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenOpeningStoryKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenOpeningStoryKey) }
    }

    // MARK: - Weapon Arsenal Management

    // Save weapon arsenal for a specific level
    private func saveLevelWeapons(level: Int, bulletCount: Int, sideMissileCount: Int) {
        cloudStorage.mutate(dictionary: levelWeaponsKey) { current in
            var levelWeapons = current
            let existing = levelWeapons["\(level)"] as? [String: Int]
            let existingBullets = existing?["bulletCount"] ?? 1
            let existingMissiles = existing?["sideMissileCount"] ?? 0

            // Only save if either weapon improved, and then keep the better of each.
            guard bulletCount > existingBullets || sideMissileCount > existingMissiles else {
                return current
            }
            levelWeapons["\(level)"] = [
                "bulletCount": max(bulletCount, existingBullets),
                "sideMissileCount": max(sideMissileCount, existingMissiles)
            ]
            return levelWeapons
        }
    }

    // Get weapon arsenal for a specific level
    func getLevelWeapons(level: Int) -> (bulletCount: Int, sideMissileCount: Int) {
        let levelWeapons = getLevelWeaponsDict()

        if let weapons = levelWeapons["\(level)"] as? [String: Int] {
            let bulletCount = weapons["bulletCount"] ?? 1
            let sideMissileCount = weapons["sideMissileCount"] ?? 0
            return (bulletCount, sideMissileCount)
        }

        // Default values for level 1 or uncompleted levels
        return (1, 0)
    }

    // Get all level weapons
    private func getLevelWeaponsDict() -> [String: Any] {
        return cloudStorage.loadDictionary(forKey: levelWeaponsKey) ?? [:]
    }

    // Get level configuration
    func getLevelConfig(for level: Int) -> LevelConfig {
        var waves = getWavesForLevel(level)
        var obstacleWaves = getObstacleWavesForLevel(level)
        let powerUpConfig = getPowerUpConfigForLevel(level)
        var asteroidWaves = getAsteroidWavesForLevel(level)

        // Pace the authored waves, then reprise them harder.
        //
        // This used to read `waves.randomElement()` in a loop, appending one random
        // existing wave per original wave. It doubled the level's length, which was the
        // stated intent, but it also meant the back half of every level was the front
        // half again in a shuffled order — often the same wave three times running, and
        // with no relationship between where the player was in the level and how hard it
        // was. A level had no shape at all: it started at its final difficulty, stayed
        // there for a minute, and then stopped. That is most of why the game felt like it
        // was going nowhere.
        //
        // `pacedWaves` fixes the density of what was authored; `reprisedWaves` replays it
        // in order and tighter, so the second half is recognisably the same level turned
        // up rather than a reshuffle. The count still doubles, which is what the obstacle
        // and asteroid padding below expects.
        waves = Self.pacedWaves(waves) + Self.reprisedWaves(waves)

        // For obstacles and asteroids, duplicate to match final enemy wave count
        // This ensures obstacles spawn throughout the entire level
        let finalEnemyWaveCount = waves.count
        let originalObstacleCount = obstacleWaves.count

        if originalObstacleCount > 0 {
            // Add obstacle waves until we match or exceed enemy wave count
            while obstacleWaves.count < finalEnemyWaveCount {
                if let randomWave = obstacleWaves.randomElement() {
                    obstacleWaves.append(randomWave)
                }
            }
        }

        let originalAsteroidCount = asteroidWaves.count
        if originalAsteroidCount > 0 {
            // Add asteroid waves until we match or exceed enemy wave count
            while asteroidWaves.count < finalEnemyWaveCount {
                if let randomWave = asteroidWaves.randomElement() {
                    asteroidWaves.append(randomWave)
                }
            }
        }

        return LevelConfig(
            levelNumber: level,
            title: "Level \(level)",
            waves: waves,
            obstacleWaves: obstacleWaves,
            powerUpConfig: powerUpConfig,
            asteroidWaves: asteroidWaves
        )
    }

    // MARK: - Wave Pacing

    /// Rescales an authored wave list to the cadence the game actually plays at.
    ///
    /// The waves in `getWavesForLevel(_:)` are hand-authored at a deliberately readable
    /// cadence — one enemy per 1.2–1.5 s, behind a 2 s lead-in — which on a screen an
    /// enemy takes 3–5 s to cross leaves the player with almost nothing in front of them.
    /// Scaling here rather than editing fifty levels of content keeps the authored shape
    /// of each wave (its enemy mix, its formation, its relative pacing against its
    /// neighbours) and changes only how tightly it is delivered.
    ///
    /// Formation waves are left alone: they spawn as a single unit in
    /// `EnemyManager.update(currentTime:)` and never read `spawnInterval`, so scaling it
    /// would be a no-op that only muddies the numbers.
    static func pacedWaves(_ waves: [EnemyWave]) -> [EnemyWave] {
        return waves.map { wave in
            scaled(wave, intervalScale: GameConfiguration.waveIntervalScale)
        }
    }

    /// The second half of a level: the same waves, in the same order, delivered harder.
    ///
    /// Replaying in order matters more than it sounds. It means the difficulty curve
    /// inside a level runs twice — a lull, a build, a peak, then the same build steeper —
    /// which gives the player something to recognise and get better at, and it puts the
    /// level's densest authored wave at the end where a climax belongs. The previous
    /// random shuffle could just as easily finish a level on its opening warm-up wave.
    static func reprisedWaves(_ waves: [EnemyWave]) -> [EnemyWave] {
        let scale = GameConfiguration.waveIntervalScale * GameConfiguration.waveRepriseIntervalScale
        return waves.map { wave in
            scaled(wave, intervalScale: scale)
        }
    }

    /// Applies the interval and lead-in scaling for one wave, respecting both floors.
    private static func scaled(_ wave: EnemyWave, intervalScale: TimeInterval) -> EnemyWave {
        let interval = wave.isFormation
            ? wave.spawnInterval
            : max(GameConfiguration.minSpawnInterval, wave.spawnInterval * intervalScale)

        let delay = max(
            GameConfiguration.minWaveDelay,
            wave.spawnDelay * GameConfiguration.waveDelayScale
        )

        return EnemyWave(
            enemies: wave.enemies,
            spawnDelay: delay,
            spawnInterval: interval,
            isFormation: wave.isFormation,
            formationPattern: wave.formationPattern
        )
    }

    /// One endless round's worth of hazards, borrowed from the campaign level its depth
    /// corresponds to.
    ///
    /// Endless builds its enemy waves procedurally in `EndlessDirector`, but there is no
    /// reason to invent a second obstacle and asteroid authoring pass when fifty levels of
    /// them already exist and are already tuned. Unpadded, unlike `getLevelConfig(for:)`:
    /// the caller tops these up once per round rather than laying out a whole level.
    func endlessHazardWaves(forRound round: Int) -> (obstacles: [ObstacleWave], asteroids: [AsteroidWave]) {
        let level = EndlessRules.hazardLevel(forRound: round)
        return (getObstacleWavesForLevel(level), getAsteroidWavesForLevel(level))
    }

    // Define waves for each level
    private func getWavesForLevel(_ level: Int) -> [EnemyWave] {
        switch level {
        // ============================================
        // LEVELS 1-10: Beginner levels
        // ============================================

        case 1:
            // Level 1: First steps - basic enemies only, but in three distinct beats.
            //
            // This level was two waves of eight identical enemies at an identical
            // cadence, which the reprise then played again: thirty-two `.basic` ships
            // descending one at a time, in a line, for the whole of a new player's first
            // impression of the game. Nothing in it changed, so nothing in it could be
            // learned, and the first formation in the game did not appear until level 4.
            //
            // Same enemy type and the same total count — this is still the tutorial
            // level and it is still easy — but now with a shape: singles to learn the
            // controls on, a tighter run to feel the first real pressure, then a
            // formation, which is the most visually striking thing the spawner can do
            // and no reason at all to withhold it for three more levels. The reprise
            // replays those three beats harder, so the level ends on a fast formation
            // rather than trailing off.
            return [
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 5),
                    spawnDelay: 0.8,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 6),
                    spawnDelay: 1.2,
                    spawnInterval: 0.85
                ),
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 5),
                    spawnDelay: 1.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                )
            ]

        case 2:
            // Level 2: Introducing fast enemies.
            //
            // The old opener was ten `.basic` in a row before anything new happened,
            // which on a level whose entire headline is "fast enemies exist" is a long
            // time to spend proving they do not yet. Every level from here follows the
            // same four-beat shape: a short warm-up on known enemies, the new enemy alone
            // so it reads, the new enemy combined with the old, and a formation to close
            // on. The reprise in `getLevelConfig(for:)` then plays those beats again
            // tighter, so each level builds twice.
            return [
                EnemyWave(
                    enemies: Array(repeating: .basic, count: 6),
                    spawnDelay: 0.8,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .fast, count: 6),
                    spawnDelay: 1.4,
                    spawnInterval: 0.95
                ),
                EnemyWave(
                    enemies: [.basic, .fast, .basic, .fast, .basic, .fast],
                    spawnDelay: 1.4,
                    spawnInterval: 1.05
                ),
                // A formation of an enemy the player already knows: this teaches the
                // shape, not a new ship.
                EnemyWave(
                    enemies: Array(repeating: .fast, count: 5),
                    spawnDelay: 1.6,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .line
                )
            ]

        case 3:
            // Level 3: Introducing striker.
            return [
                EnemyWave(
                    enemies: [.basic, .basic, .striker, .basic, .striker, .basic],
                    spawnDelay: 0.8,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .striker, count: 6),
                    spawnDelay: 1.4,
                    spawnInterval: 1.05
                ),
                EnemyWave(
                    enemies: Array(repeating: .fast, count: 6),
                    spawnDelay: 1.4,
                    spawnInterval: 0.9
                ),
                EnemyWave(
                    enemies: [.striker, .fast, .striker, .fast, .striker, .fast],
                    spawnDelay: 1.5,
                    spawnInterval: 1.0
                )
            ]

        case 4:
            // Level 4: Scouts, and the level where formations become the point — two of
            // them, in different shapes, so the player learns to read a formation as a
            // single target rather than as six separate ones.
            return [
                EnemyWave(
                    enemies: [.basic, .fast, .basic, .fast, .basic, .basic],
                    spawnDelay: 0.8,
                    spawnInterval: 1.15
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 6),
                    spawnDelay: 1.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.fast, .striker, .fast, .striker, .fast, .striker],
                    spawnDelay: 1.5,
                    spawnInterval: 1.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 6),
                    spawnDelay: 1.6,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                )
            ]

        case 5:
            // Level 5: Introducing heavy and zigzag.
            return [
                EnemyWave(
                    enemies: [.basic, .heavy, .basic, .heavy, .basic, .heavy],
                    spawnDelay: 0.8,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .zigzag, count: 6),
                    spawnDelay: 1.4,
                    spawnInterval: 1.15
                ),
                EnemyWave(
                    enemies: [.fast, .striker, .fast, .striker, .fast, .striker],
                    spawnDelay: 1.4,
                    spawnInterval: 0.95
                ),
                EnemyWave(
                    enemies: [.heavy, .zigzag, .heavy, .zigzag, .heavy, .zigzag],
                    spawnDelay: 1.5,
                    spawnInterval: 1.25
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 5),
                    spawnDelay: 1.6,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .line
                )
            ]

        case 6:
            // Level 6: Kamikaze. The opening rush is the level's signature, so it both
            // opens and closes with one — the second faster, and after the player has
            // spent the middle of the level being taught to hold position.
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 6),
                    spawnDelay: 0.8,
                    spawnInterval: 0.8
                ),
                EnemyWave(
                    enemies: [.basic, .heavy, .basic, .heavy, .basic, .heavy],
                    spawnDelay: 1.5,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 8),
                    spawnDelay: 1.6,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.zigzag, .striker, .zigzag, .striker, .zigzag, .striker],
                    spawnDelay: 1.5,
                    spawnInterval: 1.1
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 6),
                    spawnDelay: 1.4,
                    spawnInterval: 0.7
                )
            ]

        case 7:
            // Level 7: Introducing sniper — the first enemy that punishes standing still,
            // so it is deliberately paired with the crowd waves that make you want to.
            return [
                EnemyWave(
                    enemies: [.fast, .fast, .striker, .fast, .striker, .fast],
                    spawnDelay: 0.8,
                    spawnInterval: 0.95
                ),
                EnemyWave(
                    enemies: [.sniper, .basic, .sniper, .basic, .sniper],
                    spawnDelay: 1.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 8),
                    spawnDelay: 1.6,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .line
                ),
                EnemyWave(
                    enemies: [.heavy, .zigzag, .heavy, .zigzag, .heavy, .zigzag],
                    spawnDelay: 1.5,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: [.sniper, .striker, .sniper, .striker],
                    spawnDelay: 1.5,
                    spawnInterval: 1.6
                )
            ]

        case 8:
            // Level 8: First turret
            return [
                EnemyWave(
                    enemies: [.kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze],
                    spawnDelay: 1.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.turret, .turret],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 8),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.sniper, .heavy, .sniper, .sniper, .heavy, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: [.basic, .fast, .striker, .fast, .basic, .basic, .fast, .striker, .fast, .basic],
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                )
            ]

        case 9:
            // Level 9: First meteor swarm
            return [
                EnemyWave(
                    enemies: [.basic, .heavy, .basic, .heavy, .basic, .heavy, .basic, .heavy],
                    spawnDelay: 1.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 12),
                    spawnDelay: 2.0,
                    spawnInterval: 0.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 10),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.zigzag, .striker, .zigzag, .striker, .zigzag, .striker, .zigzag, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 1.1
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 2.5
                )
            ]

        case 10:
            // Level 10: First mini-boss level - mix of everything so far
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 10),
                    spawnDelay: 1.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .basic, .fast, .heavy, .zigzag, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 8),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.turret, .heavy, .turret, .turret, .heavy, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 14),
                    spawnDelay: 2.0,
                    spawnInterval: 0.35
                ),
                EnemyWave(
                    enemies: [.sniper, .heavy, .sniper, .heavy, .sniper, .heavy, .sniper, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 10),
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
                    enemies: Array(repeating: .flanker, count: 8),
                    spawnDelay: 1.0,
                    spawnInterval: 0.8
                ),
                EnemyWave(
                    enemies: [.heavy, .heavy, .heavy, .heavy, .heavy, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.sniper, .striker, .sniper, .sniper, .striker, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.6
                )
            ]

        case 12:
            // Level 12: Introducing tank
            return [
                EnemyWave(
                    enemies: [.basic, .fast, .basic, .fast, .basic, .fast, .basic, .fast],
                    spawnDelay: 1.0,
                    spawnInterval: 1.1
                ),
                EnemyWave(
                    enemies: [.tank, .heavy, .tank, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 10),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.zigzag, .zigzag, .striker, .striker, .zigzag, .zigzag, .striker, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                )
            ]

        case 13:
            // Level 13: First mine
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 8),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine],
                    spawnDelay: 2.0,
                    spawnInterval: 3.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 14),
                    spawnDelay: 2.0,
                    spawnInterval: 0.4
                ),
                EnemyWave(
                    enemies: [.turret, .turret, .turret, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.heavy, .sniper, .heavy, .heavy, .sniper, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                )
            ]

        case 14:
            // Level 14: Elite guard formation
            return [
                EnemyWave(
                    enemies: [.kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze],
                    spawnDelay: 1.0,
                    spawnInterval: 0.6
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.tank, .basic, .tank, .tank, .basic, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.sniper, .heavy, .sniper, .heavy, .sniper, .heavy, .sniper, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.4
                )
            ]

        case 15:
            // Level 15: Bomber formation
            return [
                EnemyWave(
                    enemies: [.fast, .striker, .fast, .striker, .fast, .fast, .striker, .fast, .striker, .fast],
                    spawnDelay: 1.0,
                    spawnInterval: 0.9
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 12),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.turret, .heavy, .turret, .turret, .heavy, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 16),
                    spawnDelay: 2.0,
                    spawnInterval: 0.35
                ),
                EnemyWave(
                    enemies: [.zigzag, .zigzag, .zigzag, .zigzag, .zigzag, .zigzag],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                )
            ]

        case 16:
            // Level 16: Turret spiral introduction
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 8),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 2.0,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: [.tank, .heavy, .tank, .tank, .heavy, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 12),
                    spawnDelay: 2.0,
                    spawnInterval: 0.6
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                )
            ]

        case 17:
            // Level 17: First ghost
            return [
                EnemyWave(
                    enemies: [.ghost, .ghost, .ghost, .ghost],
                    spawnDelay: 1.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .line
                ),
                EnemyWave(
                    enemies: [.heavy, .heavy, .heavy, .heavy, .heavy, .heavy, .heavy, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 10),
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.striker, .zigzag, .striker, .zigzag, .striker, .zigzag, .striker, .zigzag],
                    spawnDelay: 2.0,
                    spawnInterval: 1.0
                )
            ]

        case 18:
            // Level 18: Shield enemy
            return [
                EnemyWave(
                    enemies: [.kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze, .kamikaze],
                    spawnDelay: 1.0,
                    spawnInterval: 0.6
                ),
                EnemyWave(
                    enemies: [.shield, .shield, .shield, .shield],
                    spawnDelay: 2.0,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 10),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.turret, .turret, .turret, .turret, .turret, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                ),
                EnemyWave(
                    enemies: [.sniper, .heavy, .sniper, .heavy, .sniper, .sniper, .heavy, .sniper, .heavy, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                )
            ]

        case 19:
            // Level 19: Spinner formation
            return [
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .basic, .fast, .heavy, .zigzag, .striker],
                    spawnDelay: 1.0,
                    spawnInterval: 1.1
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 8),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 18),
                    spawnDelay: 2.0,
                    spawnInterval: 0.33
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 2.5,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 12),
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                )
            ]

        case 20:
            // Level 20: Mini-boss 2 - complete challenge so far
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 12),
                    spawnDelay: 1.0,
                    spawnInterval: 0.6
                ),
                EnemyWave(
                    enemies: [.ghost, .shield, .ghost, .ghost, .shield, .ghost],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 12),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .heavy, .heavy, .tank, .tank, .heavy, .heavy],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 10),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turret, .turretSpiral, .turretSpiral, .turret, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 20),
                    spawnDelay: 2.0,
                    spawnInterval: 0.3
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 12),
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
                    enemies: [.splitter, .splitter, .splitter, .splitter],
                    spawnDelay: 1.0,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 8),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: [.tank, .heavy, .heavy, .tank, .tank, .heavy, .heavy, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 12),
                    spawnDelay: 2.0,
                    spawnInterval: 0.7
                ),
                EnemyWave(
                    enemies: [.sniper, .striker, .sniper, .striker, .sniper, .striker, .sniper, .striker],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                )
            ]

        case 22:
            // Level 22: Commander formation
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 14),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 8),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.turret, .turret, .turret, .turret, .turret, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: [.ghost, .shield, .ghost, .shield, .ghost, .shield, .ghost, .shield],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 20),
                    spawnDelay: 2.0,
                    spawnInterval: 0.3
                )
            ]

        case 23:
            // Level 23: First laser
            return [
                EnemyWave(
                    enemies: [.laser, .laser],
                    spawnDelay: 1.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 12),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 12),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 2.5,
                    spawnInterval: 2.8
                )
            ]

        case 24:
            // Level 24: Bouncer introduction
            return [
                EnemyWave(
                    enemies: [.bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer],
                    spawnDelay: 1.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 14),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.splitter, .ghost, .splitter, .splitter, .ghost, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: [.heavy, .heavy, .heavy, .heavy, .heavy, .heavy, .heavy, .heavy, .heavy, .heavy],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                )
            ]

        case 25:
            // Level 25: Vortex introduction
            return [
                EnemyWave(
                    enemies: [.vortex, .vortex],
                    spawnDelay: 1.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 16),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 10),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.tank, .sniper, .tank, .sniper, .tank, .sniper, .tank, .sniper],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 14),
                    spawnDelay: 2.0,
                    spawnInterval: 0.65
                ),
                EnemyWave(
                    enemies: [.shield, .shield, .shield, .shield, .shield, .shield],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                )
            ]

        case 26:
            // Level 26: Teleporter introduction
            return [
                EnemyWave(
                    enemies: [.teleporter, .teleporter, .teleporter, .teleporter],
                    spawnDelay: 1.0,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 8),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.turret, .turretSpiral, .turret, .turret, .turretSpiral, .turret],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 22),
                    spawnDelay: 2.0,
                    spawnInterval: 0.28
                ),
                EnemyWave(
                    enemies: [.ghost, .splitter, .ghost, .splitter, .ghost, .splitter, .ghost, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                )
            ]

        case 27:
            // Level 27: Mirror introduction
            return [
                EnemyWave(
                    enemies: [.mirror, .mirror, .mirror, .mirror],
                    spawnDelay: 1.0,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 12),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: [.laser, .laser, .laser, .laser],
                    spawnDelay: 2.5,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                )
            ]

        case 28:
            // Level 28: Intensive mix of special enemies
            return [
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .teleporter, .ghost, .shield, .splitter, .teleporter],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 16),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.vortex, .vortex, .vortex, .vortex],
                    spawnDelay: 2.5,
                    spawnInterval: 3.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 18),
                    spawnDelay: 2.0,
                    spawnInterval: 0.45
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.4
                )
            ]

        case 29:
            // Level 29: Complex formations and special attacks
            return [
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 10),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.mirror, .laser, .mirror, .mirror, .laser, .mirror],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 8),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 24),
                    spawnDelay: 2.0,
                    spawnInterval: 0.26
                ),
                EnemyWave(
                    enemies: [.bouncer, .teleporter, .bouncer, .teleporter, .bouncer, .teleporter, .bouncer, .teleporter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 16),
                    spawnDelay: 2.0,
                    spawnInterval: 0.6
                )
            ]

        case 30:
            // Level 30: Mini-boss 3 - all special enemies
            return [
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror, .ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror],
                    spawnDelay: 1.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 12),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 16),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 3.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 10),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 8),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 2.2
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 20),
                    spawnDelay: 2.0,
                    spawnInterval: 0.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 26),
                    spawnDelay: 2.0,
                    spawnInterval: 0.25
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
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
                    enemies: [.tank, .shield, .tank, .shield, .tank, .tank, .shield, .tank, .shield, .tank],
                    spawnDelay: 1.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 20),
                    spawnDelay: 2.0,
                    spawnInterval: 0.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 14),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.vortex, .laser, .vortex, .vortex, .laser, .vortex],
                    spawnDelay: 2.5,
                    spawnInterval: 2.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 28),
                    spawnDelay: 2.0,
                    spawnInterval: 0.24
                )
            ]

        case 32:
            // Level 32: Teleporters and ghosts chaos
            return [
                EnemyWave(
                    enemies: [.teleporter, .ghost, .teleporter, .ghost, .teleporter, .teleporter, .ghost, .teleporter, .ghost, .teleporter],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 16),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                ),
                EnemyWave(
                    enemies: [.splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 18),
                    spawnDelay: 2.0,
                    spawnInterval: 0.55
                )
            ]

        case 33:
            // Level 33: Laser and mirror combination
            return [
                EnemyWave(
                    enemies: [.laser, .mirror, .laser, .mirror, .laser, .mirror, .laser, .mirror],
                    spawnDelay: 1.0,
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 10),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.9
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 12),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 2.2
                )
            ]

        case 34:
            // Level 34: Bouncer and vortex mayhem
            return [
                EnemyWave(
                    enemies: [.bouncer, .vortex, .bouncer, .vortex, .bouncer, .bouncer, .vortex, .bouncer, .vortex, .bouncer],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 14),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 22),
                    spawnDelay: 2.0,
                    spawnInterval: 0.38
                ),
                EnemyWave(
                    enemies: [.shield, .shield, .shield, .shield, .shield, .shield, .shield, .shield],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                )
            ]

        case 35:
            // Level 35: Massive formation attack
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 10),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 18),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 14),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 12),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 10),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.9
                )
            ]

        case 36:
            // Level 36: All special types at once
            return [
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .ghost, .shield, .splitter, .laser, .bouncer],
                    spawnDelay: 1.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: [.vortex, .teleporter, .mirror, .ghost, .shield, .vortex, .teleporter, .mirror, .ghost, .shield],
                    spawnDelay: 2.0,
                    spawnInterval: 1.6
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 30),
                    spawnDelay: 2.0,
                    spawnInterval: 0.23
                ),
                EnemyWave(
                    enemies: [.splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.7
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 20),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5
                )
            ]

        case 37:
            // Level 37: Tank army
            return [
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 24),
                    spawnDelay: 2.0,
                    spawnInterval: 0.36
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 18),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.laser, .vortex, .laser, .vortex, .laser, .laser, .vortex, .laser, .vortex, .laser],
                    spawnDelay: 2.5,
                    spawnInterval: 2.3
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 2.0
                )
            ]

        case 38:
            // Level 38: Chaos of all types
            return [
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank, .basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank],
                    spawnDelay: 1.0,
                    spawnInterval: 0.9
                ),
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror, .ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 14),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 10),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 32),
                    spawnDelay: 2.0,
                    spawnInterval: 0.22
                )
            ]

        case 39:
            // Level 39: Formation challenge
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 10),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 16),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 12),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 10),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 10),
                    spawnDelay: 3.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                )
            ]

        case 40:
            // Level 40: Mini-boss 4 - ultimate challenge before finale
            return [
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror, .ghost, .shield, .splitter, .laser],
                    spawnDelay: 1.0,
                    spawnInterval: 1.4
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 16),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 10),
                    spawnDelay: 3.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 24),
                    spawnDelay: 2.0,
                    spawnInterval: 0.37
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 30),
                    spawnDelay: 2.5,
                    spawnInterval: 0.23
                ),
                EnemyWave(
                    enemies: [.laser, .vortex, .mirror, .laser, .vortex, .mirror, .laser, .vortex, .mirror, .laser],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 1.9
                )
            ]

        // ============================================
        // LEVELS 41-50: Expert and final challenges
        // ============================================

        case 41:
            // Level 41: Expert beginning - balanced challenge
            return [
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 22),
                    spawnDelay: 1.0,
                    spawnInterval: 0.38
                ),
                EnemyWave(
                    enemies: [.tank, .shield, .tank, .shield, .tank, .shield, .tank, .shield, .tank, .shield, .tank, .shield],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 14),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: [.ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.6
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 28),
                    spawnDelay: 2.5,
                    spawnInterval: 0.24
                ),
                EnemyWave(
                    enemies: [.vortex, .laser, .vortex, .laser, .vortex, .laser, .vortex, .laser, .vortex, .laser],
                    spawnDelay: 2.5,
                    spawnInterval: 2.2
                )
            ]

        case 42:
            // Level 42: Splitter challenge
            return [
                EnemyWave(
                    enemies: [.splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter],
                    spawnDelay: 1.0,
                    spawnInterval: 1.7
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 16),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 18),
                    spawnDelay: 2.0,
                    spawnInterval: 0.52
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 2.0
                )
            ]

        case 43:
            // Level 43: Multiple formations
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 10),
                    spawnDelay: 1.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 12),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 16),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 14),
                    spawnDelay: 3.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 12),
                    spawnDelay: 3.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 10),
                    spawnDelay: 4.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                )
            ]

        case 44:
            // Level 44: Bouncer and mirror combination
            return [
                EnemyWave(
                    enemies: [.bouncer, .mirror, .bouncer, .mirror, .bouncer, .mirror, .bouncer, .mirror, .bouncer, .mirror, .bouncer, .mirror],
                    spawnDelay: 1.0,
                    spawnInterval: 1.5
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.7
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 24),
                    spawnDelay: 2.0,
                    spawnInterval: 0.37
                ),
                EnemyWave(
                    enemies: [.laser, .vortex, .laser, .vortex, .laser, .vortex, .laser, .vortex, .laser, .vortex],
                    spawnDelay: 2.5,
                    spawnInterval: 2.1
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 30),
                    spawnDelay: 2.5,
                    spawnInterval: 0.23
                )
            ]

        case 45:
            // Level 45: Teleporter challenge
            return [
                EnemyWave(
                    enemies: [.teleporter, .teleporter, .teleporter, .teleporter, .teleporter, .teleporter, .teleporter, .teleporter, .teleporter, .teleporter],
                    spawnDelay: 1.0,
                    spawnInterval: 1.9
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 12),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.ghost, .ghost, .ghost, .ghost, .ghost, .ghost, .ghost, .ghost, .ghost, .ghost],
                    spawnDelay: 2.0,
                    spawnInterval: 1.7
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turret],
                    spawnDelay: 3.0,
                    spawnInterval: 2.0
                ),
                EnemyWave(
                    enemies: [.shield, .shield, .shield, .shield, .shield, .shield, .shield, .shield, .shield, .shield],
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                )
            ]

        case 46:
            // Level 46: Vortex and laser challenge
            return [
                EnemyWave(
                    enemies: [.vortex, .vortex, .vortex, .vortex, .vortex, .vortex, .vortex, .vortex],
                    spawnDelay: 1.0,
                    spawnInterval: 2.5
                ),
                EnemyWave(
                    enemies: [.laser, .laser, .laser, .laser, .laser, .laser, .laser, .laser],
                    spawnDelay: 2.5,
                    spawnInterval: 2.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 18),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: [.splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.6
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 20),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 1.9
                )
            ]

        case 47:
            // Level 47: Complete chaos mix
            return [
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank, .basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank],
                    spawnDelay: 1.0,
                    spawnInterval: 0.8
                ),
                EnemyWave(
                    enemies: [.turret, .turretSpiral, .mine, .ghost, .shield, .splitter, .laser, .bouncer, .turret, .turretSpiral, .mine, .ghost, .shield, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                EnemyWave(
                    enemies: [.vortex, .teleporter, .mirror, .tank, .tank, .tank, .vortex, .teleporter, .mirror, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 16),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 12),
                    spawnDelay: 3.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 26),
                    spawnDelay: 2.0,
                    spawnInterval: 0.35
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 32),
                    spawnDelay: 2.5,
                    spawnInterval: 0.22
                ),
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 22),
                    spawnDelay: 2.0,
                    spawnInterval: 0.48
                )
            ]

        case 48:
            // Level 48: Pre-final challenge
            return [
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror, .ghost, .shield, .splitter, .laser],
                    spawnDelay: 1.0,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror, .ghost, .shield, .splitter, .laser],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.6
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 18),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 14),
                    spawnDelay: 3.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: [.turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 1.9
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 28),
                    spawnDelay: 2.0,
                    spawnInterval: 0.33
                ),
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 1.8
                )
            ]

        case 49:
            // Level 49: Final test before boss
            return [
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 10),
                    spawnDelay: 0.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 14),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 18),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 16),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 14),
                    spawnDelay: 3.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 12),
                    spawnDelay: 4.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.6
                ),
                EnemyWave(
                    enemies: [.laser, .vortex, .mirror, .laser, .vortex, .mirror, .laser, .vortex, .mirror, .laser, .vortex, .mirror],
                    spawnDelay: 2.5,
                    spawnInterval: 1.9
                ),
                EnemyWave(
                    enemies: [.ghost, .teleporter, .shield, .splitter, .bouncer, .ghost, .teleporter, .shield, .splitter, .bouncer, .ghost, .teleporter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.4
                ),
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 34),
                    spawnDelay: 2.5,
                    spawnInterval: 0.21
                ),
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 30),
                    spawnDelay: 2.0,
                    spawnInterval: 0.32
                )
            ]

        case 50:
            // Level 50: FINAL BOSS LEVEL - Ultimate challenge
            return [
                // Wave 1: Quick warm-up
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank, .basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank],
                    spawnDelay: 0.5,
                    spawnInterval: 0.7
                ),
                // Wave 2: Special enemies
                EnemyWave(
                    enemies: [.ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror, .ghost, .shield, .splitter, .laser, .bouncer, .vortex, .teleporter, .mirror],
                    spawnDelay: 1.5,
                    spawnInterval: 1.0
                ),
                // Wave 3: Tank army
                EnemyWave(
                    enemies: [.tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank, .tank],
                    spawnDelay: 2.5,
                    spawnInterval: 1.4
                ),
                // Wave 4: Scout formation
                EnemyWave(
                    enemies: Array(repeating: .scout, count: 14),
                    spawnDelay: 2.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .arrow
                ),
                // Wave 5: Formation mix
                EnemyWave(
                    enemies: Array(repeating: .formation, count: 20),
                    spawnDelay: 2.5,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .vShape
                ),
                // Wave 6: Bomber army
                EnemyWave(
                    enemies: Array(repeating: .bomber, count: 26),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .box
                ),
                // Wave 7: Elite Guard elite
                EnemyWave(
                    enemies: Array(repeating: .eliteGuard, count: 20),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .diamond
                ),
                // Wave 8: Spinner vortex
                EnemyWave(
                    enemies: Array(repeating: .spinner, count: 18),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .circle
                ),
                // Wave 9: Commander peak
                EnemyWave(
                    enemies: Array(repeating: .commander, count: 16),
                    spawnDelay: 3.0,
                    spawnInterval: 0.5,
                    isFormation: true,
                    formationPattern: .cross
                ),
                // Wave 10: Turret hell
                EnemyWave(
                    enemies: [.turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral, .turret, .turretSpiral],
                    spawnDelay: 3.0,
                    spawnInterval: 1.6
                ),
                // Wave 11: Kamikaze wave
                EnemyWave(
                    enemies: Array(repeating: .kamikaze, count: 40),
                    spawnDelay: 2.0,
                    spawnInterval: 0.26
                ),
                // Wave 12: Meteor storm
                EnemyWave(
                    enemies: Array(repeating: .meteorSwarm, count: 46),
                    spawnDelay: 2.0,
                    spawnInterval: 0.16
                ),
                // Wave 13: Flanker attack
                EnemyWave(
                    enemies: Array(repeating: .flanker, count: 30),
                    spawnDelay: 2.0,
                    spawnInterval: 0.4
                ),
                // Wave 14: Mine field
                EnemyWave(
                    enemies: [.mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine, .mine],
                    spawnDelay: 3.0,
                    spawnInterval: 1.5
                ),
                // Wave 15: Special mix finale
                EnemyWave(
                    enemies: [.laser, .vortex, .mirror, .laser, .vortex, .mirror, .laser, .vortex, .mirror, .laser, .vortex, .mirror, .laser, .vortex, .mirror, .laser, .vortex, .mirror],
                    spawnDelay: 2.5,
                    spawnInterval: 1.7
                ),
                // Wave 16: Ghost and Teleporter chaos
                EnemyWave(
                    enemies: [.ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter, .ghost, .teleporter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                // Wave 17: Shield and Splitter
                EnemyWave(
                    enemies: [.shield, .splitter, .shield, .splitter, .shield, .splitter, .shield, .splitter, .shield, .splitter, .shield, .splitter, .shield, .splitter, .shield, .splitter],
                    spawnDelay: 2.0,
                    spawnInterval: 1.5
                ),
                // Wave 18: Bouncer mayhem
                EnemyWave(
                    enemies: [.bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer, .bouncer],
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                ),
                // Wave 19: Sniper elite
                EnemyWave(
                    enemies: [.sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper, .sniper],
                    spawnDelay: 2.0,
                    spawnInterval: 1.3
                ),
                // Wave 20: FINAL ATTACK - all at once
                EnemyWave(
                    enemies: [.basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank,
                             .turret, .turretSpiral, .mine, .ghost, .shield, .splitter, .laser, .bouncer,
                             .vortex, .teleporter, .mirror, .basic, .fast, .heavy, .zigzag, .striker, .kamikaze, .sniper, .tank,
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
                    obstacles: [.wall, .wall, .wall, .wall],
                    spawnDelay: 2.0,
                    spawnInterval: 3.0,
                    minSpacing: 150
                )
            ]

        case 6...10:
            // Adding horizontal walls
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall, .wall, .wall, .horizontalWall, .wall],
                    spawnDelay: 3.0,
                    spawnInterval: 2.8,
                    minSpacing: 140
                )
            ]

        case 11...15:
            // Rotating obstacles
            return [
                ObstacleWave(
                    obstacles: [.wall, .rotatingBar, .horizontalWall, .wall, .rotatingBar, .horizontalWall],
                    spawnDelay: 2.5,
                    spawnInterval: 2.6,
                    minSpacing: 130
                ),
                ObstacleWave(
                    obstacles: [.movingWall, .movingWall, .movingWall, .movingWall],
                    spawnDelay: 3.0,
                    spawnInterval: 3.0,
                    minSpacing: 150
                )
            ]

        case 16...20:
            // Spinners and more complex obstacles
            return [
                ObstacleWave(
                    obstacles: [.rotatingBar, .spinner, .rotatingBar, .rotatingBar, .spinner, .rotatingBar],
                    spawnDelay: 2.0,
                    spawnInterval: 2.5,
                    minSpacing: 120
                ),
                ObstacleWave(
                    obstacles: [.movingWall, .horizontalWall, .movingWall, .movingWall, .horizontalWall, .movingWall],
                    spawnDelay: 2.5,
                    spawnInterval: 2.7,
                    minSpacing: 130
                )
            ]

        case 21...25:
            // New special obstacles
            return [
                ObstacleWave(
                    obstacles: [.pulsatingRing, .zigzagWall, .pulsatingRing, .pulsatingRing, .zigzagWall, .pulsatingRing],
                    spawnDelay: 2.0,
                    spawnInterval: 2.4,
                    minSpacing: 120
                ),
                ObstacleWave(
                    obstacles: [.spinner, .rotatingBar, .spinner, .spinner, .rotatingBar, .spinner],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5,
                    minSpacing: 125
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .destructibleWall],
                    spawnDelay: 3.0,
                    spawnInterval: 4.0,
                    minSpacing: 200
                )
            ]

        case 26...30:
            // Advanced obstacles
            return [
                ObstacleWave(
                    obstacles: [.spiralBlade, .waveWall, .spiralBlade, .spiralBlade, .waveWall, .spiralBlade],
                    spawnDelay: 1.8,
                    spawnInterval: 2.3,
                    minSpacing: 115
                ),
                ObstacleWave(
                    obstacles: [.triangleBarrier, .hexagonTrap, .triangleBarrier, .triangleBarrier, .hexagonTrap, .triangleBarrier],
                    spawnDelay: 2.2,
                    spawnInterval: 2.4,
                    minSpacing: 120
                ),
                ObstacleWave(
                    obstacles: [.pulsatingRing, .pulsatingRing, .pulsatingRing, .pulsatingRing],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5,
                    minSpacing: 130
                )
            ]

        case 31...35:
            // Intensive obstacle mix
            return [
                ObstacleWave(
                    obstacles: [.spiralBlade, .spinner, .waveWall, .zigzagWall, .spiralBlade, .spinner, .waveWall, .zigzagWall],
                    spawnDelay: 1.5,
                    spawnInterval: 2.2,
                    minSpacing: 110
                ),
                ObstacleWave(
                    obstacles: [.hexagonTrap, .triangleBarrier, .pulsatingRing, .hexagonTrap, .triangleBarrier, .pulsatingRing],
                    spawnDelay: 2.0,
                    spawnInterval: 2.3,
                    minSpacing: 115
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall],
                    spawnDelay: 2.5,
                    spawnInterval: 3.5,
                    minSpacing: 180
                )
            ]

        case 36...40:
            // Advanced patterns
            return [
                ObstacleWave(
                    obstacles: [.spiralBlade, .spiralBlade, .spiralBlade, .spiralBlade, .spiralBlade, .spiralBlade],
                    spawnDelay: 1.5,
                    spawnInterval: 2.1,
                    minSpacing: 105
                ),
                ObstacleWave(
                    obstacles: [.hexagonTrap, .pulsatingRing, .triangleBarrier, .waveWall, .hexagonTrap, .pulsatingRing, .triangleBarrier, .waveWall],
                    spawnDelay: 1.8,
                    spawnInterval: 2.2,
                    minSpacing: 110
                ),
                ObstacleWave(
                    obstacles: [.spinner, .spinner, .spinner, .spinner, .spinner, .spinner],
                    spawnDelay: 2.2,
                    spawnInterval: 2.3,
                    minSpacing: 115
                )
            ]

        case 41...45:
            // Expert obstacles
            return [
                ObstacleWave(
                    obstacles: [.spiralBlade, .hexagonTrap, .spiralBlade, .triangleBarrier, .spiralBlade, .hexagonTrap, .spiralBlade, .triangleBarrier],
                    spawnDelay: 1.3,
                    spawnInterval: 2.0,
                    minSpacing: 100
                ),
                ObstacleWave(
                    obstacles: [.pulsatingRing, .waveWall, .zigzagWall, .pulsatingRing, .pulsatingRing, .waveWall, .zigzagWall, .pulsatingRing],
                    spawnDelay: 1.6,
                    spawnInterval: 2.1,
                    minSpacing: 105
                ),
                ObstacleWave(
                    obstacles: [.spinner, .rotatingBar, .spinner, .rotatingBar, .spinner, .rotatingBar, .spinner, .rotatingBar],
                    spawnDelay: 2.0,
                    spawnInterval: 2.2,
                    minSpacing: 110
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall],
                    spawnDelay: 2.5,
                    spawnInterval: 3.0,
                    minSpacing: 160
                )
            ]

        case 46...49:
            // Pre-final hell
            return [
                ObstacleWave(
                    obstacles: [.spiralBlade, .hexagonTrap, .pulsatingRing, .triangleBarrier, .waveWall, .spiralBlade, .hexagonTrap, .pulsatingRing, .triangleBarrier, .waveWall],
                    spawnDelay: 1.2,
                    spawnInterval: 1.9,
                    minSpacing: 95
                ),
                ObstacleWave(
                    obstacles: [.spinner, .spinner, .spinner, .spinner, .spinner, .spinner, .spinner, .spinner],
                    spawnDelay: 1.5,
                    spawnInterval: 2.0,
                    minSpacing: 100
                ),
                ObstacleWave(
                    obstacles: [.zigzagWall, .waveWall, .movingWall, .zigzagWall, .zigzagWall, .waveWall, .movingWall, .zigzagWall],
                    spawnDelay: 1.8,
                    spawnInterval: 2.1,
                    minSpacing: 105
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall],
                    spawnDelay: 2.2,
                    spawnInterval: 2.8,
                    minSpacing: 150
                )
            ]

        case 50:
            // Final level - all obstacles
            return [
                ObstacleWave(
                    obstacles: [.wall, .horizontalWall, .rotatingBar, .movingWall, .wall, .horizontalWall, .rotatingBar, .movingWall],
                    spawnDelay: 1.0,
                    spawnInterval: 1.8,
                    minSpacing: 90
                ),
                ObstacleWave(
                    obstacles: [.spinner, .pulsatingRing, .zigzagWall, .spiralBlade, .spinner, .pulsatingRing, .zigzagWall, .spiralBlade],
                    spawnDelay: 1.5,
                    spawnInterval: 1.9,
                    minSpacing: 95
                ),
                ObstacleWave(
                    obstacles: [.waveWall, .triangleBarrier, .hexagonTrap, .waveWall, .triangleBarrier, .hexagonTrap],
                    spawnDelay: 2.0,
                    spawnInterval: 2.0,
                    minSpacing: 100
                ),
                ObstacleWave(
                    obstacles: [.destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall, .destructibleWall],
                    spawnDelay: 2.5,
                    spawnInterval: 2.5,
                    minSpacing: 140
                ),
                ObstacleWave(
                    obstacles: [.spiralBlade, .hexagonTrap, .pulsatingRing, .spinner, .spiralBlade, .hexagonTrap, .pulsatingRing, .spinner],
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
        // Progressive power-up frequency increase with more weapon powerups
        let baseInterval: TimeInterval
        let baseProbability: Double
        let typeWeights: [PowerUpType: Double]

        switch level {
        case 1...5:
            // Beginner levels - very frequent, focus on basic weapons
            baseInterval = 8.0
            baseProbability = 0.85
            typeWeights = [
                .multiShot: 4.5,        // High chance of multi-shot
                .rapidFire: 4.0,        // High chance of rapid fire
                .shield: 1.5,
                .extraLife: 1.2,
                .sideMissiles: 2.0,
                .magnet: 0.8
            ]

        case 6...10:
            // Early levels - frequent, more weapon variety
            baseInterval = 10.0
            baseProbability = 0.8
            typeWeights = [
                .multiShot: 4.0,
                .rapidFire: 4.0,
                .sideMissiles: 3.5,     // Introduce side missiles
                .lightning: 2.5,         // Introduce lightning
                .shield: 1.5,
                .extraLife: 1.0,
                .magnet: 1.0,
                .homingMissiles: 1.5
            ]

        case 11...15:
            // Mid-early levels - balanced weapon focus
            baseInterval = 11.0
            baseProbability = 0.78
            typeWeights = [
                .multiShot: 4.0,
                .rapidFire: 4.0,
                .sideMissiles: 3.5,
                .lightning: 3.5,
                .homingMissiles: 3.0,    // More homing missiles
                .shield: 1.5,
                .barrier: 1.2,           // Introduce barrier
                .extraLife: 1.0,
                .magnet: 1.0,
                .freezeBomb: 0.8
            ]

        case 16...20:
            // Mid levels - all weapon types
            baseInterval = 12.0
            baseProbability = 0.75
            typeWeights = [
                .multiShot: 3.5,
                .rapidFire: 3.5,
                .sideMissiles: 3.5,
                .lightning: 3.5,
                .homingMissiles: 3.5,
                .barrier: 1.5,
                .shield: 1.5,
                .extraLife: 1.0,
                .magnet: 1.0,
                .freezeBomb: 1.0,
                .slowMotion: 1.0,
                .scoreMultiplier: 0.8
            ]

        case 21...30:
            // Advanced levels - full arsenal
            baseInterval = 13.0
            baseProbability = 0.72
            typeWeights = [
                .multiShot: 3.5,
                .rapidFire: 3.5,
                .sideMissiles: 3.5,
                .lightning: 3.5,
                .homingMissiles: 3.5,
                .barrier: 1.8,
                .shield: 1.5,
                .nuke: 1.2,              // Introduce nuke
                .extraLife: 1.0,
                .magnet: 1.0,
                .freezeBomb: 1.0,
                .slowMotion: 1.0,
                .scoreMultiplier: 1.0
            ]

        case 31...40:
            // Expert levels - strategic variety
            baseInterval = 14.0
            baseProbability = 0.7
            typeWeights = [
                .multiShot: 3.2,
                .rapidFire: 3.2,
                .sideMissiles: 3.2,
                .lightning: 3.2,
                .homingMissiles: 3.2,
                .barrier: 1.8,
                .nuke: 1.5,
                .shield: 1.5,
                .freezeBomb: 1.2,
                .slowMotion: 1.2,
                .extraLife: 1.0,
                .magnet: 1.0,
                .scoreMultiplier: 1.0
            ]

        case 41...49:
            // Master levels - balanced challenge
            baseInterval = 15.0
            baseProbability = 0.68
            typeWeights = [
                .multiShot: 3.2,
                .rapidFire: 3.2,
                .sideMissiles: 3.2,
                .lightning: 3.2,
                .homingMissiles: 3.2,
                .barrier: 1.5,
                .nuke: 1.5,
                .shield: 1.5,
                .freezeBomb: 1.2,
                .slowMotion: 1.2,
                .extraLife: 1.0,
                .magnet: 1.0,
                .scoreMultiplier: 1.2
            ]

        case 50:
            // Final level - maximum power-ups!
            baseInterval = 7.0
            baseProbability = 0.9
            typeWeights = [
                .multiShot: 3.0,
                .rapidFire: 3.0,
                .sideMissiles: 3.0,
                .lightning: 3.0,
                .homingMissiles: 3.0,
                .nuke: 2.5,
                .barrier: 2.0,
                .shield: 2.0,
                .freezeBomb: 2.0,
                .slowMotion: 2.0,
                .extraLife: 1.5,
                .magnet: 1.5,
                .scoreMultiplier: 2.0
            ]

        default:
            baseInterval = 12.0
            baseProbability = 0.75
            typeWeights = [
                .multiShot: 3.5,
                .rapidFire: 3.5,
                .sideMissiles: 3.5,
                .lightning: 2.8,
                .homingMissiles: 2.8,
                .shield: 1.5,
                .extraLife: 1.0
            ]
        }

        return PowerUpSpawnConfig(
            spawnInterval: baseInterval,
            spawnProbability: baseProbability,
            typeWeights: typeWeights
        )
    }

    // Define asteroid waves for each level
    private func getAsteroidWavesForLevel(_ level: Int) -> [AsteroidWave] {
        switch level {
        case 1...5:
            // Basic asteroids
            return [
                AsteroidWave(
                    count: 4,
                    size: .small,
                    spawnDelay: 2.0,
                    spawnInterval: 2.5
                )
            ]

        case 6...10:
            // More asteroids
            return [
                AsteroidWave(
                    count: 6,
                    size: .small,
                    spawnDelay: 2.0,
                    spawnInterval: 2.2
                ),
                AsteroidWave(
                    count: 4,
                    size: .medium,
                    spawnDelay: 3.0,
                    spawnInterval: 2.5
                )
            ]

        case 11...15:
            // Medium asteroids
            return [
                AsteroidWave(
                    count: 6,
                    size: .medium,
                    spawnDelay: 2.0,
                    spawnInterval: 2.0
                ),
                AsteroidWave(
                    count: 8,
                    size: .small,
                    spawnDelay: 2.5,
                    spawnInterval: 1.8
                )
            ]

        case 16...20:
            // First large asteroids
            return [
                AsteroidWave(
                    count: 4,
                    size: .large,
                    spawnDelay: 2.0,
                    spawnInterval: 3.0
                ),
                AsteroidWave(
                    count: 6,
                    size: .medium,
                    spawnDelay: 2.5,
                    spawnInterval: 2.0
                ),
                AsteroidWave(
                    count: 8,
                    size: .small,
                    spawnDelay: 3.0,
                    spawnInterval: 1.6
                )
            ]

        case 21...25:
            // Size mix
            return [
                AsteroidWave(
                    count: 6,
                    size: .large,
                    spawnDelay: 1.8,
                    spawnInterval: 2.8
                ),
                AsteroidWave(
                    count: 8,
                    size: .medium,
                    spawnDelay: 2.2,
                    spawnInterval: 1.9
                ),
                AsteroidWave(
                    count: 10,
                    size: .small,
                    spawnDelay: 2.6,
                    spawnInterval: 1.5
                )
            ]

        case 26...30:
            // More large asteroids
            return [
                AsteroidWave(
                    count: 8,
                    size: .large,
                    spawnDelay: 1.6,
                    spawnInterval: 2.6
                ),
                AsteroidWave(
                    count: 10,
                    size: .medium,
                    spawnDelay: 2.0,
                    spawnInterval: 1.8
                ),
                AsteroidWave(
                    count: 12,
                    size: .small,
                    spawnDelay: 2.4,
                    spawnInterval: 1.4
                )
            ]

        case 31...35:
            // Intensive asteroid field
            return [
                AsteroidWave(
                    count: 10,
                    size: .large,
                    spawnDelay: 1.5,
                    spawnInterval: 2.4
                ),
                AsteroidWave(
                    count: 10,
                    size: .medium,
                    spawnDelay: 1.8,
                    spawnInterval: 1.7
                ),
                AsteroidWave(
                    count: 12,
                    size: .small,
                    spawnDelay: 2.2,
                    spawnInterval: 1.3
                )
            ]

        case 36...40:
            // Dense field
            return [
                AsteroidWave(
                    count: 12,
                    size: .large,
                    spawnDelay: 1.4,
                    spawnInterval: 2.2
                ),
                AsteroidWave(
                    count: 12,
                    size: .medium,
                    spawnDelay: 1.7,
                    spawnInterval: 1.6
                ),
                AsteroidWave(
                    count: 14,
                    size: .small,
                    spawnDelay: 2.0,
                    spawnInterval: 1.2
                )
            ]

        case 41...45:
            // Extreme density
            return [
                AsteroidWave(
                    count: 14,
                    size: .large,
                    spawnDelay: 1.3,
                    spawnInterval: 2.0
                ),
                AsteroidWave(
                    count: 14,
                    size: .medium,
                    spawnDelay: 1.6,
                    spawnInterval: 1.5
                ),
                AsteroidWave(
                    count: 16,
                    size: .small,
                    spawnDelay: 1.9,
                    spawnInterval: 1.1
                )
            ]

        case 46...49:
            // Pre-final storm
            return [
                AsteroidWave(
                    count: 16,
                    size: .large,
                    spawnDelay: 1.2,
                    spawnInterval: 1.9
                ),
                AsteroidWave(
                    count: 16,
                    size: .medium,
                    spawnDelay: 1.5,
                    spawnInterval: 1.4
                ),
                AsteroidWave(
                    count: 18,
                    size: .small,
                    spawnDelay: 1.8,
                    spawnInterval: 1.0
                )
            ]

        case 50:
            // Final asteroid storm
            return [
                AsteroidWave(
                    count: 20,
                    size: .large,
                    spawnDelay: 1.0,
                    spawnInterval: 1.8
                ),
                AsteroidWave(
                    count: 20,
                    size: .medium,
                    spawnDelay: 1.3,
                    spawnInterval: 1.3
                ),
                AsteroidWave(
                    count: 20,
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
