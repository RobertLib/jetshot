//
//  EnemyEdgeCaseTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Enemy faults that only show on a running playfield: what a freeze leaves on screen,
/// a squash carried into an attack run, fire from off the screen, a run with no path,
/// the bouncer's pace and a mid-level resize.
final class EnemyEdgeCaseTests: XCTestCase {

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

    /// An enemy parked where the test put it, its fire timer stopped.
    @MainActor
    private func addParkedEnemy(_ type: EnemyType, to harness: GameplayHarness, at position: CGPoint) -> Enemy {
        let enemy = harness.addEnemy(type, at: position)
        enemy.pauseShooting()
        return enemy
    }

    @MainActor
    private func hitFlashAlpha(of enemy: Enemy) -> CGFloat {
        return enemy.childNode(withName: "damageFlash")?.alpha ?? 0
    }

    // MARK: - Freeze

    /// The hit flash is a child of the enemy, and a freeze pauses the enemy's whole
    /// subtree, so a flash raised on a frozen enemy never faded.
    @MainActor
    func testAFrozenEnemyHitShowsNoStuckFlash() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let enemy = addParkedEnemy(.heavy, to: harness, at: CGPoint(x: 200, y: 500))
        enemy.freeze(duration: 5)
        enemy.health -= 1
        enemy.flashDamage()
        harness.spin(0.4)

