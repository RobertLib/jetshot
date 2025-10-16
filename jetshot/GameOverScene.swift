//
//  GameOverScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

class GameOverScene: SKScene {

    private let finalScore: Int

    init(size: CGSize, score: Int) {
        self.finalScore = score
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)

        addChild(StarfieldHelper.createStarfield(for: self))
        setupUI()
    }

    private func setupUI() {
        // Main panel background with rounded corners
        let panelWidth: CGFloat = min(size.width - 60, 350)
        let panelHeight: CGFloat = 420
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 25)
        panel.fillColor = UIColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 0.95)
        panel.strokeColor = UIColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1.0)
        panel.lineWidth = 4
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.alpha = 0
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

        // Spacing: 80px from top to icon, 57px between elements
        let spacing: CGFloat = 57

        // Sad face icon
        let sadIcon = SKLabelNode(fontNamed: "Arial-BoldMT")
        sadIcon.text = "😞"
        sadIcon.fontSize = 60
        sadIcon.position = CGPoint(x: 0, y: panelHeight / 2 - 80)
        sadIcon.alpha = 0
        panel.addChild(sadIcon)

        // Animated icon entrance
        sadIcon.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.4),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.3),
                SKAction.sequence([
                    SKAction.scale(to: 1.2, duration: 0.2),
                    SKAction.scale(to: 1.0, duration: 0.2)
                ])
            ])
        ]))

        // "LEVEL FAILED" title
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "LEVEL FAILED"
        title.fontSize = 28
        title.fontColor = UIColor(red: 0.9, green: 0.75, blue: 0.3, alpha: 1.0)
        title.position = CGPoint(x: 0, y: sadIcon.position.y - spacing + 5)
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
        scoreContainer.position = CGPoint(x: 0, y: title.position.y - spacing - 20)
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

        // Background box
        let box = SKShapeNode(rectOf: CGSize(width: 200, height: 80), cornerRadius: 15)
        box.fillColor = UIColor(red: 0.15, green: 0.2, blue: 0.3, alpha: 1.0)
        box.strokeColor = UIColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1.0)
        box.lineWidth = 2
        container.addChild(box)

        // Score label "SCORE"
        let scoreLabel = SKLabelNode(fontNamed: "Arial")
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.text = "SCORE"
        scoreLabel.fontSize = 16
        scoreLabel.fontColor = UIColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 1.0)
        scoreLabel.position = CGPoint(x: 0, y: 14)
        container.addChild(scoreLabel)

        // Score value
        let scoreValue = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreValue.horizontalAlignmentMode = .center
        scoreValue.verticalAlignmentMode = .center
        scoreValue.text = "\(finalScore)"
        scoreValue.fontSize = 28
        scoreValue.fontColor = UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        scoreValue.position = CGPoint(x: 0, y: -14)
        container.addChild(scoreValue)

        return container
    }

    private func setupButtons(on panel: SKShapeNode, panelHeight: CGFloat) {
        let buttonY: CGFloat = -panelHeight / 2 + 120

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

        // Menu button
        let menuButton = createStyledButton(
            text: "MENU",
            color: UIColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1.0),
            width: 260,
            name: "menuButton"
        )
        menuButton.position = CGPoint(x: 0, y: buttonY - 65)
        menuButton.alpha = 0
        panel.addChild(menuButton)

        menuButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
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

        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = text
        label.fontSize = 20
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        button.addChild(label)

        return button
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNodes = nodes(at: location)

        if touchedNodes.contains(where: { $0.name == "retryButton" }) {
            handleRetryButton()
        } else if touchedNodes.contains(where: { $0.name == "menuButton" }) {
            handleMenuButton()
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

    private func handleMenuButton() {
        SoundManager.shared.playShoot()

        // Button press animation
        if let menuButton = childNode(withName: "//menuButton") as? SKShapeNode {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            menuButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.returnToMenu()
            }
        }
    }

    private func restartGame() {
        let gameScene = GameScene(size: size)
        gameScene.scaleMode = .aspectFill

        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(gameScene, transition: transition)
    }

    private func returnToMenu() {
        let menuScene = MenuScene(size: size)
        menuScene.scaleMode = .aspectFill

        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(menuScene, transition: transition)
    }
}
