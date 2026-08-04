//
//  FormationAttackTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Guards the fire timer across a formation enemy's attack run.
///
/// `attackFromFormation` has to call `removeAllActions()` to stop the formation-entry
/// path tearing against the attack path, but that also clears the keyed action
/// `startShooting()` installs — so the six formation types went permanently silent the
/// moment they dived, which is the phase they are closest to the player. Nothing about
/// that is visible except by watching a wave for several seconds.
final class FormationAttackTests: XCTestCase {

    private let shootActionKey = "enemyShootAction"

    /// Every type that starts a fire timer in `init`.
    private let timerFiringTypes: [EnemyType] = [
        .basic, .fast, .heavy, .zigzag, .striker, .sniper, .tank,
        .formation, .scout, .eliteGuard, .bomber, .spinner, .commander,
        .flanker, .ghost, .shield, .splitter, .laser, .bouncer, .teleporter
    ]

    /// Types that drive their own fire from their movement routine instead.
    private let selfDrivenTypes: [EnemyType] = [
        .kamikaze, .turret, .turretSpiral, .mine, .meteorSwarm, .vortex, .mirror
    ]

    @MainActor
    private func makeEnemy(_ type: EnemyType) -> Enemy {
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        return Enemy(sceneSize: scene.size, scene: scene, type: type)
    }

    @MainActor
    func testTimerFiringTypesStartShooting() {
        for type in timerFiringTypes {
            let enemy = makeEnemy(type)
            XCTAssertNotNil(enemy.action(forKey: shootActionKey),
                            "\(type) never started its fire timer")
        }
    }

    @MainActor
    func testSelfDrivenTypesDoNotStartTheTimer() {
        for type in selfDrivenTypes {
            let enemy = makeEnemy(type)
            XCTAssertNil(enemy.action(forKey: shootActionKey),
                         "\(type) should fire from its movement routine, not the timer")
        }
    }

    @MainActor
    func testAttackRunKeepsTheFireTimer() {
        // The dive path itself; only its length matters here.
        let path = [CGPoint(x: 100, y: 700), CGPoint(x: 120, y: 400), CGPoint(x: 140, y: -20)]

        for type in [EnemyType.formation, .scout, .eliteGuard, .bomber, .spinner, .commander] {
            let enemy = makeEnemy(type)
            XCTAssertNotNil(enemy.action(forKey: shootActionKey), "\(type) precondition")

            enemy.attackFromFormation(path: path, duration: 2.0) {}

            XCTAssertNotNil(enemy.action(forKey: shootActionKey),
                            "\(type) stopped shooting for the whole attack run")
        }
    }

    @MainActor
    func testDestroyedEnemyStopsShooting() {
        // The other half of the contract: markAsDestroyed() must still silence it, or
        // restoring the timer above would resurrect fire from a dead enemy.
        let enemy = makeEnemy(.scout)
        enemy.markAsDestroyed()
        XCTAssertNil(enemy.action(forKey: shootActionKey),
                     "a destroyed enemy kept its fire timer")
    }
}
