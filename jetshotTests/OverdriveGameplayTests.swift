//
//  OverdriveGameplayTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The shard → meter → Overdrive loop, end to end in a running scene: a kill throws
/// shards, a full meter fires from a second finger, the burst clears hostile fire, and
/// a full meter absorbs a hit that would otherwise have cost a life.
///
/// See `GameplayHarness` for how the scene is brought up.
final class OverdriveGameplayTests: XCTestCase {

    @MainActor
    func testAKillBurstsIntoShards() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        XCTAssertEqual(harness.scene.liveShardCount, 0)

        let enemy = harness.addEnemy(.fast, at: CGPoint(x: 200, y: 600))
        harness.player.position = CGPoint(x: 200, y: 200)
        harness.fireBullets(onto: enemy.position)
        harness.spin(0.3)

        XCTAssertNil(enemy.parent, "the enemy survived, so this test proves nothing")
        XCTAssertGreaterThan(harness.scene.liveShardCount, 0, "the kill threw no shards")
    }

    /// Shards that reach the ship are collected and charge the meter.
    @MainActor
    func testCollectingShardsChargesTheMeter() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        // Killed right on top of the ship, so the shards are inside the pull radius.
        let enemy = harness.addEnemy(.tank, at: CGPoint(x: harness.player.position.x, y: harness.player.position.y + 60))
        enemy.health = 1
        harness.fireBullets(onto: enemy.position)
        harness.spin(2.0)

        XCTAssertGreaterThan(harness.scene.overdriveCharge, 0, "collected shards did not charge the meter")
    }

    @MainActor
    func testASecondFingerFiresAFullMeter() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugFillOverdrive()
        XCTAssertFalse(harness.scene.isOverdriveActive)

        harness.touchDown(at: CGPoint(x: harness.player.position.x, y: harness.player.position.y - 40))
        harness.secondFingerTap(at: CGPoint(x: 80, y: 500))
        harness.spin(0.1)

        XCTAssertTrue(harness.scene.isOverdriveActive, "a second finger on a full meter did not fire it")
        XCTAssertEqual(harness.scene.overdriveCharge, 0, accuracy: 1e-9, "firing did not spend the meter")
    }

    /// Without a full meter a second finger is just a finger: nothing fires.
    @MainActor
    func testASecondFingerOnAnEmptyMeterDoesNothing() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.touchDown(at: CGPoint(x: harness.player.position.x, y: harness.player.position.y - 40))
        harness.secondFingerTap(at: CGPoint(x: 80, y: 500))
        harness.spin(0.1)

        XCTAssertFalse(harness.scene.isOverdriveActive)
    }

    @MainActor
    func testTheBurstCancelsHostileFire() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        for i in 0..<6 {
            harness.addEnemyBullet(at: CGPoint(x: 60 + CGFloat(i) * 50, y: 650))
        }
        harness.scene.debugTriggerOverdrive()
        harness.spin(0.2)

        let remaining = harness.gameContent.children.filter { $0.name == "enemyBullet" }
        XCTAssertTrue(remaining.isEmpty, "\(remaining.count) hostile rounds survived the burst")
        XCTAssertGreaterThan(harness.scene.liveShardCount, 0, "cancelled rounds did not turn into shards")
    }

    /// The insurance rule: a hit on a full meter fires it instead of costing a life.
    @MainActor
    func testAFullMeterAbsorbsAHit() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugFillOverdrive()
        let lives = harness.scene.currentLives

        harness.addEnemyBullet(at: harness.player.position)
        harness.spin(0.5)

        XCTAssertEqual(harness.scene.currentLives, lives, "the hit cost a life despite a full meter")
        XCTAssertTrue(harness.scene.isOverdriveActive, "the full meter did not fire to absorb the hit")
    }

    /// And without a full meter the same hit lands as it always did.
    @MainActor
    func testAnEmptyMeterDoesNotAbsorbAHit() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        let lives = harness.scene.currentLives
        harness.addEnemyBullet(at: harness.player.position)
        harness.spin(0.5)

        XCTAssertEqual(harness.scene.currentLives, lives - 1, "an unprotected hit did not cost a life")
    }

    /// The overdrive runs its course and ends by itself.
    @MainActor
    func testTheOverdriveEnds() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.scene.debugTriggerOverdrive()
        XCTAssertTrue(harness.scene.isOverdriveActive)

        harness.spin(OverdriveRules.duration + 1.5)
        XCTAssertFalse(harness.scene.isOverdriveActive, "the overdrive never ended")
    }
}
