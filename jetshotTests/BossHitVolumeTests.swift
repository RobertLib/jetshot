//
//  BossHitVolumeTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// The boss's hit volumes against the art they stand for: the core's (see
/// `BossArt.coreVolume`) and its parts'.
///
/// The defect this was written for: every core was one circle 0.8 half widths across,
/// drawn round the hardware as well as the hull. Player rounds come up from below and
/// whichever volume a round meets first takes it, so the core's rim stood in front of
/// the gun pods, bays and satellites — and the heart's four shell nodes sat wholly inside
/// it, so the final boss's guns could not be shot off at all.
///
/// Pure geometry over a real render: the parts are drawn in 3D and turn, and only
/// `BossArt.render` knows where they end up, so each boss is drawn into a throwaway
/// canvas and its parts read back from the `BossLook`, exactly as `Boss` reads them.
@MainActor
final class BossHitVolumeTests: XCTestCase {

    /// How far below the core a part's underside has to hang, in points, before a round
    /// rising into it reaches it first. A round climbs a dozen or more points a frame;
    /// any closer and the two contacts arrive in the same physics step, and which one
    /// takes the round is SpriteKit's choice.
    private let lead: CGFloat = 8

    private func core(of config: BossConfig) -> [(center: CGPoint, radius: CGFloat)] {
        let unit = config.size / 2
        return BossArt.coreVolume(for: config.archetype, tier: config.tier).map {
            (CGPoint(x: $0.center.x * unit, y: $0.center.y * unit), $0.radius * unit)
        }
    }

    /// Draws `look` once at time `t`, which is what updates where its hardware is.
    /// Camera and extent as `Boss` builds its own wireframe.
    private func render(_ look: BossLook, of config: BossConfig, at t: Float) {
        _ = WireBody(extent: config.size / 2 * BossArt.extent(for: config.archetype), perspective: 4.5,
                     seed: t) { frame in
            BossArt.render(look, frame.canvas, t: frame.t)
        }
    }

    private func isInside(_ point: CGPoint, _ volume: [(center: CGPoint, radius: CGFloat)]) -> Bool {
        volume.contains { hypot(point.x - $0.center.x, point.y - $0.center.y) <= $0.radius }
    }

    /// Whether a round rising straight up somewhere across the part meets it before the
    /// core: in at least one column, the part's underside hangs `lead` below the core's
    /// (or the core does not reach that column at all).
    private func isReachable(part p: CGPoint, radius r: CGFloat,
                             core volume: [(center: CGPoint, radius: CGFloat)]) -> Bool {
        for k in -8...8 {
            let x = p.x + r * 0.95 * CGFloat(k) / 8
            let partBottom = p.y - sqrt(max(0, r * r - (x - p.x) * (x - p.x)))
            let coreBottom = volume.compactMap { c -> CGFloat? in
                let dx = x - c.center.x
                guard abs(dx) < c.radius else { return nil }
                return c.center.y - sqrt(c.radius * c.radius - dx * dx)
            }.min() ?? .infinity
            if coreBottom - partBottom >= lead { return true }
        }
        return false
    }

    /// Every part of every boss on the route can be shot off: at some point in the fight
    /// a round from below meets it before it meets the core.
    ///
    /// "At some point" because the gyre's satellites and the heart's shell nodes turn:
    /// one passing behind the hull is covered by it, as it should be, but each must come
    /// round to where it is not. Sampled for ten seconds, longer than a satellite takes
    /// to come round to the side. The serpent is drawn trailing sideways, the way it does
    /// across most of its figure of eight; trailing straight up, its body is behind its
    /// head from below, which is fair.
    func testEveryPartCanBeShotOffFromBelow() {
        for level in 1...GameConfiguration.totalLevels {
            let config = BossConfig.config(for: level)
            let count = BossArt.partCount(for: config.archetype, tier: config.tier)
            guard count > 0 else { continue }

            let unit = config.size / 2
            let volume = core(of: config)
            let look = BossLook(archetype: config.archetype, tier: config.tier, palette: config.palette,
                                unit: Float(unit))
            if config.archetype == .serpent {
                look.trail = (1...count).map { CGPoint(x: CGFloat($0) * unit * 0.62, y: 0) }
            }

            var unreached = Set(0..<count)
            var t: Float = 0
            while !unreached.isEmpty && t < 10 {
                render(look, of: config, at: t)
                unreached = unreached.filter { i in
                    let radius = BossArt.partRadius(for: config.archetype, index: i, count: count) * unit
                    return !isReachable(part: look.partPoints[i], radius: radius, core: volume)
                }
                t += 0.1
            }
            XCTAssertTrue(
                unreached.isEmpty,
                "level \(level)'s \(config.archetype): parts \(unreached.sorted()) are never in reach — "
                + "the core's hit volume covers them from below"
            )
        }
    }

    /// Fitting the core to the hull must not hollow the machine out: a round aimed at
    /// its middle, or at the eye or emitter its attacks come out of, still lands.
    func testTheCoreStillCoversTheMiddleOfTheMachineAndItsEye() {
        for level in 1...GameConfiguration.totalLevels {
            let config = BossConfig.config(for: level)
            let volume = core(of: config)
            let look = BossLook(archetype: config.archetype, tier: config.tier, palette: config.palette,
                                unit: Float(config.size / 2))
            render(look, of: config, at: 0)

            XCTAssertTrue(isInside(.zero, volume), "level \(level)'s \(config.archetype) is hollow in the middle")
            XCTAssertTrue(
                isInside(look.corePoint, volume),
                "level \(level)'s \(config.archetype) can be shot in the eye without being hit"
            )
        }
    }

    /// The hive's core is its comb, cell by cell, rather than one circle: a compound
    /// body. Real rounds on an outer cell — out where the widest comb reaches — have to
    /// land on the boss, and on the boss alone.
    func testTheHivesCombTakesRoundsAcrossItsWidth() {
        let harness = GameplayHarness()
        defer { harness.teardown() }
        harness.startPlaying(level: 31)

        harness.scene.bossManager.spawnBoss(level: 31) {}
        harness.spin(0.05)
        guard let boss = harness.gameContent.children.compactMap({ $0 as? Boss }).first else {
            return XCTFail("spawnBoss did not attach a Boss to the playfield")
        }
        XCTAssertEqual(boss.config.archetype, .hive)
        harness.spin(2.4)
        let partHealth = boss.parts.map(\.health)

        var rounds = 0
        while boss.healthFraction == 1 && rounds < 60 {
            let unit = boss.bossSize / 2
            harness.fireBullets(onto: CGPoint(x: boss.position.x + 0.62 * unit, y: boss.position.y + 0.05 * unit))
            harness.spin(0.03)
            rounds += 1
        }

        XCTAssertLessThan(boss.healthFraction, 1, "rounds on the comb's outer cell passed straight through it")
        XCTAssertEqual(boss.parts.map(\.health), partHealth, "rounds on the comb were taken by a bay")
    }
}
