//
//  EnemyBehaviourTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Individual enemy behaviours that only show up by watching one fly: the mine, the
/// laser, the ghost, the turrets, the flanker and the meteor swarm.
final class EnemyBehaviourTests: XCTestCase {

    @MainActor
    private func enemyBullets(in harness: GameplayHarness) -> [SKNode] {
        return harness.gameContent.children.filter { $0.name == "enemyBullet" }
    }

    /// Spins until `condition` holds, in frame-sized steps. Returns whether it did.
    @MainActor
    @discardableResult
    private func spin(_ harness: GameplayHarness, until timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            harness.spin(0.02)
        }
        return condition()
    }

    // MARK: - Mine

    @MainActor
    func testShootingAFrozenMineRetiresItOnTheSpot() {
        // A frozen enemy is paused, and the mine's removal used to be an action on the
        // mine itself — so it stayed on the playfield, still taking hits and paying out a
        // kill for each, until the freeze ran out.
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        let mine = harness.addEnemy(.mine, at: CGPoint(x: 120, y: scene.size.height * 0.6))
        mine.freeze(duration: 5)
        XCTAssertTrue(mine.isPaused, "precondition: the mine is frozen")
        let bulletsBefore = enemyBullets(in: harness).count

        var completed = false
        mine.explodeMine(isFullExplosion: false) { completed = true }

        XCTAssertNil(mine.parent, "the frozen mine is still on the playfield")
        XCTAssertTrue(completed)
        XCTAssertEqual(scene.activeEnemyCount, 0, "the mine is still counted as alive")
        XCTAssertEqual(enemyBullets(in: harness).count - bulletsBefore, 6, "the shrapnel went missing")
        XCTAssertNil(harness.gameContent.childNode(withName: "freezeOverlay"), "the freeze overlay outlived the mine")
    }

    @MainActor
    func testTheCountdownSpeedsTheRadarUpRatherThanStoppingIt() {
        // The radar is a `WireBody`, animated from its own action. The countdown used to
        // clear every action on it, freezing the sweep at the moment it was meant to race.
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        let mine = harness.addEnemy(.mine, at: CGPoint(x: 120, y: scene.size.height * 0.6))
        mine.startMineCountdown {}

        harness.spin(0.4)

        guard let radar = mine.childNode(withName: "mineRadar") else {
            XCTFail("the mine has no radar")
            return
        }
        XCTAssertNotNil(radar.action(forKey: "wireBody"), "the countdown stopped the radar")
        XCTAssertGreaterThan(radar.speed, 1, "the radar did not speed up for the countdown")
    }

    // MARK: - Laser

    @MainActor
    func testTheLaserBeamIsPartOfTheShip() {
        // The beam used to be a fixed node on the playfield: the ship flew on before it was
        // done and left it burning in place, and it outlived the ship that fired it.
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        let laser = harness.addEnemy(.laser, at: CGPoint(x: 60, y: scene.size.height * 0.7))
        laser.shoot()

        XCTAssertTrue(
            spin(harness, until: 2) { laser.childNode(withName: "laserBeam") != nil },
            "the laser never fired"
        )
        guard let beam = laser.childNode(withName: "laserBeam") else { return }

        XCTAssertNil(harness.gameContent.childNode(withName: "laserBeam"), "a beam was left on the playfield")
        XCTAssertNil(harness.gameContent.childNode(withName: "chargeEffect"), "the charge-up was left on the playfield")
        XCTAssertEqual(beam.physicsBody?.isDynamic, false, "a dynamic body would not follow the ship")
        XCTAssertEqual(beam.physicsBody?.categoryBitMask, PhysicsCategory.enemyBullet)

        // The hit volume moves with the ship...
        laser.position.x = 150
        harness.spin(0.1)
        let below = harness.gameContent.convert(CGPoint(x: 150, y: scene.size.height * 0.35), to: scene)
        XCTAssertTrue(scene.physicsWorld.body(at: below) === beam.physicsBody, "the beam's hit volume stayed behind")

        // ...and dies with it.
        laser.despawn()
        XCTAssertNil(beam.scene, "the beam outlived its ship")
    }

    @MainActor
    func testTheLaserHoldsStillForTheWholeBeam() {
        // It used to set off again 2.0 s into a 2.8 s charge and beam. Fast-forwarded, so
        // the whole descent fits in a test.
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        let laser = harness.addEnemy(.laser, at: CGPoint(x: 60, y: scene.size.height + 20))
        laser.speed = 3
        laser.startMovement {}

        var shots = 0
        var movedWhileFiring = false
        var lastY = laser.position.y
        let deadline = Date().addingTimeInterval(6)
        var wasFiring = false
        while Date() < deadline, laser.parent != nil {
            harness.spin(0.02)
            let firing = laser.childNode(withName: "laserBeam") != nil
            if firing && !wasFiring { shots += 1 }
            if firing && wasFiring && abs(laser.position.y - lastY) > 0.5 { movedWhileFiring = true }
            wasFiring = firing
            lastY = laser.position.y
        }

        XCTAssertGreaterThan(shots, 0, "the laser never fired on its way down")
        XCTAssertFalse(movedWhileFiring, "the laser moved off with its beam still burning")
    }

    // MARK: - Ghost

    @MainActor
    func testTheGhostIsClearlySolidAndClearlyPhasedInTurn() {
        // Two alpha loops used to fight over the ghost. `GameScene` now lets the player's
        // rounds through a ghost under 0.5, so both states must last long enough to read.
        // Flying, so the movement routine — home of the second loop — runs too.
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        let ghost = harness.addEnemy(.ghost, at: CGPoint(x: 120, y: scene.size.height + 20))
        ghost.startMovement {}

        // The longest unbroken stretch in each state.
        var longestSolid: TimeInterval = 0
        var longestPhased: TimeInterval = 0
        var wasPhased = ghost.isGhostPhased
        var stretchStart = Date()
        let deadline = stretchStart.addingTimeInterval(3.4)
        while Date() < deadline, ghost.parent != nil {
            harness.spin(0.02)
            let now = Date()
            let stretch = now.timeIntervalSince(stretchStart)
            if wasPhased { longestPhased = max(longestPhased, stretch) } else { longestSolid = max(longestSolid, stretch) }
            if ghost.isGhostPhased != wasPhased {
                wasPhased = ghost.isGhostPhased
                stretchStart = now
            }
        }

        XCTAssertGreaterThan(longestSolid, 1.1, "the ghost never stays solid long enough to read")
        XCTAssertGreaterThan(longestPhased, 1.1, "the ghost never stays phased long enough to read")
    }

    @MainActor
    func testAPhasedGhostHoldsItsFire() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        let ghost = harness.addEnemy(.ghost, at: CGPoint(x: 120, y: scene.size.height * 0.6))
        ghost.removeAction(forKey: "ghostFade")
        let before = enemyBullets(in: harness).count

        ghost.alpha = 0.3
        ghost.shoot()
        XCTAssertEqual(enemyBullets(in: harness).count, before, "a phased ghost fired")

        ghost.alpha = 1
        ghost.shoot()
        XCTAssertEqual(enemyBullets(in: harness).count, before + 1, "a solid ghost held its fire")
    }

    @MainActor
    func testNothingThatClearsAGhostsActionsLeavesItPhased() {
        // Cut off mid-fade, the loop leaves alpha wherever it was; under 0.5 that would be a
        // ghost the player's rounds pass through for the rest of its life.
        let scene = SKScene(size: CGSize(width: 390, height: 844))

        let diving = Enemy(sceneSize: scene.size, scene: scene, type: .ghost)
        diving.alpha = 0.3
        diving.attackFromFormation(path: [CGPoint(x: 100, y: 700), CGPoint(x: 100, y: -20)], duration: 2) {}
        XCTAssertFalse(diving.isGhostPhased, "the attack run left the ghost phased")
        XCTAssertNotNil(diving.action(forKey: "ghostFade"), "the attack run stopped the ghost phasing")

        let frozen = Enemy(sceneSize: scene.size, scene: scene, type: .ghost)
        scene.addChild(frozen)
        frozen.alpha = 0.3
        frozen.freeze(duration: 2)
        XCTAssertFalse(frozen.isGhostPhased, "the ghost froze phased")
    }

    // MARK: - Turrets

    @MainActor
    func testTurretsUndockFullyOpaque() {
        // The dock pulse was removed wherever it happened to be, so a turret flew on at
        // whatever fade it had reached.
        let harness = GameplayHarness()
        let scene = harness.startPlaying()

        for (index, type) in [EnemyType.turret, .turretSpiral].enumerated() {
            let turret = harness.addEnemy(type, at: CGPoint(x: 100 + CGFloat(index) * 190, y: scene.size.height + 20))
            turret.speed = 4
            turret.startMovement {}

            XCTAssertTrue(spin(harness, until: 3) { turret.action(forKey: "dockGlow") != nil }, "\(type) never docked")
            XCTAssertTrue(
                spin(harness, until: 3) { turret.action(forKey: "dockGlow") == nil },
                "\(type) never undocked"
            )
            XCTAssertNotNil(turret.parent, "\(type) left before it could be checked")
            XCTAssertEqual(turret.alpha, 1, accuracy: 0.001, "\(type) flew on faded")
        }
    }

    @MainActor
    func testSpiralTurretRoundsLeaveFromTheMuzzleAlongTheBarrel() {
        // The barrel is drawn along its mount's +y; rounds used to take the mount's
        // rotation as their heading — at right angles to the barrel — and leave from the
        // hub. The muzzle sits on the barrel's axis, so a round that appears there and
        // flies straight away from the hub is a round leaving along the barrel.
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        let turret = harness.addEnemy(.turretSpiral, at: CGPoint(x: 195, y: scene.size.height + 20))
        turret.startMovement {}

        XCTAssertTrue(spin(harness, until: 3) { turret.action(forKey: "dockGlow") != nil }, "the turret never docked")
        let hub = turret.position
        let muzzleDistance = 12 * EnemyType.turretSpiral.size * 1.5

        var seen = Set(enemyBullets(in: harness).map(ObjectIdentifier.init))
        var fresh: [(node: SKNode, first: CGPoint)] = []
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, fresh.count < 4 {
            harness.spin(0.016)
            for bullet in enemyBullets(in: harness) where !seen.contains(ObjectIdentifier(bullet)) {
                seen.insert(ObjectIdentifier(bullet))
                fresh.append((bullet, bullet.position))
            }
        }
        XCTAssertGreaterThanOrEqual(fresh.count, 4, "the docked turret hardly fired")

        harness.spin(0.15)
        for (bullet, first) in fresh {
            let out = CGVector(dx: first.x - hub.x, dy: first.y - hub.y)
            let distance = hypot(out.dx, out.dy)
            XCTAssertGreaterThan(distance, muzzleDistance - 3, "a round appeared inside the barrel, not at the muzzle")
            XCTAssertLessThan(distance, muzzleDistance + 15, "a round appeared well clear of the muzzle")

            let moved = CGVector(dx: bullet.position.x - first.x, dy: bullet.position.y - first.y)
            let cosine = (moved.dx * out.dx + moved.dy * out.dy) / max(0.001, hypot(moved.dx, moved.dy) * distance)
            XCTAssertGreaterThan(cosine, 0.97, "a round left at an angle to the barrel")
        }
    }

    // MARK: - Flanker

    @MainActor
    func testTheFlankerExhaustTrailsBehindItFromEitherSide() {
        // A flanker from the right is the same ship turned half a turn, and its trail used
        // to be mirrored as well — the two flips cancelled out and it flew with its
        // exhaust at the nose.
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        var sides = Set<Bool>()

        for _ in 0..<60 {
            let flanker = Enemy(sceneSize: scene.size, scene: scene, type: .flanker)
            scene.addChild(flanker)
            flanker.startMovement {}

            let fromLeft = flanker.position.x < scene.size.width / 2
            sides.insert(fromLeft)
            let travel: CGFloat = fromLeft ? 1 : -1

            guard let trail = flanker.childNode(withName: "flankerTrail") as? SKEmitterNode else {
                XCTFail("the flanker has no trail")
                continue
            }
            let heading = flanker.zRotation
            XCTAssertGreaterThan(cos(heading) * travel, 0.99, "the flanker flies tail first")
            XCTAssertLessThan(cos(heading + trail.emissionAngle) * travel, -0.99, "the exhaust blows forwards")
            let trailX = trail.position.x * cos(heading) - trail.position.y * sin(heading)
            XCTAssertLessThan(trailX * travel, 0, "the exhaust comes out ahead of the ship")
        }

        XCTAssertEqual(sides.count, 2, "sixty flankers all came from one side; the check covered only that one")
    }

    // MARK: - Meteors

    @MainActor
    func testMeteorsDriftBothWaysAndAwayFromTheNearerEdge() {
        // Every meteor used to drift down-left: the swarm's heading only ever had a
        // negative cosine.
        let width: CGFloat = 390
        let drop: CGFloat = 864
        let samples = 400

        func rightward(from x: CGFloat) -> Int {
            var count = 0
            for _ in 0..<samples {
                let drift = Enemy.meteorDrift(fromX: x, sceneWidth: width, drop: drop)
                XCTAssertGreaterThanOrEqual(abs(drift), drop * 0.1, "a meteor fell almost straight")
                XCTAssertLessThanOrEqual(abs(drift), drop * 0.42, "a meteor drifted flatter than the swarm ever did")
                if drift > 0 { count += 1 }
            }
            return count
        }

        let fromCentre = rightward(from: width / 2)
        XCTAssertGreaterThan(fromCentre, samples / 4, "meteors from the centre hardly ever drift right")
        XCTAssertLessThan(fromCentre, samples * 3 / 4, "meteors from the centre hardly ever drift left")

        XCTAssertGreaterThan(rightward(from: 30), samples * 3 / 4, "meteors by the left edge still mostly drift off it")
        XCTAssertLessThan(rightward(from: width - 30), samples / 4, "meteors by the right edge still mostly drift off it")
    }
}
