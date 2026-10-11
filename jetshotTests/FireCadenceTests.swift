//
//  FireCadenceTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// How fast the guns actually fire, measured against the gameplay clock the cadence
/// runs on, and how long rapid fire can be held before the guns overheat.
///
/// The cadence used to restart from "now" on every volley, which rounded each interval
/// up to whole frames: harmless for the normal 0.13 s (0.133 at 60 fps), but an
/// overdrive's 0.0845 s came out as 0.1 — a sixth of its fire rate gone. Rates here are
/// volleys over `gameplayClock` elapsed, so frame pacing and hit-stops do not skew them.
@MainActor
final class FireCadenceTests: XCTestCase {

    private func spin(_ harness: GameplayHarness, until condition: () -> Bool,
                      timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !condition() {
            harness.spin(0.02)
        }
    }

    func testAnOverdriveFiresAtItsIntervalNotTheNextWholeFrame() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.touchDown(at: harness.player.position)
        harness.scene.debugTriggerOverdrive()
        XCTAssertTrue(harness.scene.isOverdriveActive)
        // Past the activation hit-stop, into the steady stream.
        harness.spin(0.6)

        let volleys = harness.scene.volleysFired
        let clock = harness.scene.gameplayClock
        harness.spin(2.5)
        XCTAssertTrue(harness.scene.isOverdriveActive, "the overdrive ended inside the measurement")
        let fired = Double(harness.scene.volleysFired - volleys)
        let elapsed = harness.scene.gameplayClock - clock

        let interval = GameConfiguration.defaultShootInterval * OverdriveRules.fireIntervalScale
        let expected = elapsed / interval
        XCTAssertEqual(
            fired, expected, accuracy: max(1.5, expected * 0.05),
            "\(Int(fired)) volleys in \(elapsed) s of overdrive: one every \(elapsed / max(fired, 1)) s "
            + "against an interval of \(interval) s"
        )
    }

    /// The carried cadence must not bank the time the finger was off the glass: the
    /// first volley of a press is immediate, and the next waits a full interval.
    func testAPressFiresAtOnceAndOnlyOnce() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.holdFire(for: 0.5)
        harness.touchUp(at: harness.player.position)
        harness.spin(0.5)

        let volleys = harness.scene.volleysFired
        let clock = harness.scene.gameplayClock
        harness.touchDown(at: harness.player.position)
        spin(harness, until: { harness.scene.gameplayClock >= clock + 0.08 })

        XCTAssertEqual(
            harness.scene.volleysFired - volleys, 1,
            "a fresh press fired \(harness.scene.volleysFired - volleys) volleys in its first 0.08 s"
        )
    }

    /// Rapid fire's volleys heat the guns at `rapidFireHeatScale`. At full heat per volley
    /// the faster stream overheated a few seconds into the power-up.
    func testRapidFireHeatsTheGunsAtItsReducedRate() {
        let harness = GameplayHarness()
        harness.startPlayingWithControl()
        defer { harness.teardown() }

        harness.player.hasRapidFire = true
        let start = harness.scene.volleysFired
        harness.touchDown(at: harness.player.position)

        // Fire until the guns lock out: the count stops climbing.
        var last = harness.scene.volleysFired
        var stalledAt = Date()
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            harness.spin(0.05)
            let now = harness.scene.volleysFired
            if now != last {
                last = now
                stalledAt = Date()
            } else if Date().timeIntervalSince(stalledAt) > 0.5 && now > start {
                break
            }
        }

        let volleys = Double(last - start)
        let budget = (GameConfiguration.maxHeat
                      / (GameConfiguration.heatPerShot * GameConfiguration.rapidFireHeatScale)).rounded(.up)
        XCTAssertEqual(
            volleys, Double(budget), accuracy: 2,
            "rapid fire overheated after \(Int(volleys)) volleys, not the \(Int(budget)) its heat scale allows"
        )
    }
}
