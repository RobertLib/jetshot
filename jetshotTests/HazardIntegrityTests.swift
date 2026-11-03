//
//  HazardIntegrityTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
import simd
@testable import jetshot

/// Hazards and pickups held to what they look like and how long they live: a coin that
/// is gone has to be gone, a wall of rounds has to be a wall, a split rock has to fly
/// apart, a swaying wall has to sway about where it came in, and a boss has to open
/// with the move that names it.
@MainActor
final class HazardIntegrityTests: XCTestCase {

    // MARK: - Coin glint

    /// The glint's reset used to be a closure that held the glint, run by the glint
    /// forever: a cycle no removal broke, so every coin left its glint and both rays
    /// behind.
    func testACoinThatIsReleasedTakesItsGlintWithIt() {
        weak var glint: SKNode?
        weak var released: Coin?
        autoreleasepool {
            let coin = Coin(position: CGPoint(x: 100, y: 400))
            glint = coin.childNode(withName: Coin.glintName)
            released = coin
        }
        XCTAssertNil(released, "precondition: the coin itself was freed")
        XCTAssertNil(glint, "a released coin's glint is still alive, held by its own action")
    }

    /// The same, the way it happens in a run: one coin collected, one left to fall out
    /// of the bottom, both in a running scene.
    func testCollectedAndFallenCoinsFreeTheirGlints() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        scene.physicsWorld.gravity = .zero
        harness.present(scene, settle: 0.1)

        weak var collectedGlint: SKNode?
        weak var fallenGlint: SKNode?
        weak var collected: Coin?
        weak var fallen: Coin?
        autoreleasepool {
            let caught = Coin(position: CGPoint(x: 120, y: 400))
            let missed = Coin(position: CGPoint(x: 270, y: 400))
            missed.speed = 40 // its fall in a fraction of a second
            for coin in [caught, missed] { scene.addChild(coin) }
            collectedGlint = caught.childNode(withName: Coin.glintName)
            fallenGlint = missed.childNode(withName: Coin.glintName)
            collected = caught
            fallen = missed
            harness.spin(0.2)
            caught.collect(scorePosition: CGPoint(x: 30, y: 800))
        }
        harness.spin(0.9)

