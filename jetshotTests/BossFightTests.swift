//
//  BossFightTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Drives a real boss fight inside a running `GameScene`.
///
/// The boss is the completion gate for every level: once `spawnBoss()` sets
/// `bossSpawned`, `checkLevelCompletion()` stops counting enemies and the only way out
/// of the level is killing it. Nothing here was reachable from a test before —
/// `spawnBoss()` fires only after every wave of the level has spawned *and* the
/// playfield has stayed clear, which is minutes of real time per level — so the fight
/// is entered through `GameScene.bossManager` directly.
///
/// Damage is deliberately taken from both sides of the seam: `bossTakeDamage()` for the
/// arithmetic, and real bullets through `didBegin(_:)` for the parts of the contract that
/// only `GameScene` enforces.
///
/// Each test builds its own harness and tears it down with `defer`, matching the rest of
/// the gameplay suite — an `XCTestCase` `setUp`/`tearDown` pair is nonisolated and cannot
/// touch main-actor state without warnings.
@MainActor
final class BossFightTests: XCTestCase {

    /// Entrance is a 2.0s `moveTo`; the boss only becomes fightable on its completion.
    private let entranceDuration: TimeInterval = 2.0

    /// Level 2 rather than 1 by default: level 1 adds the "3 2 1" countdown, and none of
    /// these tests need the intro. `startPlaying()` skips waiting for player control,
    /// which the boss does not depend on.
    @discardableResult
    private func startFight(_ harness: GameplayHarness, level: Int = 2) -> Boss {
        harness.startPlaying(level: level)

        harness.scene.bossManager.spawnBoss(level: level) {}
        harness.spin(0.05)

        guard let boss = harness.gameContent.children.compactMap({ $0 as? Boss }).first else {
            XCTFail("spawnBoss did not attach a Boss to the playfield")
            return Boss(config: BossConfig.config(for: level), sceneSize: harness.scene.size)
        }
        return boss
    }

    private func waitForEntrance(_ harness: GameplayHarness) {
        harness.spin(entranceDuration + 0.4)
    }

    // MARK: - Entrance

