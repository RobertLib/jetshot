//
//  MusicPlaybackTests.swift
//  jetshotTests
//

import XCTest
import AVFoundation
@testable import jetshot

/// Which track plays, and whether it carries on or starts over, as the game moves
/// between screens, films and interruptions.
///
/// Driven against the real `SoundManager.shared`, so the music genuinely plays in the
/// test host. The music switch is persisted, so every test puts it back as it found it.
@MainActor
final class MusicPlaybackTests: XCTestCase {

    private var tracks: [String] { SoundManager.musicTracks }

    // MARK: - Screen changes

    /// Every screen calls `startBackgroundMusic()` as it arrives (and the results screens
    /// `resumeMusic()`). It used to rebuild the player each time, so the track jumped
    /// back to 0:00 on nearly every screen change.
    func testArrivingOnAScreenCarriesOnWithThePlayingTrack() throws {
        try withMusicOn { sound in
            sound.setMusicForLevel(3)
            let player = try XCTUnwrap(sound.musicPlayer, "setMusicForLevel started nothing")

            sound.startBackgroundMusic() // the menu
            sound.startBackgroundMusic() // the level grid
            sound.resumeMusic()          // a results screen
            sound.setMusicForLevel(3)    // the next try at the same level

            XCTAssertTrue(sound.musicPlayer === player,
                          "arriving on a screen rebuilt the player, restarting the track from the top")
            XCTAssertEqual(sound.musicPlayerResource, tracks[2])
        }
    }

    /// With the music off, a new level only moves the selection on; the paused player
    /// still holds the old track. Switching the music back on resumed that player as it
    /// was, playing the previous level's music for the rest of this one.
    func testSwitchingTheMusicBackOnPlaysTheCurrentLevelsTrack() {
        withMusicOn { sound in
            sound.setMusicForLevel(1)
            sound.isMusicEnabled = false
            sound.setMusicForLevel(2)
            sound.isMusicEnabled = true

            XCTAssertEqual(sound.musicPlayerResource, tracks[1],
                           "the music came back on with the previous level's track")
            XCTAssertEqual(sound.musicPlayer?.isPlaying, true)
        }
    }

    // MARK: - Story films

    /// The films ended by stopping and "restarting" the music while the selection was
    /// still the story track — which only restarted the story track. After the ending it
    /// then played on under the victory screen and the menu.
    func testTheStoryTrackHandsBackToTheRotationWhenItsFilmEnds() {
        withMusicOn { sound in
            sound.setMusicForLevel(4)
            sound.playSpecificMusic(named: SoundManager.storyMusicTrack)
            XCTAssertEqual(sound.musicPlayerResource, SoundManager.storyMusicTrack)

            sound.endSpecificMusic(fadeDuration: 0.2)
            XCTAssertEqual(sound.currentMusicResource, tracks[3],
                           "the story track was still selected after its film ended")

            // The next screen arriving.
            sound.startBackgroundMusic()
            XCTAssertEqual(sound.musicPlayerResource, tracks[3],
                           "the story track carried on after its film")
        }
    }

    /// A film watched with the music off must not leave the story track selected for
    /// whenever the music is switched back on.
    func testAFilmWatchedWithTheMusicOffLeavesTheRotationSelected() {
        withMusicOn { sound in
            sound.setMusicForLevel(5)
            sound.isMusicEnabled = false
            sound.playSpecificMusic(named: SoundManager.storyMusicTrack)
            sound.endSpecificMusic(fadeDuration: 0.2)
            sound.isMusicEnabled = true

            XCTAssertEqual(sound.musicPlayerResource, tracks[4])
        }
    }

    // MARK: - Session and interruptions

    /// The category used to be set only on the way into a music track, so with the music
    /// off the session stayed `.soloAmbient` and the first sound effect stopped whatever
    /// the player was listening to.
    func testTheSessionMixesWithOtherAudio() {
        _ = SoundManager.shared
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .ambient)
    }

    /// An interruption that ends without `.shouldResume` left the music silent until the
    /// next screen change.
    func testTheMusicComesBackAfterAnInterruptionThatDoesNotAskForIt() throws {
        try XCTSkipUnless(UIApplication.shared.applicationState == .active,
                          "the test host is not in front, so the music is meant to wait")
        try withMusicOn { sound in
            sound.setMusicForLevel(2)
            let player = try XCTUnwrap(sound.musicPlayer)

            postInterruption(.began)
            XCTAssertFalse(player.isPlaying, "the interruption did not pause the music, so this proves nothing")

            postInterruption(.ended)
            XCTAssertTrue(player.isPlaying, "the music stayed paused after the interruption ended")
        }
    }

    /// And when the interruption ended while the game was not in front, it comes back
    /// with the game.
    func testTheMusicComesBackWhenTheGameDoes() throws {
        try withMusicOn { sound in
            sound.setMusicForLevel(2)
            let player = try XCTUnwrap(sound.musicPlayer)

            postInterruption(.began)
            XCTAssertFalse(player.isPlaying)

            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertTrue(player.isPlaying, "the music stayed paused after the game came back to the front")
        }
    }

    // MARK: - Helpers

    /// Runs `body` with the music switched on, then puts the switch back.
    private func withMusicOn(_ body: (SoundManager) throws -> Void) rethrows {
        let sound = SoundManager.shared
        let wasEnabled = sound.isMusicEnabled
        sound.isMusicEnabled = true
        defer { sound.isMusicEnabled = wasEnabled }
        try body(sound)
    }

    private func postInterruption(_ type: AVAudioSession.InterruptionType) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if type == .ended {
            // Deliberately without `.shouldResume`.
            info[AVAudioSessionInterruptionOptionKey] = UInt(0)
        }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                        object: AVAudioSession.sharedInstance(), userInfo: info)
    }
}
