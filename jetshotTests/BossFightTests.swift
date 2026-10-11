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

    /// The health a boss is actually fought through: its authored figure scaled to the
    /// current fire rate. See `CombatRules.bossHealth(authored:)`.
    static func fightHealth(level: Int) -> Int {
        return CombatRules.bossHealth(authored: BossConfig.config(for: level).maxHealth)
    }


    /// Entrance is a 2.0s `moveTo`; the boss only becomes fightable on its completion.
    private let entranceDuration: TimeInterval = 2.0

    /// Level 2 rather than 1 by default: level 1 is the only level with tutorial hints
    /// and a longer title card, and none of these tests need the intro. `startPlaying()`
    /// skips waiting for player control, which the boss does not depend on.
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

        for _ in 0..<Self.fightHealth(level: 1) {
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
        let health = Self.fightHealth(level: 1)

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
    /// `enterScene(completion:)` insets each edge of the arena by a margin derived from
    /// `config.size`, and using the full silhouette rather than its half width collapsed
    /// the sweep: the level 50 boss of the time (size 200; the heart there now is 220)
    /// travelled two points on a 402pt iPhone, and on a 375pt screen the range inverted.
    /// Neither crashed — any coordinate is a valid position — so the boss just sat still.
    /// Sampled over three seconds, most of one full orbit: the heart's leg is 1.0 s, and
    /// an orbit sweeps one way in 1.6 legs.
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

        let health = Self.fightHealth(level: 1)
        for hit in 1..<health {
            XCTAssertFalse(
                harness.scene.bossManager.bossTakeDamage().defeated,
                "the boss died on hit \(hit), short of its \(health) health"
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

        for _ in 0..<Self.fightHealth(level: 1) {
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
        for _ in 0..<Self.fightHealth(level: 1) {
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

    /// The same invariant enforced by the boss rather than by its callers: a blow landed
    /// on a dead boss — through `bossTakeDamage` directly, with nothing in front of it
    /// checking first — must not be a second kill. It used to run `die()` again and
    /// report "defeated" with the full bounty a second time.
    func testASecondKillingBlowIsNoKill() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 1)
        waitForEntrance(harness)

        let manager = harness.scene.bossManager!
        let kill = manager.bossTakeDamage(amount: boss.maxHealthPoints)
        XCTAssertTrue(kill.defeated)

        let again = manager.bossTakeDamage(amount: boss.maxHealthPoints, part: boss.parts.first)
        XCTAssertFalse(again.defeated, "a dead boss was killed a second time")
        XCTAssertEqual(again.points, 0, "a dead boss paid its bounty a second time")
        XCTAssertEqual(again.partBonus, 0, "a dead boss's pod paid out")
        XCTAssertFalse(boss.takeDamage(amount: 1), "a dead boss took the killing blow again")
    }

    /// Damage before the entrance finishes is refused by the boss itself, not only by
    /// `GameScene`'s check in front of it.
    func testABossStillFlyingInTakesNoDamage() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 1)
        let early = harness.scene.bossManager.bossTakeDamage(amount: boss.maxHealthPoints)

        XCTAssertFalse(early.defeated, "the boss was killed while still flying in")
        XCTAssertEqual(boss.healthFraction, 1, "the boss took damage while still flying in")
    }

    // MARK: - Health bar

    /// The charge drains from both ends towards the middle, so each phase threshold is a
    /// pair of notches, one where each end of the charge sits when the threshold is
    /// crossed. They used to be single notches measured from the left end, as if the
    /// charge drained to the left: the first threshold was marked nowhere, and the
    /// charge reached both notches at once on the second.
    func testThePhaseNotchesSitWhereTheChargeEndsAtEachThreshold() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 1)
        waitForEntrance(harness)

        let notches = boss.phaseNotchXs
        XCTAssertEqual(notches.count, 2 * BossPhaseRules.thresholds.count, "one pair of notches per threshold")
        for x in notches {
            XCTAssertTrue(notches.contains { abs($0 + x) < 0.5 }, "the notch at \(x) has no partner across the middle")
        }

        // One hit's worth of charge: crossing a threshold can overshoot it by that much.
        let oneHit = boss.healthBarFillHalfWidth / CGFloat(boss.maxHealthPoints)
        for (index, threshold) in BossPhaseRules.thresholds.enumerated() {
            while boss.currentPhase <= index {
                _ = harness.scene.bossManager.bossTakeDamage()
            }
            let edge = boss.healthBarFillHalfWidth
            for end in [edge, -edge] {
                XCTAssertTrue(
                    notches.contains { abs($0 - end) <= oneHit + 0.5 },
                    "crossing \(threshold) left the end of the charge at \(end), on no notch (\(notches.sorted()))"
                )
            }
        }
    }

    // MARK: - Flight

    /// The boss eases from where its entrance leaves it onto its flight path. The
    /// serpent's figure of eight starts 40 points below the station it flies in to, and
    /// taking the path's first point literally dropped it there in a single frame.
    func testTheBossEasesOntoItsFlightPathInsteadOfJumping() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 6)
        XCTAssertEqual(boss.config.archetype, .serpent)

        // Late in the entrance, where it has all but stopped, through the hand-over.
        harness.spin(entranceDuration - 0.4)
        var last = boss.position
        var worst: CGFloat = 0
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline {
            harness.spin(0.01)
            worst = max(worst, abs(boss.position.y - last.y))
            last = boss.position
        }

        XCTAssertLessThan(worst, 20, "the boss jumped \(worst)pt in one frame as its flight began")
    }

    // MARK: - Attacks

    /// Every attack reports at least as long as its own volley takes to play out, so the
    /// next one never winds up while it is still firing. The older patterns reported
    /// nothing, and the warden's pod volley a fraction of its length.
    func testEveryAttackReportsHowLongItKeepsTheBossBusy() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        // Level 26: the warden with four pods, whose pod volley is the longest.
        startFight(harness, level: 26)
        waitForEntrance(harness)

        let manager = harness.scene.bossManager!
        var busy: [BossAttackPattern: TimeInterval] = [:]
        for pattern in BossAttackPattern.allCases {
            busy[pattern] = manager.performAttack(pattern)
            XCTAssertGreaterThanOrEqual(
                busy[pattern] ?? 0, manager.lastAttackVolleyLength - 1e-9,
                "\(pattern) reports \(busy[pattern] ?? 0)s busy, but its volley runs \(manager.lastAttackVolleyLength)s"
            )
        }
        XCTAssertGreaterThan(busy[.doubleSpiral] ?? 0, 1.5, "the double spiral counts as instantaneous")
        XCTAssertGreaterThan(busy[.podVolley] ?? 0, 1.5, "four pods' bursts count as a fraction of their length")
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
            "\(rounds) rounds of real bullet contacts never killed a \(Self.fightHealth(level: 1)) health boss — "
            + "the bullet/boss contact path is not wired up"
        )
        XCTAssertGreaterThanOrEqual(
            harness.scene.currentScore, scoreBefore + config.points,
            "the boss kill did not pay its \(config.points) points"
        )
    }

    // MARK: - Parts

    /// Level 1's warden carries two gun pods. Taking one off pays a bonus, takes its
    /// muzzle out of the fight and leaves the other one firing.
    func testShootingAPartOffPaysAndSilencesIt() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 1)
        waitForEntrance(harness)
        XCTAssertEqual(boss.parts.count, 2, "the warden lost its pods")
        XCTAssertEqual(boss.liveMuzzles().count, 2)

        let pod = boss.parts[0]
        let result = harness.scene.bossManager.bossTakeDamage(amount: pod.health, part: pod)
        harness.spin(0.1)

        XCTAssertTrue(pod.isDestroyed, "a pod's full health in damage did not destroy it")
        XCTAssertGreaterThan(result.partBonus, 0, "shooting a pod off paid nothing")
        XCTAssertNil(pod.physicsBody, "a destroyed pod still soaks up rounds")
        XCTAssertEqual(boss.liveMuzzles().count, 1, "the destroyed pod is still firing")
        XCTAssertNotNil(boss.muzzle(boss.liveMuzzles()[0]))

        let again = harness.scene.bossManager.bossTakeDamage(amount: 1, part: pod)
        XCTAssertEqual(again.partBonus, 0, "a pod paid out twice")
    }

    /// Going for the guns must never make the fight longer: every round that lands on a
    /// part comes off the boss's own health as well.
    func testHitsOnAPartAlsoComeOffTheBoss() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 1)
        waitForEntrance(harness)

        let health = Self.fightHealth(level: 1)
        let pod = boss.parts[1]
        for hit in 1..<health {
            XCTAssertFalse(
                harness.scene.bossManager.bossTakeDamage(amount: 1, part: pod).defeated,
                "the boss died on hit \(hit) of \(health) through its pod"
            )
        }
        XCTAssertTrue(harness.scene.bossManager.bossTakeDamage(amount: 1, part: pod).defeated,
                      "rounds on a pod did not count against the boss")
    }

    /// The contact path: real bullets parked on a pod, dispatched through
    /// `didBegin(_:)`, destroy it.
    func testRealBulletsOnAPartDestroyIt() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 1)
        waitForEntrance(harness)

        let pod = boss.parts[0]
        var rounds = 0
        while !pod.isDestroyed && harness.scene.bossManager.isBossActive() && rounds < 200 {
            harness.fireBullets(onto: harness.scenePosition(of: pod))
            harness.spin(0.03)
            rounds += 1
        }
        XCTAssertTrue(pod.isDestroyed, "\(rounds) rounds of real fire on a pod never took it off")
    }

    /// The serpent's segments follow the head: they are spread out along its wake, not
    /// stacked on it.
    func testTheSerpentsSegmentsTrailBehindItsHead() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 6)
        XCTAssertEqual(boss.config.archetype, .serpent)
        waitForEntrance(harness)
        harness.spin(1.5)

        var previous = CGPoint.zero
        for part in boss.parts {
            let gap = hypot(part.position.x - previous.x, part.position.y - previous.y)
            XCTAssertGreaterThan(gap, boss.bossSize * 0.2, "segment \(part.index) is bunched up on the one before it")
            previous = part.position
        }
    }

    // MARK: - Hazards

    /// Flying into the hull costs the hit, the way flying into any other enemy does.
    /// The mantis's dive depends on it.
    func testFlyingIntoTheBossCostsTheHit() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let boss = startFight(harness, level: 2)
        waitForEntrance(harness)

        let player = harness.player
        XCTAssertNil(player.action(forKey: "invulnerability"), "player started out already hit")
        for _ in 0..<10 {
            player.position = boss.position
            harness.spin(0.05)
        }
        XCTAssertNotNil(player.action(forKey: "invulnerability"), "ramming the boss did not hurt the player")
    }

    /// A beam is not used up by the ship it hits: it keeps burning for its full length.
    /// Every other hostile round is removed on contact.
    func testABeamSurvivesHittingTheShip() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlaying(level: 2)

        let player = harness.player
        player.position = CGPoint(x: 200, y: 300)
        let beam = SKNode()
        beam.name = "bosslaser"
        beam.position = player.position
        let body = SKPhysicsBody(rectangleOf: CGSize(width: 14, height: 400))
        body.categoryBitMask = PhysicsCategory.enemyBullet
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        body.isDynamic = false
        beam.physicsBody = body
        harness.gameContent.addChild(beam)
        harness.spin(0.5)

        XCTAssertNotNil(player.action(forKey: "invulnerability"), "the beam did not hurt the player")
        XCTAssertNotNil(beam.parent, "the beam was consumed by the ship like a bullet")
    }

    /// Whatever the boss leaves on the playfield besides bullets — beams, warnings,
    /// portals — goes with it.
    func testCleanupSweepsTheBossesHazards() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        startFight(harness)
        waitForEntrance(harness)
        for name in ["bosslaser", "bossFX"] {
            let node = SKNode()
            node.name = name
            harness.gameContent.addChild(node)
        }

        harness.scene.bossManager.cleanup()

        XCTAssertNil(harness.gameContent.childNode(withName: "bosslaser"), "a beam outlived the boss")
        XCTAssertNil(harness.gameContent.childNode(withName: "bossFX"), "a warning outlived the boss")
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
