//
//  GameCompletionScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 27.10.2025.
//

import SpriteKit

class GameCompletionScene: SKScene {

    private let totalScore: Int
    private var isInitialized = false

    init(size: CGSize, totalScore: Int) {
        self.totalScore = totalScore
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground

        // Add starfield background
        addChild(StarfieldHelper.createStarfield(for: self))
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))

        // Setup UI immediately
        setupUI()

        // Mark as initialized after scene setup completes using SKAction
        let wait = SKAction.wait(forDuration: 0.1)
        let initialize = SKAction.run { [weak self] in
            self?.isInitialized = true
        }
        run(SKAction.sequence([wait, initialize]))

        // Continue background music
        SoundManager.shared.resumeMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized else { return }

        // Remove and recreate all elements
        removeAllChildren()

        addChild(StarfieldHelper.createStarfield(for: self))
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        setupUI()
    }

    private func setupUI() {
        // Epic celebration particles
        addEpicCelebrationParticles()

        // Main panel
        let panelWidth: CGFloat = min(size.width - 60, UITheme.Dimensions.panelWidthMax)
        let panelHeight: CGFloat = 520
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

        // "VICTORY!" title
        let victoryTitle = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        victoryTitle.text = "🎉 VICTORY! 🎉"
        victoryTitle.fontSize = UITheme.Typography.sizeLarge
        victoryTitle.fontColor = UITheme.Colors.primaryGold
        victoryTitle.position = CGPoint(x: 0, y: panelHeight / 2 - 70)
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
        let congratsText = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        congratsText.text = "Congratulations!"
        congratsText.fontSize = UITheme.Typography.sizeMedium
        congratsText.fontColor = UITheme.Colors.textPrimary
        congratsText.position = CGPoint(x: 0, y: 145)
        congratsText.alpha = 0
        panel.addChild(congratsText)

        congratsText.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        // Success message
        let successText = createMultilineText(
            text: "You have completed all levels!\nYou are a master pilot!",
            fontSize: UITheme.Typography.sizeRegular,
            y: 90
        )
        successText.alpha = 0
        panel.addChild(successText)

        successText.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.3),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        // Thank you message
        let thanksText = createMultilineText(
            text: "Thank you for playing!",
            fontSize: UITheme.Typography.sizeRegular,
            y: 20
        )
        thanksText.alpha = 0
        panel.addChild(thanksText)

        thanksText.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.6),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        // Final score display
        let scoreContainer = createScoreDisplay()
        scoreContainer.position = CGPoint(x: 0, y: -100)
        scoreContainer.alpha = 0
        panel.addChild(scoreContainer)

        scoreContainer.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.9),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.moveBy(x: 0, y: 10, duration: UITheme.Animations.durationNormal)
            ])
        ]))

        // Buttons
        setupButtons(on: panel, panelHeight: panelHeight)
    }

    private func createMultilineText(text: String, fontSize: CGFloat, y: CGFloat) -> SKNode {
        let container = SKNode()
        container.position = CGPoint(x: 0, y: y)

        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let label = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
            label.text = line
            label.fontSize = fontSize
            label.fontColor = UITheme.Colors.textSecondary
            label.position = CGPoint(x: 0, y: -CGFloat(index) * (fontSize + 8))
            container.addChild(label)
        }

        return container
    }

    private func createScoreDisplay() -> SKNode {
        let container = SKNode()

        // "Total Score:" label
        let scoreLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        scoreLabel.text = "Total Score:"
        scoreLabel.fontSize = UITheme.Typography.sizeRegular
        scoreLabel.fontColor = UITheme.Colors.textSecondary
        scoreLabel.position = CGPoint(x: 0, y: 55)
        container.addChild(scoreLabel)

        // Score value
        let scoreValue = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        scoreValue.text = "\(totalScore)"
        scoreValue.fontSize = UITheme.Typography.sizeLarge
        scoreValue.fontColor = UITheme.Colors.primaryGoldLight
        scoreValue.position = CGPoint(x: 0, y: 16)
        container.addChild(scoreValue)

        return container
    }

    private func setupButtons(on panel: SKShapeNode, panelHeight: CGFloat) {
        let buttonY: CGFloat = -panelHeight / 2 + 125

        // Play Again button (restart from level 1)
        let playAgainButton = UITheme.createButton(
            text: "PLAY AGAIN",
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
        let secondaryButtonY = buttonY - 65

        let levelsButton = UITheme.createButton(
            text: "LEVELS",
            color: UITheme.Colors.buttonLevels,
            width: UITheme.Dimensions.buttonWidthSmall,
            name: "levelsButton"
        )
        levelsButton.position = CGPoint(x: -67, y: secondaryButtonY)
        levelsButton.alpha = 0
        panel.addChild(levelsButton)

        let menuButton = UITheme.createButton(
            text: "MENU",
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
        let gameScene = GameScene(size: size)
        gameScene.currentLevel = 1
        gameScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(gameScene, transition: transition)
    }

    private func goToLevelSelect() {
        let levelSelectScene = LevelSelectScene(size: size)
        levelSelectScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(levelSelectScene, transition: transition)
    }

    private func goToMenu() {
        let menuScene = MenuScene(size: size)
        menuScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(menuScene, transition: transition)
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
            particle.fillColor = colors.randomElement()!
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

        let textureSize = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: textureSize)
        let circleImage = renderer.image { context in
            let ctx = context.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                   endCenter: CGPoint(x: 16, y: 16), endRadius: 16,
                                   options: [])
        }
        fireworks.particleTexture = SKTexture(image: circleImage)

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
