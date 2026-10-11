//
//  BossPatternTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The arithmetic inside the boss's attacks that decides whether a pattern is fair: how
/// a fan is spread, where the wraith blinks to, which colour the gauge burns.
///
/// Each of these was once quietly wrong in a way no crash or fight test would show — a
/// fan tipped to one side, a blink that went nowhere, a gauge a beat behind the phase it
/// announces — so they are pinned here directly.
final class BossPatternTests: XCTestCase {

    // MARK: - Fans

    /// Every fan is centred on its aim, edge to edge across its width. The circular
    /// barrage divided by `count + 2` and covered −0.9…+0.41 rad; the spiral divided by
    /// `count` and covered −0.6…+0.48.
    func testEveryFanIsSymmetricAboutItsAim() {
        for count in 2...16 {
            for width: CGFloat in [0.9, 1.2, 1.5, 1.6, 1.8] {
                let angles = (0..<count).map { BossManager.fanAngle($0, of: count, width: width) }
                XCTAssertEqual(angles.first ?? 0, -width / 2, accuracy: 1e-9, "\(count) across \(width): left edge")
                XCTAssertEqual(angles.last ?? 0, width / 2, accuracy: 1e-9, "\(count) across \(width): right edge")
                for i in 0..<count {
                    XCTAssertEqual(angles[i], -angles[count - 1 - i], accuracy: 1e-9,
                                   "\(count) across \(width): round \(i) has no mirror")
                }
                XCTAssertEqual(angles.reduce(0, +), 0, accuracy: 1e-9, "\(count) across \(width) leans to one side")
            }
        }
    }

    func testTheCircularBarrageCoversBothSidesOfTheBoss() {
        let angles = (0..<9).map { BossManager.fanAngle($0, of: 9, width: 1.8) }
        XCTAssertEqual(angles.min() ?? 0, -0.9, accuracy: 1e-9)
        XCTAssertEqual(angles.max() ?? 0, 0.9, accuracy: 1e-9, "the boss's lower right is a safe corner")
    }

    func testAOneRoundFanGoesStraightDownItsAim() {
        XCTAssertEqual(BossManager.fanAngle(0, of: 1, width: 1.8), 0)
    }

    // MARK: - Blink

    /// The late wraiths on a phone fly an arena 159–179 pt wide. From near its middle no
    /// spot is 90 pt away, and the blink used to fade out and back in where it started.
    func testTheWraithAlwaysBlinksSomewhereElse() {
        var generator = SystemRandomNumberGenerator()
        for span: CGFloat in [40, 99, 120, 159, 179, 250, 320] {
            let minX: CGFloat = 60, maxX = minX + span
            for start in stride(from: minX, through: maxX, by: span / 8) {
                for _ in 0..<200 {
                    let x = BossManager.blinkX(from: start, minX: minX, maxX: maxX, using: &generator)
                    XCTAssertGreaterThanOrEqual(x, minX, "blinked out of the arena")
                    XCTAssertLessThanOrEqual(x, maxX, "blinked out of the arena")
                    // At least as far as the far end of the arena is, or the full reach.
                    let farthest = max(start - minX, maxX - start)
                    let required = min(farthest, max(90, span * 0.3))
                    XCTAssertGreaterThanOrEqual(abs(x - start), required - 1e-6,
                                                "a \(span) pt arena: blinked from \(start) only to \(x)")
                }
            }
        }
    }

    func testABlinkInAnArenaWithNoWidthStaysOnIt() {
        var generator = SystemRandomNumberGenerator()
        XCTAssertEqual(BossManager.blinkX(from: 195, minX: 195, maxX: 195, using: &generator), 195)
    }

    // MARK: - Heart

