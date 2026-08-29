//
//  LevelConfigTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// `getLevelConfig(for:)` runs every authored level through a pacing pass and then pads
/// its hazard tracks with `while` loops driven by `randomElement()`. Those loops are only
/// safe because the arrays they draw from are non-empty — worth pinning down for all 50
/// levels rather than discovering it as a hang on level 43. The pacing pass itself is
/// covered further down: it multiplies every authored interval, so a bad multiplier would
/// otherwise be felt only by playing all fifty levels.
final class LevelConfigTests: XCTestCase {

    @MainActor
    func testEveryLevelProducesAPlayableConfig() {
        for level in 1...GameConfiguration.totalLevels {
            let config = LevelManager.shared.getLevelConfig(for: level)

            XCTAssertEqual(config.levelNumber, level)
            XCTAssertFalse(config.waves.isEmpty, "level \(level) has no enemy waves, so it can never be completed")

            for (index, wave) in config.waves.enumerated() {
                XCTAssertFalse(wave.enemies.isEmpty, "level \(level) wave \(index) spawns nothing")
                XCTAssertGreaterThan(wave.spawnInterval, 0, "level \(level) wave \(index) would spawn every frame")
                XCTAssertGreaterThanOrEqual(wave.spawnDelay, 0)
                if wave.isFormation {
                    XCTAssertNotNil(
                        wave.formationPattern,
                        "level \(level) wave \(index) is a formation with no pattern"
                    )
                }
            }
        }
    }

    @MainActor
    func testLevelLengthIsDoubled() {
        // The generator plays the authored waves once, then reprises the whole list.
        for level in 1...GameConfiguration.totalLevels {
            let config = LevelManager.shared.getLevelConfig(for: level)
            XCTAssertEqual(
                config.waves.count % 2, 0,
                "level \(level) has an odd wave count, so the reprise did not run"
            )
        }
    }

    @MainActor
    func testTheSecondHalfOfALevelReprisesTheFirstInOrder() {
        // The shape of the difficulty curve, and the reason the reprise replaced a
        // `randomElement()` shuffle: the back half has to be the same level again, in the
        // same order, so a level builds to its authored peak twice instead of finishing
        // on whichever wave the shuffle happened to draw last.
        for level in 1...GameConfiguration.totalLevels {
            let waves = LevelManager.shared.getLevelConfig(for: level).waves
            let half = waves.count / 2

            for index in 0..<half {
                XCTAssertEqual(
                    waves[index].enemies, waves[index + half].enemies,
                    "level \(level) wave \(index) is not reprised in place"
                )
                XCTAssertEqual(
                    waves[index].isFormation, waves[index + half].isFormation,
                    "level \(level) wave \(index) changes formation status on reprise"
                )
            }
        }
    }

    @MainActor
    func testTheRepriseIsNeverGentlerThanTheFirstPass() {
        // The whole point of the second half is that it is tighter. A regression that
        // swapped the multipliers would still produce a playable level, just a limp one.
        for level in 1...GameConfiguration.totalLevels {
            let waves = LevelManager.shared.getLevelConfig(for: level).waves
            let half = waves.count / 2

            for index in 0..<half where !waves[index].isFormation {
                XCTAssertLessThanOrEqual(
                    waves[index + half].spawnInterval, waves[index].spawnInterval,
                    "level \(level) wave \(index) spawns slower on its reprise than on its first pass"
                )
            }
        }
    }

    // MARK: - Early-level variety

    /// The concrete shape of "boring", and the thing the early levels were rebuilt to
    /// avoid: level 2 used to open with ten identical `.basic` in a row, and level 1 was
    /// thirty-two of them across the whole level. A single-type wave is fine and often
    /// deliberate — it is how a level introduces its headline enemy so the player can
    /// actually see it — but past about six in a row it stops being an introduction and
    /// starts being a queue.
    ///
    /// Bounded to the levels that teach the game. From level 8 the swarm enemies arrive
    /// (`.meteorSwarm` comes twelve and fourteen at a time) and a long identical run is
    /// exactly the intended effect there.
    @MainActor
    func testTeachingLevelsNeverQueueUpOneEnemyForTooLong() {
        let maxIdenticalRun = 6

        for level in 1...7 {
            let config = LevelManager.shared.getLevelConfig(for: level)

            for (index, wave) in config.waves.enumerated() where !wave.isFormation {
                var longestRun = 0
                var currentRun = 0
                var previous: EnemyType?

                for enemy in wave.enemies {
                    currentRun = (enemy == previous) ? currentRun + 1 : 1
                    longestRun = max(longestRun, currentRun)
                    previous = enemy
                }

                XCTAssertLessThanOrEqual(
                    longestRun, maxIdenticalRun,
                    "level \(level) wave \(index) sends \(longestRun) identical enemies in a row"
                )
            }
        }
    }

    /// Every level the player meets first has to offer more than one kind of beat — two
    /// enemy types, or a formation, which reads as a distinct beat even when it is built
    /// from an enemy already on screen. Level 1 passes on the formation alone, which is
    /// the whole reason its closing V exists.
    @MainActor
    func testEveryEarlyLevelOffersMoreThanOneKindOfBeat() {
        for level in 1...10 {
            let waves = LevelManager.shared.getLevelConfig(for: level).waves

            let distinctTypes = Set(waves.flatMap { $0.enemies })
            let formations = waves.filter { $0.isFormation }.count

            XCTAssertTrue(
                distinctTypes.count > 1 || formations > 0,
                "level \(level) is one enemy type delivered one way, start to finish"
            )
        }
    }

