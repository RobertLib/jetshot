//
//  EndlessRoundRenewalTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// What an endless round renews besides its enemy waves — the power-up table, the coin
/// allowance and the hazard track — and the round count itself after a boss.
///
/// Every one of these came from the campaign's one-level-per-scene shape: set up once
/// from level 1's configuration and never touched again, which an endless run outlives
/// within a minute. None of them fails loudly. The run just quietly stops dropping the
/// good power-ups, stops paying coins, drags hazards from rounds long gone, or repeats a
/// round number — so they are pinned here rather than left to be noticed.
///
/// See `GameplayHarness` for how the scene is brought up.
@MainActor
final class EndlessRoundRenewalTests: XCTestCase {

    /// Spins until `condition` holds, and reports whether it did.
    private func wait(_ harness: GameplayHarness, upTo timeout: TimeInterval,
                      until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            harness.spin(0.05)
        }
        return condition()
    }

    // MARK: - Power-up table

    /// Round 12 borrows level 24's hazards, so it should draw level 24's power-ups — the
    /// full arsenal — and not level 1's six beginner types.
    func testADeepRoundDrawsTheDeepLevelsPowerUps() throws {
        let harness = GameplayHarness()
        harness.startPlayingWithControl(endless: true)
        defer { harness.teardown() }

        let opening = try XCTUnwrap(harness.scene.powerUpSpawnTable, "no power-up spawner was built")
        XCTAssertNil(opening.typeWeights[.nuke], "round one is already dropping nukes")

        harness.scene.debugSetEndlessRound(12)
        harness.spin(0.4) // `debugSetEndlessRound` polls on a 0.1 s tick

        let deep = try XCTUnwrap(harness.scene.powerUpSpawnTable)
        let expected = LevelManager.shared
            .getLevelConfig(for: EndlessRules.hazardLevel(forRound: 12)).powerUpConfig
        XCTAssertEqual(Set(deep.typeWeights.keys), Set(expected.typeWeights.keys),
                       "round 12 is not drawing the power-up table of the level its hazards come from")
        XCTAssertEqual(deep.spawnInterval, expected.spawnInterval, accuracy: 1e-9)

        for type in [PowerUpType.lightning, .homingMissiles, .barrier, .freezeBomb,
                     .slowMotion, .scoreMultiplier, .nuke] {
            XCTAssertNotNil(deep.typeWeights[type], "\(type) can never drop at round 12")
        }
    }

    // MARK: - Coin allowance

    /// A `CoinManager` on a plain scene, driven on a fake clock: the cap and its refresh
    /// are pure bookkeeping, and a real level would take minutes to reach the cap.
    private func drive(_ coins: CoinManager, from clock: inout TimeInterval, for seconds: TimeInterval) {
        let end = clock + seconds
        while clock < end {
            clock += 0.05
            coins.update(currentTime: clock)
        }
    }

    func testTheCoinCapStopsTheSpawnerAndARefreshRestartsIt() {
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        let config = CoinSpawnConfig(spawnInterval: 0.1, spawnProbability: 1.0, minCoins: 5, maxCoins: 5)
        let coins = CoinManager(scene: scene, config: config)
        var clock: TimeInterval = 1

        drive(coins, from: &clock, for: 3)
        let capped = coins.totalCoinsSpawned
        XCTAssertGreaterThanOrEqual(capped, 5, "the spawner never reached its cap")
        XCTAssertEqual(coins.remainingAllowance, 0)

        drive(coins, from: &clock, for: 3)
        XCTAssertEqual(coins.totalCoinsSpawned, capped, "the spawner ran past its cap")

        coins.refreshAllowance()
        XCTAssertEqual(coins.remainingAllowance, 5, "a refresh did not grant a fresh level's worth")

        drive(coins, from: &clock, for: 3)
        XCTAssertGreaterThan(coins.totalCoinsSpawned, capped,
                             "a refreshed allowance did not restart the spawner")
    }

    /// Allowance a boss round leaves unspent is not banked into a flood afterwards.
    func testARefreshDoesNotCarryUnspentAllowanceOver() {
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        let config = CoinSpawnConfig(spawnInterval: 0.1, spawnProbability: 1.0, minCoins: 5, maxCoins: 5)
        let coins = CoinManager(scene: scene, config: config)

        coins.refreshAllowance()
        coins.refreshAllowance()
        XCTAssertEqual(coins.remainingAllowance, 5)
    }

    // MARK: - Round count after a boss

    /// The round 5 boss is round 5; the run picks up at round 6 after it.
    func testTheRoundAfterABossIsTheNextRound() throws {
        let harness = GameplayHarness()
        harness.startPlayingWithControl(endless: true)
        defer { harness.teardown() }
        harness.scene.debugSetInvulnerable(true)

        harness.scene.debugSetEndlessRound(5)
        XCTAssertTrue(wait(harness, upTo: 8) { harness.scene.bossManager.isBossActive() },
                      "the round 5 boss never became fightable")
        XCTAssertEqual(harness.scene.endlessRound, 5)

        // Down to its last point, then killed by a real round so the scene's own defeat
        // path — and with it the aftermath that resumes the run — is what runs.
        let boss = try XCTUnwrap(harness.scene.bossManager.getBoss())
        _ = harness.scene.bossManager.bossTakeDamage(amount: boss.maxHealthPoints - 1)
        XCTAssertTrue(wait(harness, upTo: 4) {
            if harness.scene.bossManager.isBossActive() { harness.fireBullets(onto: boss.position) }
            return !harness.scene.bossManager.isBossActive()
        }, "real rounds never finished the boss")

        XCTAssertTrue(wait(harness, upTo: 8) { harness.scene.isPerkPickerUp },
                      "the boss's defeat never offered a perk")
        XCTAssertEqual(harness.scene.endlessRound, 5, "the round moved on before the pick")

        harness.spin(0.5) // let the cards slide in
        let card = try XCTUnwrap(harness.scene.debugPerkCardCentre(0), "the picker showed no cards")
        harness.touchDown(at: card)
        harness.touchUp(at: card)
        harness.spin(1.0)

        XCTAssertFalse(harness.scene.isPerkPickerUp)
        XCTAssertEqual(harness.scene.endlessRound, 6,
                       "the run resumed on the boss's own round number instead of the next one")
        XCTAssertFalse(EndlessRules.isBossRound(harness.scene.endlessRound))
    }

    // MARK: - Hazards

    func testReplacingTheAsteroidTrackDropsWhatWasStillQueued() {
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        let manager = AsteroidManager(scene: scene, waves: [
            AsteroidWave(count: 30, size: .small, spawnDelay: 0, spawnInterval: 0.1)
        ])
        var clock: TimeInterval = 1
        for _ in 0..<10 {
            clock += 0.11
            manager.update(currentTime: clock)
        }
        let spawnedBefore = manager.totalAsteroidsSpawned
        XCTAssertGreaterThan(spawnedBefore, 0, "nothing spawned, so this proves nothing")

        manager.replaceWaves([AsteroidWave(count: 3, size: .small, spawnDelay: 0, spawnInterval: 0.1)],
                             currentTime: clock)
        XCTAssertEqual(manager.totalAsteroidsToSpawn - manager.totalAsteroidsSpawned, 3)

        for _ in 0..<100 {
            clock += 0.11
            manager.update(currentTime: clock)
        }
        XCTAssertEqual(manager.totalAsteroidsSpawned, spawnedBefore + 3,
                       "the replaced track kept spawning behind the new one")
    }

    func testReplacingTheObstacleTrackDropsWhatWasStillQueued() {
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        let manager = ObstacleManager(scene: scene, waves: [
            ObstacleWave(obstacles: Array(repeating: .spinner, count: 20), spawnDelay: 0,
                         spawnInterval: 0.1, minSpacing: 80),
            ObstacleWave(obstacles: [.wall, .wall], spawnDelay: 0, spawnInterval: 0.1, minSpacing: 80)
        ])
        var clock: TimeInterval = 1
        for _ in 0..<6 {
            clock += 0.11
            manager.update(currentTime: clock)
        }
        let spawnedBefore = scene.children.filter { $0.name == "obstacle" }.count
        XCTAssertGreaterThan(spawnedBefore, 0, "nothing spawned, so this proves nothing")

        manager.replaceWaves([
            ObstacleWave(obstacles: [.spinner, .spinner], spawnDelay: 0, spawnInterval: 0.1, minSpacing: 80)
        ], currentTime: clock)
        XCTAssertEqual(manager.queuedWaveCount, 1)

        for _ in 0..<100 {
            clock += 0.11
            manager.update(currentTime: clock)
        }
        XCTAssertEqual(scene.children.filter { $0.name == "obstacle" }.count, spawnedBefore + 2,
                       "the replaced track kept spawning behind the new one")
        XCTAssertEqual(manager.queuedWaveCount, 0)
    }

    /// In a running run: two rounds begun back to back leave exactly the second round's
    /// hazards queued — not the second's behind the first's behind the opening track.
    func testEachRoundQueuesOnlyItsOwnHazards() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl(endless: true)
        defer { harness.teardown() }

        harness.scene.debugSetEndlessRound(2)
        harness.spin(0.3)
        harness.scene.debugSetEndlessRound(3)
        harness.spin(0.3)

        let round3 = LevelManager.shared.endlessHazardWaves(forRound: 3)
        let queued = harness.scene.queuedHazards
        XCTAssertLessThanOrEqual(queued.obstacleWaves, round3.obstacles.count,
                                 "earlier rounds' walls are still queued ahead of round 3's")
        XCTAssertLessThanOrEqual(queued.asteroids, round3.asteroids.reduce(0) { $0 + $1.count },
                                 "earlier rounds' asteroids are still queued ahead of round 3's")
        XCTAssertGreaterThan(queued.obstacleWaves + queued.asteroids, 0,
                             "round 3 queued no hazards at all")
    }
}
