//
//  ObstacleHitboxTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Obstacles against what they are drawn as: a hitbox has to be where the shape is and
/// nowhere else, through every frame of the shape's animation, and a piece that has been
/// shot away has to stop being solid.
///
/// The hitbox probes ask the physics world itself (`body(at:)`), so they measure the
/// body SpriteKit is actually simulating — scale included — rather than the one that was
/// built. That needs a running view, hence the harness; a plain `SKScene` is presented in
/// it, since none of this involves `GameScene`.
@MainActor
final class ObstacleHitboxTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)
    private let centre = CGPoint(x: 195, y: 420)

    private func hostedScene(_ harness: GameplayHarness) -> SKScene {
        let scene = SKScene(size: sceneSize)
        scene.physicsWorld.gravity = .zero
        harness.present(scene, settle: 0.1)
        return scene
    }

    /// An obstacle parked at `centre`, unrotated and at rest, so a probe in obstacle
    /// coordinates lands where the test means it to.
    private func parkedObstacle(_ type: ObstacleType, in scene: SKScene, harness: GameplayHarness) -> Obstacle {
        let obstacle = Obstacle(type: type, sceneSize: sceneSize, position: centre)
        obstacle.speed = 0
        scene.addChild(obstacle)
        harness.spin(0.15)
        return obstacle
    }

    private func isSolid(_ scene: SKScene, at offset: CGPoint) -> Bool {
        let point = CGPoint(x: centre.x + offset.x, y: centre.y + offset.y)
        return scene.physicsWorld.body(at: point) != nil
    }

    private func rotated(_ point: CGPoint, by angle: CGFloat) -> CGPoint {
        return point.applying(CGAffineTransform(rotationAngle: angle))
    }

    // MARK: - Spiral blade

    func testSpiralBladeIsSolidAlongItsThreeDrawnArms() {
        let harness = GameplayHarness()
        let scene = hostedScene(harness)
        _ = parkedObstacle(.spiralBlade, in: scene, harness: harness)

        // On the drawn arm's centre line, past the hub: 25 pt out along the root, and
        // 50 pt out on the thin spike.
        let root = CGPoint(x: 2.1, y: 25)
        let spike = CGPoint(x: 1.9, y: 50)
        for arm in 0..<3 {
            let angle = CGFloat(arm) * 2 * .pi / 3
            XCTAssertTrue(isSolid(scene, at: rotated(root, by: angle)),
                          "arm \(arm) of the blade is drawn but can be flown through at its root")
            XCTAssertTrue(isSolid(scene, at: rotated(spike, by: angle)),
                          "arm \(arm) of the blade is drawn but its spike has no hitbox")
        }
        XCTAssertTrue(isSolid(scene, at: CGPoint(x: -8, y: -6)), "the drawn hub is not solid")
    }

    func testSpiralBladeIsNotSolidWhereNoArmIsDrawn() {
        // Where the spinner's "+" cross used to put three invisible arms.
        let harness = GameplayHarness()
        let scene = hostedScene(harness)
        _ = parkedObstacle(.spiralBlade, in: scene, harness: harness)

        for probe in [CGPoint(x: 40, y: 0), CGPoint(x: 0, y: -40), CGPoint(x: -40, y: 0), CGPoint(x: 0, y: -20)] {
            XCTAssertFalse(isSolid(scene, at: probe),
                           "the blade hurts at \(probe), where nothing is drawn")
        }
    }

    // MARK: - Pulsating ring

    func testRingCentreIsOpenAndItsBandIsSolid() {
        let harness = GameplayHarness()
        let scene = hostedScene(harness)
        let ring = parkedObstacle(.pulsatingRing, in: scene, harness: harness)

        for probe in [CGPoint.zero, CGPoint(x: 0, y: 20), CGPoint(x: -18, y: -18)] {
            XCTAssertFalse(isSolid(scene, at: probe), "the ring's drawn hole at \(probe) is solid")
        }
        for angle in stride(from: CGFloat(0), to: 2 * .pi, by: .pi / 5) {
            let probe = CGPoint(x: 40 * cos(angle), y: 40 * sin(angle))
            XCTAssertTrue(isSolid(scene, at: probe), "the ring's band is not solid at \(probe)")
        }
        XCTAssertFalse(isSolid(scene, at: CGPoint(x: 56, y: 0)), "the ring is solid outside its rim")

        // Same contact rules as every other obstacle.
        XCTAssertEqual(ring.physicsBody?.categoryBitMask, PhysicsCategory.obstacle)
        XCTAssertEqual(ring.physicsBody?.contactTestBitMask, PhysicsCategory.player | PhysicsCategory.bullet)
        XCTAssertEqual(ring.physicsBody?.collisionBitMask, PhysicsCategory.none)
        XCTAssertEqual(ring.physicsBody?.isDynamic, false)
    }

    // MARK: - Animated scale

    /// Every scale animation has to run on the node that carries the hitbox (SpriteKit
    /// scales a body with its own node or an ancestor, not a child).
    func testScaleAnimationsRunOnTheNodeThatOwnsTheHitbox() {
        for (type, key) in [(ObstacleType.pulsatingRing, "pulse"), (.hexagonTrap, "pulse"), (.spiralBlade, "expand")] {
            let obstacle = Obstacle(type: type, sceneSize: sceneSize, position: centre)
            XCTAssertNotNil(obstacle.physicsBody, "\(type) has no hitbox")
            XCTAssertNotNil(obstacle.action(forKey: key),
                            "\(type)'s '\(key)' animation runs below its hitbox, so the drawing and the hitbox part ways")
        }
    }

    /// The real thing, measured: a hexagon swollen past 1.2x is solid beyond its resting
    /// rim, and one shrunk under 0.9x is not solid at its resting rim.
    func testPulsingHexagonHitboxSwellsAndShrinksWithTheDrawing() {
        let harness = GameplayHarness()
        let scene = hostedScene(harness)
        let hexagon = Obstacle(type: .hexagonTrap, sceneSize: sceneSize, position: centre)
        // Holds it in place and unrotated; the pulse keeps running.
        hexagon.removeAction(forKey: "moveDown")
        hexagon.removeAction(forKey: "rotate")
        scene.addChild(hexagon)

        // The drawing's scale, wherever the animation runs.
        func drawnScale() -> CGFloat {
            return hexagon.xScale * (hexagon.children.first?.xScale ?? 1)
        }
        func wait(until condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                harness.spin(0.03)
                if condition() { return true }
            }
            return false
        }

        // Vertex 0 of the 45 pt hexagon sits on +x.
        XCTAssertTrue(wait { drawnScale() >= 1.2 }, "the hexagon never swelled")
        XCTAssertTrue(isSolid(scene, at: CGPoint(x: 45 * 1.1, y: 0)),
                      "the hexagon is drawn swollen but its hitbox stayed at rest size")

        XCTAssertTrue(wait { drawnScale() <= 0.9 }, "the hexagon never shrank")
        XCTAssertFalse(isSolid(scene, at: CGPoint(x: 45 * 0.97, y: 0)),
                       "the hexagon is drawn shrunk but its hitbox stayed at rest size")
    }

    // MARK: - Destructible wall

    private func blocks(of node: SKNode) -> [SKShapeNode] {
        var found: [SKShapeNode] = []
        for child in node.children {
            if child.name == "destructibleBlock", let block = child as? SKShapeNode {
                found.append(block)
            }
            found += blocks(of: child)
        }
        return found
    }

    func testShotAwayBlockStopsBeingSolidAtOnce() {
        let wall = Obstacle(type: .destructibleWall, sceneSize: sceneSize, position: centre)
        guard let block = blocks(of: wall).first else {
            return XCTFail("the destructible wall has no blocks")
        }
        XCTAssertNotNil(block.physicsBody, "precondition: a standing block is solid")

        XCTAssertTrue(wall.destroyBlock(hitNode: block))
        XCTAssertNotNil(block.parent, "precondition: the block is still fading out")
        XCTAssertNil(block.physicsBody,
                     "a block that has been shot away stays solid while it fades, eating bolts and hurting the ship")
        XCTAssertFalse(wall.destroyBlock(hitNode: block), "one block was destroyed twice")
    }

    // MARK: - Leaving the screen

    func testObstacleThatFallsOffTheBottomLeavesTheTree() {
        let harness = GameplayHarness()
        let scene = hostedScene(harness)
        let obstacle = Obstacle(type: .spinner, sceneSize: sceneSize, position: centre)
        obstacle.speed = 20 // its 8 s fall in 0.4 s
        scene.addChild(obstacle)
        harness.spin(1.0)

        XCTAssertNil(obstacle.parent, "an obstacle that fell off the bottom is still in the scene")
    }
}

