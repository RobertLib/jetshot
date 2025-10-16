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
    private var isInitialized = false

    init(size: CGSize, level: Int, score: Int) {
        self.level = level
        self.score = score
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)

        // Mark level as completed
        LevelManager.shared.completeLevel(level)

        addChild(StarfieldHelper.createStarfield(for: self))
        setupUI()
        isInitialized = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized else { return }

        // Remove and recreate all elements
        removeAllChildren()

        addChild(StarfieldHelper.createStarfield(for: self))
        setupUI()
    }

    private func setupUI() {
        // Add golden success particles in background
        addSuccessParticles()

        // Main panel background with rounded corners and golden glow
        let panelWidth: CGFloat = min(size.width - 60, 350)
        let panelHeight: CGFloat = 500
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 25)
        panel.fillColor = UIColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 0.95)
        panel.strokeColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0) // Golden border for success
        panel.lineWidth = 4
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.alpha = 0

        // Add outer golden glow effect
        if let glowPanel = panel.copy() as? SKShapeNode {
            glowPanel.fillColor = .clear
            glowPanel.strokeColor = UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.6)
            glowPanel.lineWidth = 8
            glowPanel.setScale(1.02)
            glowPanel.alpha = 0
            addChild(glowPanel)

            // Pulse animation for glow
            glowPanel.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.6),
                SKAction.fadeIn(withDuration: 0.4),
                SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.4, duration: 1.0),
                    SKAction.fadeAlpha(to: 0.8, duration: 1.0)
                ]))
            ]))
        }

        addChild(panel)

        // Animate panel entrance
        panel.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.2),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.4),
                SKAction.scale(to: 1.0, duration: 0.4)
            ])
        ]))
        panel.setScale(0.8)

        // Stars decoration at top
        createStarRating(on: panel, y: panelHeight / 2 - 60)

        // "LEVEL COMPLETE" title - clean and simple
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "LEVEL COMPLETE"
        title.fontSize = 28
        title.fontColor = UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        title.position = CGPoint(x: 0, y: panelHeight / 2 - 120)
        title.alpha = 0
        panel.addChild(title)

        // Animated title entrance
        title.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.5),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.3),
                SKAction.sequence([
                    SKAction.scale(to: 1.3, duration: 0.2),
                    SKAction.scale(to: 1.0, duration: 0.2)
                ])
            ])
        ]))

        // Level number badge
        let levelBadge = createLevelBadge()
        levelBadge.position = CGPoint(x: 0, y: panelHeight / 2 - 185)
        levelBadge.alpha = 0
        panel.addChild(levelBadge)
        levelBadge.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.7),
            SKAction.fadeIn(withDuration: 0.3)
        ]))

        // Score display with icon
        let scoreContainer = createScoreDisplay()
        scoreContainer.position = CGPoint(x: 0, y: -40)
        scoreContainer.alpha = 0
        panel.addChild(scoreContainer)
        scoreContainer.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.9),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.3),
                SKAction.moveBy(x: 0, y: 10, duration: 0.3)
            ])
        ]))

        // Buttons with better spacing and animation
        setupButtons(on: panel, panelHeight: panelHeight)

        // Celebration particles
        createCelebrationParticles()
    }

    private func createStarRating(on panel: SKShapeNode, y: CGFloat) {
        // 3 gold stars for completing the level - simple and clean
        let starSpacing: CGFloat = 50
        for i in 0..<3 {
            let starContainer = SKNode()
            starContainer.position = CGPoint(x: CGFloat(i - 1) * starSpacing, y: y)
            panel.addChild(starContainer)

            // Glow effect behind star
            let glowStar = createStar()
            glowStar.fillColor = UIColor(red: 1.0, green: 0.9, blue: 0.4, alpha: 0.6)
            glowStar.strokeColor = .clear
            glowStar.setScale(1.3)
            glowStar.alpha = 0
            starContainer.addChild(glowStar)

            // Main star
            let star = createStar()
            star.fillColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
            star.strokeColor = UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1.0)
            star.lineWidth = 3
            star.setScale(0)
            starContainer.addChild(star)

            // Pop-in animation with delay
            let popAnimation = SKAction.sequence([
                SKAction.wait(forDuration: 0.3 + Double(i) * 0.15),
                SKAction.group([
                    SKAction.scale(to: 1.0, duration: 0.3),
                    SKAction.sequence([
                        SKAction.rotate(byAngle: .pi / 4, duration: 0.15),
                        SKAction.rotate(byAngle: -.pi / 4, duration: 0.15)
                    ])
                ])
            ])
            star.run(popAnimation)

            // Glow pulse animation
            glowStar.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.3 + Double(i) * 0.15),
                SKAction.fadeAlpha(to: 0.6, duration: 0.3),
                SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.3, duration: 1.0),
                    SKAction.fadeAlpha(to: 0.7, duration: 1.0)
                ]))
            ]))


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
                SKAction.wait(forDuration: 0.5 + Double(i) * 0.15),
                SKAction.fadeIn(withDuration: 0.2)
            ]))
        }
    }

    private func createStar() -> SKShapeNode {
        let path = CGMutablePath()
        let points = 5
        let outerRadius: CGFloat = 20
        let innerRadius: CGFloat = 10

        for i in 0..<points * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(points)
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let x = radius * cos(angle - .pi / 2)
            let y = radius * sin(angle - .pi / 2)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        return SKShapeNode(path: path)
    }

    private func createLevelBadge() -> SKNode {
        let container = SKNode()

        // Outer glow ring
        let glowBadge = SKShapeNode(circleOfRadius: 38)
        glowBadge.fillColor = .clear
        glowBadge.strokeColor = UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.6)
        glowBadge.lineWidth = 6
        container.addChild(glowBadge)

        // Pulse animation for glow
        glowBadge.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 1.0),
            SKAction.fadeAlpha(to: 0.7, duration: 1.0)
        ])))

        // Main badge circle
        let badge = SKShapeNode(circleOfRadius: 35)
        badge.fillColor = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        badge.strokeColor = UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
        badge.lineWidth = 3
        container.addChild(badge)

        // Inner highlight
        let highlight = SKShapeNode(circleOfRadius: 32)
        highlight.fillColor = .clear
        highlight.strokeColor = UIColor(white: 1.0, alpha: 0.3)
        highlight.lineWidth = 2
        highlight.position = CGPoint(x: 0, y: 2)
        container.addChild(highlight)

        // Level label
        let levelLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        levelLabel.text = "\(level)"
        levelLabel.fontSize = 32
        levelLabel.fontColor = .white
        levelLabel.horizontalAlignmentMode = .center
        levelLabel.verticalAlignmentMode = .center
        container.addChild(levelLabel)

        return container
    }

    private func createScoreDisplay() -> SKNode {
        let container = SKNode()

        // Background box with better styling
        let box = SKShapeNode(rectOf: CGSize(width: 200, height: 60), cornerRadius: 15)
        box.fillColor = UIColor(red: 0.15, green: 0.2, blue: 0.3, alpha: 1.0)
        box.strokeColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0) // Golden border to match theme
        box.lineWidth = 3
        container.addChild(box)

        // Inner highlight
        let highlight = SKShapeNode(rectOf: CGSize(width: 196, height: 56), cornerRadius: 13)
        highlight.fillColor = .clear
        highlight.strokeColor = UIColor(white: 1.0, alpha: 0.15)
        highlight.lineWidth = 2
        highlight.position = CGPoint(x: 0, y: 1)
        container.addChild(highlight)

        // Score label
        let scoreLabel = SKLabelNode(fontNamed: "Arial")
        scoreLabel.text = "SCORE"
        scoreLabel.fontSize = 16
        scoreLabel.fontColor = UIColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 1.0)
        scoreLabel.position = CGPoint(x: 0, y: 7)
        container.addChild(scoreLabel)

        // Score value with glow
        let scoreValueShadow = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreValueShadow.text = "\(score)"
        scoreValueShadow.fontSize = 28
        scoreValueShadow.fontColor = UIColor(red: 1.0, green: 0.9, blue: 0.4, alpha: 0.6)
        scoreValueShadow.position = CGPoint(x: 0, y: -21)
        scoreValueShadow.setScale(1.1)
        container.addChild(scoreValueShadow)

        // Pulse glow
        scoreValueShadow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 1.0),
            SKAction.fadeAlpha(to: 0.7, duration: 1.0)
        ])))

        let scoreValue = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreValue.text = "\(score)"
        scoreValue.fontSize = 28
        scoreValue.fontColor = UIColor(red: 1.0, green: 0.95, blue: 0.3, alpha: 1.0)
        scoreValue.position = CGPoint(x: 0, y: -21)
        container.addChild(scoreValue)

        return container
    }

    private func setupButtons(on panel: SKShapeNode, panelHeight: CGFloat) {
        let buttonY: CGFloat = -panelHeight / 2 + 130

        // Next level button (if not last level) - highlighted as primary action
        if level < LevelManager.shared.totalLevels {
            let nextButton = createStyledButton(
                text: "NEXT ▶",
                color: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0), // Green for success/continue
                width: 260,
                name: "nextButton"
            )
            nextButton.position = CGPoint(x: 0, y: buttonY)
            nextButton.alpha = 0
            panel.addChild(nextButton)

            nextButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.1),
                SKAction.fadeIn(withDuration: 0.3)
            ]))

            // Add subtle pulse to next button
            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.05, duration: 0.8),
                SKAction.scale(to: 1.0, duration: 0.8)
            ])
            nextButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.4),
                SKAction.repeatForever(pulse)
            ]))
        }

        // Secondary buttons container
        let secondaryButtonY = buttonY - 65

        let levelsButton = createStyledButton(
            text: "LEVELS",
            color: UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0),
            width: 125,
            name: "levelsButton"
        )
        levelsButton.position = CGPoint(x: -67, y: secondaryButtonY)
        levelsButton.alpha = 0
        panel.addChild(levelsButton)

        let menuButton = createStyledButton(
            text: "MENU",
            color: UIColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1.0),
            width: 125,
            name: "menuButton"
        )
        menuButton.position = CGPoint(x: 67, y: secondaryButtonY)
        menuButton.alpha = 0
        panel.addChild(menuButton)

        levelsButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.2),
            SKAction.fadeIn(withDuration: 0.3)
        ]))

        menuButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.3),
            SKAction.fadeIn(withDuration: 0.3)
        ]))
    }

    private func createStyledButton(text: String, color: UIColor, width: CGFloat, name: String) -> SKShapeNode {
        let button = SKShapeNode(rectOf: CGSize(width: width, height: 50), cornerRadius: 12)
        button.fillColor = color

        // Calculate lighter border color based on fill color
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        button.strokeColor = UIColor(hue: hue, saturation: max(0, saturation - 0.2), brightness: min(1, brightness + 0.3), alpha: alpha)

        button.lineWidth = 3
        button.name = name

        // Add shadow effect with a darker copy behind
        let shadow = SKShapeNode(rectOf: CGSize(width: width, height: 50), cornerRadius: 12)
        shadow.fillColor = .black
        shadow.alpha = 0.3
        shadow.position = CGPoint(x: 0, y: -4)
        shadow.zPosition = -1
        button.addChild(shadow)

        // Add subtle inner glow
        let innerGlow = SKShapeNode(rectOf: CGSize(width: width - 4, height: 46), cornerRadius: 10)
        innerGlow.fillColor = .clear
        innerGlow.strokeColor = UIColor(white: 1.0, alpha: 0.2)
        innerGlow.lineWidth = 2
        innerGlow.position = CGPoint(x: 0, y: 1)
        innerGlow.zPosition = 1
        button.addChild(innerGlow)

        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = text
        label.fontSize = 20
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.zPosition = 2
        button.addChild(label)

        return button
    }

    private func createCelebrationParticles() {
        // Create confetti-like particles
        for _ in 0..<20 {
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
                handleNextButton()
            case "levelsButton":
                HapticManager.shared.lightTap()
                handleLevelsButton()
            case "menuButton":
                HapticManager.shared.lightTap()
                handleMenuButton()
            default:
                break
            }
        }
    }

    private func handleNextButton() {
        SoundManager.shared.playShoot()

        // Button press animation
        if let nextButton = childNode(withName: "//nextButton") as? SKShapeNode {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            nextButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.startNextLevel()
            }
        }
    }

    private func handleLevelsButton() {
        SoundManager.shared.playShoot()

        // Button press animation
        if let levelsButton = childNode(withName: "//levelsButton") as? SKShapeNode {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            levelsButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.goToLevelSelect()
            }
        }
    }

    private func handleMenuButton() {
        SoundManager.shared.playShoot()

        // Button press animation
        if let menuButton = childNode(withName: "//menuButton") as? SKShapeNode {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            menuButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.goToMenu()
            }
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
        // Golden success particles floating upward
        let particles = SKEmitterNode()

        // Create a moderate circle texture for particles
        let textureSize = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: textureSize)
        let circleImage = renderer.image { context in
            UIColor.white.setFill()
            let rect = CGRect(origin: .zero, size: textureSize)
            context.cgContext.fillEllipse(in: rect)
        }
        particles.particleTexture = SKTexture(image: circleImage)

        particles.particleBirthRate = 20 // Moderate density
        particles.particleLifetime = 4.5
        particles.particleLifetimeRange = 2.0
        particles.particlePositionRange = CGVector(dx: size.width * 1.2, dy: 0) // Cover full width
        particles.particleSpeed = 40
        particles.particleSpeedRange = 25
        particles.emissionAngle = CGFloat.pi / 2 // Upward
        particles.emissionAngleRange = CGFloat.pi / 6
        particles.particleAlpha = 0.6 // Subtle but visible
        particles.particleAlphaRange = 0.25
        particles.particleAlphaSpeed = -0.12
        particles.particleScale = 0.55 // Moderate size
        particles.particleScaleRange = 0.3
        particles.particleScaleSpeed = -0.08
        particles.particleColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        particles.particleColorBlendFactor = 1.0
        particles.particleColorSequence = nil
        particles.particleBlendMode = .add
        particles.position = CGPoint(x: size.width / 2, y: -20) // Bottom center for fire effect
        particles.zPosition = -1
        particles.name = "successParticles"

        // Add sparkling effect
        let sparkle = SKAction.sequence([
            SKAction.run {
                particles.particleColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
            },
            SKAction.wait(forDuration: 0.3),
            SKAction.run {
                particles.particleColor = UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1.0)
            },
            SKAction.wait(forDuration: 0.3)
        ])
        particles.run(SKAction.repeatForever(sparkle))

        addChild(particles)
    }
}
