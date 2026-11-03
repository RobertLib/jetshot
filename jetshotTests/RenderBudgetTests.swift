//
//  RenderBudgetTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Pins the texture caches' eviction and render scales, and the redraw pacing.
///
/// None of these show up as a wrong picture. A cache that empties itself when full,
/// a bloom rendered at 3x or a throttle that slips a frame all draw correctly; the
/// symptoms are a hitch mid-wave, memory that is nine times what it needs to be and
/// a spinning hull that judders, none of which a screenshot catches.
final class RenderBudgetTests: XCTestCase {

    // MARK: - Cache eviction

    func testFullCacheEvictsOnlyTheLeastRecentlyUsedEntry() {
        var cache = NeonFX.LRUCache<String, Int>(capacity: 3)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")
        cache.insert(3, forKey: "c")
        // "a" is the oldest by insertion, but is in use; "b" has gone longest unasked.
        XCTAssertEqual(cache.value(forKey: "a"), 1)
        cache.insert(4, forKey: "d")

        XCTAssertEqual(cache.count, 3, "a full cache grew, or emptied itself")
        XCTAssertFalse(cache.contains("b"), "the least recently used entry survived")
        XCTAssertTrue(cache.contains("a"), "an entry in use was evicted")
        XCTAssertTrue(cache.contains("c"))
        XCTAssertTrue(cache.contains("d"))
    }

    func testReplacingAKeyInAFullCacheEvictsNothing() {
        var cache = NeonFX.LRUCache<String, Int>(capacity: 2)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")
        cache.insert(3, forKey: "b")

        XCTAssertEqual(cache.count, 2)
        XCTAssertTrue(cache.contains("a"))
        XCTAssertEqual(cache.value(forKey: "b"), 3)
    }

    /// The regression itself: one-off glows used to flush the shared ones with them.
    @MainActor
    func testSharedGlowSurvivesAStreamOfOneOffGlows() {
        NeonFX.clearCaches()
        let shared = UIColor(red: 0, green: 1, blue: 1, alpha: 1)
        let original = NeonFX.radialGlow(radius: 10, color: shared).texture

        // Well past the cache's capacity in distinct colours, the shared one asked for
        // now and then the way a coin's or an enemy's is.
        for i in 0..<250 {
            let red = (CGFloat(i) + 0.5) / 255
            _ = NeonFX.radialGlow(radius: 10, color: UIColor(red: red, green: 0.3, blue: 0.6, alpha: 1))
            if i % 10 == 0 { _ = NeonFX.radialGlow(radius: 10, color: shared) }
        }

        XCTAssertIdentical(NeonFX.radialGlow(radius: 10, color: shared).texture, original,
                           "the shared glow was thrown out and re-rendered")
    }

    // MARK: - Render scale

    @MainActor
    func testRadialGlowRendersAt1x() throws {
        NeonFX.clearCaches()
        let texture = try XCTUnwrap(NeonFX.radialGlow(radius: 40, color: .orange).texture)
        XCTAssertEqual(texture.cgImage().width, 128, "the glow texture is rendered at device scale")
    }

    @MainActor
    func testWideBloomRendersAt1xAndKeepsItsSizeInPoints() throws {
        NeonFX.clearCaches()
        let shape = SKShapeNode(circleOfRadius: 12)
        shape.fillColor = .cyan
        let halo = try XCTUnwrap(bloomSprite(on: shape, blur: 6))
        let texture = try XCTUnwrap(halo.texture)

        // Padded for the falloff: 3 sigma plus the dilation either side of the shape.
        let padding: CGFloat = 6 * 3 + 1.5 + 2
        XCTAssertGreaterThanOrEqual(halo.size.width, 24 + 2 * padding)
        XCTAssertEqual(CGFloat(texture.cgImage().width), halo.size.width, accuracy: 0.001,
                       "a wide bloom is rendered at more than 1x")
    }

    @MainActor
    func testTightBloomRendersAtNoMoreThan2x() throws {
        NeonFX.clearCaches()
        let shape = SKShapeNode(rectOf: CGSize(width: 4, height: 20))
        shape.fillColor = .magenta
        let halo = try XCTUnwrap(bloomSprite(on: shape, blur: 1.5))
        let texture = try XCTUnwrap(halo.texture)

        let deviceScale = UIGraphicsImageRendererFormat.preferred().scale
        XCTAssertEqual(CGFloat(texture.cgImage().width), halo.size.width * min(deviceScale, 2), accuracy: 0.001)
    }

    @MainActor
    private func bloomSprite(on shape: SKShapeNode, blur: CGFloat) -> SKSpriteNode? {
        NeonFX.addBloom(to: shape, blur: blur)?.children.first as? SKSpriteNode
    }

    // MARK: - Grade

    @MainActor
    func testGradeIsAThumbnailStretchedOverTheScreen() throws {
        NeonFX.clearCaches()
        let screen = CGSize(width: 430, height: 932)
        let grade = NeonFX.gradeOverlay(size: screen)
        let image = try XCTUnwrap(grade.texture).cgImage()

        XCTAssertEqual(grade.size, screen, "the overlay no longer covers the screen")
        XCTAssertEqual(image.height, 128, "the vignette is rendered at screen resolution")
        // Same shape as the screen, so the stretch is uniform and the vignette round.
        XCTAssertEqual(CGFloat(image.width) / CGFloat(image.height), screen.width / screen.height, accuracy: 0.01)
    }

    @MainActor
    func testGradeIsSharedBetweenSizesOfTheSameShape() {
        NeonFX.clearCaches()
        let full = NeonFX.gradeOverlay(size: CGSize(width: 430, height: 932))
        let half = NeonFX.gradeOverlay(size: CGSize(width: 215, height: 466))
        XCTAssertIdentical(full.texture, half.texture)
    }