    func testBossEntersThePlayfieldWithItsHealthBar() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness)

        XCTAssertNotNil(boss.parent, "the boss is not attached to the playfield")
        XCTAssertTrue(
            boss.isHealthBarAttached,
            "the boss arrived without a health bar, so the fight has no visible progress"
        )
    }

    /// The bar hangs a fixed drop below the *HUD margin* of the scene it joins.
    ///
    /// Both halves of that used to be wrong, because the placement was computed in
    /// `Boss.init`. The node has no scene there, so the safe-area lookup it did could only
    /// ever return 0 — pinning the margin to `minTopMargin` and pulling the bar (and the
    /// "⚡ BOSS ⚡" label riding 30pt above it) up into the score-and-lives band on every
    /// notched device. And the height it measured against was whatever `init` was handed,
    /// which is why this builds the boss for a scene nothing like the one it attaches to.
    ///
    /// The margin arithmetic itself is pinned by `GameConfigurationTests`; what this adds
    /// is that the boss actually routes through it, against a live view, at attach time.
    func testHealthBarHangsBelowTheHUDMarginOfTheSceneItJoins() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlaying(level: 2)

        let boss = Boss(config: BossConfig.config(for: 2), sceneSize: CGSize(width: 120, height: 120))
        boss.addHealthBarToScene(harness.scene)

        XCTAssertEqual(
            boss.healthBarY,
            harness.scene.size.height
                - GameConfiguration.topMargin(in: harness.view)
                - Boss.healthBarDropBelowHUD,
            accuracy: 0.5,
            "the health bar is not measured down from the HUD margin of the scene it joined"
        )
    }

    /// The bar goes the moment the boss dies, not when the explosion sequence finishes
    /// removing the boss — otherwise an empty bar sits over the level-complete handoff.
    func testTheHealthBarGoesAwayTheInstantTheBossDies() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 1)
        waitForEntrance(harness)

        for _ in 0..<BossConfig.config(for: 1).maxHealth {
            _ = harness.scene.bossManager.bossTakeDamage()
        }

        XCTAssertFalse(
            boss.isHealthBarAttached,
            "the health bar outlived the boss it was tracking"
        )
    }

    /// `isAlive()` is `isActive && currentHealth > 0`, and `isActive` is only set by the
    /// entrance animation's completion. Until then the boss is on screen but not yet a
    /// legal target — which is what `bulletDidCollideWithBoss` checks before doing
    /// anything.
    func testBossIsNotFightableUntilItsEntranceFinishes() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        startFight(harness)

        XCTAssertFalse(
            harness.scene.bossManager.isBossActive(),
            "the boss was fightable while still flying in"
        )

        waitForEntrance(harness)

        XCTAssertTrue(
            harness.scene.bossManager.isBossActive(),
            "the boss never became fightable, so its level can never be completed"
        )
    }

    /// The entrance guard has to hold against real contacts, not just direct queries:
    /// bullets fired while the boss is still gliding in are absorbed, and the boss must
    /// still need its full health afterwards.
    func testBulletsFiredDuringTheEntranceDoNoDamage() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 1)
        let health = BossConfig.config(for: 1).maxHealth

        // Bullets land on the boss while it is mid-entrance.
        for _ in 0..<10 {
            harness.fireBullets(onto: boss.position)
            harness.spin(0.05)
        }

        waitForEntrance(harness)

        // If any of those bullets had registered, the boss would die early.
        for hit in 1..<health {
            let result = harness.scene.bossManager.bossTakeDamage()
            XCTAssertFalse(
                result.defeated,
                "the boss died on hit \(hit) of \(health) — entrance bullets were counted"
            )
        }
        XCTAssertTrue(
            harness.scene.bossManager.bossTakeDamage().defeated,
            "the boss survived its full health in hits"
        )
    }

    /// The patrol has to actually cross the screen, on the biggest boss in the game.
    ///
    /// `startMovement()` insets each edge by a margin derived from `config.size`, and
    /// using the full silhouette rather than its half width collapsed the sweep: the
    /// level 50 boss (size 200) travelled two points on a 402pt iPhone, and on a 375pt
    /// screen the range inverted. Neither crashed — `moveTo` takes any coordinate — so
    /// the boss just sat still. Sampled over one full leg (`movementSpeed` is 1.0s here).
    func testTheLargestBossPatrolsAcrossTheScreen() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: GameConfiguration.totalLevels)
        waitForEntrance(harness)

        var lowest = boss.position.x
        var highest = boss.position.x
        for _ in 0..<30 {
            harness.spin(0.1)
            lowest = min(lowest, boss.position.x)
            highest = max(highest, boss.position.x)
        }

        let sweep = highest - lowest
        let sceneWidth = harness.scene.size.width
        XCTAssertGreaterThan(
            sweep, sceneWidth * 0.25,
            "the largest boss swept only \(sweep)pt of a \(sceneWidth)pt screen — its patrol has collapsed"
        )

        // And it must stay on screen while doing it.
        let halfWidth = BossConfig.config(for: GameConfiguration.totalLevels).size * 0.5
        XCTAssertGreaterThanOrEqual(lowest, halfWidth * 0.5, "the boss patrolled off the left edge")
        XCTAssertLessThanOrEqual(
            highest, sceneWidth - halfWidth * 0.5,
            "the boss patrolled off the right edge"
        )
    }

    // MARK: - Damage

    func testBossDiesAfterExactlyItsConfiguredHealthInHits() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        startFight(harness, level: 1)
        waitForEntrance(harness)

        let config = BossConfig.config(for: 1)

        for hit in 1..<config.maxHealth {
            XCTAssertFalse(
                harness.scene.bossManager.bossTakeDamage().defeated,
                "the boss died on hit \(hit), short of its \(config.maxHealth) health"
            )
        }

        let killing = harness.scene.bossManager.bossTakeDamage()
        XCTAssertTrue(killing.defeated, "the boss outlived its own health total")
        XCTAssertEqual(
            killing.points, config.points,
            "the kill paid \(killing.points) instead of the configured \(config.points)"
        )
    }

    /// A defeated boss reports itself inactive, which is the single condition both damage
    /// paths check before paying out — `bulletDidCollideWithBoss` and the lightning
    /// sweep in `shootLightning()`. Without it `takeDamage()` would keep clamping health
    /// to zero and keep returning "defeated", awarding the boss's points once per bullet
    /// still in the air.
    func testADefeatedBossStopsBeingAValidTarget() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        startFight(harness, level: 1)
        waitForEntrance(harness)

        for _ in 0..<BossConfig.config(for: 1).maxHealth {
            _ = harness.scene.bossManager.bossTakeDamage()
        }

        XCTAssertFalse(
            harness.scene.bossManager.isBossActive(),
            "a dead boss still reports itself fightable, so its points can be collected twice"
        )
    }

    /// The same invariant from the outside: bullets arriving after the kill must not pay
    /// the bounty a second time.
    func testBulletsArrivingAfterTheKillDoNotPayOutAgain() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 1)
        waitForEntrance(harness)

        let config = BossConfig.config(for: 1)
        for _ in 0..<config.maxHealth {
            _ = harness.scene.bossManager.bossTakeDamage()
        }

        let scoreAfterKill = harness.scene.currentScore

        for _ in 0..<6 {
            harness.fireBullets(onto: boss.position)
            harness.spin(0.05)
        }

        // Bounded rather than fixed: the level is still running, so a coin reaching the
        // ship during these few frames legitimately adds its 10 points. A second bounty
        // would add \(config.points).
        XCTAssertLessThan(
            harness.scene.currentScore, scoreAfterKill + config.points,
            "late bullets paid out the boss bounty again"
        )
    }

    /// Closes the loop on the contact path itself: real bullets, dispatched through
    /// `didBegin(_:)`, have to be what kills the boss and pays the score. Everything
    /// above drives `bossTakeDamage()` directly, which would pass even if the physics
    /// wiring were broken.
    func testRealBulletContactsKillTheBossAndPayTheScore() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 1)
        waitForEntrance(harness)

        let config = BossConfig.config(for: 1)
        let scoreBefore = harness.scene.currentScore

        // Generous budget: contacts are reported per physics step, so a step that
        // registers only one of several parked bullets simply needs more rounds.
        var rounds = 0
        while harness.scene.bossManager.isBossActive() && rounds < 200 {
            harness.fireBullets(onto: boss.position)
            harness.spin(0.03)
            rounds += 1
        }

        XCTAssertFalse(
            harness.scene.bossManager.isBossActive(),
            "\(rounds) rounds of real bullet contacts never killed a \(config.maxHealth) health boss — "
            + "the bullet/boss contact path is not wired up"
        )
        XCTAssertGreaterThanOrEqual(
            harness.scene.currentScore, scoreBefore + config.points,
            "the boss kill did not pay its \(config.points) points"
        )
    }

    // MARK: - Teardown

    func testCleanupDetachesTheBossAndItsHealthBar() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness)
        waitForEntrance(harness)

        harness.scene.bossManager.cleanup()

        XCTAssertNil(boss.parent, "cleanup left the boss in the playfield")
        XCTAssertFalse(boss.isHealthBarAttached, "cleanup left the health bar in the HUD")
        XCTAssertFalse(harness.scene.bossManager.isBossActive())
        XCTAssertFalse(
            harness.gameContent.children.contains(where: { $0 is Boss }),
            "a Boss node survived cleanup"
        )
    }

    /// `cleanup()` is called from `GameScene.willMove(from:)` and can also be reached by
    /// a fight that ends normally, so it has to tolerate running twice.
    func testCleanupIsIdempotent() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        startFight(harness)
        waitForEntrance(harness)

        harness.scene.bossManager.cleanup()
        harness.scene.bossManager.cleanup()

        XCTAssertFalse(harness.scene.bossManager.isBossActive())
    }

    /// Leaving the scene has to take the boss with it. `BossManager` deliberately has no
    /// `deinit` — it would touch SKNode state off the main actor — so
    /// `willMove(from:)` is the only thing that detaches the boss, and a regression here
    /// leaks the boss and its health bar into the next scene.
    func testLeavingTheSceneTearsTheBossDown() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness)
        waitForEntrance(harness)

        harness.teardown()

        XCTAssertNil(boss.parent, "the boss outlived the scene that owned it")
    }
}
