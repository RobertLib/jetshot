//
//  GameCompletionScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 27.10.2025.
//

import SpriteKit

class GameCompletionScene: SKScene {

    /// Shared vertical rhythm for the results panels. See `UITheme.PanelRhythm`.
    private typealias Rhythm = UITheme.PanelRhythm

    /// How far the figure block rises during its entrance. It starts this far below
    /// its laid-out position and ends exactly on it.
    private static let figuresRise: CGFloat = 10

    private let totalScore: Int
    private var isInitialized = false

    init(size: CGSize, totalScore: Int) {
        self.totalScore = totalScore
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The victory screen, shown once the ending crawl has played.
    ///
    /// `didMove(to:)` used to immediately present `StoryScene(type: .ending)` and return,
    /// which left this entire scene unreachable: `setupUI()` is only called from
    /// `didChangeSize`, and that is gated on `isInitialized`, which nothing ever set.
    /// So the trophy, the total score and all three buttons never rendered, and beating
    /// level 50 dropped the player from the crawl straight back to the level select.
    /// The crawl now runs *before* this scene — see `LevelCompleteScene` and
    /// `StoryScene`'s `.ending` case — and this is the terminal screen.
    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground
        buildScene()
        isInitialized = true

        SoundManager.shared.startBackgroundMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized else { return }

        // Remove and recreate all elements
        removeAllChildren()
        buildScene()
    }

    private func buildScene() {
        StarfieldHelper.addDepthLayers(to: self)
        addChild(StarfieldHelper.createStarfield(for: self))
        NeonFX.attachGrade(to: self, zPosition: -5)
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        setupUI()
    }

    override func willMove(from view: SKView) {
        // Clean up all resources before scene is removed
        removeAllActions()
        removeAllChildren()
    }

