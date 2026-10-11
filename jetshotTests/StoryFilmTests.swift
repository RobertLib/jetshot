//
//  StoryFilmTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Covers the opening and ending films.
///
/// The films are code, not assets, so the ways they can break are code-shaped: a
/// paragraph of the story dropped when shots are rearranged, captions in a long
/// translation running into each other or past the end of their shot, a sentence split
/// mid-thought, a shot whose maths produces nothing (or NaN) at some point of its run.
@MainActor
final class StoryFilmTests: XCTestCase {

    private func narration(of type: StoryType) -> String {
        StoryScene.shots(for: type).flatMap { $0.lines.map(\.text) }.joined(separator: "\n")
    }

    // MARK: - Story coverage

    func testEveryOpeningParagraphIsNarrated() {
        let film = narration(of: .opening)
        XCTAssertTrue(film.contains(L10n.Story.openingTitle), "the opening lost its title card")
        for paragraph in L10n.Story.openingParagraphs {
            XCTAssertTrue(film.contains(paragraph), "the opening never shows: \(paragraph)")
        }
    }

    /// Every paragraph but "∞", which the last shot draws as a figure instead.
    func testEveryEndingParagraphIsNarrated() {
        let film = narration(of: .ending)
        XCTAssertTrue(film.contains(L10n.Story.endingTitle), "the ending lost its title card")
        for paragraph in L10n.Story.endingParagraphs where paragraph != "∞" {
            XCTAssertTrue(film.contains(paragraph), "the ending never shows: \(paragraph)")
        }
    }

    // MARK: - Timing

    func testFilmsRunAFewMinutesAtMost() {
        for type in [StoryType.opening, .ending] {
            let total = StoryScene.shots(for: type).map { ShotTimeline($0).duration }.reduce(0, +)
            XCTAssertGreaterThan(total, 60, "\(type) is too short to read")
            XCTAssertLessThan(total, 200, "\(type) drags on")
        }
    }

    /// Captions follow one another without overlapping, and every one has gone before
    /// its shot cuts away — whatever the length of the translation.
    func testCaptionsFitTheirShots() {
        for type in [StoryType.opening, .ending] {
            for (index, shot) in StoryScene.shots(for: type).enumerated() {
                let timeline = ShotTimeline(shot)
                var previousEnd: Float = 0
                for beat in timeline.beats {
                    XCTAssertGreaterThanOrEqual(beat.start, previousEnd, "\(type) shot \(index + 1): captions overlap")
                    XCTAssertGreaterThan(beat.end, beat.start)
                    previousEnd = beat.end
                }
                XCTAssertLessThanOrEqual(previousEnd, timeline.duration,
                                         "\(type) shot \(index + 1): a caption outlives its shot")
            }
        }
    }

    func testSentenceSplitting() {
        XCTAssertEqual(ShotTimeline.sentences(in: "The path will not be easy. Reality itself will resist."),
                       ["The path will not be easy.", "Reality itself will resist."])
        // An ellipsis that trails off, or leads in, is not a break.
        XCTAssertEqual(ShotTimeline.sentences(in: "We stand at the very end of time...").count, 1)
        XCTAssertEqual(ShotTimeline.sentences(in: "...or you perish along with this universe.").count, 1)
        // Czech quotes close after the question mark.
        XCTAssertEqual(ShotTimeline.sentences(in: "Někdo se zeptá: „Jak to všechno začalo?“ A odpověď přijde."),
                       ["Někdo se zeptá: „Jak to všechno začalo?“", "A odpověď přijde."])
        // A lower-case continuation is not a new sentence.
        XCTAssertEqual(ShotTimeline.sentences(in: "Wait... and see.").count, 1)
    }

    // MARK: - Rendering

    private func sprites(in node: SKNode) -> [SKSpriteNode] {
        node.children.flatMap { child -> [SKSpriteNode] in
            var found = sprites(in: child)
            if let sprite = child as? SKSpriteNode, !sprite.isHidden { found.append(sprite) }
            return found
        }
    }

    /// Renders every shot at five points of its run: something must be drawn, and
    /// nothing may land at a NaN position — which is what a degenerate normalise or a
    /// division by a zero depth turns into on screen.
    func testEveryShotDrawsThroughoutItsRun() {
        let viewport = CGRect(x: 0, y: 180, width: 390, height: 480)
        let canvas = WireCanvas(viewport: viewport)
        let overlay = StoryOverlay(canvas: canvas, frame: viewport, typeScale: 1)

        for type in [StoryType.opening, .ending] {
            for (index, shot) in StoryScene.shots(for: type).enumerated() {
                let timeline = ShotTimeline(shot)
                for fraction: Float in [0.02, 0.25, 0.5, 0.75, 0.98] {
                    let t = fraction * timeline.duration
                    canvas.settings = WireCanvas.Settings()
                    shot.render(ShotFrame(t: t, previousT: t - 1.0 / 60, duration: timeline.duration,
                                          canvas: canvas, overlay: overlay, timeline: timeline))
                    canvas.end()
                    XCTAssertGreaterThan(canvas.drawnCount, 0, "\(type) shot \(index + 1) is blank at \(fraction)")
                    for sprite in sprites(in: canvas) {
                        XCTAssertFalse(sprite.position.x.isNaN || sprite.position.y.isNaN,
                                       "\(type) shot \(index + 1) drew at NaN at \(fraction)")
                        XCTAssertFalse(sprite.size.width.isNaN || sprite.size.height.isNaN)
                    }
                }
                overlay.reset()
                _ = overlay.drainCues()
            }
        }
    }

    func testFilmPlaysInAView() {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: view.frame)
        window.addSubview(view)
        window.isHidden = false

        let scene = StoryScene(size: view.bounds.size, type: .ending)
        view.presentScene(scene)
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(view.scene === scene, "the film left before it played")
        XCTAssertFalse(scene.children.isEmpty)

        view.presentScene(MenuScene(size: view.bounds.size))
    }
}
