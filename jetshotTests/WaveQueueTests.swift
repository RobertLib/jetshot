//
//  WaveQueueTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// `EnemyManager`'s queue: what it counts, and when it lets the next wave go.
final class WaveQueueTests: XCTestCase {

    @MainActor
    private func enemies(in node: SKNode) -> Int {
        return node.children.filter { $0 is Enemy }.count
    }

    /// Drives a manager on a scene that is never presented, so no action runs: an
    /// enemy stays wherever it spawned and a formation never finishes flying in.
    @MainActor
    private func drive(_ manager: EnemyManager, from start: TimeInterval, to end: TimeInterval) {
        var time = start
        while time <= end {
            manager.update(currentTime: time)
            time += 0.05
        }
    }

    @MainActor
    private func formation(_ pattern: FormationPattern, count: Int = 4, of type: EnemyType = .basic) -> EnemyWave {
        return EnemyWave(
            enemies: Array(repeating: type, count: count),
            spawnDelay: 0.4,
            spawnInterval: 0.5,
            isFormation: true,
            formationPattern: pattern
        )
    }

    // MARK: - Progress count

    @MainActor
    func testWingmenDoNotRunTheProgressCountPastTheQueue() {
        // `GameScene` draws the level's progress bar as spawned / to-spawn. Wingmen used
        // to count as spawned without counting towards the total, so on a busy level the
        // bar was full well before the last wave had started.
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        let queued = 40
        let manager = EnemyManager(scene: scene, waves: [
            EnemyWave(enemies: Array(repeating: .basic, count: queued), spawnDelay: 0.1, spawnInterval: 0.05)
        ])

        var time: TimeInterval = 0
        while !manager.areAllWavesSpawned() && time < 30 {
            manager.update(currentTime: time)
            XCTAssertLessThanOrEqual(manager.totalEnemiesSpawned, manager.totalEnemiesToSpawn)
            time += 0.05
        }

        XCTAssertGreaterThan(enemies(in: scene), queued, "no wingman flew, so this proves nothing")
        XCTAssertEqual(manager.totalEnemiesSpawned, queued)
        XCTAssertEqual(manager.totalEnemiesToSpawn, queued)
    }

    // MARK: - Back-to-back formations

    @MainActor
    func testAFormationHoldsTheNextFormationOffItsSlots() {
        // Unpresented, the first formation never settles, so this exercises the hold and
        // its backstop. Every pattern shares one slot grid; two formations one lead-in
        // apart used to arrive on top of each other.
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        let manager = EnemyManager(scene: scene, waves: [formation(.vShape), formation(.diamond)])

        drive(manager, from: 0, to: 10)
        XCTAssertEqual(enemies(in: scene), 4, "the second formation flew in on top of the first")

        drive(manager, from: 10.05, to: 14)
        XCTAssertEqual(enemies(in: scene), 8, "a formation that never settles held the queue for good")
    }

    @MainActor
    func testALooseWaveAfterAFormationIsNotHeld() {
        // Loose enemies come in from random points along the top and fly through; only a
        // formation needs the slot grid.
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        let manager = EnemyManager(scene: scene, waves: [
            formation(.vShape),
            EnemyWave(enemies: [.basic, .basic], spawnDelay: 0.4, spawnInterval: 0.3)
        ])

        drive(manager, from: 0, to: 2)
        XCTAssertGreaterThanOrEqual(enemies(in: scene), 5, "a loose wave waited on a formation")
    }

    @MainActor
    func testAWipedOutFormationHoldsNothing() {
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        let manager = EnemyManager(scene: scene, waves: [formation(.vShape), formation(.circle)])

        drive(manager, from: 0, to: 0.6)
        XCTAssertEqual(enemies(in: scene), 4)
        for case let enemy as Enemy in scene.children {
            enemy.despawn()
        }

        drive(manager, from: 0.65, to: 2)
        XCTAssertEqual(enemies(in: scene), 4, "the next formation waited on one that no longer exists")
    }

    @MainActor
    func testTheNextFormationArrivesOnceTheFirstHasStartedItsAttack() {
        // The real thing, with actions running: the hold has to let go when the first
        // formation has flown in and begun its attack (entry plus the 2 s attack delay),
        // not sit out the backstop.
        //
        // Kamikazes, because they hold their fire: a ship shot down mid-test would take
        // the scene, and the formation's clock, with it.
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        let manager = EnemyManager(scene: scene, waves: [
            formation(.vShape, count: 3, of: .kamikaze),
            formation(.line, count: 3, of: .kamikaze)
        ])

        let start = Date()
        var secondArrivedAfter: TimeInterval?
        while Date().timeIntervalSince(start) < 11 {
            manager.update(currentTime: Date().timeIntervalSince(start))
            if manager.totalEnemiesSpawned == 6 {
                secondArrivedAfter = Date().timeIntervalSince(start)
                break
            }
            harness.spin(0.02)
        }

        guard let arrival = secondArrivedAfter else {
            XCTFail("the second formation never came")
            return
        }
        // Entry for three is 0.4 s of stagger plus a 1.5 s flight, then a 2 s hold.
        XCTAssertGreaterThan(arrival, 3.5, "the second formation came before the first had let go of its slots")
        XCTAssertLessThan(arrival, 9, "the queue sat out its backstop instead of following the formation")
    }
}