        XCTAssertEqual(hitFlashAlpha(of: enemy), 0, accuracy: 0.001, "a frozen enemy stayed a white silhouette")
        XCTAssertEqual(enemy.xScale, enemy.restingScale, accuracy: 0.001)
        XCTAssertEqual(enemy.yScale, enemy.restingScale, accuracy: 0.001)
    }

    /// A hit reaction still playing when the freeze lands used to be paused partway.
    @MainActor
    func testAFreezeClearsAHitReactionInProgress() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let enemy = addParkedEnemy(.heavy, to: harness, at: CGPoint(x: 200, y: 500))
        enemy.flashDamage()
        XCTAssertTrue(
            spin(harness, until: 0.3) { abs(enemy.xScale - enemy.restingScale) > 0.01 },
            "precondition: the hit squash never started"
        )
        XCTAssertGreaterThan(hitFlashAlpha(of: enemy), 0.1, "precondition: the hit flash is up")

        enemy.freeze(duration: 5)
        harness.spin(0.3)

        XCTAssertEqual(hitFlashAlpha(of: enemy), 0, accuracy: 0.001, "the freeze held the hit flash on")
        XCTAssertEqual(enemy.xScale, enemy.restingScale, accuracy: 0.001, "the freeze held the enemy squashed")
        XCTAssertEqual(enemy.yScale, enemy.restingScale, accuracy: 0.001, "the freeze held the enemy squashed")
    }

    /// A teleporter caught mid-blink stayed invisible or half-faded for the whole freeze,
    /// while it could still be shot.
    @MainActor
    func testATeleporterFrozenMidBlinkIsFullyVisible() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        defer { harness.teardown() }

        let teleporter = addParkedEnemy(.teleporter, to: harness, at: CGPoint(x: 200, y: scene.size.height - 100))
        teleporter.startMovement {}
        XCTAssertTrue(
            spin(harness, until: 1) { teleporter.alpha < 0.8 },
            "precondition: the teleporter never blinked"
        )

        teleporter.freeze(duration: 5)
        XCTAssertEqual(teleporter.alpha, 1, accuracy: 0.001, "the teleporter froze mid-blink")

        harness.spin(0.5)
        XCTAssertEqual(teleporter.alpha, 1, accuracy: 0.001, "the frozen teleporter faded")
    }

    // MARK: - Formation runs

    /// `attackFromFormation` clears every action, the hit squash included, and cut off
    /// partway the squash left the enemy flying its whole run distorted.
    @MainActor
    func testAnAttackRunStartsAtTheRestingScale() {
        let harness = GameplayHarness()
        harness.startPlaying()
        defer { harness.teardown() }

        let enemy = addParkedEnemy(.formation, to: harness, at: CGPoint(x: 200, y: 600))
        enemy.flashDamage()
        XCTAssertTrue(
            spin(harness, until: 0.3) { abs(enemy.xScale - enemy.restingScale) > 0.01 },
            "precondition: the hit squash never started"
        )

        enemy.attackFromFormation(
            path: [CGPoint(x: 200, y: 600), CGPoint(x: 220, y: 300), CGPoint(x: 240, y: -20)],
            duration: 3
        ) {}

        XCTAssertEqual(enemy.xScale, enemy.restingScale, accuracy: 0.001, "the attack run started squashed")
        XCTAssertEqual(enemy.yScale, enemy.restingScale, accuracy: 0.001, "the attack run started squashed")
        harness.spin(0.3)
        XCTAssertEqual(enemy.xScale, enemy.restingScale, accuracy: 0.001)
        XCTAssertEqual(enemy.yScale, enemy.restingScale, accuracy: 0.001)
    }

    /// A run with nothing to fly has to retire the enemy. It used to only latch the flag
    /// every removal step checks, leaving the enemy in place and registered for good.
    @MainActor
    func testAnAttackRunWithNoPathRetiresTheEnemy() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        defer { harness.teardown() }

        let enemy = harness.addEnemy(.bomber, at: CGPoint(x: 200, y: 600))
        let before = scene.activeEnemyCount

        var completions = 0
        enemy.attackFromFormation(path: [CGPoint(x: 200, y: 600)], duration: 3) { completions += 1 }

        XCTAssertEqual(completions, 1)
        XCTAssertNil(enemy.parent, "the enemy stayed on the playfield")
        XCTAssertEqual(scene.activeEnemyCount, before - 1, "the enemy is still counted as alive")
        XCTAssertNil(enemy.action(forKey: "enemyShootAction"), "the retired enemy kept its fire timer")
    }

    // MARK: - Fire from off the screen

    @MainActor
    func testNoVolleyFromOffThePlayfield() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        defer { harness.teardown() }
        let size = scene.size

        // Where a formation member waits before it flies in, and where a flanker enters.
        let parked = addParkedEnemy(.bomber, to: harness, at: CGPoint(x: 200, y: size.height + 50))
        let flanker = addParkedEnemy(.flanker, to: harness, at: CGPoint(x: -20, y: size.height / 2))
        let before = enemyBullets(in: harness).count

        parked.shoot()
        flanker.shoot()
        XCTAssertEqual(enemyBullets(in: harness).count, before, "an enemy fired from off the screen")

        parked.position = CGPoint(x: 200, y: size.height - 150)
        parked.shoot()
        XCTAssertEqual(enemyBullets(in: harness).count, before + 1, "an enemy on the playfield held its fire")
    }

    /// The real thing: members of an eight-strong bomber wave wait up to 1.4 s above the
    /// top edge, against a 0.9-1.6 s fire timer that starts when they are built.
    @MainActor
    func testAFormationWaveDoesNotFireFromAboveTheScreen() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        defer { harness.teardown() }

        let formations = FormationManager(scene: scene)
        let wave = formations.spawnFormation(
            pattern: .box,
            types: Array(repeating: .bomber, count: 8),
            attackDelay: 60,
            onEnemyComplete: {}
        )
        XCTAssertNotNil(wave)

        var firedFromAbove = false
        let deadline = Date().addingTimeInterval(2.2)
        while Date() < deadline, !firedFromAbove {
            harness.spin(0.02)
            firedFromAbove = enemyBullets(in: harness).contains { $0.position.y > scene.size.height }
        }
        XCTAssertFalse(firedFromAbove, "a formation member fired from above the top of the screen")
    }

    // MARK: - Bouncer

    /// Pins the pace at a low frame rate. Not a regression test: the old fixed 0.016 s
    /// step held this pace too, because SpriteKit carries the leftover time of a long
    /// frame through `repeatForever(sequence([run, wait]))` and ran several ticks in it.
    /// Measured at 21 fps: 198 pt/s before the change, 200 after.
    @MainActor
    func testTheBouncerHoldsItsPaceAtALowFrameRate() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        defer { harness.teardown() }
        harness.view.preferredFramesPerSecond = 20

        let bouncer = addParkedEnemy(.bouncer, to: harness, at: CGPoint(x: 195, y: scene.size.height - 50))
        bouncer.startMovement {}
        harness.spin(0.1)

        let startY = bouncer.position.y
        let start = Date()
        harness.spin(1.0)
        let elapsed = Date().timeIntervalSince(start)
        let pace = (startY - bouncer.position.y) / CGFloat(elapsed)

        // 200 pt/s, at any frame rate.
        XCTAssertEqual(pace, 200, accuracy: 40, "the bouncer's pace follows the frame rate")
    }

    /// Its step is measured on its own action clock, so SLOW MO and pause still apply.
    @MainActor
    func testTheBouncerStillSlowsAndStops() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        defer { harness.teardown() }

        let bouncer = addParkedEnemy(.bouncer, to: harness, at: CGPoint(x: 195, y: scene.size.height - 50))
        bouncer.speed = 0.5
        bouncer.startMovement {}
        harness.spin(0.1)

        var startY = bouncer.position.y
        var start = Date()
        harness.spin(1.0)
        let pace = (startY - bouncer.position.y) / CGFloat(Date().timeIntervalSince(start))
        XCTAssertEqual(pace, 100, accuracy: 25, "SLOW MO no longer slows the bouncer")

        bouncer.isPaused = true
        startY = bouncer.position.y
        start = Date()
        harness.spin(0.4)
        XCTAssertEqual(bouncer.position.y, startY, accuracy: 0.001, "a paused bouncer kept moving")

        // And no catch-up on resume: the time it spent paused is not owed to it.
        bouncer.isPaused = false
        harness.spin(0.05)
        XCTAssertLessThan(startY - bouncer.position.y, 20, "the bouncer jumped on resume")
    }

    // MARK: - Resize

    /// Shrinks the playfield the way a Split View resize does.
    @MainActor
    private func narrow(_ harness: GameplayHarness, to width: CGFloat) {
        let height = harness.scene.size.height
        harness.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        harness.scene.size = CGSize(width: width, height: height)
        harness.spin(0.1)
        XCTAssertEqual(harness.scene.size.width, width, accuracy: 0.5, "precondition: the playfield did not resize")
    }

    /// The enemies in these two are built before the resize, as they would be in play: an
    /// enemy only ever saw the size it was built with.
    @MainActor
    func testTheBouncerBouncesOffTheEdgesOfAResizedScreen() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        defer { harness.teardown() }

        // Inside the old edges, and left outside the new right edge by the resize.
        let bouncer = addParkedEnemy(.bouncer, to: harness, at: CGPoint(x: 290, y: scene.size.height - 50))
        narrow(harness, to: 300)
        bouncer.startMovement {}

        var widest: CGFloat = 0
        let deadline = Date().addingTimeInterval(1.2)
        harness.spin(0.05)
        while Date() < deadline, bouncer.parent != nil {
            widest = max(widest, bouncer.position.x)
            harness.spin(0.02)
        }
        XCTAssertLessThanOrEqual(widest, 270.5, "the bouncer is still bouncing off the old screen edge")
    }

    @MainActor
    func testTeleportersLandOnAResizedScreen() {
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        defer { harness.teardown() }

        let teleporters = (0..<8).map { index in
            addParkedEnemy(.teleporter, to: harness,
                           at: CGPoint(x: 150, y: scene.size.height - 60 - CGFloat(index) * 10))
        }
        narrow(harness, to: 300)
        for teleporter in teleporters {
            teleporter.startMovement {}
        }

        // The first jump comes 0.2 s in, at the bottom of the first blink.
        harness.spin(0.45)
        for teleporter in teleporters {
            XCTAssertLessThanOrEqual(teleporter.position.x, 250.5, "a teleporter jumped past the new screen edge")
            XCTAssertGreaterThanOrEqual(teleporter.position.x, 49.5)
        }
    }
}
