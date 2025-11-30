//
//  MenuScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import SpriteKit

class MenuScene: SKScene {

    private var titleLabel: SKLabelNode!
    private var startButton: SKShapeNode!
    private var startButtonLabel: SKLabelNode!
    private var gameCenterButton: SKShapeNode!
    private var isInitialized = false

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground

        addChild(StarfieldHelper.createStarfield(for: self))
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        setupTitle()
        setupStartButton()
        setupGameCenterButton()
        isInitialized = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized else { return }

        // Remove and recreate all elements
        removeAllChildren()

        addChild(StarfieldHelper.createStarfield(for: self))
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        setupTitle()
        setupStartButton()
        setupGameCenterButton()
    }

    private func setupTitle() {
        // Main title
        titleLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        titleLabel.text = "JETSHOT"
        titleLabel.fontSize = UITheme.Typography.sizeHuge
        titleLabel.fontColor = UITheme.Colors.primaryCyan
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 70)

        // Add glow effect
        titleLabel.run(SKAction.repeatForever(
            SKAction.sequence([
                SKAction.fadeAlpha(to: UITheme.Animations.alphaFadedHigh, duration: UITheme.Animations.durationGlowPulse),
                SKAction.fadeAlpha(to: UITheme.Animations.alphaFull, duration: UITheme.Animations.durationGlowPulse)
            ])
        ))

        addChild(titleLabel)

        // Subtitle
        let subtitleLabel = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        subtitleLabel.text = "Space Shooter"
        subtitleLabel.fontSize = UITheme.Typography.sizeRegular
        subtitleLabel.fontColor = UITheme.Colors.textPrimary
        subtitleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 20)
        addChild(subtitleLabel)

        // Credits - Creator info
        let creditsLabel = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        creditsLabel.text = "Created by RobLib"
        creditsLabel.fontSize = UITheme.Typography.sizeSmall
        creditsLabel.fontColor = UITheme.Colors.textSecondary.withAlphaComponent(0.6)
        creditsLabel.position = CGPoint(x: size.width / 2, y: 30)
        addChild(creditsLabel)
    }

    private func setupStartButton() {
        startButton = UITheme.createButton(
            text: "START",
            color: UITheme.Colors.primaryCyan,
            width: UITheme.Dimensions.buttonWidthLarge,
            name: "startButton"
        )
        startButton.position = CGPoint(x: size.width / 2, y: size.height / 2 - 62.5)

        // Add glow effect
        GlowHelper.addEnhancedGlow(to: startButton, color: UITheme.Colors.primaryCyan, intensity: 0.3)

        // Pulse animation
        startButton.run(UITheme.createButtonPulseAnimation())

        addChild(startButton)

        // Store reference to label for future updates if needed
        startButtonLabel = startButton.childNode(withName: "//SKLabelNode") as? SKLabelNode
    }

    private func setupGameCenterButton() {
        // Create outlined button (no background fill)
        let buttonWidth = UITheme.Dimensions.buttonWidthLarge
        let buttonHeight = UITheme.Dimensions.buttonHeight

        gameCenterButton = SKShapeNode(
            rectOf: CGSize(width: buttonWidth, height: buttonHeight),
            cornerRadius: UITheme.Dimensions.cornerRadiusMedium
        )
        gameCenterButton.fillColor = .clear  // No background
        gameCenterButton.strokeColor = UITheme.Colors.accentGreen
        gameCenterButton.lineWidth = UITheme.Dimensions.lineWidthMedium
        gameCenterButton.name = "gameCenterButton"
        gameCenterButton.position = CGPoint(x: size.width / 2, y: size.height / 2 - 137.5)

        // Add label
        let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        label.text = "GAME CENTER"
        label.fontSize = UITheme.Typography.sizeSmall
        label.fontColor = UITheme.Colors.accentGreen
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.zPosition = 2
        gameCenterButton.addChild(label)

        addChild(gameCenterButton)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNodes = nodes(at: location)

        // Check if start button was tapped
        if touchedNodes.contains(where: { $0.name == "startButton" }) {
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)
            startGame()
        }

        // Check if Game Center button was tapped
        if touchedNodes.contains(where: { $0.name == "gameCenterButton" }) {
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)
            showGameCenter()
        }
    }

    private func startGame() {
        // Button press animation
        startButton.run(UITheme.createButtonPressAnimation { [weak self] in
            self?.transitionToGame()
        })
    }

    private func transitionToGame() {
        // Go to level select screen instead of directly to game
        let levelSelectScene = LevelSelectScene(size: size)
        levelSelectScene.scaleMode = scaleMode

        // Transition with animation
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(levelSelectScene, transition: transition)
    }

    private func showGameCenter() {
        // Button press animation
        gameCenterButton.run(UITheme.createButtonPressAnimation { [weak self] in
            self?.presentGameCenterView()
        })
    }

    private func presentGameCenterView() {
        guard let viewController = view?.window?.rootViewController else {
            print("⚠️ Cannot show Game Center - no view controller found")
            return
        }

        // Check if player is authenticated
        if !GameCenterManager.shared.isAuthenticated {
            // Try to authenticate first
            GameCenterManager.shared.authenticatePlayer(from: viewController)
            return
        }

        // Show leaderboard (default view)
        GameCenterManager.shared.showLeaderboard(from: viewController)
    }
}

