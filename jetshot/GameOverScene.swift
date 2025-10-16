//
//  GameOverScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

class GameOverScene: SKScene {

    private let finalScore: Int
    private let currentLevel: Int
    private var isInitialized = false

    init(size: CGSize, score: Int, level: Int = 1) {
        self.finalScore = score
        self.currentLevel = level
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground

        addChild(StarfieldHelper.createStarfield(for: self))
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        setupUI()
        isInitialized = true

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
        // Add red warning particles in background
        addWarningParticles()

        // Main panel background with rounded corners and glow
        let panelWidth: CGFloat = min(size.width - 60, UITheme.Dimensions.panelWidthMax)
        let panelHeight = 420.0
        let panel = UITheme.createPanel(
            width: panelWidth,
            height: panelHeight,
            borderColor: UITheme.Colors.dangerRed
        )
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.alpha = 0

        // Add outer glow effect
        if let glowPanel = panel.copy() as? SKShapeNode {
            glowPanel.fillColor = .clear
            glowPanel.strokeColor = UITheme.Colors.dangerRedLight
            glowPanel.lineWidth = UITheme.Dimensions.lineWidthGlowStrong
            glowPanel.setScale(1.02)
            glowPanel.alpha = 0
            addChild(glowPanel)

            // Pulse animation for glow
            glowPanel.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.6),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationMedium),
                UITheme.createGlowPulseAnimation()
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

        // Better spacing for proper layout
        let spacing = UITheme.Dimensions.spacingLarge

        // X mark icon (defeat symbol) - smaller and better positioned
        let defeatIcon = createDefeatIcon()
        defeatIcon.position = CGPoint(x: 0, y: panelHeight / 2 - 65)
        defeatIcon.setScale(0.8) // Make it smaller
        defeatIcon.alpha = 0
        panel.addChild(defeatIcon)