    @MainActor
    func testPacingTightensTheAuthoredCadenceWithoutClumping() {
        // Both ends of the pacing pass. Too loose and the playfield is empty, which is
        // the state this pass exists to fix; below the floor and a wave stops reading as
        // individual enemies at all.
        for level in 1...GameConfiguration.totalLevels {
            let config = LevelManager.shared.getLevelConfig(for: level)

            for (index, wave) in config.waves.enumerated() where !wave.isFormation {
                XCTAssertGreaterThanOrEqual(
                    wave.spawnInterval, GameConfiguration.minSpawnInterval,
                    "level \(level) wave \(index) spawns below the readable floor"
                )
                XCTAssertGreaterThanOrEqual(
                    wave.spawnDelay, GameConfiguration.minWaveDelay,
                    "level \(level) wave \(index) has no lead-in at all"
                )
            }
        }
    }

    @MainActor
    func testPacingScalesAnAuthoredWaveByTheConfiguredFactors() {
        // Direct on the pure helpers, so the multipliers are pinned to a worked example
        // rather than inferred from whatever the levels happen to contain.
        let authored = EnemyWave(enemies: [.basic, .basic], spawnDelay: 2.0, spawnInterval: 1.4)

        let paced = LevelManager.pacedWaves([authored])[0]
        XCTAssertEqual(paced.spawnInterval, 1.4 * GameConfiguration.waveIntervalScale, accuracy: 0.0001)
        XCTAssertEqual(paced.spawnDelay, 2.0 * GameConfiguration.waveDelayScale, accuracy: 0.0001)
        XCTAssertEqual(paced.enemies, authored.enemies)

        let reprised = LevelManager.reprisedWaves([authored])[0]
        XCTAssertEqual(
            reprised.spawnInterval,
            1.4 * GameConfiguration.waveIntervalScale * GameConfiguration.waveRepriseIntervalScale,
            accuracy: 0.0001
        )
        XCTAssertLessThan(reprised.spawnInterval, paced.spawnInterval)
    }

    @MainActor
    func testPacingLeavesFormationWavesAlone() {
        // A formation spawns as one unit in `EnemyManager.update(currentTime:)` and never
        // reads `spawnInterval`, so scaling it would be a silent no-op that only makes
        // the numbers lie about what the wave does.
        let authored = EnemyWave(
            enemies: [.scout, .scout],
            spawnDelay: 2.5,
            spawnInterval: 0.5,
            isFormation: true,
            formationPattern: .arrow
        )

        let paced = LevelManager.pacedWaves([authored])[0]
        XCTAssertEqual(paced.spawnInterval, 0.5, accuracy: 0.0001)
        XCTAssertTrue(paced.isFormation)
        XCTAssertEqual(paced.formationPattern, .arrow)
    }

    @MainActor
    func testObstacleAndAsteroidWavesCoverTheWholeLevel() {
        // Both are padded out to the enemy wave count so hazards keep coming for the
        // whole level rather than stopping halfway through.
        for level in 1...GameConfiguration.totalLevels {
            let config = LevelManager.shared.getLevelConfig(for: level)

            if !config.obstacleWaves.isEmpty {
                XCTAssertGreaterThanOrEqual(
                    config.obstacleWaves.count, config.waves.count,
                    "level \(level) runs out of obstacle waves before the enemies stop"
                )
            }
            if !config.asteroidWaves.isEmpty {
                XCTAssertGreaterThanOrEqual(
                    config.asteroidWaves.count, config.waves.count,
                    "level \(level) runs out of asteroid waves before the enemies stop"
                )
            }
        }
    }

    @MainActor
    func testPowerUpWeightsAreUsable() {
        for level in 1...GameConfiguration.totalLevels {
            let config = LevelManager.shared.getLevelConfig(for: level).powerUpConfig

            XCTAssertGreaterThan(config.spawnInterval, 0, "level \(level) power-ups would spawn every frame")
            XCTAssertTrue(
                (0...1).contains(config.spawnProbability),
                "level \(level) power-up probability \(config.spawnProbability) is outside 0...1"
            )
            XCTAssertFalse(config.typeWeights.isEmpty, "level \(level) has no power-up types")

            // The weighted picker walks cumulative weights against a random draw in
            // 0...total; a non-positive total or a negative weight breaks that.
            let total = config.typeWeights.values.reduce(0, +)
            XCTAssertGreaterThan(total, 0, "level \(level) power-up weights sum to \(total)")
            for (type, weight) in config.typeWeights {
                XCTAssertGreaterThanOrEqual(weight, 0, "level \(level) weights \(type) negatively")
            }
        }
    }

    @MainActor
    func testOutOfRangeLevelsStillReturnAConfig() {
        // Reached if a saved progress value ever outruns totalLevels.
        for level in [0, -1, GameConfiguration.totalLevels + 1, 999] {
            let config = LevelManager.shared.getLevelConfig(for: level)
            XCTAssertFalse(config.waves.isEmpty, "level \(level) fell through to an unplayable config")
        }
    }

    @MainActor
    func testFirstLevelIsAlwaysUnlocked() {
        XCTAssertTrue(LevelManager.shared.isLevelUnlocked(1))
    }

    @MainActor
    func testLevelWeaponsDefaultToTheStartingArsenal() {
        // An unplayed level must report the opening loadout, not zero guns — a zero
        // here would hand the player a ship that cannot shoot.
        let weapons = LevelManager.shared.getLevelWeapons(level: GameConfiguration.totalLevels + 500)
        XCTAssertEqual(weapons.bulletCount, 1)
        XCTAssertEqual(weapons.sideMissileCount, 0)
    }
}