        XCTAssertNil(collected, "precondition: the collected coin was freed")
        XCTAssertNil(fallen, "precondition: the coin that fell out was freed")
        XCTAssertNil(collectedGlint, "a collected coin's glint outlived it")
        XCTAssertNil(fallenGlint, "a fallen coin's glint outlived it")
    }

    // MARK: - Lattice walls

    /// Every x the ship can fly at is in reach of a round of every wall, except inside
    /// that wall's gap — and the gap is still a gap a ship fits through.
    ///
    /// The walls used to start at x = 12 and step 30 pt, so on most widths the right edge
    /// was out of reach (342 against a ship pinned at 365 on a 375 pt phone), and a 6 pt
    /// lane lay between every two rounds, at the same x in every wall.
    func testLatticeWallsLeaveNoLaneButTheirGap() {
        let reach = ProjectileFX.HostileKind.boss.hitRadius + Player.hitboxRadius
        var generator = SystemRandomNumberGenerator()
        let widths: [CGFloat] = [320, 375, 390, 393, 402, 414, 428, 430, 440, 744, 768, 820, 1024, 1032]

        for width in widths {
            let layout = BossManager.latticeLayout(width: width)
            let xs = layout.xs
            guard let first = xs.first, let last = xs.last, xs.count > layout.gapWidth + 1 else {
                XCTFail("\(width) pt: no lattice to speak of")
                continue
            }
            XCTAssertEqual(first, width - last, accuracy: 1e-6, "\(width) pt: the lattice is not centred")
            let spacing = (last - first) / CGFloat(xs.count - 1)
            let flight = Player.flightBounds(sceneWidth: width, sceneHeight: 800, safeAreaBottom: 0)

            for _ in 0..<60 {
                let gaps = BossManager.latticeGaps(walls: 6, slots: xs.count, gapWidth: layout.gapWidth,
                                                   drift: layout.drift, using: &generator)
                for (n, gap) in gaps.enumerated() {
                    XCTAssertTrue(gap >= 0 && gap + layout.gapWidth <= xs.count, "\(width) pt: gap \(gap) off the lattice")
                    if n > 0 {
                        XCTAssertLessThanOrEqual(CGFloat(abs(gap - gaps[n - 1])) * spacing, 90 + 1e-6,
                                                 "\(width) pt: the gap jumped further than it ever did")
                    }

                    // The rounds either side of the gap, or the screen edge for a gap at one.
                    let low = gap > 0 ? xs[gap - 1] : -CGFloat.infinity
                    let high = gap + layout.gapWidth < xs.count ? xs[gap + layout.gapWidth] : CGFloat.infinity
                    let passage = min(high - reach, flight.maxX) - max(low + reach, flight.minX)
                    // What the old 30 pt lattice left: four steps between the rounds either
                    // side of the gap, or three in from the first round for a gap at an edge.
                    let atEdge = low == -.infinity || high == .infinity
                    let before = atEdge ? 12 + 3 * 30 - flight.minX - reach : 4 * 30 - 2 * reach
                    XCTAssertGreaterThanOrEqual(passage, before - 1e-6,
                                                "\(width) pt: the gap at \(gap) is narrower than it used to be")

                    // Every stretch of the flight range no round reaches has to be the gap.
                    let rounds = xs.enumerated().filter { $0.offset < gap || $0.offset >= gap + layout.gapWidth }.map(\.element)
                    var safe: [(CGFloat, CGFloat)] = []
                    if let leftmost = rounds.first { safe.append((flight.minX, leftmost - reach)) }
                    for (a, b) in zip(rounds, rounds.dropFirst()) { safe.append((a + reach, b - reach)) }
                    if let rightmost = rounds.last { safe.append((rightmost + reach, flight.maxX)) }
                    for (from, to) in safe {
                        let lo = max(from, flight.minX), hi = min(to, flight.maxX)
                        guard hi > lo else { continue }
                        XCTAssertTrue(lo >= low && hi <= high,
                                      "\(width) pt: a ship at \(lo)…\(hi) sits out a wall whose gap is \(low)…\(high)")
                    }
                }
            }
        }
    }

    // MARK: - Boss opening

    /// The first thing every boss does is its signature move, as `BossArchetype.signature`
    /// promises. `BossConfigTests` checks the signature is in the opening act; the draw
    /// out of that act used to be random, so the signature came first only by chance.
    func testTheFirstAttackOfEveryFightIsItsSignature() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlaying(level: 2)
        let manager = harness.scene.bossManager!

        var levels: [BossArchetype: Int] = [:]
        for level in 1...GameConfiguration.totalLevels where levels[BossConfig.config(for: level).archetype] == nil {
            levels[BossConfig.config(for: level).archetype] = level
        }
        XCTAssertEqual(levels.count, BossArchetype.allCases.count, "precondition: every archetype is fought somewhere")

        for (archetype, level) in levels.sorted(by: { $0.value < $1.value }) {
            for _ in 0..<3 {
                manager.spawnBoss(level: level) {}
                XCTAssertEqual(manager.nextAttack(), archetype.signature,
                               "the level \(level) \(archetype) does not open with its signature")
                manager.cleanup()
            }
        }
    }

    // MARK: - Boss health bar

    /// The charge drains without its shape being rebuilt for every round that lands.
    func testTheHealthBarDrainsWithoutRebuildingItsShape() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlaying(level: 2)
        harness.scene.bossManager.spawnBoss(level: 2) {}
        harness.spin(2.4)
        guard let boss = harness.gameContent.children.compactMap({ $0 as? Boss }).first else {
            return XCTFail("no boss")
        }
        XCTAssertTrue(boss.isAlive(), "precondition: the boss has finished its entrance")

        let shape = boss.healthBarFillPath
        let full = boss.healthBarFillHalfWidth
        let hits = 5
        for _ in 0..<hits { _ = harness.scene.bossManager.bossTakeDamage() }

        XCTAssertTrue(boss.healthBarFillPath == shape, "the charge's shape was rebuilt on a hit")
        let left = CGFloat(boss.maxHealthPoints - hits) / CGFloat(boss.maxHealthPoints)
        XCTAssertEqual(boss.healthBarFillHalfWidth, full * left, accuracy: 0.01,
                       "the charge does not show the health that is left")
    }

    // MARK: - Asteroids

    /// Split pieces fan out across the lower half-turn: one each way, and for three, one
    /// down the middle. The range used to start at 0.75π, which put two of three pieces
    /// on the same leftward drift.
    func testSplitPiecesSpreadEvenlyBothWays() {
        let pair = (0..<2).map { cos(AsteroidManager.splitAngle($0, of: 2)) }
        XCTAssertLessThan(pair[0], -0.9)
        XCTAssertGreaterThan(pair[1], 0.9)

        let three = (0..<3).map { AsteroidManager.splitAngle($0, of: 3) }
        let drifts = three.map { cos($0) }
        XCTAssertEqual(drifts.filter { $0 < -0.5 }.count, 1, "three pieces: \(drifts)")
        XCTAssertEqual(drifts.filter { $0 > 0.5 }.count, 1, "three pieces: \(drifts)")
        XCTAssertEqual(drifts.filter { abs($0) < 0.1 }.count, 1, "three pieces: \(drifts)")
        XCTAssertEqual(drifts.reduce(0, +), 0, accuracy: 1e-9, "the split leans to one side")
        for angle in three {
            XCTAssertLessThanOrEqual(sin(angle), 1e-9, "a piece leaves upward")
        }

        XCTAssertEqual(cos(AsteroidManager.splitAngle(0, of: 1)), 0, accuracy: 1e-9, "a lone piece drifts sideways")
    }

    /// The hitbox radius against the rock that is drawn: the mean of its outline over
    /// many orientations, for the subdivided large and medium meshes and the coarse
    /// small one. Orthographic, which the body's mild perspective changes by about 2%.
    func testAsteroidHitRadiusMatchesTheDrawnRock() {
        var generator = SystemRandomNumberGenerator()
        for size in [AsteroidSize.large, .medium, .small] {
            let base = Float(size.baseSize)
            var ratios: [CGFloat] = []
            for seed in 0..<60 {
                let mesh = WireMesh.rock(radius: base * 0.92, seed: UInt64(seed * 7919 + 13), roughness: 0.34,
                                         subdivisions: size == .small ? 0 : 1)
                var total: Float = 0
                var samples = 0
                for _ in 0..<12 {
                    let axis = simd_normalize(Vec3(Float.random(in: -1...1, using: &generator),
                                                   Float.random(in: -1...1, using: &generator),
                                                   Float.random(in: -1...1, using: &generator)) + Vec3(0, 0, 0.01))
                    let turn = simd_quatf(angle: Float.random(in: 0...(2 * .pi), using: &generator), axis: axis)
                    let projected = mesh.vertices.map { turn.act($0) }
                    for k in 0..<16 {
                        let a = Float(k) / 16 * 2 * .pi
                        total += projected.map { $0.x * cos(a) + $0.y * sin(a) }.max() ?? 0
                        samples += 1
                    }
                }
                let silhouette = CGFloat(total / Float(samples))
                ratios.append(Asteroid.hitRadius(of: mesh) / silhouette)
            }
            for ratio in ratios {
                XCTAssertEqual(ratio, 1, accuracy: 0.13, "a \(size) rock's hitbox is \(ratio)x its drawn outline")
            }
            let mean = ratios.reduce(0, +) / CGFloat(ratios.count)
            XCTAssertEqual(mean, 1, accuracy: 0.09, "\(size) rocks' hitboxes average \(mean)x their outlines")
        }
    }

    /// The body SpriteKit simulates is the round one the rock declares, solid all the
    /// way round to just inside it and nowhere just outside it, within the size range
    /// the rocks are drawn at.
    func testAsteroidBodyIsRoundAndTheSizeOfItsRock() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        scene.physicsWorld.gravity = .zero
        harness.present(scene, settle: 0.1)

        let centre = CGPoint(x: 195, y: 420)
        for size in [AsteroidSize.large, .medium, .small] {
            for _ in 0..<6 {
                let rock = Asteroid(sceneSize: scene.size, scene: scene, size: size, startPosition: centre)
                rock.speed = 0
                scene.addChild(rock)
                harness.spin(0.05)

                let radius = (rock.path?.boundingBox.width ?? 0) / 2
                XCTAssertGreaterThan(radius, size.baseSize * 0.7, "a \(size) rock's hitbox is smaller than any rock drawn")
                XCTAssertLessThan(radius, size.baseSize * 1.1, "a \(size) rock's hitbox is bigger than any rock drawn")
                for k in 0..<8 {
                    let a = CGFloat(k) / 8 * 2 * .pi
                    let inside = CGPoint(x: centre.x + cos(a) * radius * 0.9, y: centre.y + sin(a) * radius * 0.9)
                    let outside = CGPoint(x: centre.x + cos(a) * (radius + 1.5), y: centre.y + sin(a) * (radius + 1.5))
                    XCTAssertTrue(scene.physicsWorld.body(at: inside) === rock.physicsBody,
                                  "a \(size) rock is not solid just inside its outline at \(Int(a * 180 / .pi))°")
                    XCTAssertNil(scene.physicsWorld.body(at: outside),
                                 "a \(size) rock is solid outside its outline at \(Int(a * 180 / .pi))°")
                }
                rock.removeFromParent()
            }
        }
    }

    /// Rocks of a size share one glow texture. Each used to bloom its own random outline,
    /// a CoreImage blur and a GPU readback on the main thread for every rock and piece.
    func testAsteroidsOfOneSizeShareTheirGlow() {
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        func glow(of size: AsteroidSize) -> SKTexture? {
            let rock = Asteroid(sceneSize: scene.size, scene: scene, size: size)
            return rock.childNode(withName: "enhancedGlow")?.children.compactMap { ($0 as? SKSpriteNode)?.texture }.first
        }
        for size in [AsteroidSize.large, .medium, .small] {
            let first = glow(of: size)
            XCTAssertNotNil(first, "a \(size) rock has no glow")
            for _ in 0..<4 {
                XCTAssertTrue(glow(of: size) === first, "two \(size) rocks bloomed separate glows")
            }
        }
    }

    // MARK: - Swaying walls

    /// Moving, zigzag and wave walls swing evenly either side of where they spawned and
    /// keep the whole drawn wall on screen while they do. The sway used to be a sweep
    /// right and back, centred a half sweep to the right of the spawn point.
    func testSwayingWallsSwingAboutWhereTheySpawned() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        let size = CGSize(width: 390, height: 844)
        let scene = SKScene(size: size)
        scene.physicsWorld.gravity = .zero
        harness.present(scene, settle: 0.1)

        // Nominal reach either way, and half the drawn width with its teeth or waves.
        let kinds: [(ObstacleType, reach: CGFloat, halfWidth: CGFloat)] = [
            (.movingWall, 50, 10), (.zigzagWall, 50, 18), (.waveWall, 60, 12.5 + 6 * sin(.pi / 3))
        ]
        var tracked: [(wall: Obstacle, spawn: CGFloat, reach: CGFloat, halfWidth: CGFloat, low: CGFloat, high: CGFloat)] = []
        for (row, kind) in kinds.enumerated() {
            // The middle of the screen and both ends of `ObstacleManager`'s spawn range.
            for (column, x) in [CGFloat(195), 60, size.width - 60].enumerated() {
                let wall = Obstacle(type: kind.0, sceneSize: size, position: CGPoint(x: x, y: 130 + CGFloat(row * 3 + column) * 70))
                wall.removeAction(forKey: "moveDown")
                wall.speed = 4
                scene.addChild(wall)
                tracked.append((wall, x, kind.reach, kind.halfWidth, x, x))
            }
        }

        let deadline = Date().addingTimeInterval(4.0) // 16 s of sway: three sweeps or more each
        while Date() < deadline {
            harness.spin(0.02)
            for i in tracked.indices {
                let x = tracked[i].wall.position.x
                tracked[i].low = min(tracked[i].low, x)
                tracked[i].high = max(tracked[i].high, x)
            }
        }

        for t in tracked {
            let name = "\(t.wall.type) spawned at \(Int(t.spawn))"
            XCTAssertEqual((t.low + t.high) / 2, t.spawn, accuracy: 1.5, "\(name) sways about \((t.low + t.high) / 2)")
            XCTAssertGreaterThanOrEqual(t.low - t.halfWidth, -0.5, "\(name) sways off the left of the screen")
            XCTAssertLessThanOrEqual(t.high + t.halfWidth, size.width + 0.5, "\(name) sways off the right of the screen")
            let expected = Obstacle.swayReach(t.reach, halfWidth: t.halfWidth, at: t.spawn, sceneWidth: size.width)
            XCTAssertEqual((t.high - t.low) / 2, expected, accuracy: 1.5, "\(name) sways \((t.high - t.low) / 2) each way")
            XCTAssertGreaterThan(expected, 40, "\(name) barely sways")
        }
    }
}
