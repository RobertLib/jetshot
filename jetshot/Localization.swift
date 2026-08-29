//
//  Localization.swift
//  jetshot
//
//  Created by Robert Libšanský on 29.08.2026.
//

import Foundation

/// Every piece of text the player can read, in one place.
///
/// The game ships English (its development language) and Czech. Which one a player
/// gets is decided by iOS, not by us: the system walks the player's preferred-language
/// list, finds `cs` if it is there, and falls back to `en` for everyone else. There is
/// deliberately no in-game language switch and no locale sniffing — a device set to
/// Czech is the whole rule.
///
/// Each accessor names an explicit key rather than letting the English string be its
/// own key. Short UI words collide across contexts once translated — `RESUME` and
/// `CONTINUE` are both "POKRAČOVAT" in Czech, and `BEST` is "REKORD" on a score line
/// but wants different wording anywhere it is a superlative — so the key has to carry
/// the context that the English word alone does not.
///
/// The `defaultValue:` on every entry is the English text itself, which means a key
/// missing from `Localizable.xcstrings` degrades to readable English rather than to
/// the raw key. Interpolations in a default value are what Xcode turns into the
/// format specifiers (`%lld` for `Int`) that the translations reuse.
enum L10n {

    // MARK: - Shared

    /// Words that appear on more than one screen. Kept common only where the *meaning*
    /// is the same in both places, not merely the English spelling: `common.retry` is
    /// on the game-over and pause screens because it is the same action, while
    /// `pause.resume` stays separate from `levelComplete.continue` even though Czech
    /// renders both as "POKRAČOVAT".
    enum Common {
        static var menu: String {
            String(localized: "common.menu", defaultValue: "MENU")
        }
        static var levels: String {
            String(localized: "common.levels", defaultValue: "LEVELS")
        }
        static var retry: String {
            String(localized: "common.retry", defaultValue: "RETRY")
        }
        static var back: String {
            String(localized: "common.back", defaultValue: "BACK")
        }
        static var score: String {
            String(localized: "common.score", defaultValue: "SCORE")
        }
        static var yes: String {
            String(localized: "common.yes", defaultValue: "YES")
        }
        static var no: String {
            String(localized: "common.no", defaultValue: "NO")
        }
        /// The endless record line, shown under the menu button and again on game over.
        static func endlessRecord(score: Int, round: Int) -> String {
            String(localized: "common.endlessRecord", defaultValue: "BEST  \(score)  ·  ROUND \(round)")
        }
        static func best(_ score: Int) -> String {
            String(localized: "common.best", defaultValue: "BEST  \(score)")
        }
    }

    // MARK: - Main menu

    enum Menu {
        static var subtitle: String {
            String(localized: "menu.subtitle", defaultValue: "SPACE SHOOTER")
        }
        static var credits: String {
            String(localized: "menu.credits", defaultValue: "CREATED BY ROBLIB")
        }
        static var start: String {
            String(localized: "menu.start", defaultValue: "START")
        }
        static var endless: String {
            String(localized: "menu.endless", defaultValue: "ENDLESS")
        }
        static var settings: String {
            String(localized: "menu.settings", defaultValue: "SETTINGS")
        }
    }

    // MARK: - Settings

    enum Settings {
        static var title: String {
            String(localized: "settings.title", defaultValue: "SETTINGS")
        }
        static var close: String {
            String(localized: "settings.close", defaultValue: "CLOSE")
        }
        static var music: String {
            String(localized: "settings.music", defaultValue: "MUSIC")
        }
        static var sound: String {
            String(localized: "settings.sound", defaultValue: "SOUND")
        }
        static var haptics: String {
            String(localized: "settings.haptics", defaultValue: "HAPTICS")
        }
        static var on: String {
            String(localized: "settings.on", defaultValue: "ON")
        }
        static var off: String {
            String(localized: "settings.off", defaultValue: "OFF")
        }
    }

    // MARK: - Level select