/// `ObstacleWave.minSpacing` against the spawner. Driven by hand on a plain scene: the
/// manager only needs a scene to parent to and a clock.
@MainActor
final class ObstacleSpacingTests: XCTestCase {

    func testConsecutiveSpawnsHonourTheWavesMinSpacing() {
        // Wide enough that a lane 600 pt either side of the last spawn always leaves
        // room (ten tries at under 1200/5880 each), so a failure is the rule, not luck.
        // Spawns 1 s apart, inside the clustering window, so each one has to keep clear
        // of the one before; the one before that is out of the window.
        let scene = SKScene(size: CGSize(width: 6000, height: 844))
        let spacing: CGFloat = 600
        let count = 41
        let wave = ObstacleWave(
            obstacles: Array(repeating: .wall, count: count),
            spawnDelay: 0,
            spawnInterval: 1.0,
            minSpacing: spacing
        )
        let manager = ObstacleManager(scene: scene, waves: [wave])
        for step in 0...((count + 2) * 2) {
            manager.update(currentTime: TimeInterval(step) * 0.5)
        }

        let xs = scene.children.compactMap { ($0 as? Obstacle)?.position.x }
        XCTAssertEqual(xs.count, count)
        for (previous, next) in zip(xs, xs.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                abs(next - previous), spacing,
                "two obstacles spawned 1 s apart only \(Int(abs(next - previous))) pt apart, inside the wave's \(Int(spacing)) pt"
            )
        }
    }
}
