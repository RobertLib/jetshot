//
//  PlayerWeaponTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The player's two gameplay verbs — shooting and moving — checked directly on `Player`.
///
/// Both are reachable without a presented scene, which keeps these fast and fully
/// deterministic. `GameScene.shoot()` is private and gated on `isGameStarted`, but it is
/// a thin wrapper: heat, sound and the move action. The geometry that decides whether the
/// player can actually hit anything — how many bullets, where they start, which physics
/// categories they carry — is all `Player.shoot()`, which is what this covers.
final class PlayerWeaponTests: XCTestCase {

    private static let sceneSize = CGSize(width: 390, height: 844)

    @MainActor
    private func makePlayer(bullets: Int = 1, missiles: Int = 0) -> Player {
        let player = Player(sceneSize: Self.sceneSize, safeAreaBottom: 34)
        player.position = CGPoint(x: 195, y: 100)
        player.bulletCount = bullets
        player.sideMissileCount = missiles
        return player
    }

    // MARK: - Bullet count

    @MainActor
    func testOpeningLoadoutFiresOneBullet() {
        let bullets = makePlayer(bullets: 1).shoot()
        XCTAssertEqual(bullets.count, 1)
    }

    @MainActor
    func testStraightBulletsScaleUpToFour() {
        for count in 1...4 {
            let bullets = makePlayer(bullets: count).shoot()
            XCTAssertEqual(bullets.count, count, "bulletCount \(count) fired \(bullets.count) bullets")
            XCTAssertTrue(
                bullets.allSatisfy { $0.userData?["angle"] == nil },
                "bulletCount \(count) should be straight fire only"
            )
        }
    }

    @MainActor
    func testBulletsBeyondFourAreAngled() {
        // Guns 5-8 fan out; the first four stay straight.
        for count in 5...8 {
            let bullets = makePlayer(bullets: count).shoot()
            XCTAssertEqual(bullets.count, count, "bulletCount \(count) fired \(bullets.count) bullets")

            let angled = bullets.filter { $0.userData?["angle"] != nil }
            XCTAssertEqual(angled.count, count - 4, "bulletCount \(count) produced \(angled.count) angled shots")

            for bullet in angled {
                let angle = bullet.userData?["angle"] as? CGFloat
                XCTAssertNotNil(angle, "an angled bullet carries no angle, so it would fly straight")
                XCTAssertNotEqual(angle, 0, "an angled bullet with a zero angle is just a straight one")
            }
        }
    }

    @MainActor
    func testArsenalIsCappedAtTheConfiguredMaximum() {
        // Player clamps on assignment; without that, guns 9+ would index past the
        // four-entry angle table in shoot() and trap.
        let player = makePlayer(bullets: GameConfiguration.maxBulletCount + 5)
        XCTAssertEqual(player.bulletCount, GameConfiguration.maxBulletCount)
        XCTAssertEqual(player.shoot().count, GameConfiguration.maxBulletCount)
    }

    // MARK: - Bullet physics

    @MainActor
    func testEveryBulletCanHitSomething() {
        // A bullet with no body, the wrong category or an empty contact mask flies
        // straight through every enemy in the game.
        let bullets = makePlayer(bullets: 8).shoot()
        XCTAssertEqual(bullets.count, 8)

        for (index, bullet) in bullets.enumerated() {
            guard let body = bullet.physicsBody else {
                XCTFail("bullet \(index) has no physics body")
                continue
            }
            XCTAssertEqual(body.categoryBitMask, PhysicsCategory.bullet, "bullet \(index) has the wrong category")
            XCTAssertEqual(body.collisionBitMask, PhysicsCategory.none, "bullet \(index) would bounce off things")
            XCTAssertNotEqual(
                body.contactTestBitMask & PhysicsCategory.enemy, 0,
                "bullet \(index) does not test for enemies, so it could never score a hit"
            )
            XCTAssertEqual(bullet.name, "bullet", "bullet \(index) is unnamed, so cleanup sweeps would miss it")
        }
    }

