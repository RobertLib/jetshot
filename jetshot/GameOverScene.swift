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
        backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)

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
        // Add red warning particles in background
        addWarningParticles()

        // Main panel background with rounded corners and glow
        let panelWidth: CGFloat = min(size.width - 60, 350)
        let panelHeight: CGFloat = 420
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 25)
        panel.fillColor = UIColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 0.95)
        panel.strokeColor = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0) // Red border for game over
        panel.lineWidth = 4
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.alpha = 0

        // Add outer glow effect
        if let glowPanel = panel.copy() as? SKShapeNode {
            glowPanel.fillColor = .clear
            glowPanel.strokeColor = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.5)
            glowPanel.lineWidth = 8
            glowPanel.setScale(1.02)
            glowPanel.alpha = 0
            addChild(glowPanel)

            // Pulse animation for glow
            glowPanel.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.6),
                SKAction.fadeIn(withDuration: 0.4),
                SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.3, duration: 1.0),
                    SKAction.fadeAlpha(to: 0.7, duration: 1.0)
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

        // Better spacing for proper layout
        let spacing: CGFloat = 60

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
                SKAction.fadeIn(withDuration: 0.3),
                SKAction.sequence([
                    SKAction.scale(to: 0.9, duration: 0.15),
                    SKAction.scale(to: 0.8, duration: 0.15)
                ]),
                SKAction.sequence([
                    SKAction.rotate(byAngle: 0.2, duration: 0.1),
                    SKAction.rotate(byAngle: -0.4, duration: 0.1),
                    SKAction.rotate(byAngle: 0.2, duration: 0.1)
                ])
            ])
        ]))

        // "LEVEL FAILED" title - more space from icon
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "LEVEL FAILED"
        title.fontSize = 28
        title.fontColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        title.position = CGPoint(x: 0, y: defeatIcon.position.y - spacing - 10)
        title.alpha = 0
        panel.addChild(title)

        // Animated title entrance
        title.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.5),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.3),
                SKAction.sequence([
                    SKAction.scale(to: 1.2, duration: 0.2),
                    SKAction.scale(to: 1.0, duration: 0.2)
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
                SKAction.fadeIn(withDuration: 0.3),
                SKAction.moveBy(x: 0, y: 10, duration: 0.3)
            ])
        ]))

        // Buttons with better spacing and animation
        setupButtons(on: panel, panelHeight: panelHeight)
    }

    private func createScoreDisplay() -> SKNode {
        let container = SKNode()

        // Background box with gradient effect
        let box = SKShapeNode(rectOf: CGSize(width: 200, height: 80), cornerRadius: 15)
        box.fillColor = UIColor(red: 0.15, green: 0.2, blue: 0.3, alpha: 1.0)
        box.strokeColor = UIColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 1.0)
        box.lineWidth = 3
        container.addChild(box)

        // Inner highlight
        let highlight = SKShapeNode(rectOf: CGSize(width: 196, height: 76), cornerRadius: 13)
        highlight.fillColor = .clear
        highlight.strokeColor = UIColor(white: 1.0, alpha: 0.15)
        highlight.lineWidth = 2
        highlight.position = CGPoint(x: 0, y: 2)
        container.addChild(highlight)

        // Score label "SCORE" with icon
        let scoreLabel = SKLabelNode(fontNamed: "Arial")
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.text = "SCORE"
        scoreLabel.fontSize = 16
        scoreLabel.fontColor = UIColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 1.0)
        scoreLabel.position = CGPoint(x: 0, y: 16)
        container.addChild(scoreLabel)

        // Score value with glow
        let scoreValueShadow = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreValueShadow.horizontalAlignmentMode = .center
        scoreValueShadow.verticalAlignmentMode = .center
        scoreValueShadow.text = "\(finalScore)"
        scoreValueShadow.fontSize = 28
        scoreValueShadow.fontColor = UIColor(red: 1.0, green: 0.7, blue: 0.0, alpha: 0.6)
        scoreValueShadow.position = CGPoint(x: 0, y: -13)
        scoreValueShadow.setScale(1.1)
        container.addChild(scoreValueShadow)

        // Pulse glow
        scoreValueShadow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 1.0),
            SKAction.fadeAlpha(to: 0.7, duration: 1.0)
        ])))

        let scoreValue = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreValue.horizontalAlignmentMode = .center
        scoreValue.verticalAlignmentMode = .center
        scoreValue.text = "\(finalScore)"
        scoreValue.fontSize = 28
        scoreValue.fontColor = UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        scoreValue.position = CGPoint(x: 0, y: -13)
        container.addChild(scoreValue)

        return container
    }

    private func setupButtons(on panel: SKShapeNode, panelHeight: CGFloat) {
        let buttonY: CGFloat = -panelHeight / 2 + 125

        // Retry button
        let retryButton = createStyledButton(
            text: "RETRY",
            color: UIColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1.0),
            width: 260,
            name: "retryButton"
        )
        retryButton.position = CGPoint(x: 0, y: buttonY)
        retryButton.alpha = 0
        panel.addChild(retryButton)

        retryButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.9),
            SKAction.fadeIn(withDuration: 0.3)
        ]))

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
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeIn(withDuration: 0.3)
        ]))

        menuButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.1),
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
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 2
        button.addChild(label)

        return button
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        if let nodeName = touchedNode.name ?? touchedNode.parent?.name {
            switch nodeName {
            case "retryButton":
                HapticManager.shared.lightTap()
                handleRetryButton()
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

    private func handleRetryButton() {
        SoundManager.shared.playShoot()

        // Button press animation
        if let retryButton = childNode(withName: "//retryButton") as? SKShapeNode {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            retryButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.restartGame()
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
        // Red warning particles floating in background - fire effect from bottom
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

        particles.particleBirthRate = 18 // Moderate density
        particles.particleLifetime = 4.5
        particles.particleLifetimeRange = 2.0
        particles.particlePositionRange = CGVector(dx: size.width * 1.2, dy: 0) // Cover full width
        particles.particleSpeed = 35
        particles.particleSpeedRange = 25
        particles.emissionAngle = CGFloat.pi / 2 // Upward
        particles.emissionAngleRange = CGFloat.pi / 4
        particles.particleAlpha = 0.5 // Subtle but visible
        particles.particleAlphaRange = 0.25
        particles.particleAlphaSpeed = -0.12
        particles.particleScale = 0.5 // Moderate size
        particles.particleScaleRange = 0.25
        particles.particleScaleSpeed = -0.08
        particles.particleColor = UIColor(red: 1.0, green: 0.3, blue: 0.2, alpha: 1.0)
        particles.particleColorBlendFactor = 1.0
        particles.particleBlendMode = .add
        particles.position = CGPoint(x: size.width / 2, y: -20) // Center bottom
        particles.zPosition = -1
        particles.name = "warningParticles"
        addChild(particles)
    }
}
