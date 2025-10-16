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
    private var isInitialized = false

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)

        addChild(StarfieldHelper.createStarfield(for: self))
        setupTitle()
        setupStartButton()
        isInitialized = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized else { return }

        // Remove and recreate all elements
        removeAllChildren()

        addChild(StarfieldHelper.createStarfield(for: self))
        setupTitle()
        setupStartButton()
    }

    private func setupTitle() {
        // Main title
        titleLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        titleLabel.text = "JETSHOT"
        titleLabel.fontSize = 64
        titleLabel.fontColor = .cyan
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 70)

        // Add glow effect
        titleLabel.run(SKAction.repeatForever(
            SKAction.sequence([
                SKAction.fadeAlpha(to: 0.7, duration: 1.0),
                SKAction.fadeAlpha(to: 1.0, duration: 1.0)
            ])
        ))

        addChild(titleLabel)

        // Subtitle
        let subtitleLabel = SKLabelNode(fontNamed: "Arial")
        subtitleLabel.text = "Space Shooter"
        subtitleLabel.fontSize = 24
        subtitleLabel.fontColor = .white
        subtitleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 20)
        addChild(subtitleLabel)
    }

    private func setupStartButton() {
        // Button background
        let buttonWidth: CGFloat = 160
        let buttonHeight: CGFloat = 50

        startButton = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 12)
        startButton.fillColor = .cyan
        startButton.strokeColor = UIColor(red: 0.6, green: 1.0, blue: 1.0, alpha: 1.0) // Lighter cyan for border
        startButton.lineWidth = 3
        startButton.position = CGPoint(x: size.width / 2, y: size.height / 2 - 62.5)
        startButton.name = "startButton"

        // Pulse animation
        let scaleUp = SKAction.scale(to: 1.1, duration: 0.8)
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.8)
        startButton.run(SKAction.repeatForever(SKAction.sequence([scaleUp, scaleDown])))

        addChild(startButton)

        // Button label
        startButtonLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        startButtonLabel.text = "START"
        startButtonLabel.fontSize = 28
        startButtonLabel.fontColor = .black
        startButtonLabel.verticalAlignmentMode = .center
        startButtonLabel.position = CGPoint(x: 0, y: 0)
        startButton.addChild(startButtonLabel)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNodes = nodes(at: location)

        // Check if start button was tapped
        if touchedNodes.contains(where: { $0.name == "startButton" }) {
            HapticManager.shared.lightTap()
            startGame()
        }
    }

    private func startGame() {
        // Play sound
        SoundManager.shared.playShoot()

        // Button press animation
        let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
        startButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
            self?.transitionToGame()
        }
    }

    private func transitionToGame() {
        // Go to level select screen instead of directly to game
        let levelSelectScene = LevelSelectScene(size: size)
        levelSelectScene.scaleMode = scaleMode

        // Transition with animation
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(levelSelectScene, transition: transition)
    }
}
