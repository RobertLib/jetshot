//
//  EnemyLifecycleTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// `GameScene.activeEnemies` holds strong references, so an enemy that leaves the tree
/// without unregistering stays alive — and stays counted. Every off-screen despawn used
/// to latch `hasCompletedMovement` and call `removeFromParent()` directly, never
/// reaching `markAsDestroyed()`, the only place `unregisterEnemy` lives.
final class EnemyLifecycleTests: XCTestCase {

    /// A scene that is deliberately never presented in a view: registerEnemy /
    /// unregisterEnemy and the `Enemy` teardown path do not depend on `didMove(to:)`
    /// having run, and skipping it keeps these tests fast and deterministic.
    ///
    /// Built per test rather than in `setUp()`, which is nonisolated and so cannot
    /// touch a main-actor `GameScene`.
    @MainActor
    private func makeScene() -> GameScene {
        return GameScene(size: CGSize(width: 390, height: 844))
    }

    @MainActor
    private func makeEnemy(_ type: EnemyType = .basic, in scene: GameScene) -> Enemy {
        return Enemy(sceneSize: scene.size, scene: scene, type: type)
    }

    @MainActor
    func testRegisteringAndUnregisteringBalances() {
        let scene = makeScene()
        XCTAssertEqual(scene.activeEnemyCount, 0)

        let enemy = makeEnemy(in: scene)
        scene.registerEnemy(enemy)
        XCTAssertEqual(scene.activeEnemyCount, 1)

        scene.unregisterEnemy(enemy)
        XCTAssertEqual(scene.activeEnemyCount, 0)
    }

    @MainActor
    func testDespawnLeavesTheCache() {
        let scene = makeScene()
        let enemy = makeEnemy(in: scene)
        scene.registerEnemy(enemy)
        XCTAssertEqual(scene.activeEnemyCount, 1)

        enemy.despawn()

        XCTAssertEqual(scene.activeEnemyCount, 0, "an enemy that flew off screen is still cached")
        XCTAssertNil(enemy.parent)
    }

    @MainActor
    func testMarkAsDestroyedLeavesTheCache() {
        let scene = makeScene()
        let enemy = makeEnemy(in: scene)
        scene.registerEnemy(enemy)

        enemy.markAsDestroyed()

        XCTAssertEqual(scene.activeEnemyCount, 0)
    }

    @MainActor
    func testDespawnIsIdempotent() {
        let scene = makeScene()
        let enemy = makeEnemy(in: scene)
        scene.registerEnemy(enemy)

        enemy.despawn()
        enemy.despawn()

        XCTAssertEqual(scene.activeEnemyCount, 0)
    }

    @MainActor
    func testDespawnUnregistersEveryEnemyType() {
        let scene = makeScene()
        // Each type wires up its own actions and children in setupEnemy/startMovement,
        // and several override the despawn path; all of them must still unregister.
        let types: [EnemyType] = [
            .basic, .fast, .heavy, .kamikaze, .zigzag, .sniper, .tank, .striker,
            .turret, .turretSpiral, .mine, .splitter, .bouncer, .teleporter,
            .ghost, .shield, .mirror, .vortex, .meteorSwarm, .flanker
        ]

        for type in types {
            let enemy = makeEnemy(type, in: scene)
            scene.registerEnemy(enemy)
            XCTAssertEqual(scene.activeEnemyCount, 1, "\(type) did not register")

            enemy.despawn()
            XCTAssertEqual(scene.activeEnemyCount, 0, "\(type) stayed in the cache after despawn")
        }
    }

    @MainActor
    func testVortexLeavesTheDedicatedVortexCacheToo() {
        let scene = makeScene()
        // Vortex enemies are held in a second cache for the bullet-attraction sweep,
        // which has no "rebuild when empty" fallback of its own.
        let vortex = makeEnemy(.vortex, in: scene)
        scene.registerEnemy(vortex)
        XCTAssertEqual(scene.activeEnemyCount, 1)

        vortex.despawn()
        XCTAssertEqual(scene.activeEnemyCount, 0)
    }

    @MainActor
    func testManyDespawnsDoNotAccumulate() {
        let scene = makeScene()
        // The shape of the original leak: a long level where enemy after enemy runs off
        // the bottom of the screen.
        for _ in 0..<200 {
            let enemy = makeEnemy(in: scene)
            scene.registerEnemy(enemy)
            enemy.despawn()
        }
        XCTAssertEqual(scene.activeEnemyCount, 0, "escaped enemies accumulated in the cache")
    }

    @MainActor
    func testDespawnedEnemyIsReleased() {
        let scene = makeScene()
        // The cache holding a strong reference is what turned the missing unregister
        // into a leak; once unregistered the node must actually deallocate.
        weak var weakEnemy: Enemy?
        autoreleasepool {
            let enemy = makeEnemy(in: scene)
            weakEnemy = enemy
            scene.registerEnemy(enemy)
            enemy.despawn()
        }
        XCTAssertNil(weakEnemy, "despawned enemy is still retained somewhere")
    }
}