    @MainActor
    func testBulletsStartAheadOfTheShip() {
        let player = makePlayer(bullets: 4)
        for bullet in player.shoot() {
            XCTAssertGreaterThan(
                bullet.position.y, player.position.y,
                "a bullet spawned at or behind the ship would register a hit on nothing"
            )
        }
    }

    // MARK: - Missiles

    @MainActor
    func testMissilesFireFromBothFlanks() {
        let player = makePlayer(bullets: 1, missiles: 2)
        let left = player.shootMissile(side: -1)
        let right = player.shootMissile(side: 1)

        XCTAssertLessThan(left.position.x, right.position.x, "both missiles came out of the same side")
        for missile in [left, right] {
            XCTAssertEqual(missile.physicsBody?.categoryBitMask, PhysicsCategory.bullet)
            XCTAssertEqual(missile.name, "missile")
        }
    }

    @MainActor
    func testMissileCountIsCapped() {
        let player = makePlayer(missiles: GameConfiguration.maxSideMissileCount + 3)
        XCTAssertEqual(player.sideMissileCount, GameConfiguration.maxSideMissileCount)
    }

    // MARK: - Movement bounds

    @MainActor
    func testShipActuallyFollowsAnInBoundsTarget() {
        // Guards the clamping tests below from passing vacuously: if moveToInstant did
        // nothing at all, the ship would trivially never leave the screen either.
        let player = makePlayer()
        let start = player.position

        player.moveToInstant(
            x: start.x + 80, y: start.y + 120,
            sceneWidth: Self.sceneSize.width,
            sceneHeight: Self.sceneSize.height,
            safeAreaBottom: 34
        )

        XCTAssertGreaterThan(player.position.x, start.x, "the ship ignored a horizontal move")
        XCTAssertGreaterThan(player.position.y, start.y, "the ship ignored a vertical move")
    }

    @MainActor
    func testMovementIsClampedInsideTheScene() {
        let player = makePlayer()
        let width = Self.sceneSize.width
        let height = Self.sceneSize.height

        // Far off every edge in turn; the ship must stay somewhere on screen.
        let targets = [
            CGPoint(x: -5000, y: 400),
            CGPoint(x: 5000, y: 400),
            CGPoint(x: 195, y: -5000),
            CGPoint(x: 195, y: 5000)
        ]

        for target in targets {
            player.moveToInstant(
                x: target.x, y: target.y,
                sceneWidth: width, sceneHeight: height, safeAreaBottom: 34
            )
            XCTAssertTrue(
                (0...width).contains(player.position.x),
                "x \(player.position.x) left the screen after aiming at \(target)"
            )
            XCTAssertTrue(
                (0...height).contains(player.position.y),
                "y \(player.position.y) left the screen after aiming at \(target)"
            )
        }
    }

    @MainActor
    func testShipStaysAboveTheHomeIndicator() {
        // safeAreaBottom exists so the ship never hides under the home indicator, where
        // the player can neither see it nor drag it back out.
        let player = makePlayer()
        let safeAreaBottom: CGFloat = 34

        player.moveToInstant(
            x: 195, y: -1000,
            sceneWidth: Self.sceneSize.width,
            sceneHeight: Self.sceneSize.height,
            safeAreaBottom: safeAreaBottom
        )

        XCTAssertGreaterThanOrEqual(
            player.position.y, safeAreaBottom,
            "the ship settled below the safe area at y=\(player.position.y)"
        )
    }

    @MainActor
    func testUpdateBoundsKeepsTheShipOnScreenAfterAResize() {
        // Rotation and iPad Split View both resize the scene under the player.
        let player = makePlayer()
        player.moveToInstant(
            x: 380, y: 800,
            sceneWidth: Self.sceneSize.width,
            sceneHeight: Self.sceneSize.height,
            safeAreaBottom: 34
        )

        let narrower = CGSize(width: 200, height: 400)
        player.updateBounds(sceneSize: narrower, safeAreaBottom: 0)
        player.moveToInstant(
            x: 380, y: 800,
            sceneWidth: narrower.width, sceneHeight: narrower.height, safeAreaBottom: 0
        )

        XCTAssertTrue(
            (0...narrower.width).contains(player.position.x),
            "the ship stayed off the right edge of the resized scene at x=\(player.position.x)"
        )
    }
}