    enum LevelSelect {
        static var title: String {
            String(localized: "levelSelect.title", defaultValue: "SELECT LEVEL")
        }
        static func page(_ current: Int, of total: Int) -> String {
            String(localized: "levelSelect.page", defaultValue: "Page \(current) / \(total)")
        }
        static var reset: String {
            String(localized: "levelSelect.reset", defaultValue: "RESET")
        }
        static var resetTitle: String {
            String(localized: "levelSelect.resetTitle", defaultValue: "RESET PROGRESS?")
        }
        static var resetMessage: String {
            String(localized: "levelSelect.resetMessage", defaultValue: "All level progress will be lost.")
        }
        static var resetWarning: String {
            String(localized: "levelSelect.resetWarning", defaultValue: "This action cannot be undone!")
        }
    }

    // MARK: - In-game HUD and overlays

    enum HUD {
        static var score: String { Common.score }
        static var endless: String {
            String(localized: "hud.endless", defaultValue: "ENDLESS")
        }
        static func level(_ number: Int) -> String {
            String(localized: "hud.level", defaultValue: "LEVEL \(number)")
        }
        static func round(_ number: Int) -> String {
            String(localized: "hud.round", defaultValue: "ROUND \(number)")
        }
        static var warning: String {
            String(localized: "hud.warning", defaultValue: "! WARNING !")
        }
        static var extremeDanger: String {
            String(localized: "hud.extremeDanger", defaultValue: "EXTREME DANGER")
        }
        static var boss: String {
            String(localized: "hud.boss", defaultValue: "⚡ BOSS ⚡")
        }
        static var heat: String {
            String(localized: "hud.heat", defaultValue: "HEAT")
        }
        static var overheated: String {
            String(localized: "hud.overheated", defaultValue: "OVERHEATED!")
        }
    }

    // MARK: - Pause

    enum Pause {
        static var title: String {
            String(localized: "pause.title", defaultValue: "PAUSED")
        }
        static func level(_ number: Int) -> String {
            String(localized: "pause.level", defaultValue: "Level \(number)")
        }
        static var resume: String {
            String(localized: "pause.resume", defaultValue: "RESUME")
        }
        static var settings: String {
            String(localized: "pause.settings", defaultValue: "SETTINGS")
        }
    }

    // MARK: - Combo chain

    enum Combo {
        static func chain(_ length: Int) -> String {
            String(localized: "combo.chain", defaultValue: "CHAIN \(length)")
        }
        /// "3 TO x4" — how many more kills buy the next multiplier tier.
        static func toNextTier(remaining: Int, multiplier: Int) -> String {
            String(localized: "combo.toNextTier", defaultValue: "\(remaining) TO x\(multiplier)")
        }
        static var lost: String {
            String(localized: "combo.lost", defaultValue: "CHAIN LOST")
        }
    }

    // MARK: - Tutorial

    /// Level-one coaching, delivered over live gameplay.
    enum Tutorial {
        static var move: String {
            String(localized: "tutorial.move", defaultValue: "DRAG TO MOVE  •  GUNS FIRE THEMSELVES")
        }
        static var coins: String {
            String(localized: "tutorial.coins", defaultValue: "GRAB COINS — THEY SET YOUR STAR RATING")
        }
        static var chain: String {
            String(localized: "tutorial.chain", defaultValue: "KILL FAST TO CHAIN — CHAINS MULTIPLY SCORE")
        }
    }

    // MARK: - Power-up pickups

