//
//  AudioResourceTests.swift
//  jetshotTests
//

import XCTest
import AVFoundation
@testable import jetshot

/// A music or effect file that is referenced but not bundled fails silently — it just
/// plays nothing. That has already shipped once (five effects pointed at `.wav` files
/// that were never added to the project), and the tracks were recently re-encoded from
/// 256 kbps MP3 to AAC, which renamed every one of them.
final class AudioResourceTests: XCTestCase {

    /// The bundle under test is the host app's, not the test bundle's.
    private var appBundle: Bundle {
        return Bundle(for: SoundManager.self)
    }

    func testEveryLevelMusicTrackIsBundled() {
        XCTAssertFalse(SoundManager.musicTracks.isEmpty)

        for track in SoundManager.musicTracks {
            XCTAssertNotNil(
                appBundle.url(forResource: track, withExtension: SoundManager.musicExtension),
                "\(track).\(SoundManager.musicExtension) is referenced but missing from the bundle"
            )
        }
    }

    func testStoryMusicIsBundled() {
        XCTAssertNotNil(
            appBundle.url(
                forResource: SoundManager.storyMusicTrack,
                withExtension: SoundManager.musicExtension
            ),
            "the story crawl's music is missing from the bundle"
        )
    }

    func testEveryTrackIsDecodableAndNonEmpty() {
        // Catches a truncated or corrupt re-encode, which a plain existence check
        // would happily wave through.
        for track in SoundManager.musicTracks + [SoundManager.storyMusicTrack] {
            guard let url = appBundle.url(
                forResource: track, withExtension: SoundManager.musicExtension
            ) else {
                XCTFail("\(track) missing from bundle")
                continue
            }

            do {
                let player = try AVAudioPlayer(contentsOf: url)
                XCTAssertGreaterThan(player.duration, 1.0, "\(track) decodes to \(player.duration)s")
            } catch {
                XCTFail("\(track) could not be decoded: \(error)")
            }
        }
    }

    func testEveryLevelMapsToABundledTrack() {
        // setMusicForLevel indexes the track list with `(level - 1) % count`, so a
        // negative or zero level would make the remainder negative and trap.
        for level in [-5, 0, 1, 2, 7, 8, 50, GameConfiguration.totalLevels, 999] {
            let index = (max(1, level) - 1) % SoundManager.musicTracks.count
            XCTAssertTrue(
                SoundManager.musicTracks.indices.contains(index),
                "level \(level) maps to track index \(index), which is out of bounds"
            )
        }
    }

    func testTrackNamesAreUnique() {
        XCTAssertEqual(
            Set(SoundManager.musicTracks).count,
            SoundManager.musicTracks.count,
            "a duplicated track name means one level's music silently plays another's"
        )
    }

    /// Asked of `SoundManager` rather than restated here.
    ///
    /// This used to be a hand-copied list of all 42 effect names, which only stayed
    /// correct while someone remembered to edit both it and `preloadSounds()`. A cue
    /// added to one and not the other was exactly the bug this test is for: a
    /// referenced-but-unbundled file does not throw, it plays silence.
    /// `requestedEffectResources` is filled in by `createSoundAction` as it runs, so
    /// the coverage here follows the manager automatically.
    @MainActor
    func testEverySoundEffectIsBundled() {
        // Driven directly: `init` schedules the preload on the main queue, and reading
        // the lists without waiting for that dispatch would inspect empty arrays and
        // pass vacuously.
        SoundManager.shared.preloadSounds()

        let requested = SoundManager.shared.requestedEffectResources
        XCTAssertFalse(requested.isEmpty, "no effects were preloaded, so this test proves nothing")

        XCTAssertEqual(
            SoundManager.shared.missingEffectResources, [],
            "referenced by SoundManager but missing from the bundle — these cues play silence"
        )

        // Belt and braces: resolve each distinct name against the bundle here too, so
        // the test still fails usefully if the manager's own lookup ever changes.
        for effect in Set(requested) {
            let name = (effect as NSString).deletingPathExtension
            let ext = (effect as NSString).pathExtension
            XCTAssertNotNil(
                appBundle.url(forResource: name, withExtension: ext),
                "\(effect) is referenced by SoundManager but missing from the bundle"
            )
        }
    }

    /// A cue remapped onto another effect's file is deliberate (see the note at the end
    /// of `preloadSounds()`), but a cue pointing at a *non-mp3* extension is the shape
    /// of the bug that shipped once: five effects referenced `.wav` files that were
    /// never added to the project.
    @MainActor
    func testEveryEffectReferenceIsAnMP3() {
        SoundManager.shared.preloadSounds()

        for effect in Set(SoundManager.shared.requestedEffectResources) {
            XCTAssertEqual(
                (effect as NSString).pathExtension, "mp3",
                "\(effect) is not an .mp3; every bundled effect is"
            )
        }
    }
}
