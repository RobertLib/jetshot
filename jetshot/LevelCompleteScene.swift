//
//  LevelCompleteScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

class LevelCompleteScene: SKScene {

    private let level: Int
    private let score: Int
    private let coinsCollected: Int
    private let totalCoins: Int
    private var isInitialized = false

    init(size: CGSize, level: Int, score: Int, coinsCollected: Int = 0, totalCoins: Int = 0) {
        self.level = level
        self.score = score
        self.coinsCollected = coinsCollected
        self.totalCoins = totalCoins
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground

        // Calculate stars earned based on coins collected
        let starsEarned = calculateStarsEarned()

        // Mark level as completed with score and stars
        LevelManager.shared.completeLevel(level, score: score, stars: starsEarned)

        // Add starfield first (lightweight)
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

    private func calculateStarsEarned() -> Int {
        // If no coins in level, always give 3 stars (backwards compatibility)
        guard totalCoins > 0 else { return 3 }

        // Calculate percentage of coins collected
        let percentage = Double(coinsCollected) / Double(totalCoins)

        // Debug output
        print("🌟 Level \(level) complete: Collected \(coinsCollected)/\(totalCoins) coins (\(Int(percentage * 100))%)")

        // Star thresholds:
        // 1 star: < 40% coins
        // 2 stars: 40-69% coins
        // 3 stars: 70%+ coins
        if percentage >= 0.70 {
            print("🌟 Earned 3 stars!")
            return 3
        } else if percentage >= 0.40 {
            print("🌟 Earned 2 stars!")
            return 2
        } else {
            print("🌟 Earned 1 star!")
            return 1
        }
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
        // Add golden success particles in background
        addSuccessParticles()

        // Main panel background with rounded corners and golden glow
        let panelWidth: CGFloat = min(size.width - 60, UITheme.Dimensions.panelWidthMax)
        let panelHeight = 420.0
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
            glowPanel.strokeColor = UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.6)
            glowPanel.lineWidth = UITheme.Dimensions.lineWidthGlowStrong
            glowPanel.setScale(1.02)
            glowPanel.alpha = 0
            addChild(glowPanel)

            // Pulse animation for glow
            glowPanel.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.6),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationMedium),
                SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.4, duration: UITheme.Animations.durationGlowPulse),
                    SKAction.fadeAlpha(to: 0.8, duration: UITheme.Animations.durationGlowPulse)
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

        let spacing = UITheme.Dimensions.spacingLarge

        // Stars decoration at top
        let starsY = panelHeight / 2 - 65
        createStarRating(on: panel, y: starsY)

        // "LEVEL COMPLETE" title - clean and simple
        let title = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        title.text = "LEVEL COMPLETE"
        title.fontSize = UITheme.Typography.sizeMedium
        title.fontColor = UITheme.Colors.primaryGold
        title.position = CGPoint(x: 0, y: starsY - spacing - 10)
        title.alpha = 0
        panel.addChild(title)

        // Animated title entrance
        title.run(SKAction.sequence([
            SKAction.wait(forDuration: UITheme.Animations.durationSlow),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.sequence([
                    SKAction.scale(to: 1.3, duration: UITheme.Animations.durationQuick),
                    SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationQuick)
                ])
            ])
        ]))

        // Score display with icon
        let scoreContainer = createScoreDisplay()
        scoreContainer.position = CGPoint(x: 0, y: title.position.y - 75)
        scoreContainer.alpha = 0
        panel.addChild(scoreContainer)
        scoreContainer.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.9),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.moveBy(x: 0, y: 10, duration: UITheme.Animations.durationNormal)
            ])
        ]))

        // Buttons with better spacing and animation
        setupButtons(on: panel, panelHeight: panelHeight)

        // Celebration particles
        createCelebrationParticles()
    }

    private func createStarRating(on panel: SKShapeNode, y: CGFloat) {
        // Calculate how many stars player earned based on coins collected
        let starsEarned = calculateStarsEarned()

        let starSpacing = UITheme.Dimensions.spacingMedium
        for i in 0..<3 {
            let starContainer = SKNode()
            starContainer.position = CGPoint(x: CGFloat(i - 1) * starSpacing, y: y)
            panel.addChild(starContainer)

            // Determine if this star should be filled
            let isEarned = i < starsEarned

            // Glow effect behind star (only for earned stars)
            let glowStar = UITheme.createStar()
            glowStar.fillColor = UIColor(red: 1.0, green: 0.9, blue: 0.4, alpha: 0.6)
            glowStar.strokeColor = .clear
            glowStar.setScale(1.3)
            glowStar.alpha = 0
            starContainer.addChild(glowStar)

            // Main star
            let star = UITheme.createStar()
            if isEarned {
                // Filled gold star for earned
                star.fillColor = UITheme.Colors.primaryGold
                star.strokeColor = UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1.0)
            } else {
                // Empty gray star for not earned
                star.fillColor = UIColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.5)
                star.strokeColor = UIColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 0.8)
            }
            star.lineWidth = UITheme.Dimensions.lineWidthMedium
            star.setScale(0)
            starContainer.addChild(star)

            // Pop-in animation with delay
            let popAnimation = SKAction.sequence([
                SKAction.wait(forDuration: UITheme.Animations.durationNormal + Double(i) * 0.15),
                SKAction.group([
                    SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationNormal),
                    SKAction.sequence([
                        SKAction.rotate(byAngle: .pi / 4, duration: 0.15),
                        SKAction.rotate(byAngle: -.pi / 4, duration: 0.15)
                    ])
                ])
            ])
            star.run(popAnimation)

            // Glow pulse animation (only for earned stars)
            if isEarned {
                glowStar.run(SKAction.sequence([
                    SKAction.wait(forDuration: UITheme.Animations.durationNormal + Double(i) * 0.15),
                    SKAction.fadeAlpha(to: 0.6, duration: UITheme.Animations.durationNormal),
                    SKAction.repeatForever(SKAction.sequence([
                        SKAction.fadeAlpha(to: UITheme.Animations.alphaFadedLow, duration: UITheme.Animations.durationGlowPulse),
                        SKAction.fadeAlpha(to: UITheme.Animations.alphaFadedHigh, duration: UITheme.Animations.durationGlowPulse)
                    ]))
                ]))
            }


            // Add sparkle particles around stars - now with fixed texture
            let sparkle = SKEmitterNode()

            // Create larger circle texture for sparkles
            let sparkleSize = CGSize(width: 24, height: 24)
            let sparkleRenderer = UIGraphicsImageRenderer(size: sparkleSize)
            let sparkleImage = sparkleRenderer.image { context in
                UIColor.white.setFill()
                let rect = CGRect(origin: .zero, size: sparkleSize)
                context.cgContext.fillEllipse(in: rect)
            }
            sparkle.particleTexture = SKTexture(image: sparkleImage)

            sparkle.particleBirthRate = 5 // More sparkles
            sparkle.particleLifetime = 1.5
            sparkle.particlePositionRange = CGVector(dx: 20, dy: 20)
            sparkle.particleSpeed = 15
            sparkle.particleSpeedRange = 10
            sparkle.emissionAngleRange = .pi * 2
            sparkle.particleAlpha = 1.0 // Brighter
            sparkle.particleAlphaSpeed = -0.7
            sparkle.particleScale = 0.4 // Larger
            sparkle.particleScaleSpeed = -0.2
            sparkle.particleColor = UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1.0)
            sparkle.particleColorBlendFactor = 1.0
            sparkle.particleBlendMode = .add
            sparkle.alpha = 0
            starContainer.addChild(sparkle)

            sparkle.run(SKAction.sequence([
                SKAction.wait(forDuration: UITheme.Animations.durationSlow + Double(i) * 0.15),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationQuick)
            ]))
        }
    }

    private func createScoreDisplay() -> SKNode {
        let container = SKNode()

        // Score label
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
        scoreValue.text = "\(score)"
        scoreValue.fontSize = UITheme.Typography.sizeLarge
        scoreValue.fontColor = UITheme.Colors.primaryGoldLight
        scoreValue.position = CGPoint(x: 0, y: -18)
        container.addChild(scoreValue)

        return container
    }

    private func setupButtons(on panel: SKShapeNode, panelHeight: CGFloat) {
        let buttonY: CGFloat = -panelHeight / 2 + 125

        // Check if this is the last level
        let isLastLevel = level >= LevelManager.shared.totalLevels

        // Next level button (if not last level) - highlighted as primary action
        if !isLastLevel {
            let nextButton = UITheme.createButton(
                text: "NEXT",
                color: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0),
                width: UITheme.Dimensions.buttonWidthXLarge,
                name: "nextButton"
            )
            nextButton.position = CGPoint(x: 0, y: buttonY)
            nextButton.alpha = 0
            panel.addChild(nextButton)

            nextButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.1),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
            ]))

            // Add subtle pulse to next button
            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.05, duration: UITheme.Animations.durationButtonPulse),
                SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationButtonPulse)
            ])
            nextButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.4),
                SKAction.repeatForever(pulse)
            ]))
        } else {
            // If last level, show "Continue to Victory" button
            let victoryButton = UITheme.createButton(
                text: "CONTINUE",
                color: UIColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0), // Golden color
                width: UITheme.Dimensions.buttonWidthXLarge,
                name: "victoryButton"
            )
            victoryButton.position = CGPoint(x: 0, y: buttonY)
            victoryButton.alpha = 0
            panel.addChild(victoryButton)

            victoryButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.1),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
            ]))

            // Add golden pulse to victory button
            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.05, duration: UITheme.Animations.durationButtonPulse),
                SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationButtonPulse)
            ])
            victoryButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.4),
                SKAction.repeatForever(pulse)
            ]))
        }

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
            SKAction.wait(forDuration: 1.2),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        menuButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.3),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))
    }

    private func createCelebrationParticles() {
        // Create confetti-like particles (reduced for better performance)
        for _ in 0..<12 {  // Reduced from 20
            let particle = SKShapeNode(rectOf: CGSize(width: 8, height: 8), cornerRadius: 2)
            let colors: [UIColor] = [.red, .yellow, .green, .cyan, .magenta]
            particle.fillColor = colors.randomElement()!
            particle.strokeColor = .clear
            particle.position = CGPoint(x: size.width / 2, y: size.height - 100)
            particle.zPosition = 10
            addChild(particle)

            let randomX = CGFloat.random(in: -150...150)
            let randomY = CGFloat.random(in: -200...100)
            let duration = Double.random(in: 1.0...2.0)

            let move = SKAction.moveBy(x: randomX, y: randomY, duration: duration)
            let rotate = SKAction.rotate(byAngle: .pi * 4, duration: duration)
            let fade = SKAction.fadeOut(withDuration: duration)

            particle.run(SKAction.group([move, rotate, fade])) {
                particle.removeFromParent()
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        if let nodeName = touchedNode.name ?? touchedNode.parent?.name {
            switch nodeName {
            case "nextButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleNextButton()
            case "victoryButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleVictoryButton()
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

    private func handleNextButton() {
        // Button press animation
        if let nextButton = childNode(withName: "//nextButton") as? SKShapeNode {
            nextButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.startNextLevel()
            })
        }
    }

    private func handleVictoryButton() {
        // Button press animation
        if let victoryButton = childNode(withName: "//victoryButton") as? SKShapeNode {
            victoryButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.showGameCompletion()
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

    private func startNextLevel() {
        let nextLevel = level + 1
        if nextLevel <= LevelManager.shared.totalLevels {
            let gameScene = GameScene(size: size)
            gameScene.currentLevel = nextLevel
            gameScene.scaleMode = scaleMode
            let transition = SKTransition.fade(withDuration: 0.5)
            view?.presentScene(gameScene, transition: transition)
        }
    }

    private func showGameCompletion() {
        // Get total score from all completed levels
        let totalScore = LevelManager.shared.getTotalScore()
        let gameCompletionScene = GameCompletionScene(size: size, totalScore: totalScore)
        gameCompletionScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(gameCompletionScene, transition: transition)
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

    private func addSuccessParticles() {
        // Golden fire effect from bottom
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

        // Golden fire color sequence: white-hot -> bright yellow -> golden -> orange -> dark
        let colorSequence = SKKeyframeSequence(keyframeValues: [
            UIColor(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0),   // Hot white
            UIColor(red: 1.0, green: 0.95, blue: 0.5, alpha: 1.0),  // Bright yellow
            UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0),  // Golden
            UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 0.8),   // Orange
            UIColor(red: 0.4, green: 0.2, blue: 0.0, alpha: 0.0)    // Dark fade
        ], times: [0, 0.2, 0.4, 0.7, 1.0])
        particles.particleColorSequence = colorSequence

        particles.particleBirthRate = 30  // Reduced from 50
        particles.particleLifetime = 2.0  // Reduced from 2.5
        particles.particleLifetimeRange = 0.8  // Reduced from 1.0
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
        particles.name = "successParticles"

        addChild(particles)
    }
}
