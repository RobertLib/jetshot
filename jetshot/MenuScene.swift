//
//  MenuScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import SpriteKit

/// The front of the game, framed as the films are: the picture letterboxed, the ship
/// flying in it, the title set the way the opening film's last shot sets it, and the
/// choices underneath as lit HUD frames.
class MenuScene: SKScene {

    private var startButton: SKShapeNode!
    private var isInitialized = false
    /// START and ENDLESS leave this screen, once. See `FilmUI.Exit`.
    private let exit = FilmUI.Exit()
    private var safeAreaTop: CGFloat = 0
    private var safeAreaBottom: CGFloat = 0

    /// The running timecode in the frame's furniture, and when it started.
    private var timecodeLabel: SKLabelNode?
    private var timecodeStart: TimeInterval?

    /// Forgiveness added around each button's outline. Kept under half of `buttonGap`,
    /// the tightest button-to-button gap any of the menu's configurations produces, so
    /// two hit areas can never meet.
    private static let touchSlop: CGFloat = 6

    // Vertical rhythm for the stack under the title.
    //
    // Named, and the difference between them is the whole point: a caption sits close
    // to the button it describes and well clear of the unrelated one below it. The
    // record line used to be placed at a hand-picked y that gave it ~5pt of air above
    // and ~7pt below, between buttons that are themselves 16pt apart — so ENDLESS, the
    // record and SETTINGS read as one mashed block rather than a button with a caption.

    // Not private, so `MenuLayoutTests` can assert the spacing it actually gets rather
    // than a second copy of these numbers — the same reason `GameScene.activeEnemyCount`
    // is exposed.

    /// Between two buttons.
    static let buttonGap: CGFloat = 16

    /// From a button's bottom edge to its own caption.
    static let captionGap: CGFloat = 9

    /// From a caption to the next, unrelated button. Deliberately the largest of the
    /// three — it is what stops the caption from reading as SETTINGS' label.
    static let captionToButtonGap: CGFloat = 22

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground
        readSafeArea(from: view)
        buildScene(animated: true)
        isInitialized = true