    /// The floating label that names a pickup as it is collected.
    enum PowerUp {
        static var extraLife: String {
            String(localized: "powerUp.extraLife", defaultValue: "+1 LIFE")
        }
        static var multiShot: String {
            String(localized: "powerUp.multiShot", defaultValue: "MULTI SHOT")
        }
        static var sideMissiles: String {
            String(localized: "powerUp.sideMissiles", defaultValue: "SIDE MISSILES")
        }
        static var shield: String {
            String(localized: "powerUp.shield", defaultValue: "SHIELD")
        }
        static var lightning: String {
            String(localized: "powerUp.lightning", defaultValue: "LIGHTNING")
        }
        static var rapidFire: String {
            String(localized: "powerUp.rapidFire", defaultValue: "RAPID FIRE")
        }
        static var magnet: String {
            String(localized: "powerUp.magnet", defaultValue: "MAGNET")
        }
        static var slowMotion: String {
            String(localized: "powerUp.slowMotion", defaultValue: "SLOW MOTION")
        }
        static var freezeBomb: String {
            String(localized: "powerUp.freezeBomb", defaultValue: "FREEZE BOMB")
        }
        static var homingMissiles: String {
            String(localized: "powerUp.homingMissiles", defaultValue: "HOMING MISSILES")
        }
        static var scoreDouble: String {
            String(localized: "powerUp.scoreDouble", defaultValue: "SCORE x2")
        }
        static var barrier: String {
            String(localized: "powerUp.barrier", defaultValue: "BARRIER")
        }
        static var nuke: String {
            String(localized: "powerUp.nuke", defaultValue: "NUKE")
        }
        static var livesMax: String {
            String(localized: "powerUp.livesMax", defaultValue: "LIVES MAX")
        }
        static var gunsMax: String {
            String(localized: "powerUp.gunsMax", defaultValue: "GUNS MAX")
        }
        static var missilesMax: String {
            String(localized: "powerUp.missilesMax", defaultValue: "MISSILES MAX")
        }
    }

    // MARK: - Level complete

    enum LevelComplete {
        static var title: String {
            String(localized: "levelComplete.title", defaultValue: "LEVEL COMPLETE")
        }
        static func newBest(improvement: Int) -> String {
            String(localized: "levelComplete.newBest", defaultValue: "NEW BEST  +\(improvement)")
        }
        static var personalBestSet: String {
            String(localized: "levelComplete.personalBestSet", defaultValue: "PERSONAL BEST SET")
        }
        static func bestChain(length: Int, multiplier: Int) -> String {
            String(localized: "levelComplete.bestChain", defaultValue: "BEST CHAIN  \(length)  ·  x\(multiplier)")
        }
        static var next: String {
            String(localized: "levelComplete.next", defaultValue: "NEXT")
        }
        static var `continue`: String {
            String(localized: "levelComplete.continue", defaultValue: "CONTINUE")
        }
    }

    // MARK: - Game over

    enum GameOver {
        static var title: String {
            String(localized: "gameOver.title", defaultValue: "LEVEL FAILED")
        }
        static func reachedRound(_ round: Int) -> String {
            String(localized: "gameOver.reachedRound", defaultValue: "REACHED ROUND \(round)")
        }
        static var newRecord: String {
            String(localized: "gameOver.newRecord", defaultValue: "NEW RECORD")
        }
    }

    // MARK: - Game completion

    enum Completion {
        static var title: String {
            String(localized: "completion.title", defaultValue: "🎉 VICTORY! 🎉")
        }
        static var congratulations: String {
            String(localized: "completion.congratulations", defaultValue: "Congratulations!")
        }
        static var success: String {
            String(localized: "completion.success", defaultValue: "You have completed all levels!\nYou are a master pilot!")
        }
        static var thanks: String {
            String(localized: "completion.thanks", defaultValue: "Thank you for playing!")
        }
        static var totalScore: String {
            String(localized: "completion.totalScore", defaultValue: "Total Score:")
        }
        static var playAgain: String {
            String(localized: "completion.playAgain", defaultValue: "PLAY AGAIN")
        }
    }

    // MARK: - Story crawls

    /// The opening and ending crawls.
    ///
    /// Each paragraph is its own key rather than one blob with embedded newlines:
    /// `StoryScene` lays the paragraphs out one at a time, measuring each label's
    /// wrapped height to place the next, and a translator working paragraph-by-paragraph
    /// cannot accidentally destroy that structure by reflowing a single long string.
    ///
    /// The empty strings that space the crawl out are not translated — they are layout,
    /// and `storyParagraphs(for:)` re-inserts them around the localized text.
    enum Story {
        static var skipHint: String {
            String(localized: "story.skipHint", defaultValue: "Tap anywhere to skip")
        }

