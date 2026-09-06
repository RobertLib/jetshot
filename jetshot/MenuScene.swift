//
//  MenuScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import SpriteKit

class MenuScene: SKScene {

    private var startButton: SKShapeNode!
    private var isInitialized = false

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

        StarfieldHelper.addDepthLayers(to: self)
        addChild(StarfieldHelper.createStarfield(for: self))
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        NeonFX.attachGrade(to: self, zPosition: 5)
        setupTitle()
        setupStartButton()
        isInitialized = true

        // Start background music
        SoundManager.shared.startBackgroundMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized else { return }

        // Remove and recreate all elements
        removeAllChildren()

        StarfieldHelper.addDepthLayers(to: self)
        addChild(StarfieldHelper.createStarfield(for: self))
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        NeonFX.attachGrade(to: self, zPosition: 5)
        setupTitle()
        setupStartButton()
    }

    override func willMove(from view: SKView) {
        // Clean up all resources before scene is removed
        removeAllActions()
        removeAllChildren()
    }

    private func setupTitle() {
        // Warm light rising off the horizon, so the title has something to sit
        // against instead of floating in flat black.
        let horizon = NeonFX.radialGlow(
            radius: size.width * 0.95,
            color: UIColor(red: 0.10, green: 0.52, blue: 0.85, alpha: 1.0)
        )
        horizon.position = CGPoint(x: size.width / 2, y: size.height * 0.52)
        horizon.alpha = 0.32
        horizon.zPosition = -6
        horizon.name = "menuHorizon"
        addChild(horizon)

        // Main title. Local, not a stored property: nothing outside this method reads
        // it, and the last property that shadowed a node here (`startButtonLabel`) was
        // bound to the wrong node for exactly as long as nobody read it back.
        let titleLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        titleLabel.text = "JETSHOT"
        titleLabel.fontSize = UITheme.Typography.sizeHuge + 12
        titleLabel.fontColor = UITheme.Colors.primaryCyanLight
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 70)
        titleLabel.zPosition = 10
        NeonFX.addTextBloom(to: titleLabel, color: UITheme.Colors.primaryCyan, blur: 16, intensity: 1.0)

        // Breathe the glow, not the text: pulsing the label's own alpha made the
        // title itself dim, which reads as a flicker rather than as energy.
        if let bloom = titleLabel.childNode(withName: "textBloom") {
            bloom.run(SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.5, duration: UITheme.Animations.durationGlowPulse),
                    SKAction.fadeAlpha(to: 1.0, duration: UITheme.Animations.durationGlowPulse)
                ])
            ))
        }

        addChild(titleLabel)

        // Hairline rule under the title, a cheap way to make the lockup look set
        // rather than stacked.
        let rule = SKShapeNode(rectOf: CGSize(width: 168, height: 1.5), cornerRadius: 0.75)
        rule.fillColor = UITheme.Colors.primaryCyan.withAlphaComponent(0.55)
        rule.strokeColor = .clear
        rule.blendMode = .add
        rule.position = CGPoint(x: size.width / 2, y: size.height / 2 + 44)
        rule.zPosition = 10
        addChild(rule)

        // Subtitle
        let subtitleLabel = SKLabelNode()
        subtitleLabel.attributedText = NeonFX.trackedText(
            L10n.Menu.subtitle,
            font: UITheme.Typography.fontRegular,
            size: UITheme.Typography.sizeSmall,
            color: UITheme.Colors.textSecondary,
            tracking: 6
        )
        subtitleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 14)
        subtitleLabel.zPosition = 10
        addChild(subtitleLabel)

        // Credits - Creator info
        let creditsLabel = SKLabelNode()
        creditsLabel.attributedText = NeonFX.trackedText(
            L10n.Menu.credits,
            font: UITheme.Typography.fontRegular,
            size: UITheme.Typography.sizeTiny,
            color: UITheme.Colors.textSecondary.withAlphaComponent(0.5),
            tracking: 3
        )
        creditsLabel.position = CGPoint(x: size.width / 2, y: 30)
        creditsLabel.zPosition = 10
        addChild(creditsLabel)
    }

    private func setupStartButton() {
        startButton = UITheme.createButton(
            text: L10n.Menu.start,
            color: UITheme.Colors.primaryCyan,
            width: UITheme.Dimensions.buttonWidthLarge,
            name: "startButton"
        )
        startButton.position = CGPoint(x: size.width / 2, y: size.height / 2 - 62.5)
        startButton.zPosition = 10

        // Add glow effect
        GlowHelper.addEnhancedGlow(to: startButton, color: UITheme.Colors.primaryCyan, intensity: 0.3)

        // Pulse animation
        startButton.run(UITheme.createButtonPulseAnimation())

        addChild(startButton)

        // START's label is deliberately not held onto. The line that used to do it was
        // `startButton.childNode(withName: "//SKLabelNode")`, and `//` makes SpriteKit
        // search from the *root* of the tree rather than from `startButton` — so it
        // bound the property to the title label "JETSHOT", which `setupTitle()` adds
        // first. Nothing read it back, so the mistake was invisible. If a future caller
        // does need the label, ask the button for it without the prefix:
        // `startButton.childNode(withName: "SKLabelNode") as? SKLabelNode`.

        // Endless, once the player has actually played something.
        //
        // Gated on level 1 rather than shown from a cold start: it is the mode with no
        // tutorial, no intro and no completion, and dropping a brand-new player into it
        // before they have flown the ship once is the worst first impression the game can
        // make. Clearing level 1 is a low enough bar that anyone who wants it gets it in
        // under two minutes.
        let settingsHeight: CGFloat = 42
        var settingsY = size.height / 2 - 130

        if LevelManager.shared.isLevelCompleted(1) {
            let endlessHeight: CGFloat = 44
            let endlessCenterY = size.height / 2 - 125
            let endlessButton = UITheme.createButton(
                text: L10n.Menu.endless,
                color: UITheme.Colors.primaryGold,
                width: UITheme.Dimensions.buttonWidthLarge,
                name: "endlessButton",
                height: endlessHeight
            )
            endlessButton.position = CGPoint(x: size.width / 2, y: endlessCenterY)
            endlessButton.zPosition = 10
            addChild(endlessButton)

            // Everything below ENDLESS is measured down from its bottom edge rather
            // than placed at its own hand-picked y, which is what let the record line
            // and SETTINGS drift into it. See the gap constants at the top.
            var cursorY = endlessCenterY - endlessHeight / 2

            // The record under the button is the whole pitch for the mode.
            let records = LevelManager.shared.getEndlessRecords()
            if records.bestScore > 0 {
                let best = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
                best.text = L10n.Common.endlessRecord(score: records.bestScore, round: records.bestRound)
                best.fontSize = 13
                best.fontColor = UITheme.Colors.textSecondary
                best.horizontalAlignmentMode = .center
                best.verticalAlignmentMode = .center
                best.zPosition = 10
                // Named so the layout is assertable; nothing looks it up at runtime.
                best.name = "endlessRecord"

                // Measured, not assumed, so the spacing holds if the font or size here
                // ever changes. `verticalAlignmentMode = .center` puts the frame
                // symmetrically around the position, hence the half-heights.
                let captionHeight = best.calculateAccumulatedFrame().height
                cursorY -= Self.captionGap + captionHeight / 2
                best.position = CGPoint(x: size.width / 2, y: cursorY)
                addChild(best)

                cursorY -= captionHeight / 2 + Self.captionToButtonGap
            } else {
                // No record yet. SETTINGS closes the gap instead of holding the
                // caption's slot open, which a fixed y used to do.
                cursorY -= Self.buttonGap
            }

            settingsY = cursorY - settingsHeight / 2
        }

        // Settings, deliberately understated so it doesn't compete with START.
        let settingsButton = UITheme.createButton(
            text: L10n.Menu.settings,
            color: UITheme.Colors.buttonMenu,
            width: UITheme.Dimensions.buttonWidthSmall,
            name: "settingsButton",
            height: settingsHeight
        )
        settingsButton.position = CGPoint(x: size.width / 2, y: settingsY)
        settingsButton.zPosition = 10
        addChild(settingsButton)
    }



    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // The settings panel is modal: while it is up it gets first refusal on every
        // tap, so nothing behind it can be triggered through the scrim.
        if let settings = childNode(withName: SettingsOverlay.nodeName) as? SettingsOverlay {
            let topName = nodes(at: location).first(where: { $0.name != nil })?.name
            settings.handleTap(named: topName)
            return
        }

        if isTap(location, on: "startButton") {
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)
            startGame()
            return
        }

        if isTap(location, on: "endlessButton") {
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)
            startEndlessRun()
            return
        }

        if isTap(location, on: "settingsButton") {
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)
            showSettings()
        }
    }

    /// Hit-tests a menu button against its own outline.
    ///
    /// `nodes(at:)` reports a node whenever the point falls inside *any* of its
    /// descendants, and START's glow halo is a child sprite padded out for the
    /// bloom's Gaussian tail — roughly three times the button's own height, far
    /// enough down to cover SETTINGS. Name-matching that list handed every
    /// SETTINGS tap to START, so measure the button's path instead and leave the
    /// decoration out of the hit area.
    private func isTap(_ location: CGPoint, on buttonName: String) -> Bool {
        guard let button = childNode(withName: buttonName) as? SKShapeNode,
              let bounds = button.path?.boundingBoxOfPath else { return false }
        // Converting into the button's space keeps the START pulse's scale honest.
        let local = convert(location, to: button)
        return bounds.insetBy(dx: -Self.touchSlop, dy: -Self.touchSlop).contains(local)
    }

    private func showSettings() {
        guard childNode(withName: SettingsOverlay.nodeName) == nil else { return }
        addChild(SettingsOverlay(sceneSize: size))
    }

    private func startGame() {
        // Button press animation
        startButton.run(UITheme.createButtonPressAnimation { [weak self] in
            self?.transitionToGame()
        })
    }

    /// Straight into a run — endless has no level to pick, which is most of its appeal
    /// as the "one more go" mode.
    private func startEndlessRun() {
        guard let view = view else { return }

        let gameScene = GameScene(size: view.bounds.size)
        gameScene.scaleMode = scaleMode
        gameScene.isEndless = true

        view.presentScene(gameScene, transition: SKTransition.fade(withDuration: 0.5))
    }

    private func transitionToGame() {
        guard let view = view else { return }
        // Go to level select screen instead of directly to game
        let levelSelectScene = LevelSelectScene(size: view.bounds.size)
        levelSelectScene.scaleMode = scaleMode

        // Transition with animation
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(levelSelectScene, transition: transition)
    }

}

