//
//  CoinFormationTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Coins fall straight down at a fixed x, so anything placed outside the screen is
/// unreachable — and because it still counts towards the level's coin total, it quietly
/// costs the player stars. `.wave` and `.zigzag` span ±125pt, which on a 375pt-wide
/// phone used to reach x = -25 and x = 400.
final class CoinFormationTests: XCTestCase {

    /// Widths from the narrowest iPhone the deployment target still supports up to iPad.
    private let widths: [CGFloat] = [320, 375, 390, 428, 440, 744, 1024]
    private let height: CGFloat = 900

    /// Matches the inset `CoinManager.place` reserves for half a coin sprite.
    private let margin: CGFloat = 30

    @MainActor
    private func manager(width: CGFloat) -> CoinManager {
        let scene = SKScene(size: CGSize(width: width, height: height))
        return CoinManager(
            scene: scene,
            config: CoinSpawnConfig(spawnInterval: 5, spawnProbability: 1, minCoins: 10, maxCoins: 18)
        )
    }

    @MainActor
    func testEveryFormationStaysWithinReachOnEveryWidth() {
        for width in widths {
            let size = CGSize(width: width, height: height)
            let coinManager = manager(width: width)

            for formation in Self.allFormations {
                // Formations randomise their coin count and horizontal placement, so
                // repeat enough to catch an edge case rather than trusting one roll.
                for attempt in 0..<200 {
                    let positions = coinManager.generateFormationPositions(
                        formation: formation, sceneSize: size
                    )
                    XCTAssertFalse(positions.isEmpty, "\(formation) produced no coins")

                    for point in positions {
                        XCTAssertGreaterThanOrEqual(
                            point.x, 0,
                            "\(formation) at width \(width) attempt \(attempt): x=\(point.x) off the left edge"
                        )
                        XCTAssertLessThanOrEqual(
                            point.x, width,
                            "\(formation) at width \(width) attempt \(attempt): x=\(point.x) off the right edge"
                        )
                    }
                }
            }
        }
    }

    @MainActor
    func testFormationsSpawnEntirelyAboveTheTopEdge() {
        // `.cross` reaches below its own origin, which used to spawn its bottom coin
        // already on screen — the coin popped into view instead of falling in.
        for width in widths {
            let size = CGSize(width: width, height: height)
            let coinManager = manager(width: width)

            for formation in Self.allFormations {
                for _ in 0..<50 {
                    let positions = coinManager.generateFormationPositions(
                        formation: formation, sceneSize: size
                    )
                    for point in positions {
                        XCTAssertGreaterThan(
                            point.y, height,
                            "\(formation) spawned a coin at y=\(point.y), already on a \(height)pt screen"
                        )
                    }
                }
            }
        }
    }

    @MainActor
    func testPlaceHonoursTheMarginWhenTheShapeFits() {
        let size = CGSize(width: 400, height: height)
        // A 100pt-wide shape fits comfortably inside 400 - 2*30.
        let shape = [CGPoint(x: -50, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0)]

        for _ in 0..<500 {
            let placed = CoinManager.place(shape, in: size)
            for point in placed {
                XCTAssertGreaterThanOrEqual(point.x, margin - 0.001)
                XCTAssertLessThanOrEqual(point.x, size.width - margin + 0.001)
            }
        }
    }

    @MainActor
    func testPlaceCentresAShapeWiderThanTheScreen() {
        // Degenerate case: nothing can satisfy the margin, so the fallback centres the
        // shape rather than picking from an inverted range (which would trap).
        let size = CGSize(width: 200, height: height)
        let tooWide = [CGPoint(x: -400, y: 0), CGPoint(x: 400, y: 0)]

        let placed = CoinManager.place(tooWide, in: size)
        XCTAssertEqual(placed.count, 2)
        let centre = (placed[0].x + placed[1].x) / 2
        XCTAssertEqual(centre, size.width / 2, accuracy: 0.001)
    }

    @MainActor
    func testPlacePreservesShapeAndOrdering() {
        let size = CGSize(width: 400, height: height)
        let shape = [CGPoint(x: -50, y: 0), CGPoint(x: 0, y: 20), CGPoint(x: 50, y: 40)]
        let placed = CoinManager.place(shape, in: size)

        XCTAssertEqual(placed.count, shape.count)
        // Placement is a pure translation, so every gap between coins is unchanged.
        for i in 1..<shape.count {
            XCTAssertEqual(placed[i].x - placed[i - 1].x, shape[i].x - shape[i - 1].x, accuracy: 0.001)
            XCTAssertEqual(placed[i].y - placed[i - 1].y, shape[i].y - shape[i - 1].y, accuracy: 0.001)
        }
    }

    @MainActor
    func testPlaceHandlesASingleCoin() {
        let size = CGSize(width: 375, height: height)
        let placed = CoinManager.place([.zero], in: size)
        XCTAssertEqual(placed.count, 1)
        XCTAssertGreaterThanOrEqual(placed[0].x, margin - 0.001)
        XCTAssertLessThanOrEqual(placed[0].x, size.width - margin + 0.001)
    }

    // `CoinFormation` is not CaseIterable; mirror the list its own `random()` uses.
    private static let allFormations: [CoinFormation] = [
        .line, .vShape, .circle, .wave, .diagonal, .cross, .arrow, .zigzag
    ]
}
