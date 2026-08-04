//
//  ParticleTextureTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The point of `ParticleTexture` is that repeated requests do not re-render. Nine call
/// sites used to each build their own copy inline, four of them during gameplay — a full
/// `UIGraphicsImageRenderer` pass plus an `SKTexture` upload on every coin pickup and
/// every bullet a vortex absorbed.
final class ParticleTextureTests: XCTestCase {


    @MainActor
    func testRepeatedRequestsReturnTheSameInstance() {
        ParticleTexture.clearCache()
        // Identity, not just equality: a fresh render would be a different object and
        // a separate GPU upload.
        XCTAssertIdentical(
            ParticleTexture.solidCircle(diameter: 8),
            ParticleTexture.solidCircle(diameter: 8)
        )
        XCTAssertIdentical(
            ParticleTexture.softCircle(diameter: 32),
            ParticleTexture.softCircle(diameter: 32)
        )
        XCTAssertIdentical(
            ParticleTexture.glowCircle(diameter: 32),
            ParticleTexture.glowCircle(diameter: 32)
        )
    }

    @MainActor
    func testDifferentSizesAreCachedSeparately() {
        ParticleTexture.clearCache()
        let small = ParticleTexture.solidCircle(diameter: 4)
        let large = ParticleTexture.solidCircle(diameter: 24)

        XCTAssertNotIdentical(small, large)
        XCTAssertEqual(small.size().width, 4, accuracy: 0.001)
        XCTAssertEqual(large.size().width, 24, accuracy: 0.001)
    }

    @MainActor
    func testDifferentShapesAtTheSameSizeDoNotCollide() {
        ParticleTexture.clearCache()
        // All three share a diameter at 32pt, so the cache key has to include the shape.
        let soft = ParticleTexture.softCircle(diameter: 32)
        let glow = ParticleTexture.glowCircle(diameter: 32)
        let solid = ParticleTexture.solidCircle(diameter: 32)

        XCTAssertNotIdentical(soft, glow)
        XCTAssertNotIdentical(soft, solid)
        XCTAssertNotIdentical(glow, solid)
    }

    @MainActor
    func testClearCacheForcesARerender() {
        ParticleTexture.clearCache()
        let before = ParticleTexture.solidCircle(diameter: 8)
        ParticleTexture.clearCache()
        let after = ParticleTexture.solidCircle(diameter: 8)

        XCTAssertNotIdentical(before, after)
        // Still usable after the memory-warning path has run.
        XCTAssertEqual(after.size().width, 8, accuracy: 0.001)
    }

    @MainActor
    func testEverySizeUsedByTheGameRenders() {
        ParticleTexture.clearCache()
        // The diameters the call sites actually ask for.
        for diameter in [CGFloat(4), 8, 24, 32] {
            XCTAssertGreaterThan(ParticleTexture.solidCircle(diameter: diameter).size().width, 0)
        }
        XCTAssertGreaterThan(ParticleTexture.softCircle(diameter: 32).size().width, 0)
        XCTAssertGreaterThan(ParticleTexture.glowCircle(diameter: 32).size().width, 0)
    }
}