        // `safeAreaInsets` can still read zero during didMove(to:); re-frame once the
        // view has been through a layout pass, so the bars swallow the Dynamic Island.
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self = self, let view = view, self.view != nil, !self.exit.isTaken else { return }
            let before = (self.safeAreaTop, self.safeAreaBottom)
            self.readSafeArea(from: view)
            if before != (self.safeAreaTop, self.safeAreaBottom) {
                self.removeAllChildren()
                self.buildScene(animated: false)
            }
        }

        SoundManager.shared.startBackgroundMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Not while leaving — see `LevelCompleteScene.didChangeSize(_:)`.
        guard isInitialized, !exit.isTaken else { return }
        removeAllChildren()
        buildScene(animated: false)
    }

    override func willMove(from view: SKView) {
        removeAllActions()
        removeAllChildren()
    }

    override func update(_ currentTime: TimeInterval) {
        guard let label = timecodeLabel else { return }
        let start = timecodeStart ?? currentTime
        timecodeStart = start
        // Film frames, 24 to the second — the films' own timecode.
        let frames = Int((currentTime - start) * 24)
        let text = String(format: "%02d:%02d:%02d", frames / 1440, (frames / 24) % 60, frames % 24)
        if label.attributedText?.string != text {
            FilmUI.set(label, text, font: UITheme.Typography.fontNumeric, size: label.fontSize,
                       color: UITheme.Colors.textSecondary.withAlphaComponent(0.7), tracking: 1.5)
        }
    }

    private func readSafeArea(from view: SKView) {
        safeAreaTop = GameConfiguration.safeAreaTop(in: view)
        safeAreaBottom = GameConfiguration.safeAreaBottom(in: view)
    }

    // MARK: - Layout

    private func buildScene(animated: Bool) {
        GameBackdrop.attachAmbient(to: self, look: .forLevel(1))
        NeonFX.attachGrade(to: self, zPosition: 5)

        let depths = FilmUI.Letterbox.depths(size: size, safeTop: safeAreaTop, safeBottom: safeAreaBottom)
        let frame = FilmUI.Letterbox(size: size, top: depths.top, bottom: depths.bottom, closing: animated)
        frame.zPosition = 40
        addChild(frame)

        // The furniture the films print over the picture: a running timecode, and the
        // campaign as a shot counter — the level the player is on, of fifty.
        let total = LevelManager.shared.totalLevels
        let current = (1...total).last(where: { LevelManager.shared.isLevelUnlocked($0) }) ?? 1
        let labels = frame.addFurniture(left: "00:00:00",
                                        right: String(format: "%02d / %02d", current, total),
                                        recording: true)
        timecodeLabel = labels.left
        timecodeStart = nil

        setupTitle(picture: frame.picture)
        setupHeroShip(picture: frame.picture)
        setupButtons()
        setupCredits(bottomDepth: depths.bottom)
    }

    /// How much larger everything is drawn on a wide screen; 1 on every phone. See
    /// `FilmUI.uiScale(for:)`.
    private var uiScale: CGFloat { FilmUI.uiScale(for: size) }

    /// Where the title's lettering is centred. The stack under it is measured from
    /// the same anchor, as it always has been, so its layout tests still hold.
    private var titleY: CGFloat { size.height / 2 + 84 * uiScale }

    private func setupTitle(picture: CGRect) {
        let centre = CGPoint(x: size.width / 2, y: titleY)

        // Light behind the lettering, and a line of it through the middle — the opening
        // film's title shot, held.
        let glow = NeonFX.radialGlow(radius: size.width * 0.75, color: StoryPalette.cyan)
        glow.position = centre
        glow.alpha = 0.16
        glow.zPosition = -6
        glow.name = "menuHorizon"
        addChild(glow)

        let line = FilmUI.tube(CGPoint(x: -size.width * 0.46, y: 0), CGPoint(x: size.width * 0.46, y: 0),
                               width: 1, color: StoryPalette.cyan)
        line.position = CGPoint(x: centre.x, y: centre.y - 3)
        line.alpha = 0.35
        line.zPosition = 9
        line.xScale = 0.01
        let draw = SKAction.scaleX(to: 1, duration: 1.0)
        draw.timingMode = .easeOut
        line.run(.sequence([.wait(forDuration: 0.25), draw]))
        addChild(line)

        // The game's name is the one word on screen that is never translated.
        let title = FilmUI.title("JETSHOT", size: 70 * uiScale, color: UITheme.Colors.primaryCyanLight,
                                 glow: StoryPalette.cyan, tracking: 12 * uiScale, maxWidth: size.width - 44,
                                 minimumSize: 40, bloom: 1.0)
        title.position = centre
        title.zPosition = 10
        title.name = "menuTitle"
        title.alpha = 0
        title.setScale(1.08)
        let settle = SKAction.scale(to: 1, duration: 1.4)
        settle.timingMode = .easeOut
        title.run(.group([.fadeIn(withDuration: 0.6), settle]))
        addChild(title)

        // The subtitle types itself in under the title, the way the films tag a shot.
        let subtitle = Cinematic.typewriter(L10n.Menu.subtitle, fontSize: 13 * uiScale, color: StoryPalette.cyan,
                                            tracking: 5 * uiScale, delay: 0.7, duration: 0.7,
                                            maxWidth: size.width - 48)
        subtitle.position = CGPoint(x: centre.x, y: centre.y - 50 * uiScale)
        subtitle.zPosition = 10
        addChild(subtitle)
    }

    /// The ship itself, flying above the title with the sky rushing past it.
    ///
    /// The real `Player` node, at twice the size and with its physics stripped, costs
    /// nothing to keep in sync with the in-game ship and says what the game is before
    /// anyone reads a word.
    private func setupHeroShip(picture: CGRect) {
        let streaks = StarfieldHelper.createSpeedStreaks(for: self)
        streaks.particleBirthRate = 9
        streaks.particleAlpha = 0.22
        streaks.zPosition = -8
        addChild(streaks)

        let ship = Player(sceneSize: size, safeAreaBottom: 0)
        ship.physicsBody = nil
        ship.childNode(withName: "collector")?.physicsBody = nil
        ship.name = "menuHeroShip"
        ship.setScale(2.0 * uiScale)
        ship.zPosition = 8

        // Centred in the picture between its top edge and the title, whatever the
        // device's proportions.
        let titleTop = titleY + 40 * uiScale
        ship.position = CGPoint(x: size.width / 2, y: (titleTop + picture.maxY) / 2 - 6)
        addChild(ship)

        let bob = SKAction.sequence([
            .moveBy(x: 0, y: 7, duration: 1.4),
            .moveBy(x: 0, y: -7, duration: 1.4)
        ])
        bob.timingMode = .easeInEaseOut
        ship.run(.repeatForever(bob))

        // A slow lazy weave, so it reads as flying rather than as a sticker.
        let weave = SKAction.sequence([
            .moveBy(x: 14, y: 0, duration: 2.6),
            .moveBy(x: -28, y: 0, duration: 5.2),
            .moveBy(x: 14, y: 0, duration: 2.6)
        ])
        weave.timingMode = .easeInEaseOut
        ship.run(.repeatForever(weave))
    }

    private func setupButtons() {
        let x = size.width / 2
        // Each button is built at its phone size and drawn at `uiScale`, so every
        // height and gap below is scaled with it.
        let scale = uiScale
        let startHeight: CGFloat = 54

        startButton = UITheme.createButton(
            text: L10n.Menu.start,
            color: StoryPalette.cyan,
            width: UITheme.Dimensions.buttonWidthLarge,
            name: "startButton",
            height: startHeight,
            primary: true
        )
        startButton.position = CGPoint(x: x, y: size.height / 2 - 62.5 * scale)
        startButton.setScale(scale)
        startButton.zPosition = 10
        addChild(startButton)

        // Endless, once the player has actually played something.
        //
        // Gated on level 1 rather than shown from a cold start: it is the mode with no
        // tutorial, no intro and no completion, and dropping a brand-new player into it
        // before they have flown the ship once is the worst first impression the game can
        // make. Clearing level 1 is a low enough bar that anyone who wants it gets it in
        // under two minutes.
        let settingsHeight: CGFloat = 42
        var settingsY = size.height / 2 - 132 * scale

        if LevelManager.shared.isLevelCompleted(1) {
            let endlessHeight: CGFloat = 46
            let endlessCenterY = startButton.position.y - (startHeight / 2 + Self.buttonGap + endlessHeight / 2) * scale
            let endlessButton = UITheme.createButton(
                text: L10n.Menu.endless,
                color: StoryPalette.gold,
                width: UITheme.Dimensions.buttonWidthLarge,
                name: "endlessButton",
                height: endlessHeight
            )
            endlessButton.position = CGPoint(x: x, y: endlessCenterY)
            endlessButton.setScale(scale)
            endlessButton.zPosition = 10
            addChild(endlessButton)

            // Everything below ENDLESS is measured down from its bottom edge rather
            // than placed at its own hand-picked y, which is what let the record line
            // and SETTINGS drift into it. See the gap constants at the top.
            var cursorY = endlessCenterY - endlessHeight * scale / 2

            // The record under the button is the whole pitch for the mode.
            let records = LevelManager.shared.getEndlessRecords()
            if records.bestScore > 0 {
                let best = FilmUI.mono(
                    L10n.Common.endlessRecord(score: records.bestScore, round: records.bestRound),
                    size: 11, color: StoryPalette.gold.withAlphaComponent(0.85), tracking: 1.2,
                    maxWidth: size.width - 40
                )
                best.setScale(scale)
                best.zPosition = 10
                // Named so the layout is assertable; nothing looks it up at runtime.
                best.name = "endlessRecord"

                // Measured, not assumed, so the spacing holds if the type here changes.
                let captionHeight = best.calculateAccumulatedFrame().height
                cursorY -= Self.captionGap * scale + captionHeight / 2
                best.position = CGPoint(x: x, y: cursorY)
                addChild(best)

                cursorY -= captionHeight / 2 + Self.captionToButtonGap * scale
            } else {
                // No record yet. SETTINGS closes the gap instead of holding the
                // caption's slot open.
                cursorY -= Self.buttonGap * scale
            }

            settingsY = cursorY - settingsHeight * scale / 2
        }

        // Settings, deliberately understated so it doesn't compete with START.
        let settingsButton = UITheme.createButton(
            text: L10n.Menu.settings,
            color: FilmUI.neutral,
            width: UITheme.Dimensions.buttonWidthSmall,
            name: "settingsButton",
            height: settingsHeight
        )
        settingsButton.position = CGPoint(x: x, y: settingsY)
        settingsButton.setScale(scale)
        settingsButton.zPosition = 10
        addChild(settingsButton)

        // The stack arrives a beat after the title, top to bottom.
        let stack = children.filter { ["startButton", "endlessButton", "endlessRecord", "settingsButton"].contains($0.name ?? "") }
            .sorted { $0.position.y > $1.position.y }
        for (index, node) in stack.enumerated() {
            node.alpha = 0
            node.run(.sequence([.wait(forDuration: 0.5 + Double(index) * 0.08),
                                .fadeIn(withDuration: 0.35)]))
        }
    }

    /// The credit sits in the bottom bar, under the picture, where the films put their
    /// subtitles.
    private func setupCredits(bottomDepth: CGFloat) {
        let credits = FilmUI.mono(L10n.Menu.credits, size: 10,
                                  color: UITheme.Colors.textSecondary.withAlphaComponent(0.5),
                                  tracking: 3, maxWidth: size.width - 40)
        credits.position = CGPoint(x: size.width / 2, y: max(safeAreaBottom + 10, bottomDepth / 2))
        credits.zPosition = 50
        addChild(credits)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Once START or ENDLESS has been chosen, the screen is on its way out and nothing
        // else on it answers.
        guard !exit.isTaken, let touch = touches.first else { return }
        let location = touch.location(in: self)

        // The settings panel is modal: while it is up it gets first refusal on every
        // tap, so nothing behind it can be triggered through the scrim.
        if let settings = childNode(withName: SettingsOverlay.nodeName) as? SettingsOverlay {
            settings.handleTap(at: location)
            return
        }

        if isTap(location, on: "startButton") {
            exit.take()
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)
            startGame()
            return
        }

        if isTap(location, on: "endlessButton") {
            exit.take()
            HapticManager.shared.lightTap()
            // ENDLESS presents on this same touch, with no press animation to give a
            // click queued on this scene a frame to start in — the transition pauses it
            // first. See `SoundManager.playSceneExitClickSound()`.
            SoundManager.shared.playSceneExitClickSound()
            startEndlessRun()
            return
        }

        if isTap(location, on: "settingsButton") {
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)
            showSettings()
        }
    }

    /// Hit-tests a menu button against its own outline, so nothing soft and glowing
    /// around it can widen what counts as a tap on it.
    private func isTap(_ location: CGPoint, on buttonName: String) -> Bool {
        guard let button = childNode(withName: buttonName) as? SKShapeNode,
              let bounds = button.path?.boundingBoxOfPath else { return false }
        // Converting into the button's space keeps any scale on it honest.
        let local = convert(location, to: button)
        return bounds.insetBy(dx: -Self.touchSlop, dy: -Self.touchSlop).contains(local)
    }

    private func showSettings() {
        guard childNode(withName: SettingsOverlay.nodeName) == nil else { return }
        addChild(SettingsOverlay(sceneSize: size))
    }

    private func startGame() {
        startButton.run(UITheme.createButtonPressAnimation { [weak self] in
            self?.transitionToGame()
        })
    }

    /// Straight into a run — endless has no level to pick, which is most of its appeal
    /// as the "one more go" mode.
    private func startEndlessRun() {
        exit.present(from: self) { size in
            let gameScene = GameScene(size: size)
            gameScene.isEndless = true
            return gameScene
        }
    }

    private func transitionToGame() {
        exit.present(from: self) { LevelSelectScene(size: $0) }
    }
}