        // Animated icon entrance with shake
        defeatIcon.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.4),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.sequence([
                    SKAction.scale(to: 0.9, duration: 0.15),
                    SKAction.scale(to: 0.8, duration: 0.15)
                ]),
                SKAction.sequence([
                    SKAction.rotate(byAngle: 0.2, duration: UITheme.Animations.durationFast),
                    SKAction.rotate(byAngle: -0.4, duration: UITheme.Animations.durationFast),
                    SKAction.rotate(byAngle: 0.2, duration: UITheme.Animations.durationFast)
                ])
            ])
        ]))

        // "LEVEL FAILED" title - more space from icon
        let title = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        title.text = "LEVEL FAILED"
        title.fontSize = UITheme.Typography.sizeMedium
        title.fontColor = UITheme.Colors.dangerRed
        title.position = CGPoint(x: 0, y: defeatIcon.position.y - spacing - 10)
        title.alpha = 0
        panel.addChild(title)

        // Animated title entrance
        title.run(SKAction.sequence([
            SKAction.wait(forDuration: UITheme.Animations.durationSlow),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.sequence([
                    SKAction.scale(to: 1.2, duration: UITheme.Animations.durationQuick),
                    SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationQuick)
                ])
            ])
        ]))

        // Score display
        let scoreContainer = createScoreDisplay()
        scoreContainer.position = CGPoint(x: 0, y: title.position.y - 75)
        scoreContainer.alpha = 0
        panel.addChild(scoreContainer)
        scoreContainer.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.7),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.moveBy(x: 0, y: 10, duration: UITheme.Animations.durationNormal)
            ])
        ]))

        // Buttons with better spacing and animation
        setupButtons(on: panel, panelHeight: panelHeight)
    }

    private func createScoreDisplay() -> SKNode {
        let container = SKNode()

        // Score label "SCORE" with icon
        let scoreLabel = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.text = "SCORE"
        scoreLabel.fontSize = UITheme.Typography.sizeRegular
        scoreLabel.fontColor = UITheme.Colors.textSecondary
        scoreLabel.position = CGPoint(x: 0, y: 19)
        container.addChild(scoreLabel)

        // Score value
        let scoreValue = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        scoreValue.horizontalAlignmentMode = .center
        scoreValue.verticalAlignmentMode = .center
        scoreValue.text = "\(finalScore)"
        scoreValue.fontSize = UITheme.Typography.sizeLarge
        scoreValue.fontColor = UITheme.Colors.primaryGold
        scoreValue.position = CGPoint(x: 0, y: -18)
        container.addChild(scoreValue)

        return container
    }

    private func setupButtons(on panel: SKShapeNode, panelHeight: CGFloat) {
        let buttonY: CGFloat = -panelHeight / 2 + 125

        // Retry button
        let retryButton = UITheme.createButton(
            text: "RETRY",
            color: UITheme.Colors.successGreen,
            width: UITheme.Dimensions.buttonWidthXLarge,
            name: "retryButton"
        )
        retryButton.position = CGPoint(x: 0, y: buttonY)
        retryButton.alpha = 0
        panel.addChild(retryButton)

        retryButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.9),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
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
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        menuButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.1),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        if let nodeName = touchedNode.name ?? touchedNode.parent?.name {
            switch nodeName {
            case "retryButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleRetryButton()
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

    private func handleRetryButton() {
        // Button press animation
        if let retryButton = childNode(withName: "//retryButton") as? SKShapeNode {
            retryButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.restartGame()
            })
        }
    }

    private func handleLevelsButton() {
        // Button press animation
        if let levelsButton = childNode(withName: "//levelsButton") as? SKShapeNode {
            levelsButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.goToLevelSelect()
            })
        }
    }

    private func handleMenuButton() {
        // Button press animation
        if let menuButton = childNode(withName: "//menuButton") as? SKShapeNode {
            menuButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.goToMenu()
            })
        }
    }

    private func restartGame() {
        let gameScene = GameScene(size: size)
        gameScene.currentLevel = currentLevel // Restart the same level
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

    private func createDefeatIcon() -> SKNode {
        let container = SKNode()

        // Red circle background
        let circle = SKShapeNode(circleOfRadius: 35)
        circle.fillColor = UIColor(red: 0.8, green: 0.15, blue: 0.15, alpha: 1.0)
        circle.strokeColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        circle.lineWidth = 4
        container.addChild(circle)

        // Add inner glow circle
        let glowCircle = SKShapeNode(circleOfRadius: 32)
        glowCircle.fillColor = .clear
        glowCircle.strokeColor = UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 0.5)
        glowCircle.lineWidth = 6
        glowCircle.alpha = 0.6
        container.addChild(glowCircle)

        // Pulse animation for glow
        glowCircle.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.8),
            SKAction.fadeAlpha(to: 0.8, duration: 0.8)
        ])))

        // Sad face emoji
        // Left eye
        let leftEye = SKShapeNode(circleOfRadius: 4)
        leftEye.fillColor = .white
        leftEye.strokeColor = .white
        leftEye.lineWidth = 2
        leftEye.position = CGPoint(x: -10, y: 6)
        container.addChild(leftEye)

        // Right eye
        let rightEye = SKShapeNode(circleOfRadius: 4)
        rightEye.fillColor = .white
        rightEye.strokeColor = .white
        rightEye.lineWidth = 2
        rightEye.position = CGPoint(x: 10, y: 6)
        container.addChild(rightEye)

        // Frowning mouth (upward arc, angry expression)
        let mouthPath = CGMutablePath()
        mouthPath.move(to: CGPoint(x: -12, y: -10))
        mouthPath.addQuadCurve(
            to: CGPoint(x: 12, y: -10),
            control: CGPoint(x: 0, y: -2)
        )

        let mouth = SKShapeNode(path: mouthPath)
        mouth.strokeColor = .white
        mouth.lineWidth = 3
        mouth.lineCap = .round
        container.addChild(mouth)

        return container
    }

    private func addWarningParticles() {
        // Red fire effect from bottom
        let particles = SKEmitterNode()

        // Simple circular texture for better performance
        let textureSize = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: textureSize)
        let circleImage = renderer.image { context in
            let ctx = context.cgContext
            // Soft circle with radial gradient
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                   endCenter: CGPoint(x: 16, y: 16), endRadius: 16,
                                   options: [])
        }
        particles.particleTexture = SKTexture(image: circleImage)

        // Fire color sequence: white-hot -> yellow -> orange -> red -> dark
        let colorSequence = SKKeyframeSequence(keyframeValues: [
            UIColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0),   // Hot white
            UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0),   // Yellow
            UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0),   // Orange
            UIColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 0.8),   // Red
            UIColor(red: 0.2, green: 0.0, blue: 0.0, alpha: 0.0)    // Dark fade
        ], times: [0, 0.2, 0.4, 0.7, 1.0])
        particles.particleColorSequence = colorSequence

        particles.particleBirthRate = 50
        particles.particleLifetime = 2.5
        particles.particleLifetimeRange = 1.0
        particles.particlePositionRange = CGVector(dx: size.width * 1.2, dy: 10)
        particles.particleSpeed = 80
        particles.particleSpeedRange = 40
        particles.emissionAngle = .pi / 2  // Upward
        particles.emissionAngleRange = .pi / 6
        particles.particleAlpha = 0.8
        particles.particleAlphaSpeed = -0.3
        particles.particleScale = 0.4
        particles.particleScaleRange = 0.3
        particles.particleScaleSpeed = -0.1
        particles.particleRotation = 0
        particles.particleRotationSpeed = 3.0
        particles.particleBlendMode = .add
        particles.yAcceleration = 20
        particles.xAcceleration = 0
        particles.particleColorBlendFactor = 1.0
        particles.position = CGPoint(x: size.width / 2, y: -20)
        particles.zPosition = -1
        particles.name = "warningParticles"
        addChild(particles)
    }
}
