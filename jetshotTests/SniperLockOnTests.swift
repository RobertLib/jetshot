//
//  SniperLockOnTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The sniper's lock-on: a reticle drops on the ship, closes for 0.8 s, and the shot
/// goes through it.
///
/// Snipers never actually ran this until the player lookup in `shootAimed` was fixed,
/// and switching it on exposed two faults the dead path had been hiding: the reticle was
/// never removed, so every lock-on stayed on the playfield for the rest of the level,
/// and the shot re-read the ship's position when it fired, so it went wherever the ship
/// had moved to and never near the reticle that was supposed to telegraph it.
final class SniperLockOnTests: XCTestCase {

    private let reticleName = "targetingReticle"

    @MainActor
    private func enemyRounds(in harness: GameplayHarness) -> [SKNode] {
        return harness.gameContent.children.filter { $0.name == "enemyBullet" }
    }

    /// A sniper parked where the test put it, with its own fire timer stopped so the
    /// only shot in the air is the one the test fires.
    @MainActor
    private func addSniper(to harness: GameplayHarness, at position: CGPoint) -> Enemy {
        let sniper = harness.addEnemy(.sniper, at: position)
        sniper.pauseShooting()
        return sniper
    }

    @MainActor
    func testReticleRemovesItselfAfterTheLock() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let reticle = VectorFX3D.createTargetingReticle(at: CGPoint(x: 200, y: 300), color: .red, lockDuration: 0.3)
        harness.gameContent.addChild(reticle)

        harness.spin(0.15)
        XCTAssertNotNil(reticle.parent, "the reticle vanished before its lock had played out")

        harness.spin(0.8)
        XCTAssertNil(reticle.parent, "the reticle stayed on the playfield after its lock")
    }

    @MainActor
    func testSniperShotGoesThroughTheLockPoint() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        // Stop the intro's entry animation so the ship stays where the test puts it.
        harness.player.removeAllActions()
        harness.player.position = CGPoint(x: 280, y: 200)

        let sniperPosition = CGPoint(x: 100, y: 700)
        let sniper = addSniper(to: harness, at: sniperPosition)
        sniper.shoot()

        guard let reticle = harness.node(named: reticleName) else {
            return XCTFail("the sniper fired without a lock-on reticle")
        }
        let lockPoint = reticle.position
        XCTAssertEqual(lockPoint, CGPoint(x: 280, y: 200), "the reticle did not land on the ship")

        // Sidestep during the lock — far enough that a shot aimed at the ship's new
        // position would leave on a clearly different heading.
        harness.player.position = CGPoint(x: 80, y: 200)
        harness.spin(1.1)

        let rounds = enemyRounds(in: harness)
        XCTAssertEqual(rounds.count, 1, "expected exactly the sniper's aimed shot in the air")
        guard let round = rounds.first else { return }

        let aim = CGVector(dx: lockPoint.x - sniperPosition.x, dy: lockPoint.y - sniperPosition.y)
        let flight = CGVector(dx: round.position.x - sniperPosition.x, dy: round.position.y - sniperPosition.y)
        let aimLength = hypot(aim.dx, aim.dy)
        let flightLength = hypot(flight.dx, flight.dy)
        XCTAssertGreaterThan(flightLength, 20, "the shot never left the sniper")

        // Sine of the angle between the two headings, and which way along it.
        let sine = (aim.dx * flight.dy - aim.dy * flight.dx) / (aimLength * flightLength)
        let cosine = (aim.dx * flight.dx + aim.dy * flight.dy) / (aimLength * flightLength)
        XCTAssertLessThan(abs(sine), 0.05, "the shot is not heading through the reticle")
        XCTAssertGreaterThan(cosine, 0, "the shot is heading away from the reticle")
    }

    @MainActor
    func testReticleGoesWithASniperKilledMidLock() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        harness.player.removeAllActions()
        harness.player.position = CGPoint(x: 200, y: 200)

        let sniper = addSniper(to: harness, at: CGPoint(x: 200, y: 700))
        sniper.shoot()

        guard let reticle = harness.node(named: reticleName) else {
            return XCTFail("the sniper fired without a lock-on reticle")
        }

        harness.spin(0.2)
        sniper.despawn()
        harness.spin(0.2)

        XCTAssertNil(reticle.parent, "a dead sniper's reticle stayed up for a shot that is not coming")

        harness.spin(0.8)
        XCTAssertTrue(enemyRounds(in: harness).isEmpty, "a sniper fired after it was gone")
    }
}
