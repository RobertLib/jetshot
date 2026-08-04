//
//  PhysicsCategoryTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// `GameScene.didBegin(_:)` sorts each contact's two bodies by `categoryBitMask` and
/// then matches fixed (first, second) pairs. That dispatch is only correct while the
/// masks keep the ordering it was written against — and it has already gone wrong once:
/// `barrier` outranks every other category, so it always lands in `secondBody`, and the
/// barrier branches originally tested for it in `firstBody`. They could never match,
/// which left the whole barrier power-up as decoration that blocked nothing.
final class PhysicsCategoryTests: XCTestCase {

    private static let all: [(name: String, mask: UInt32)] = [
        ("player", PhysicsCategory.player),
        ("bullet", PhysicsCategory.bullet),
        ("enemy", PhysicsCategory.enemy),
        ("enemyBullet", PhysicsCategory.enemyBullet),
        ("obstacle", PhysicsCategory.obstacle),
        ("powerUp", PhysicsCategory.powerUp),
        ("asteroid", PhysicsCategory.asteroid),
        ("coin", PhysicsCategory.coin),
        ("barrier", PhysicsCategory.barrier)
    ]

    func testNoneIsEmpty() {
        XCTAssertEqual(PhysicsCategory.none, 0)
    }

    func testEveryCategoryIsADistinctSingleBit() {
        var seen: Set<UInt32> = []
        for entry in Self.all {
            XCTAssertEqual(
                entry.mask.nonzeroBitCount, 1,
                "\(entry.name) is not a single bit, so contactTestBitMask arithmetic would overlap"
            )
            XCTAssertTrue(seen.insert(entry.mask).inserted, "\(entry.name) reuses another category's bit")
        }
    }

    func testBarrierOutranksEveryOtherCategory() {
        // This is the invariant the barrier collision branches depend on: after the
        // sort in didBegin(_:), barrier is always secondBody.
        for entry in Self.all where entry.name != "barrier" {
            XCTAssertLessThan(
                entry.mask, PhysicsCategory.barrier,
                "\(entry.name) now outranks barrier, which silently breaks barrier collisions"
            )
        }
    }

    func testPlayerAndBulletSortAheadOfTheirTargets() {
        // didBegin(_:) matches (player, enemy), (player, obstacle), (bullet, enemy),
        // (bullet, asteroid), (player, coin) and so on — all written with the actor
        // first, so the actor's mask has to be the lower one.
        XCTAssertLessThan(PhysicsCategory.player, PhysicsCategory.enemy)
        XCTAssertLessThan(PhysicsCategory.player, PhysicsCategory.enemyBullet)
        XCTAssertLessThan(PhysicsCategory.player, PhysicsCategory.obstacle)
        XCTAssertLessThan(PhysicsCategory.player, PhysicsCategory.powerUp)
        XCTAssertLessThan(PhysicsCategory.player, PhysicsCategory.asteroid)
        XCTAssertLessThan(PhysicsCategory.player, PhysicsCategory.coin)
        XCTAssertLessThan(PhysicsCategory.bullet, PhysicsCategory.enemy)
        XCTAssertLessThan(PhysicsCategory.bullet, PhysicsCategory.obstacle)
        XCTAssertLessThan(PhysicsCategory.bullet, PhysicsCategory.asteroid)
    }

    func testEnemyAndEnemyBulletSortAheadOfBarrier() {
        // barrierDidCollideWithEnemy / ...EnemyBullet read firstBody as the enemy side.
        XCTAssertLessThan(PhysicsCategory.enemy, PhysicsCategory.barrier)
        XCTAssertLessThan(PhysicsCategory.enemyBullet, PhysicsCategory.barrier)
    }
}