    private func setupUI() {
        // Epic celebration particles
        addEpicCelebrationParticles()

        // Main panel
        let panelWidth: CGFloat = min(size.width - 60, UITheme.Dimensions.panelWidthMax)

        // Measured before the panel exists, so the panel is sized to its content — see
        // `UITheme.PanelStack`. The fixed 520 this replaces was picked against the
        // English copy, and the two body blocks below wrap to a different number of
        // lines in every other language.
        let victoryTitle = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        victoryTitle.text = L10n.Completion.title
        victoryTitle.fontSize = UITheme.Typography.sizeLarge
        victoryTitle.fontColor = UITheme.Colors.primaryGold
        victoryTitle.horizontalAlignmentMode = .center
        let titleHeight = UITheme.capBandHeight(of: victoryTitle)

        let congratsText = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        congratsText.text = L10n.Completion.congratulations
        congratsText.fontSize = UITheme.Typography.sizeMedium
        congratsText.fontColor = UITheme.Colors.textPrimary
        congratsText.horizontalAlignmentMode = .center
        let congratsHeight = UITheme.capBandHeight(of: congratsText)

        let successText = createMultilineText(
            text: L10n.Completion.success,
            fontSize: UITheme.Typography.sizeRegular
        )
        let thanksText = createMultilineText(
            text: L10n.Completion.thanks,
            fontSize: UITheme.Typography.sizeRegular
        )
        let figures = createScoreDisplay()
        let buttonHeight = UITheme.Dimensions.buttonHeight

        var stack = UITheme.PanelStack()
        stack.add(gapAbove: Rhythm.edge, height: titleHeight)
        stack.add(gapAbove: Rhythm.emblemToTitle, height: congratsHeight)
        stack.add(gapAbove: Rhythm.aroundFigures, height: successText.height)
        stack.add(gapAbove: Rhythm.figureLine, height: thanksText.height)
        stack.add(gapAbove: Rhythm.aroundFigures, height: figures.height)
        stack.add(gapAbove: Rhythm.aroundFigures, height: buttonHeight)
        stack.add(gapAbove: Rhythm.buttonRow, height: buttonHeight)

        let panelHeight = stack.height
        let panel = UITheme.createPanel(
            width: panelWidth,
            height: panelHeight,
            borderColor: UITheme.Colors.primaryGold
        )
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.alpha = 0

        // Add outer golden glow effect
        if let glowPanel = panel.copy() as? SKShapeNode {
            glowPanel.fillColor = .clear
            glowPanel.strokeColor = UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.8)
            glowPanel.lineWidth = UITheme.Dimensions.lineWidthGlowStrong
            glowPanel.setScale(1.03)
            glowPanel.alpha = 0
            addChild(glowPanel)

            // Pulse animation for glow
            glowPanel.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.5),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationMedium),
                SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.5, duration: UITheme.Animations.durationGlowPulse),
                    SKAction.fadeAlpha(to: 1.0, duration: UITheme.Animations.durationGlowPulse)
                ]))
            ]))
        }

        addChild(panel)

        // Animate panel entrance
        panel.run(SKAction.sequence([
            SKAction.wait(forDuration: UITheme.Animations.durationQuick),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationMedium),
                SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationMedium)
            ])
        ]))
        panel.setScale(0.8)

        // Placement pass, walking the same rows back down from the panel's top edge.
        stack.start(panelHeight: panelHeight)

        // "VICTORY!" title
        UITheme.centerOnCapBand(
            victoryTitle,
            centerY: stack.next(gapAbove: Rhythm.edge, height: titleHeight)
        )
        victoryTitle.alpha = 0
        panel.addChild(victoryTitle)

        // Animated title entrance with bounce
        victoryTitle.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.6),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.sequence([
                    SKAction.scale(to: 1.4, duration: UITheme.Animations.durationQuick),
                    SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationQuick)
                ])
            ])
        ]))

        // Congratulations message
        UITheme.centerOnCapBand(
            congratsText,
            centerY: stack.next(gapAbove: Rhythm.emblemToTitle, height: congratsHeight)
        )
        congratsText.alpha = 0
        panel.addChild(congratsText)

        congratsText.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        // Success message
        successText.node.position = CGPoint(
            x: 0,
            y: stack.next(gapAbove: Rhythm.aroundFigures, height: successText.height)
        )
        successText.node.alpha = 0
        panel.addChild(successText.node)

        successText.node.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.3),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        // Thank you message
        thanksText.node.position = CGPoint(
            x: 0,
            y: stack.next(gapAbove: Rhythm.figureLine, height: thanksText.height)
        )
        thanksText.node.alpha = 0
        panel.addChild(thanksText.node)

        thanksText.node.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.6),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        // Final score display
        let scoreContainer = figures.node
        scoreContainer.position = CGPoint(
            x: 0,
            y: stack.next(gapAbove: Rhythm.aroundFigures, height: figures.height)
        )
        // The entrance rises *into* the slot rather than out of it. `moveBy` is
        // relative and permanent, so running it from the laid-out position left the
        // block sitting 10pt above where the stack put it for the rest of the scene's
        // life — which is what tipped the figures off centre between the title and the
        // button. Starting the same 10pt low makes the animation land on the layout.
        scoreContainer.position.y -= Self.figuresRise
        scoreContainer.alpha = 0
        panel.addChild(scoreContainer)

        scoreContainer.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.9),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.moveBy(x: 0, y: Self.figuresRise, duration: UITheme.Animations.durationNormal)
            ])
        ]))

        // Buttons
        setupButtons(
            on: panel,
            primaryY: stack.next(gapAbove: Rhythm.aroundFigures, height: buttonHeight),
            secondaryY: stack.next(gapAbove: Rhythm.buttonRow, height: buttonHeight)
        )
    }

    /// A block of body copy, one label per line, centred on the returned node's origin.
    ///
    /// The caller no longer passes a `y`: the block reports its own height and the panel
    /// stack decides where it goes. Line pitch comes from the rhythm rather than from
    /// `fontSize + 8`, so a block of copy breathes the same as every other stack in the
    /// results panels.
    private func createMultilineText(text: String, fontSize: CGFloat) -> (node: SKNode, height: CGFloat) {
        let container = SKNode()

        let rows = text.components(separatedBy: "\n").enumerated().map { index, line -> (label: SKLabelNode, gapAbove: CGFloat) in
            let label = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
            label.text = line
            label.fontSize = fontSize
            label.fontColor = UITheme.Colors.textSecondary
            label.horizontalAlignmentMode = .center
            return (label, index == 0 ? 0 : Rhythm.bodyLine)
        }

        let height = UITheme.stackLabels(rows, in: container)
        return (container, height)
    }

    /// The caption and the total, as one tight pair. See `UITheme.PanelRhythm`.
    private func createScoreDisplay() -> (node: SKNode, height: CGFloat) {
        let container = SKNode()

        // "Total Score:" label
        let scoreLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        scoreLabel.text = L10n.Completion.totalScore
        scoreLabel.fontSize = UITheme.Typography.sizeRegular
        scoreLabel.fontColor = UITheme.Colors.textSecondary
        scoreLabel.horizontalAlignmentMode = .center

        // Score value
        let scoreValue = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        scoreValue.text = "\(totalScore)"
        scoreValue.fontSize = UITheme.Typography.sizeLarge
        scoreValue.fontColor = UITheme.Colors.primaryGoldLight
        scoreValue.horizontalAlignmentMode = .center

        // Named so `ResultsPanelCentringTests` can find the block it is asserting on;
        // nothing looks it up at runtime. Structural matching would not do on this
        // screen — the two body-copy blocks above are label-only containers too.
        container.name = "figureBlock"

        let height = UITheme.stackLabels([
            (scoreLabel, 0),
            (scoreValue, Rhythm.captionToValue)
        ], in: container)
        return (container, height)
    }

    private func setupButtons(on panel: SKShapeNode, primaryY: CGFloat, secondaryY: CGFloat) {
        let buttonY = primaryY

        // Play Again button (restart from level 1)
        let playAgainButton = UITheme.createButton(
            text: L10n.Completion.playAgain,
            color: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0),
            width: UITheme.Dimensions.buttonWidthXLarge,
            name: "playAgainButton"
        )
        playAgainButton.position = CGPoint(x: 0, y: buttonY)
        playAgainButton.alpha = 0
        panel.addChild(playAgainButton)

        playAgainButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.2),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        // Add subtle pulse to play again button
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: UITheme.Animations.durationButtonPulse),
            SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationButtonPulse)
        ])
        playAgainButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.5),
            SKAction.repeatForever(pulse)
        ]))

        // Secondary buttons container
        let secondaryButtonY = secondaryY

        let levelsButton = UITheme.createButton(
            text: L10n.Common.levels,
            color: UITheme.Colors.buttonLevels,
            width: UITheme.Dimensions.buttonWidthSmall,
            name: "levelsButton"
        )
        levelsButton.position = CGPoint(x: -67, y: secondaryButtonY)
        levelsButton.alpha = 0
        panel.addChild(levelsButton)

        let menuButton = UITheme.createButton(
            text: L10n.Common.menu,
            color: UITheme.Colors.buttonMenu,
            width: UITheme.Dimensions.buttonWidthSmall,
            name: "menuButton"
        )
        menuButton.position = CGPoint(x: 67, y: secondaryButtonY)
        menuButton.alpha = 0
        panel.addChild(menuButton)

        levelsButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.3),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        menuButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.4),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        if let nodeName = touchedNode.name ?? touchedNode.parent?.name {
            switch nodeName {
            case "playAgainButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handlePlayAgainButton()
            case "levelsButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleLevelsButton()
            case "menuButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleMenuButton()
            default:
                break
            }
        }
    }

    private func handlePlayAgainButton() {
        if let playAgainButton = childNode(withName: "//playAgainButton") as? SKShapeNode {
            playAgainButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.startNewGame()
            })
        }
    }

    private func handleLevelsButton() {
        if let levelsButton = childNode(withName: "//levelsButton") as? SKShapeNode {
            levelsButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.goToLevelSelect()
            })
        }
    }

    private func handleMenuButton() {
        if let menuButton = childNode(withName: "//menuButton") as? SKShapeNode {
            menuButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.goToMenu()
            })
        }
    }

    private func startNewGame() {
        guard let view = view else { return }
        let gameScene = GameScene(size: view.bounds.size)
        gameScene.scaleMode = scaleMode
        gameScene.currentLevel = 1
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(gameScene, transition: transition)
    }

    private func goToLevelSelect() {
        guard let view = view else { return }
        // Show the last page with all completed levels
        let levelSelectScene = LevelSelectScene(size: view.bounds.size, startLevel: LevelManager.shared.totalLevels)
        levelSelectScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(levelSelectScene, transition: transition)
    }

    private func goToMenu() {
        guard let view = view else { return }
        let menuScene = MenuScene(size: view.bounds.size)
        menuScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(menuScene, transition: transition)
    }

    // MARK: - Visual Effects

    private func addEpicCelebrationParticles() {
        // Multi-colored confetti explosion
        for _ in 0..<30 {
            let particle = SKShapeNode(rectOf: CGSize(width: 10, height: 10), cornerRadius: 2)
            let colors: [UIColor] = [
                .red, .yellow, .green, .cyan, .magenta,
                UITheme.Colors.primaryGold, .orange, .purple
            ]
            particle.fillColor = colors.randomElement() ?? .yellow
            particle.strokeColor = .clear
            particle.position = CGPoint(x: size.width / 2, y: size.height - 50)
            particle.zPosition = 10
            addChild(particle)

            let randomX = CGFloat.random(in: -200...200)
            let randomY = CGFloat.random(in: -300...100)
            let duration = Double.random(in: 1.5...3.0)

            let move = SKAction.moveBy(x: randomX, y: randomY, duration: duration)
            let rotate = SKAction.rotate(byAngle: .pi * 6, duration: duration)
            let fade = SKAction.fadeOut(withDuration: duration)

            particle.run(SKAction.group([move, rotate, fade])) {
                particle.removeFromParent()
            }
        }

        // Golden fireworks from bottom
        let fireworks = SKEmitterNode()

        fireworks.particleTexture = ParticleTexture.softCircle(diameter: 32)

        let colorSequence = SKKeyframeSequence(keyframeValues: [
            UIColor(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0),
            UIColor(red: 1.0, green: 0.95, blue: 0.5, alpha: 1.0),
            UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0),
            UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.6),
            UIColor(red: 0.4, green: 0.2, blue: 0.0, alpha: 0.0)
        ], times: [0, 0.2, 0.4, 0.7, 1.0])
        fireworks.particleColorSequence = colorSequence

        fireworks.particleBirthRate = 50
        fireworks.particleLifetime = 3.0
        fireworks.particleLifetimeRange = 1.5
        fireworks.particlePositionRange = CGVector(dx: size.width * 1.5, dy: 20)
        fireworks.particleSpeed = 120
        fireworks.particleSpeedRange = 60
        fireworks.emissionAngle = .pi / 2
        fireworks.emissionAngleRange = .pi / 4
        fireworks.particleAlpha = 0.9
        fireworks.particleAlphaSpeed = -0.3
        fireworks.particleScale = 0.5
        fireworks.particleScaleRange = 0.3
        fireworks.particleScaleSpeed = -0.1
        fireworks.particleRotation = 0
        fireworks.particleRotationSpeed = 4.0
        fireworks.particleBlendMode = .add
        fireworks.yAcceleration = 30
        fireworks.particleColorBlendFactor = 1.0
        fireworks.position = CGPoint(x: size.width / 2, y: -20)
        fireworks.zPosition = -1

        addChild(fireworks)
    }
}