        static var openingTitle: String {
            String(localized: "story.opening.title", defaultValue: "END OF AGES")
        }

        static var openingParagraphs: [String] {
            [
                String(localized: "story.opening.p1", defaultValue: "We stand at the very end of time..."),
                String(localized: "story.opening.p2", defaultValue: "The universe has reached its critical point. Stars are living their final moments, black holes have consumed most matter, and the very fabric of spacetime is beginning to collapse."),
                String(localized: "story.opening.p3", defaultValue: "Quantum mechanics, once strictly separated from the macroscopic world, now bleeds into reality. Dimensions overlap, time flows chaotically, and physical laws lose their meaning."),
                String(localized: "story.opening.p4", defaultValue: "You are the pilot of the experimental ship Singularity-7, civilization's last hope. Your mission is not to save this dying universe, that is no longer possible."),
                String(localized: "story.opening.p5", defaultValue: "Your mission is to escape."),
                String(localized: "story.opening.p6", defaultValue: "Gather enough quantum energy from collapsing regions of space, penetrate through dimensional rifts, and reach the epicenter of the collapse."),
                String(localized: "story.opening.p7", defaultValue: "There, in the very heart of the dying universe, you must activate protocol Big Bang Zero, ignite a new singularity, a new universe, a new beginning."),
                String(localized: "story.opening.p8", defaultValue: "The path will not be easy. Remnants of ancient civilizations, transformed into hostile quantum entities, guard the last fragments of energy. Cosmic anomalies will seek to consume you. Reality itself will resist."),
                String(localized: "story.opening.p9", defaultValue: "But there is no other way."),
                String(localized: "story.opening.p10", defaultValue: "Either you successfully penetrate into the new singularity..."),
                String(localized: "story.opening.p11", defaultValue: "...or you perish along with this universe.")
            ]
        }

        static var endingTitle: String {
            String(localized: "story.ending.title", defaultValue: "NEW BEGINNING")
        }

        static var endingParagraphs: [String] {
            [
                String(localized: "story.ending.p1", defaultValue: "You did it..."),
                String(localized: "story.ending.p2", defaultValue: "You flew through collapsing dimensions, overcame quantum entities of ancient civilizations, survived the collapse of spacetime itself."),
                String(localized: "story.ending.p3", defaultValue: "At the epicenter of the dying universe, where time stopped and reality lost its meaning, you activated protocol Big Bang Zero."),
                String(localized: "story.ending.p4", defaultValue: "Your ship Singularity-7 became the catalyst for new creation. The quantum energy you gathered forms the seed of a new universe."),
                String(localized: "story.ending.p5", defaultValue: "Around you forms a new singularity, an infinitesimal point of infinite density, from which space, time, matter and energy will be born."),
                String(localized: "story.ending.p6", defaultValue: "You see the first flashes of new stars being born from the dust of the old universe. You feel new dimensions forming around you, new physical laws, new possibilities."),
                String(localized: "story.ending.p7", defaultValue: "Your mission was successful. The old universe died, but its legacy will survive in the new creation."),
                String(localized: "story.ending.p8", defaultValue: "Perhaps someday, billions of years in the future, when this new universe grows and matures, someone will ask:"),
                String(localized: "story.ending.p9", defaultValue: "\"How did it all begin?\""),
                String(localized: "story.ending.p10", defaultValue: "And the answer will be hidden in the quantum foam of space, the story of a pilot who risked everything to give life a new chance."),
                // Not translated: a symbol, and the one line of the crawl that is the
                // same in every language.
                "∞",
                String(localized: "story.ending.p11", defaultValue: "Thank you for playing!"),
                String(localized: "story.ending.p12", defaultValue: "You saved not only the universe,"),
                String(localized: "story.ending.p13", defaultValue: "but existence itself.")
            ]
        }
    }
}