    // MARK: - Hazard stripes

    @MainActor
    func testHazardStripesInDifferentColoursDoNotShareATexture() {
        SurfaceFX.clearCaches()
        let size = CGSize(width: 60, height: 20)
        let amber = SurfaceFX.hazardStripes(size: size, cornerRadius: 4) as? SKSpriteNode
        let red = SurfaceFX.hazardStripes(size: size, cornerRadius: 4, color: .red) as? SKSpriteNode
        let amberAgain = SurfaceFX.hazardStripes(size: size, cornerRadius: 4) as? SKSpriteNode

        XCTAssertNotIdentical(amber?.texture, red?.texture, "a red panel was given the amber stripes")
        XCTAssertIdentical(amber?.texture, amberAgain?.texture)
    }

    // MARK: - Backdrop

    /// The funnel legs of the well sector cut their holes per column now; fly each of
    /// them through several wells' worth of ground, on a phone and on an iPad.
    @MainActor
    func testFunnelStagesFlyThroughSeveralWells() {
        let funnelLevels = (1...50).filter { BackdropStage.of(BackdropLook.forLevel($0)).has(.funnels) }
        XCTAssertFalse(funnelLevels.isEmpty, "no level has funnels to test")
        for size in [CGSize(width: 390, height: 844), CGSize(width: 1024, height: 1366)] {
            for level in funnelLevels {
                let backdrop = GameBackdrop(size: size, level: level, endless: false)
                // Ten seconds at cruise is a couple of wells passing under the ship.
                for _ in 0..<600 { backdrop.update(dt: 1.0 / 60) }
                XCTAssertEqual(backdrop.look, BackdropLook.forLevel(level))
            }
        }
    }

    // MARK: - Redraw pacing

    /// Redraws over `frames`, as the gaps between them in frames.
    private func redrawGaps(interval: Float, frames: [Float]) -> [Int] {
        var pacer = FramePacer(interval: interval)
        pacer.restart()
        var gaps: [Int] = []
        var since = 0
        for dt in frames {
            since += 1
            pacer.advance(by: dt)
            if pacer.claimRedraw(frame: dt) {
                gaps.append(since)
                since = 0
            }
        }
        return gaps
    }

    /// Frame times around `rate`, nudged either way by a fraction of a microsecond — the
    /// jitter that used to decide whether a 30 Hz redraw landed on the second frame or
    /// the third.
    private func jittered(_ rate: Float, count: Int) -> [Float] {
        var rng = SystemRandomNumberGenerator()
        return (0..<count).map { _ in 1 / rate + Float.random(in: -4e-7...4e-7, using: &rng) }
    }

    func testThirtyHertzHoldsEveryOtherFrameAtSixty() {
        let gaps = redrawGaps(interval: 1.0 / 30, frames: jittered(60, count: 600))
        XCTAssertEqual(Set(gaps), [2], "redraws slipped between frames: \(gaps.prefix(20))")
    }

    func testThirtyHertzHoldsEveryFourthFrameAtOneTwenty() {
        let gaps = redrawGaps(interval: 1.0 / 30, frames: jittered(120, count: 1200))
        XCTAssertEqual(Set(gaps), [4], "redraws slipped between frames: \(gaps.prefix(20))")
    }

    func testThirtyHertzRedrawsEveryFrameAtThirty() {
        let gaps = redrawGaps(interval: 1.0 / 30, frames: jittered(30, count: 300))
        XCTAssertEqual(Set(gaps), [1])
    }

    func testZeroIntervalRedrawsEveryFrame() {
        XCTAssertEqual(Set(redrawGaps(interval: 0, frames: jittered(60, count: 120))), [1])
    }

    func testStallIsNotFollowedByABurst() {
        var frames = jittered(60, count: 60)
        // A frame between two redraws runs long. It redraws, and the cadence picks up
        // again from there rather than redrawing on the next frames to catch up.
        frames[31] = 0.1
        let gaps = redrawGaps(interval: 1.0 / 30, frames: frames)
        XCTAssertEqual(Set(gaps), [2], "redraws bunched up after the stall: \(gaps)")
    }

    func testShowingAgainIsNotFollowedByABurst() {
        var pacer = FramePacer(interval: 1.0 / 30)
        pacer.restart()
        // Hidden: the clock runs on, but nothing asks to redraw.
        for _ in 0..<20 { pacer.advance(by: 1.0 / 60) }
        var redraws: [Bool] = []
        for _ in 0..<8 {
            pacer.advance(by: 1.0 / 60)
            redraws.append(pacer.claimRedraw(frame: 1.0 / 60))
        }
        XCTAssertEqual(redraws, [true, false, true, false, true, false, true, false])
    }

    func testAverageRateHoldsWhenFramesDoNotDivideTheInterval() {
        // 40 Hz: no whole number of frames per redraw, so only the average can be right.
        let gaps = redrawGaps(interval: 1.0 / 30, frames: jittered(40, count: 400))
        let redrawsPerSecond = Float(gaps.count) / 10
        XCTAssertEqual(redrawsPerSecond, 30, accuracy: 0.5)
    }

    func testForcedRedrawIgnoresTheSchedule() {
        var pacer = FramePacer(interval: 1.0 / 30)
        pacer.restart()
        pacer.advance(by: 1.0 / 60)
        XCTAssertFalse(pacer.claimRedraw(frame: 1.0 / 60))
        pacer.force()
        pacer.advance(by: 1.0 / 60)
        XCTAssertTrue(pacer.claimRedraw(frame: 1.0 / 60))
        // And the schedule starts again from there.
        pacer.advance(by: 1.0 / 60)
        XCTAssertFalse(pacer.claimRedraw(frame: 1.0 / 60))
    }
}
