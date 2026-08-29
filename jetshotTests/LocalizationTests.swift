//
//  LocalizationTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Guards the two ways a translation silently breaks in a shipped build: a key that
/// resolves to nothing, and a translated format string whose specifiers no longer match
/// the arguments the call site pushes.
///
/// `@MainActor` because the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, which puts `L10n` and `UITheme` on the main actor.
@MainActor
final class LocalizationTests: XCTestCase {

    /// The bundle the strings actually ship in.
    ///
    /// `Bundle(for: LocalizationTests.self)` would be the *test* bundle, which contains
    /// no translations at all; the catalog is compiled into the app. Asking for a class
    /// from the app module is what crosses that boundary.
    private static let appBundle = Bundle(for: MenuScene.self)

    /// Reading `cs.lproj` directly rather than through `String(localized:)`.
    ///
    /// The test host runs in whatever language the machine is set to, so the ordinary
    /// lookup would return English here and prove nothing about the Czech table. Loading
    /// the language's bundle by path is what lets these assertions run on an English
    /// machine.
    private func bundle(forLanguage language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Self.appBundle.path(forResource: language, ofType: "lproj"),
            "\(language).lproj is missing from the app bundle — those translations did not ship"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    private func czechBundle() throws -> Bundle { try bundle(forLanguage: "cs") }
    private func englishBundle() throws -> Bundle { try bundle(forLanguage: "en") }

    /// Every key the game asks for, paired with the arguments its call site supplies.
    ///
    /// Listed by hand rather than reflected out of `L10n`: an enum of static properties
    /// has nothing to enumerate at runtime, and the point of the list is to fail when
    /// someone adds an accessor and forgets the catalog entry.
    private static let keys: [String] = [
        "common.menu", "common.levels", "common.retry", "common.back", "common.score",
        "common.yes", "common.no", "common.endlessRecord", "common.best",
        "menu.subtitle", "menu.credits", "menu.start", "menu.endless", "menu.settings",
        "settings.title", "settings.close", "settings.music", "settings.sound",
        "settings.haptics", "settings.on", "settings.off",
        "levelSelect.title", "levelSelect.page", "levelSelect.reset", "levelSelect.resetTitle",
        "levelSelect.resetMessage", "levelSelect.resetWarning",
        "hud.endless", "hud.level", "hud.round", "hud.warning", "hud.extremeDanger",
        "hud.boss", "hud.heat", "hud.overheated",
        "pause.title", "pause.level", "pause.resume", "pause.settings",
        "combo.chain", "combo.toNextTier", "combo.lost",
        "tutorial.move", "tutorial.coins", "tutorial.chain",
        "powerUp.extraLife", "powerUp.multiShot", "powerUp.sideMissiles", "powerUp.shield",
        "powerUp.lightning", "powerUp.rapidFire", "powerUp.magnet", "powerUp.slowMotion",
        "powerUp.freezeBomb", "powerUp.homingMissiles", "powerUp.scoreDouble",
        "powerUp.barrier", "powerUp.nuke", "powerUp.livesMax", "powerUp.gunsMax",
        "powerUp.missilesMax",
        "levelComplete.title", "levelComplete.newBest", "levelComplete.personalBestSet",
        "levelComplete.bestChain", "levelComplete.next", "levelComplete.continue",
        "gameOver.title", "gameOver.reachedRound", "gameOver.newRecord",
        "completion.title", "completion.congratulations", "completion.success",
        "completion.thanks", "completion.totalScore", "completion.playAgain",
        "story.skipHint",
        "story.opening.title",
        "story.opening.p1", "story.opening.p2", "story.opening.p3", "story.opening.p4",
        "story.opening.p5", "story.opening.p6", "story.opening.p7", "story.opening.p8",
        "story.opening.p9", "story.opening.p10", "story.opening.p11",
        "story.ending.title",
        "story.ending.p1", "story.ending.p2", "story.ending.p3", "story.ending.p4",
        "story.ending.p5", "story.ending.p6", "story.ending.p7", "story.ending.p8",
        "story.ending.p9", "story.ending.p10", "story.ending.p11", "story.ending.p12",
        "story.ending.p13"
    ]

    /// A missing key makes `localizedString` hand back the key itself, which on screen is
    /// the raw "levelSelect.resetWarning" rather than any sentence.
    func testEveryKeyIsTranslatedIntoCzech() throws {
        let bundle = try czechBundle()
        for key in Self.keys {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(value, key, "no Czech translation for \(key)")
            XCTAssertFalse(value.isEmpty, "empty Czech translation for \(key)")
        }
    }

    func testEveryKeyExistsInEnglish() throws {
        let bundle = try englishBundle()
        for key in Self.keys {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(value, key, "no English source string for \(key)")
        }
    }

    /// The failure this catches is not a typo but a crash.
    ///
    /// `String(localized:)` formats the *translated* string with the arguments the call
    /// site pushed. A Czech string that dropped one of its two `%lld` — easy to do, since
    /// Czech word order moves them around — leaves `String(format:)` reading an argument
    /// that was never supplied.
    func testFormatSpecifiersSurviveTranslation() throws {
        let czech = try czechBundle()
        let english = try englishBundle()

        for key in Self.keys {
            let source = english.localizedString(forKey: key, value: nil, table: nil)
            let translated = czech.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertEqual(
                Self.specifiers(in: source),
                Self.specifiers(in: translated),
                "format specifiers differ between en and cs for \(key)"
            )
        }
    }

    private static func specifiers(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:lld|ld|d|@|f)")
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    // MARK: - Layout

    /// Every Czech button label, against the width it is actually drawn at.
    ///
    /// This is the assertion that protects the shipping layout: button widths were all
    /// chosen against English copy, and Czech is the longer language everywhere —
    /// "NASTAVENÍ" against a 125pt SETTINGS button, "NEKONEČNÁ HRA" against a 200pt
    /// ENDLESS one. Both halves matter. Overflowing the stroke is the obvious failure;
    /// hitting `fitLabel`'s 11pt floor is the quieter one, because that is the point at
    /// which the label stops shrinking and starts overflowing anyway.
    func testEveryCzechButtonLabelFitsItsButton() throws {
        let czech = try czechBundle()

        // Paired with the width at each `UITheme.createButton` call site.
        let buttons: [(key: String, width: CGFloat)] = [
            ("menu.start", UITheme.Dimensions.buttonWidthLarge),
            ("menu.endless", UITheme.Dimensions.buttonWidthLarge),
            ("menu.settings", UITheme.Dimensions.buttonWidthSmall),
            ("common.levels", UITheme.Dimensions.buttonWidthSmall),
            ("common.menu", UITheme.Dimensions.buttonWidthSmall),
            ("common.retry", UITheme.Dimensions.buttonWidthXLarge),
            ("levelComplete.next", UITheme.Dimensions.buttonWidthXLarge),
            ("levelComplete.continue", UITheme.Dimensions.buttonWidthXLarge),
            ("completion.playAgain", UITheme.Dimensions.buttonWidthXLarge),
            ("settings.close", 160),
            ("common.back", 140),
            ("levelSelect.reset", 140),
            ("common.yes", 120),
            ("common.no", 120)
        ]

        for (key, width) in buttons {
            let text = czech.localizedString(forKey: key, value: nil, table: nil)
            let button = UITheme.createButton(text: text, color: .white, width: width, name: key)
            let label = try XCTUnwrap(button.children.compactMap { $0 as? SKLabelNode }.first)

            // The 1pt slack absorbs the rounding in SpriteKit's glyph measurement.
            XCTAssertLessThanOrEqual(
                label.frame.width, width - 20 + 1,
                "\"\(text)\" overflows its \(width)pt button"
            )
            XCTAssertGreaterThan(
                label.fontSize, 11,
                "\"\(text)\" only fits its \(width)pt button by hitting the legibility floor"
            )
        }
    }

    /// The floor is a deliberate limit, not a bug: past it `fitLabel` stops shrinking and
    /// lets the text overflow rather than rendering something nobody can read. Pinned
    /// here so a future change to `minimumFontSize` is a decision rather than a surprise.
    func testFitLabelStopsAtTheLegibilityFloor() {
        let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        label.text = "NEKONEČNÁ HRA A JEŠTĚ NĚCO NAVÍC"
        label.fontSize = 20

        UITheme.fitLabel(label, toWidth: 40)

        XCTAssertEqual(label.fontSize, 11, "should have clamped rather than shrunk further")
    }

    func testShortLabelsKeepTheirPointSize() {
        let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        label.text = "OK"
        label.fontSize = 20

        UITheme.fitLabel(label, toWidth: 200)

        XCTAssertEqual(label.fontSize, 20, "a label that already fits must not be touched")
    }

    /// `fitLabel` shrinks but never grows: a button whose text fits keeps the size the
    /// designer chose, so English layout is unchanged by the localization work.
    func testFitLabelNeverEnlarges() {
        for width in [CGFloat(40), 100, 300, 1000] {
            let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
            label.text = "SETTINGS"
            label.fontSize = 20
            UITheme.fitLabel(label, toWidth: width)
            XCTAssertLessThanOrEqual(label.fontSize, 20)
        }
    }

    // MARK: - Content

    /// The crawl is laid out one paragraph at a time with a blank label between beats.
    /// `StoryScene.spaced(_:)` rebuilds that rhythm from the translated paragraphs, so
    /// the gaps cannot be lost in translation.
    func testStoryParagraphsAreSeparatedByBlankLines() {
        let opening = L10n.Story.openingParagraphs
        XCTAssertFalse(opening.isEmpty)
        XCTAssertFalse(opening.contains(where: \.isEmpty), "the catalog should hold copy, not layout")

        let ending = L10n.Story.endingParagraphs
        XCTAssertFalse(ending.isEmpty)
        XCTAssertTrue(ending.contains("∞"), "the untranslated symbol beat is missing")
    }
}
