//
//  ExplosionFXTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// Covers the two pure lookups behind an explosion.
///
/// Both used to be `switch` statements inlined in `GameScene.createExplosion`, reachable
/// only by blowing something up in a running scene. `GameConfigurationTests` already pins
/// the raw intensity ladder down; what was untested is the *mapping* — that the ladder
/// survives the size lookup, and that the iPad reduction is applied to every rung rather
/// than to whichever one someone remembered.
///
/// No `@MainActor`: both functions are `nonisolated`, which is the whole reason a test
/// module can reach them without standing up a scene.
final class ExplosionFXTests: XCTestCase {

    private let sizes: [ExplosionSize] = [.small, .normal, .large, .huge]

    func testShakeGrowsWithBlastSize() {
        let intensities = sizes.map { ExplosionFX.cameraShake(for: $0, isIPad: false).intensity }
        XCTAssertEqual(
            intensities, intensities.sorted(),
            "camera shake does not grow with blast size once mapped through cameraShake(for:isIPad:)"
        )
    }

    func testLongerShakeForBiggerBlasts() {
        let durations = sizes.map { ExplosionFX.cameraShake(for: $0, isIPad: false).duration }
        XCTAssertEqual(durations, durations.sorted(), "a bigger blast does not shake for longer")
    }

    func testIPadGetsAGentlerKickAtEverySize() {
        for size in sizes {
            let phone = ExplosionFX.cameraShake(for: size, isIPad: false).intensity
            let pad = ExplosionFX.cameraShake(for: size, isIPad: true).intensity
            XCTAssertLessThan(pad, phone, "\(size) shakes an iPad as hard as a phone")
            XCTAssertGreaterThan(pad, 0, "\(size) shakes an iPad not at all")
        }
    }

    func testIPadReductionDoesNotChangeShakeDuration() {
        // Only the amplitude is dialled back for comfort; cutting the duration too would
        // desynchronise the shake from the burst animation it accompanies.
        for size in sizes {
            XCTAssertEqual(
                ExplosionFX.cameraShake(for: size, isIPad: true).duration,
                ExplosionFX.cameraShake(for: size, isIPad: false).duration,
                "\(size) shakes for a different length of time on iPad"
            )
        }
    }

    func testBurstScaleGrowsWithBlastSize() {
        let scales = sizes.map { ExplosionFX.sizeMultiplier(for: $0) }
        XCTAssertEqual(scales, scales.sorted(), "a bigger blast does not draw bigger")
        XCTAssertTrue(scales.allSatisfy { $0 > 0 }, "a blast size collapses the whole burst to nothing")
    }
}
