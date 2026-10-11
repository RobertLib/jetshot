//
//  SceneExitSoundTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
import AVFoundation
@testable import jetshot

/// Cues fired by a scene in the act of leaving.
///
/// The game-over and level-complete jingles, the ENDLESS click and the story's
/// tap-to-skip click were all queued as actions on the outgoing scene a moment before it
/// presented the next one. The transition pauses the outgoing scene first, so none of
/// them ever played. They now go through `SoundManager`'s own players, which belong to no
/// scene.
@MainActor
final class SceneExitSoundTests: XCTestCase {

    func testTheResultJinglesPlayWithoutAScene() {
        withSoundOn { sound in
            sound.playGameOverSound()
            XCTAssertEqual(sound.detachedPlayers["game-over.mp3"]?.isPlaying, true,
                           "the game-over jingle did not start")

            sound.playLevelCompleteSound()
            XCTAssertEqual(sound.detachedPlayers["level-complete.mp3"]?.isPlaying, true,
                           "the level-complete jingle did not start")
        }
    }

    func testTheyHonourTheSoundSwitch() {
        withSoundOn { sound in
            sound.isSoundEnabled = false
            sound.playGameOverSound()
            sound.playLevelCompleteSound()
            sound.playSceneExitClickSound()

            for (name, player) in sound.detachedPlayers {
                XCTAssertFalse(player.isPlaying, "\(name) played with the sound switched off")
            }
        }
    }

    /// End to end: ENDLESS presents the run on the same touch, and its click still plays.
    func testTheEndlessClickPlaysAsTheMenuLeaves() {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        withCleanProgress {
            withSoundOn { sound in
                LevelManager.shared.completeLevel(1, score: 5_000)
                let menu = MenuScene(size: harness.view.bounds.size)
                harness.present(menu, settle: 1.0)

                guard let endless = menu.childNode(withName: "endlessButton") else {
                    return XCTFail("the menu did not build ENDLESS")
                }
                menu.touchesBegan([HarnessTouch(endless.position)], with: nil)

                XCTAssertEqual(sound.detachedPlayers["button-click.mp3"]?.isPlaying, true,
                               "ENDLESS left the menu without its click")
            }
        }
    }

    // MARK: - Helpers

    /// Runs `body` with fresh players and the sound switched on, then stops them and puts
    /// the switch back.
    private func withSoundOn(_ body: (SoundManager) -> Void) {
        let sound = SoundManager.shared
        let wasEnabled = sound.isSoundEnabled
        sound.preloadSounds()
        sound.isSoundEnabled = true
        defer {
            sound.isSoundEnabled = wasEnabled
            sound.detachedPlayers.values.forEach { $0.stop() }
        }
        body(sound)
    }
}
