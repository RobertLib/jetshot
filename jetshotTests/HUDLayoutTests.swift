//
//  HUDLayoutTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Pins the vertical clearances around the chain meter in the top-right HUD corner.
///
/// The meter is boxed in on both sides, and neither neighbour is obvious from the call
/// site that places it. Above is the pause button, whose glow halo makes its apparent
/// edge lower than its 44pt outline. Below is the boss health bar: it is centred and
/// 80% of the screen wide, so its right end runs underneath the meter at the same x,
/// even though the two are written in different files and never mention each other.
///
/// At a drop of 58 those gaps were 9pt and 4pt — the meter read as stuck to the pause
/// button, and there was no room to move it down without landing on the boss bar. Both
/// constants moved together, so both gaps are asserted here: tightening either one
/// again should fail rather than just look wrong.
final class HUDLayoutTests: XCTestCase {

    /// Minimum air the pause button needs below it. Its glow is drawn well outside the
    /// outline, so anything under ~15pt reads as touching.
    private let minimumPauseClearance: CGFloat = 15

    // MARK: - Measuring

    /// The chain meter's panel in scene coordinates.
    ///
    /// Measured even though the meter starts hidden — `alpha` does not affect geometry,
    /// so no chain has to be seeded to check where it sits.
    @MainActor
    private func meterRect(in scene: SKScene) -> CGRect? {
        guard let meter = scene.childNode(withName: "//\(ComboSystem.meterNodeName)") else {
            return nil
        }
        return meter.calculateAccumulatedFrame()
    }

    @MainActor
    private func pauseRect(in scene: SKScene) -> CGRect? {
        guard let button = scene.childNode(withName: "//pauseButton") as? SKShapeNode,
              let box = button.path?.boundingBoxOfPath else { return nil }
        // Its own outline, not the accumulated frame: the glow halo child is padded out
        // for the bloom's Gaussian tail and would swamp the gap being measured.
        return box.offsetBy(dx: button.position.x, dy: button.position.y)
    }

    // MARK: - Above: the pause button

    @MainActor
    func testTheChainMeterHangsClearOfThePauseButton() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlaying(level: 2)

        guard let pause = pauseRect(in: harness.scene),
              let meter = meterRect(in: harness.scene) else {
            return XCTFail("the HUD did not build the pause button and the chain meter")
        }

        let gap = pause.minY - meter.maxY
        XCTAssertGreaterThan(
            gap, minimumPauseClearance,
            "the chain meter is \(Int(gap))pt under the pause button — close enough to read as stuck to it"
        )
    }

    /// The meter sits below the pause button, not beside or above it. Guards against a
    /// sign slip in the drop turning the clearance above into an overlap elsewhere.
    @MainActor
    func testTheChainMeterSitsBelowThePauseButton() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlaying(level: 2)

        guard let pause = pauseRect(in: harness.scene),
              let meter = meterRect(in: harness.scene) else {
            return XCTFail("the HUD did not build the pause button and the chain meter")
        }

        XCTAssertLessThan(meter.maxY, pause.minY, "the chain meter is not below the pause button")
        // Right-aligned with it, which is what makes the pair read as one corner block.
        XCTAssertEqual(meter.maxX, pause.maxX, accuracy: 3,
                       "the chain meter and the pause button are no longer right-aligned")
    }

    // MARK: - Below: the boss health bar

    /// The one that cannot be seen from either file: the boss bar's right end runs under
    /// the meter, so moving the meter down eats into the bar's space.
    @MainActor
    func testTheChainMeterDoesNotLandOnTheBossHealthBar() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlaying(level: 2)

        harness.scene.bossManager.spawnBoss(level: 2) {}
        harness.spin(0.05)

        guard let boss = harness.gameContent.children.compactMap({ $0 as? Boss }).first else {
            return XCTFail("spawnBoss did not attach a Boss to the playfield")
        }
        guard let meter = meterRect(in: harness.scene) else {
            return XCTFail("the HUD did not build the chain meter")
        }

        // The bar is 20pt tall around its centre, plus a 2pt stroke.
        let barTop = boss.healthBarY + 10 + 1
        XCTAssertLessThan(
            barTop, meter.minY,
            "the boss health bar overlaps the chain meter by \(Int(barTop - meter.minY))pt"
        )
    }

    /// Both drops are measured from the same HUD margin, so the pair has to survive a
    /// resize rather than only being right on the device the numbers were tuned on.
    @MainActor
    func testTheClearancesSurviveAResize() {
        let harness = GameplayHarness(size: CGSize(width: 375, height: 667))
        defer { harness.teardown() }
        harness.startPlaying(level: 2)

        guard let pause = pauseRect(in: harness.scene),
              let meter = meterRect(in: harness.scene) else {
            return XCTFail("the HUD did not build on a 667pt screen")
        }

        XCTAssertGreaterThan(
            pause.minY - meter.maxY, minimumPauseClearance,
            "the chain meter crowded the pause button on a 667pt screen"
        )
    }
}