    /// The heart's orbital spiral spins its shell nodes up through `look.spin`, and its
    /// rounds leave from those nodes. They used to turn on the plain clock, which the
    /// spin never reached, so the signature fired straight lines.
    @MainActor
    func testSpinningUpTheHeartTurnsTheGunsItFiresFrom() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        let level = GameConfiguration.totalLevels
        XCTAssertEqual(BossConfig.config(for: level).archetype, .heart)
        harness.startPlaying(level: level)
        harness.scene.bossManager.spawnBoss(level: level) {}
        harness.spin(2.4)
        guard let boss = harness.gameContent.children.compactMap({ $0 as? Boss }).first else {
            return XCTFail("no boss")
        }
        // Nothing else turning it: no attacks, so no spin-up of their own, and held in
        // place, so its lean into its flight does not swing the guns about on screen.
        boss.removeAction(forKey: "bossAttackSchedule")
        boss.beginManoeuvre()
        harness.spin(0.5)

        /// How far gun 0 turns about the middle of the four, in `seconds`, net.
        func turn(over seconds: TimeInterval) -> CGFloat {
            func angle() -> CGFloat {
                let guns = (0..<boss.muzzleCount).compactMap { boss.muzzle($0) }
                guard guns.count == 4, let gun = boss.muzzle(0) else { return 0 }
                let mid = CGPoint(x: guns.map(\.x).reduce(0, +) / 4, y: guns.map(\.y).reduce(0, +) / 4)
                return atan2(gun.y - mid.y, gun.x - mid.x)
            }
            var total: CGFloat = 0
            var last = angle()
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                harness.spin(0.05)
                let now = angle()
                var step = now - last
                while step > .pi { step -= 2 * .pi }
                while step < -.pi { step += 2 * .pi }
                total += step
                last = now
            }
            return abs(total)
        }

        boss.look.spin = 1
        let idle = turn(over: 1.0)
        boss.look.spin = 2.8
        let spun = turn(over: 1.0)
        XCTAssertGreaterThan(idle, 0, "the heart's guns never turned")
        XCTAssertGreaterThan(spun, idle * 2, "spinning the heart up left its guns turning at \(spun / max(idle, 1e-6))x")
    }

    // MARK: - Nameplate

    /// Every boss's name fits over its bar: on the narrowest phone, and on a bar far
    /// narrower than any phone gives it, where the long names have to shrink. The 20 pt
    /// name was handed the default 24 pt floor for its shrink-to-fit, so it could never
    /// shrink at all — today's names happen to fit a phone at full size, so that only
    /// waited for a longer name or translation to run off the ends of the bar.
    @MainActor
    func testEveryBossNameFitsOverItsHealthBar() {
        for width: CGFloat in [375, 240] {
            let size = CGSize(width: width, height: 667)
            var names = Set<String>()
            for level in 1...GameConfiguration.totalLevels {
                let config = BossConfig.config(for: level)
                guard names.insert(config.displayName).inserted else { continue }
                let boss = Boss(config: config, sceneSize: size)
                XCTAssertGreaterThan(boss.nameplateWidth, 0, "\(config.displayName) has no nameplate")
                XCTAssertLessThanOrEqual(boss.nameplateWidth, boss.healthBarWidth,
                                         "\(config.displayName) runs past the ends of a \(width) pt screen's bar")
            }
        }
    }

    // MARK: - Gauge

    /// The gauge changes colour on the same health the fight changes act on, where the
    /// notches are, not at 0.6 and 0.3 a beat later.
    @MainActor
    func testTheGaugeChangesColourExactlyWhereThePhaseChanges() {
        var previousPhase = BossPhaseRules.phase(forHealthFraction: 1)
        var previousColor = Boss.gaugeColor(for: 1)
        for step in stride(from: 1000, through: 0, by: -1) {
            let fraction = CGFloat(step) / 1000
            let phase = BossPhaseRules.phase(forHealthFraction: fraction)
            let color = Boss.gaugeColor(for: fraction)
            if phase == previousPhase {
                XCTAssertEqual(color, previousColor, "the gauge changed colour mid-act, at \(fraction)")
            } else {
                XCTAssertNotEqual(color, previousColor, "the fight entered act \(phase) at \(fraction) in the same colour")
            }
            previousPhase = phase
            previousColor = color
        }
    }
}
