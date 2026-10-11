//
//  WeaponHeatGaugeTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The HEAT gauge against the lockout it reports.
///
/// The gauge is driven by hand here — `registerShot` and `update` with a made-up gameplay
/// clock — because that clock is the point: `GameScene` stops calling `update` while
/// paused, so anything the gauge shows has to follow the times it is handed, not the wall
/// clock. The track and label are found by type, the way `installHUD(on:sceneWidth:)`
/// lays them out: the track is the first child, the label the only `SKLabelNode`.
@MainActor
final class WeaponHeatGaugeTests: XCTestCase {

    private struct Gauge {
        let scene: SKScene // held: the system only keeps it weakly
        let system: WeaponHeatSystem
        let track: SKShapeNode
        let label: SKLabelNode
    }

    private func makeGauge(in scene: SKScene = SKScene(size: CGSize(width: 390, height: 844))) -> Gauge {
        let hud = SKNode()
        scene.addChild(hud)
        let system = WeaponHeatSystem(scene: scene)
        system.installHUD(on: hud, sceneWidth: scene.size.width)
        let track = hud.children.first as? SKShapeNode
        let label = hud.children.compactMap { $0 as? SKLabelNode }.first
        XCTAssertNotNil(track)
        XCTAssertNotNil(label)
        return Gauge(scene: scene, system: system, track: track ?? SKShapeNode(), label: label ?? SKLabelNode())
    }

    /// Fires at `time` until the guns lock out; returns how many shots that took.
    @discardableResult
    private func overheat(_ system: WeaponHeatSystem, at time: TimeInterval, scale: CGFloat = 1) -> Int {
        var shots = 0
        while !system.isOverheated && shots < 10_000 {
            system.registerShot(currentTime: time, scale: scale)
            shots += 1
        }
        XCTAssertTrue(system.isOverheated, "the guns never overheated")
        return shots
    }

    private var lockout: TimeInterval { GameConfiguration.overheatCooldownTime }

    private func isRed(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return r > 0.9 && g < 0.1
    }

    private func isGreen(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return g > 0.9 && r < 0.1
    }

    // MARK: - OVERHEATED

    func testOverheatedShowsForExactlyTheLockout() {
        let gauge = makeGauge()
        let start: TimeInterval = 10
        overheat(gauge.system, at: start)

        XCTAssertEqual(gauge.label.text, L10n.HUD.overheated)
        XCTAssertEqual(gauge.label.alpha, 1)

        gauge.system.update(deltaTime: 1 / 60, currentTime: start + lockout - 0.01, isFiring: true)
        XCTAssertTrue(gauge.system.isOverheated)
        XCTAssertEqual(gauge.label.text, L10n.HUD.overheated, "OVERHEATED went out before the lockout ended")

        gauge.system.update(deltaTime: 1 / 60, currentTime: start + lockout, isFiring: true)
        XCTAssertFalse(gauge.system.isOverheated)
        XCTAssertEqual(gauge.label.text, L10n.HUD.heat,
                       "the guns are back but the gauge still says OVERHEATED")
    }

    func testOverheatFlashBlinksOnTheGameplayClock() {
        let gauge = makeGauge()
        let start: TimeInterval = 10
        overheat(gauge.system, at: start)

        for (offset, lit) in [(0.1, true), (0.4, false), (0.7, true), (1.0, false), (1.3, true)] {
            gauge.system.update(deltaTime: 1 / 60, currentTime: start + offset, isFiring: true)
            XCTAssertEqual(isRed(gauge.track.fillColor), lit, "\(offset) s into the lockout the track should be \(lit ? "red" : "dark")")
        }
    }

    /// Paused gameplay hands the gauge no time at all. The old flash was an action on the
    /// HUD layer, which never pauses, so it ran its 1.8 s out regardless — behind the
    /// pause menu, and past the end of the lockout.
    func testOverheatDisplayDoesNotRunOnTheWallClock() {
        let harness = GameplayHarness()
        let scene = SKScene(size: CGSize(width: 390, height: 844))
        harness.present(scene, settle: 0.1)
        let gauge = makeGauge(in: scene)

        overheat(gauge.system, at: 10)
        harness.spin(2.2) // longer than the old flash, with no gameplay time passing

        XCTAssertTrue(gauge.system.isOverheated)
        XCTAssertEqual(gauge.label.text, L10n.HUD.overheated,
                       "the lockout display ran on without the gameplay clock")
        XCTAssertFalse(gauge.track.hasActions(), "the gauge is being animated on the wall clock")
    }

    // MARK: - Guns ready

    func testGunsReadyFlashIsShownBeforeTheGaugeHides() {
        let gauge = makeGauge()
        let start: TimeInterval = 10
        overheat(gauge.system, at: start)

        gauge.system.update(deltaTime: 1 / 60, currentTime: start + lockout, isFiring: false)
        XCTAssertEqual(gauge.track.alpha, 1, "the gauge hid on the frame its green flash started")
        XCTAssertTrue(isGreen(gauge.track.fillColor), "the guns came back without the green flash")

        gauge.system.update(deltaTime: 1 / 60, currentTime: start + lockout + 0.1, isFiring: false)
        XCTAssertEqual(gauge.track.alpha, 1)

        gauge.system.update(deltaTime: 1 / 60, currentTime: start + lockout + 0.5, isFiring: false)
        XCTAssertEqual(gauge.track.alpha, 0, "the cold gauge stayed up after its flash")
        XCTAssertEqual(gauge.label.alpha, 0)
        XCTAssertFalse(isGreen(gauge.track.fillColor))
    }

    func testResetEndsTheLockoutDisplay() {
        let gauge = makeGauge()
        overheat(gauge.system, at: 10)

        gauge.system.reset()

        XCTAssertFalse(gauge.system.isOverheated)
        XCTAssertEqual(gauge.label.text, L10n.HUD.heat)
        XCTAssertEqual(gauge.track.alpha, 0)
    }

    // MARK: - Shot scale

    /// `scale` is linear: a half-heat shot (rapid fire) takes twice as many to overheat.
    func testHalfScaleShotsAddHalfTheHeat() {
        let full = overheat(makeGauge().system, at: 0, scale: 1)
        let half = overheat(makeGauge().system, at: 0, scale: 0.5)

        XCTAssertEqual(Double(half), Double(full) * 2, accuracy: 1)
    }
}
