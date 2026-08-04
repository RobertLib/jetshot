//
//  LevelConfigTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// `getLevelConfig(for:)` duplicates waves at random to double each level's length,
/// using `while` loops driven by `randomElement()`. Those loops are only safe because
/// the arrays they draw from are non-empty — worth pinning down for all 50 levels
/// rather than discovering it as a hang on level 43.
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
        // The generator appends one duplicate per original wave.
        for level in 1...GameConfiguration.totalLevels {
            let config = LevelManager.shared.getLevelConfig(for: level)
            XCTAssertEqual(
                config.waves.count % 2, 0,
                "level \(level) has an odd wave count, so the doubling pass did not run"
            )
        }
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
