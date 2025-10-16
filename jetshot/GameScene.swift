//
//  GameScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import SpriteKit
import GameplayKit

// Physics categories for collision detection
struct PhysicsCategory {
    static let none: UInt32 = 0
    static let player: UInt32 = 0b1        // 1
    static let bullet: UInt32 = 0b10       // 2
    static let enemy: UInt32 = 0b100       // 4
    static let enemyBullet: UInt32 = 0b1000 // 8
    static let obstacle: UInt32 = 0b10000  // 16
    static let powerUp: UInt32 = 0b100000  // 32
}

class GameScene: SKScene, SKPhysicsContactDelegate {

    // Level system
    var currentLevel: Int = 1
    private var levelConfig: LevelConfig!

    // Game objects
    private var player: Player!
    private var enemyManager: EnemyManager!
    private var obstacleManager: ObstacleManager!
    private var powerUpManager: PowerUpManager!
    private var scoreLabel: SKLabelNode!
    private var score: Int = 0 {
        didSet {
            scoreLabel.text = "Score: \(score)"
        }
    }

    // Level completion tracking
    private var noEnemiesTime: TimeInterval?
    private let levelCompletionDelay: TimeInterval = 2.0 // Complete level 2 seconds after last enemy disappears

    // Lives system
    private var lives: Int = 3 {
        didSet {
            updateLivesDisplay(topMargin: currentTopMargin)
        }
    }
    private var livesNodes: [SKShapeNode] = []
    private var currentTopMargin: CGFloat = 50
    private var isInvulnerable: Bool = false
    private let invulnerabilityDuration: TimeInterval = 2.0

    // Timers
    private var lastUpdateTime: TimeInterval = 0
    private var lastShootTime: TimeInterval = 0
    private let shootInterval: TimeInterval = 0.3

    // Touch tracking
    private var isTouching = false
    private var touchLocation: CGPoint = .zero
    private let shootDistanceThreshold: CGFloat = 50 // Distance within which shooting is allowed

    // Pause system
    private var isGamePaused: Bool = false
    private var pauseButton: SKShapeNode!
    private var pauseOverlay: SKNode?
    private var isInitialized = false

    // Level intro
    private var isGameStarted: Bool = false

    override func didMove(to view: SKView) {
        // Setup physics
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        // Dark background for better glow contrast
        backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.12, alpha: 1.0)

        // Load level configuration
        levelConfig = LevelManager.shared.getLevelConfig(for: currentLevel)

        addChild(StarfieldHelper.createStarfield(for: self))
        setupPlayer(view: view)
        setupEnemyManager()
        setupObstacleManager()
        setupPowerUpManager()
        setupUI(view: view)
        isInitialized = true

        // Pause the game and show level intro
        isPaused = true
        showLevelIntro()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized, let view = view else { return }

        // Get safe area bottom inset
        let safeAreaBottom: CGFloat
        if let windowScene = view.window?.windowScene {
            safeAreaBottom = windowScene.windows.first?.safeAreaInsets.bottom ?? 0
        } else {
            safeAreaBottom = 0
        }

        // Update player bounds
        player.updateBounds(sceneSize: size, safeAreaBottom: safeAreaBottom)

        // Reposition UI elements
        setupUI(view: view)

        // Update starfield position and size
        if let starfield = childNode(withName: "starfield") as? SKEmitterNode {
            StarfieldHelper.updateStarfield(starfield, for: self)
        }

        // Update pause overlay if it exists
        if let overlay = pauseOverlay {
            overlay.removeFromParent()
            pauseOverlay = nil
            if isGamePaused {
                showPauseOverlay()
            }
        }
    }

    private func setupPlayer(view: SKView) {
        // Get safe area bottom inset
        let safeAreaBottom: CGFloat
        if let windowScene = view.window?.windowScene {
            safeAreaBottom = windowScene.windows.first?.safeAreaInsets.bottom ?? 0
        } else {
            safeAreaBottom = 0
        }

        player = Player(sceneSize: size, safeAreaBottom: safeAreaBottom)
        addChild(player)
    }

    private func setupEnemyManager() {
        enemyManager = EnemyManager(scene: self, waves: levelConfig.waves)
    }

    private func setupObstacleManager() {
        obstacleManager = ObstacleManager(scene: self, waves: levelConfig.obstacleWaves)
    }

    private func setupPowerUpManager() {
        powerUpManager = PowerUpManager(scene: self, config: levelConfig.powerUpConfig)
    }

    private func setupUI(view: SKView) {
        // Remove old UI elements if they exist
        scoreLabel?.removeFromParent()
        pauseButton?.removeFromParent()
        livesNodes.forEach { $0.removeFromParent() }
        livesNodes.removeAll()

        scoreLabel = SKLabelNode(fontNamed: "Arial")
        scoreLabel.fontSize = 24
        scoreLabel.fontColor = .white
        scoreLabel.verticalAlignmentMode = .center

        // Calculate safe area top inset
        let safeAreaTop: CGFloat
        if let windowScene = view.window?.windowScene {
            safeAreaTop = windowScene.windows.first?.safeAreaInsets.top ?? 0
        } else {
            safeAreaTop = 0
        }

        // Calculate consistent top margin for all UI elements
        // On iPhone with safe area (Dynamic Island), this will be safe area + 30
        // On iPad/Mac with no/small safe area, this ensures minimum 50 points from top
        let topMargin = max(safeAreaTop + 20, 40)

        // Position label below safe area - centered vertically with hearts and button
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height - topMargin)
        scoreLabel.text = "Score: \(score)"
        scoreLabel.zPosition = 100
        addChild(scoreLabel)

        // Setup lives display (same height as score)
        updateLivesDisplay(topMargin: topMargin)

        // Setup pause button (same height as score)
        setupPauseButton(topMargin: topMargin)
    }

    private func updateLivesDisplay(topMargin: CGFloat) {
        // Store current top margin for future updates
        currentTopMargin = topMargin

        // Remove old lives display
        livesNodes.forEach { $0.removeFromParent() }
        livesNodes.removeAll()

        // Create detailed player ship shapes for each life
        let shipSize: CGFloat = 22
        let spacing: CGFloat = 6
        let leftMargin: CGFloat = 20

        // Position ships at the same height as score label and pause button
        for i in 0..<max(0, lives) {
            let ship = createDetailedPlayerShip(size: shipSize)
            ship.position = CGPoint(x: leftMargin + shipSize / 2 + CGFloat(i) * (shipSize + spacing),
                                    y: size.height - topMargin)
            ship.zPosition = 100
            addChild(ship)
            livesNodes.append(ship)
        }
    }

    private func createPlayerShip(size: CGFloat) -> SKShapeNode {
        // Simplified version for compatibility
        return createDetailedPlayerShip(size: size)
    }

    private func createDetailedPlayerShip(size: CGFloat) -> SKShapeNode {
        // Create detailed spaceship matching the player's design
        let scale = size / 36.0 // Scale to match desired size

        let path = CGMutablePath()

        // Main fuselage (center) - scaled version of player ship
        path.move(to: CGPoint(x: 0, y: 18 * scale))
        path.addLine(to: CGPoint(x: -5 * scale, y: 8 * scale))
        path.addLine(to: CGPoint(x: -4 * scale, y: -2 * scale))

        // Left wing
        path.addLine(to: CGPoint(x: -12 * scale, y: -8 * scale))
        path.addLine(to: CGPoint(x: -10 * scale, y: -12 * scale))
        path.addLine(to: CGPoint(x: -5 * scale, y: -10 * scale))

        // Back left engine
        path.addLine(to: CGPoint(x: -6 * scale, y: -18 * scale))
        path.addLine(to: CGPoint(x: -3 * scale, y: -18 * scale))
        path.addLine(to: CGPoint(x: -3 * scale, y: -10 * scale))

        // Center back
        path.addLine(to: CGPoint(x: 0, y: -8 * scale))
        path.addLine(to: CGPoint(x: 3 * scale, y: -10 * scale))

        // Back right engine
        path.addLine(to: CGPoint(x: 3 * scale, y: -18 * scale))
        path.addLine(to: CGPoint(x: 6 * scale, y: -18 * scale))
        path.addLine(to: CGPoint(x: 5 * scale, y: -10 * scale))

        // Right wing
        path.addLine(to: CGPoint(x: 10 * scale, y: -12 * scale))
        path.addLine(to: CGPoint(x: 12 * scale, y: -8 * scale))
        path.addLine(to: CGPoint(x: 4 * scale, y: -2 * scale))

        // Right fuselage
        path.addLine(to: CGPoint(x: 5 * scale, y: 8 * scale))

        path.closeSubpath()

        let ship = SKShapeNode(path: path)
        ship.fillColor = UIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)
        ship.strokeColor = UIColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 1.0)
        ship.lineWidth = 1.5

        // Add cockpit detail
        let cockpit = SKShapeNode(circleOfRadius: 2 * scale)
        cockpit.fillColor = UIColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.9)
        cockpit.strokeColor = .clear
        cockpit.position = CGPoint(x: 0, y: 8 * scale)
        ship.addChild(cockpit)

        return ship
    }

    private func showLevelIntro() {
        let introNode = SKNode()
        introNode.zPosition = 2000
        introNode.speed = 1.0 // Always animate at normal speed even when scene is paused
        introNode.name = "levelIntro"

        // Semi-transparent background
        let background = SKSpriteNode(color: UIColor(white: 0, alpha: 0.85), size: size)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        introNode.addChild(background)

        // Level number label
        let levelLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        levelLabel.text = "LEVEL \(currentLevel)"
        levelLabel.fontSize = 44
        levelLabel.fontColor = .white
        levelLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        levelLabel.alpha = 0
        levelLabel.setScale(0.5)
        introNode.addChild(levelLabel)

        addChild(introNode)

        // Animation sequence
        let fadeIn = SKAction.fadeIn(withDuration: 0.4)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.4)
        let appear = SKAction.group([fadeIn, scaleUp])

        let wait = SKAction.wait(forDuration: 1.5)

        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let scaleDown = SKAction.scale(to: 1.2, duration: 0.3)
        let disappear = SKAction.group([fadeOut, scaleDown])

        let startGame = SKAction.run { [weak self] in
            self?.startGame()
        }

        let remove = SKAction.removeFromParent()

        let sequence = SKAction.sequence([appear, wait, disappear, startGame, remove])
        levelLabel.run(sequence)

        // Fade out background
        let backgroundFade = SKAction.sequence([
            SKAction.wait(forDuration: 2.2),
            SKAction.fadeOut(withDuration: 0.3)
        ])
        background.run(backgroundFade)
    }

    private func startGame() {
        isGameStarted = true
        isPaused = false
    }

    private func setupPauseButton(topMargin: CGFloat) {
        // Create enhanced pause button
        let buttonSize: CGFloat = 44
        let pauseButton = SKShapeNode(rectOf: CGSize(width: buttonSize, height: buttonSize), cornerRadius: 10)
        let fillColor = UIColor(red: 0.15, green: 0.25, blue: 0.35, alpha: 0.9)
        pauseButton.fillColor = fillColor
        pauseButton.strokeColor = UIColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1.0)
        pauseButton.lineWidth = 3
        pauseButton.name = "pauseButton"

        // Position at the same height as hearts and score
        let rightMargin: CGFloat = 28
        pauseButton.position = CGPoint(x: size.width - rightMargin - 10, y: size.height - topMargin)
        pauseButton.zPosition = 100
        addChild(pauseButton)

        // Add inner border for depth
        let innerBorder = SKShapeNode(rectOf: CGSize(width: buttonSize - 6, height: buttonSize - 6), cornerRadius: 8)
        innerBorder.fillColor = .clear
        innerBorder.strokeColor = UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 0.3)
        innerBorder.lineWidth = 1.5
        pauseButton.addChild(innerBorder)

        // Add enhanced pause icon (two vertical bars with rounded ends)
        let barWidth: CGFloat = 6
        let barHeight: CGFloat = 18
        let barSpacing: CGFloat = 7

        let leftBar = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        leftBar.fillColor = UIColor(red: 0.8, green: 0.95, blue: 1.0, alpha: 1.0)
        leftBar.strokeColor = UIColor(red: 0.5, green: 0.9, blue: 1.0, alpha: 1.0)
        leftBar.lineWidth = 1
        leftBar.position = CGPoint(x: -barSpacing / 2, y: 0)
        pauseButton.addChild(leftBar)

        let rightBar = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        rightBar.fillColor = UIColor(red: 0.8, green: 0.95, blue: 1.0, alpha: 1.0)
        rightBar.strokeColor = UIColor(red: 0.5, green: 0.9, blue: 1.0, alpha: 1.0)
        rightBar.lineWidth = 1
        rightBar.position = CGPoint(x: barSpacing / 2, y: 0)
        pauseButton.addChild(rightBar)

        // Add subtle glow
        GlowHelper.addEnhancedGlow(to: pauseButton, color: UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0), intensity: 0.5)

        self.pauseButton = pauseButton
    }

    private func showPauseOverlay() {
        guard pauseOverlay == nil else { return }

        let overlay = SKNode()
        overlay.zPosition = 1000
        overlay.speed = 1.0 // Always animate at normal speed even when scene is paused

        // Semi-transparent background
        let background = SKSpriteNode(color: UIColor(white: 0, alpha: 0), size: size)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        background.name = "pauseOverlayBackground"
        overlay.addChild(background)

        // Fade in background
        background.run(SKAction.fadeAlpha(to: 0.7, duration: 0.3))

        // Pause panel - increased height to accommodate retry button
        let panelWidth: CGFloat = min(size.width - 60, 300)
        let panelHeight: CGFloat = 350
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 25)
        panel.fillColor = UIColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 0.95)
        panel.strokeColor = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0) // Brighter cyan border
        panel.lineWidth = 4
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.alpha = 0
        panel.setScale(0.8)

        // Add outer glow effect for pause panel
        let glowPanel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 25)
        glowPanel.fillColor = .clear
        glowPanel.strokeColor = UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.5)
        glowPanel.lineWidth = 8
        glowPanel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        glowPanel.setScale(0.82)
        glowPanel.alpha = 0
        overlay.addChild(glowPanel)

        overlay.addChild(panel)

        // Animate panel entrance - same as GameOverScene
        let panelAnimation = SKAction.sequence([
            SKAction.wait(forDuration: 0.2),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.4),
                SKAction.scale(to: 1.0, duration: 0.4)
            ])
        ])
        panel.run(panelAnimation)
        glowPanel.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.2),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.4),
                SKAction.scale(to: 1.02, duration: 0.4)
            ]),
            SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.3, duration: 1.0),
                SKAction.fadeAlpha(to: 0.6, duration: 1.0)
            ]))
        ]))

        // "PAUSED" title - simple and clean
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "PAUSED"
        title.fontSize = 36
        title.fontColor = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
        title.position = CGPoint(x: 0, y: panelHeight / 2 - 50)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        panel.addChild(title)

        // Level info
        let levelInfo = SKLabelNode(fontNamed: "Arial")
        levelInfo.text = "Level \(currentLevel)"
        levelInfo.fontSize = 22
        levelInfo.fontColor = UIColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0)
        levelInfo.position = CGPoint(x: 0, y: panelHeight / 2 - 90)
        levelInfo.horizontalAlignmentMode = .center
        levelInfo.verticalAlignmentMode = .center
        panel.addChild(levelInfo)

        // Resume button
        let resumeButton = createPauseMenuButton(
            text: "RESUME",
            color: UIColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1.0),
            width: 220,
            name: "resumeButton"
        )
        resumeButton.position = CGPoint(x: 0, y: 23)
        panel.addChild(resumeButton)

        // Retry button
        let retryButton = createPauseMenuButton(
            text: "RETRY",
            color: UIColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1.0),
            width: 220,
            name: "pauseRetryButton"
        )
        retryButton.position = CGPoint(x: 0, y: -42)
        panel.addChild(retryButton)

        // Secondary buttons container
        let secondaryButtonY: CGFloat = -107

        let levelsButton = createPauseMenuButton(
            text: "LEVELS",
            color: UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0),
            width: 105,
            name: "pauseLevelsButton"
        )
        levelsButton.position = CGPoint(x: -57, y: secondaryButtonY)
        panel.addChild(levelsButton)

        let menuButton = createPauseMenuButton(
            text: "MENU",
            color: UIColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1.0),
            width: 105,
            name: "pauseMenuButton"
        )
        menuButton.position = CGPoint(x: 57, y: secondaryButtonY)
        panel.addChild(menuButton)

        pauseOverlay = overlay
        addChild(overlay)
    }

    private func createPauseMenuButton(text: String, color: UIColor, width: CGFloat, name: String) -> SKShapeNode {
        let button = SKShapeNode(rectOf: CGSize(width: width, height: 50), cornerRadius: 12)
        button.fillColor = color

        // Calculate lighter border color based on fill color
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        button.strokeColor = UIColor(hue: hue, saturation: max(0, saturation - 0.2), brightness: min(1, brightness + 0.3), alpha: alpha)

        button.lineWidth = 3
        button.name = name

        // Add shadow effect
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
        label.name = name // Set name on label too for easier touch detection
        label.zPosition = 2
        button.addChild(label)

        return button
    }

    private func hidePauseOverlay() {
        guard let overlay = pauseOverlay else { return }

        // Animate panel exit - just fade out, no scaling to avoid position change
        overlay.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))

        pauseOverlay = nil
    }

    private func handleResumeButton() {
        // Play sound
        SoundManager.shared.playShoot()

        // Button press animation
        if let resumeButton = pauseOverlay?.childNode(withName: "//resumeButton") as? SKShapeNode {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            resumeButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.togglePause()
            }
        }
    }

    private func handlePauseRetryButton() {
        // Play sound
        SoundManager.shared.playShoot()

        // Button press animation
        if let retryButton = pauseOverlay?.childNode(withName: "//pauseRetryButton") as? SKShapeNode {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            retryButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.restartGame()
            }
        }
    }

    private func handlePauseLevelsButton() {
        // Play sound
        SoundManager.shared.playShoot()

        // Button press animation
        if let levelsButton = pauseOverlay?.childNode(withName: "//pauseLevelsButton") as? SKShapeNode {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            levelsButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.goToLevelSelect()
            }
        }
    }

    private func handlePauseMenuButton() {
        // Play sound
        SoundManager.shared.playShoot()

        // Button press animation
        if let menuButton = pauseOverlay?.childNode(withName: "//pauseMenuButton") as? SKShapeNode {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            menuButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.goToMenu()
            }
        }
    }

    private func goToMenu() {
        let menuScene = MenuScene(size: size)
        menuScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(menuScene, transition: transition)
    }

    private func restartGame() {
        let gameScene = GameScene(size: size)
        gameScene.currentLevel = currentLevel
        gameScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(gameScene, transition: transition)
    }

    private func togglePause() {
        isGamePaused.toggle()

        if isGamePaused {
            enemyManager.pauseSpawning()
            obstacleManager.pause()
            powerUpManager.pause()
            // Pause physics
            physicsWorld.speed = 0
            // Pause all gameplay nodes but not the overlay
            enumerateChildNodes(withName: "//*") { node, _ in
                if node != self.pauseOverlay {
                    node.isPaused = true
                }
            }
            // Pause enemy shooting
            enumerateChildNodes(withName: "enemy") { node, _ in
                if let enemy = node as? Enemy {
                    enemy.pauseShooting()
                }
            }
            showPauseOverlay()
        } else {
            // Resume physics
            physicsWorld.speed = 1
            // Resume all nodes
            enumerateChildNodes(withName: "//*") { node, _ in
                node.isPaused = false
            }
            // Resume enemy shooting
            enumerateChildNodes(withName: "enemy") { node, _ in
                if let enemy = node as? Enemy {
                    enemy.resumeShooting()
                }
            }
            enemyManager.resumeSpawning()
            obstacleManager.resume()
            powerUpManager.resume()
            hidePauseOverlay()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check if pause button was tapped (only when game has started)
        let nodesAtPoint = nodes(at: location)

        // First check for interactive elements (buttons)
        for node in nodesAtPoint {
            if isGameStarted && (node.name == "pauseButton" || node.parent?.name == "pauseButton") {
                HapticManager.shared.lightTap()
                togglePause()
                return
            }

            // Check pause overlay buttons
            if isGamePaused {
                if node.name == "resumeButton" || node.parent?.name == "resumeButton" {
                    HapticManager.shared.lightTap()
                    handleResumeButton()
                    return
                }
                if node.name == "pauseRetryButton" || node.parent?.name == "pauseRetryButton" {
                    HapticManager.shared.lightTap()
                    handlePauseRetryButton()
                    return
                }
                if node.name == "pauseLevelsButton" || node.parent?.name == "pauseLevelsButton" {
                    HapticManager.shared.lightTap()
                    handlePauseLevelsButton()
                    return
                }
                if node.name == "pauseMenuButton" || node.parent?.name == "pauseMenuButton" {
                    HapticManager.shared.lightTap()
                    handlePauseMenuButton()
                    return
                }
            }
        }

        // If paused and no button was clicked, check if background overlay was tapped (close menu)
        // Only close if we clicked directly on background, not on panel or its children
        if isGamePaused {
            let topNode = nodesAtPoint.first
            if topNode?.name == "pauseOverlayBackground" {
                HapticManager.shared.lightTap()
                togglePause()
                return
            }
        }

        // Don't handle game touches when paused or game hasn't started
        if isGamePaused || !isGameStarted { return }

        isTouching = true
        touchLocation = location

        // Move player to touch location with animation
        player.moveTo(x: location.x, sceneWidth: size.width)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused or game hasn't started
        if isGamePaused || !isGameStarted { return }

        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        isTouching = true
        touchLocation = location

        // Move player instantly to follow touch smoothly
        player.moveToInstant(x: location.x, sceneWidth: size.width)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused or game hasn't started
        if isGamePaused || !isGameStarted { return }
        isTouching = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused or game hasn't started
        if isGamePaused || !isGameStarted { return }
        isTouching = false
    }

    private func shoot() {
        let bullets = player.shoot()

        for bullet in bullets {
            addChild(bullet)

            // Move bullet upwards
            let moveAction = SKAction.moveTo(y: size.height + 20, duration: 1.5)
            let removeAction = SKAction.removeFromParent()
            bullet.run(SKAction.sequence([moveAction, removeAction]))
        }

        // Shoot missiles if available
        if player.sideMissileCount > 0 {
            for i in 0..<player.sideMissileCount {
                let side = i == 0 ? -1 : 1
                let missile = player.shootMissile(side: side)
                addChild(missile)

                // Move missile upwards
                let moveAction = SKAction.moveTo(y: size.height + 20, duration: 1.2)
                let removeAction = SKAction.removeFromParent()
                missile.run(SKAction.sequence([moveAction, removeAction]))
            }
        }

        // Play shoot sound
        SoundManager.shared.playShoot()
    }

    // Collision detection
    func didBegin(_ contact: SKPhysicsContact) {
        let firstBody: SKPhysicsBody
        let secondBody: SKPhysicsBody

        if contact.bodyA.categoryBitMask < contact.bodyB.categoryBitMask {
            firstBody = contact.bodyA
            secondBody = contact.bodyB
        } else {
            firstBody = contact.bodyB
            secondBody = contact.bodyA
        }

        // Bullet hit enemy
        if firstBody.categoryBitMask == PhysicsCategory.bullet &&
           secondBody.categoryBitMask == PhysicsCategory.enemy {
            bulletDidCollideWithEnemy(bullet: firstBody.node as? SKShapeNode,
                                     enemy: secondBody.node as? Enemy)
        }

        // Player hit enemy
        if firstBody.categoryBitMask == PhysicsCategory.player &&
           secondBody.categoryBitMask == PhysicsCategory.enemy {
            playerDidCollideWithEnemy(enemy: secondBody.node as? Enemy)
        }

        // Player hit enemy bullet
        if firstBody.categoryBitMask == PhysicsCategory.player &&
           secondBody.categoryBitMask == PhysicsCategory.enemyBullet {
            playerDidCollideWithEnemyBullet(bullet: secondBody.node as? SKShapeNode)
        }

        // Player hit obstacle
        if firstBody.categoryBitMask == PhysicsCategory.player &&
           secondBody.categoryBitMask == PhysicsCategory.obstacle {
            playerDidCollideWithObstacle(obstacle: secondBody.node as? Obstacle)
        }

        // Bullet hit obstacle
        if firstBody.categoryBitMask == PhysicsCategory.bullet &&
           secondBody.categoryBitMask == PhysicsCategory.obstacle {
            bulletDidCollideWithObstacle(bullet: firstBody.node as? SKShapeNode)
        }

        // Player hit powerup
        if firstBody.categoryBitMask == PhysicsCategory.player &&
           secondBody.categoryBitMask == PhysicsCategory.powerUp {
            playerDidCollideWithPowerUp(powerUp: secondBody.node as? PowerUp)
        }
    }

    private func bulletDidCollideWithEnemy(bullet: SKShapeNode?, enemy: Enemy?) {
        guard let bullet = bullet, let enemy = enemy else { return }

        bullet.removeFromParent()

        // Decrease enemy health
        enemy.health -= 1

        // Check if enemy is destroyed
        if enemy.health <= 0 {
            // Explosion effect and sound
            createExplosion(at: enemy.position)
            SoundManager.shared.playExplosion()

            // Add score based on enemy type
            score += enemy.enemyType.points

            // Mark enemy as destroyed to prevent completion callback
            enemy.markAsDestroyed()
            enemy.removeFromParent()
        } else {
            // Enemy took damage but is still alive (Tank)
            // Small hit effect without destroying
            createHitEffect(at: enemy.position)
            SoundManager.shared.playHit()

            // Flash effect to show damage
            let flash = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.3, duration: 0.1),
                SKAction.fadeAlpha(to: 1.0, duration: 0.1)
            ])
            enemy.run(flash)
        }
    }

    private func playerDidCollideWithEnemy(enemy: Enemy?) {
        guard let enemy = enemy else { return }

        // Skip if player is invulnerable or has shield
        if isInvulnerable || player.hasShield {
            if player.hasShield {
                // Deactivate shield on hit
                player.hasShield = false
                // Small explosion effect
                createExplosion(at: enemy.position)
                SoundManager.shared.playHit()
            }

            // Mark enemy as destroyed and remove
            enemy.markAsDestroyed()
            enemy.removeFromParent()
            return
        }

        // Explosion effect and sound
        createExplosion(at: enemy.position)
        SoundManager.shared.playHit()

        // Mark enemy as destroyed to prevent completion callback
        enemy.markAsDestroyed()
        enemy.removeFromParent()

        // Lose a life
        lives -= 1

        // Check for game over
        if lives <= 0 {
            gameOver()
            return
        }

        // Reset powerups on life loss
        player.resetPowerUps()

        // Play hit animation and activate invulnerability
        player.playHitAnimation()
        activateInvulnerability()
    }

    private func playerDidCollideWithEnemyBullet(bullet: SKShapeNode?) {
        guard let bullet = bullet else { return }

        // Skip if player is invulnerable or has shield
        if isInvulnerable || player.hasShield {
            if player.hasShield {
                // Deactivate shield on hit
                player.hasShield = false
                // Small explosion effect
                createExplosion(at: bullet.position)
                SoundManager.shared.playHit()
            }
            bullet.removeFromParent()
            return
        }

        // Small explosion effect and sound
        createExplosion(at: bullet.position)
        SoundManager.shared.playHit()
        bullet.removeFromParent()

        // Lose a life
        lives -= 1

        // Check for game over
        if lives <= 0 {
            gameOver()
            return
        }

        // Reset powerups on life loss
        player.resetPowerUps()

        // Play hit animation and activate invulnerability
        player.playHitAnimation()
        activateInvulnerability()
    }

    private func playerDidCollideWithObstacle(obstacle: Obstacle?) {
        guard obstacle != nil else { return }

        // Skip if player is invulnerable or has shield
        if isInvulnerable || player.hasShield {
            if player.hasShield {
                // Deactivate shield on hit
                player.hasShield = false
                // Create explosion effect at player position
                createExplosion(at: player.position)
                SoundManager.shared.playHit()
                HapticManager.shared.heavyTap()
            }
            return
        }

        // Create explosion effect at player position
        createExplosion(at: player.position)
        SoundManager.shared.playHit()
        HapticManager.shared.heavyTap()

        // Lose a life
        lives -= 1

        // Check for game over
        if lives <= 0 {
            gameOver()
            return
        }

        // Reset powerups on life loss
        player.resetPowerUps()

        // Play hit animation and activate invulnerability
        player.playHitAnimation()
        activateInvulnerability()
    }

    private func bulletDidCollideWithObstacle(bullet: SKShapeNode?) {
        guard let bullet = bullet else { return }

        // Simply remove the bullet - no explosion or sound for bullet hitting obstacle
        bullet.removeFromParent()
    }

    private func playerDidCollideWithPowerUp(powerUp: PowerUp?) {
        guard let powerUp = powerUp else { return }

        // Check if already collected (prevent multiple calls)
        if powerUp.physicsBody == nil { return }

        // Immediately disable physics to prevent multiple collisions
        powerUp.physicsBody = nil

        // Play collection sound
        SoundManager.shared.playShoot()

        // Add score for collecting powerup
        score += powerUp.powerUpType.points

        // Apply powerup effect based on type
        switch powerUp.powerUpType {
        case .extraLife:
            if lives < 4 {
                lives += 1
                HapticManager.shared.heavyTap()
            }

        case .multiShot:
            if player.bulletCount < 4 {
                player.bulletCount += 1
                HapticManager.shared.lightTap()
            }

        case .sideMissiles:
            if player.sideMissileCount < 2 {
                player.sideMissileCount += 1
                HapticManager.shared.lightTap()
            }

        case .shield:
            activateShield()
            HapticManager.shared.heavyTap()
        }

        // Animate powerup collection
        powerUp.collect()
    }

    private func activateShield() {
        player.hasShield = true

        // Deactivate shield after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.player.hasShield = false
        }
    }

    private func activateInvulnerability() {
        isInvulnerable = true

        // Blinking animation during invulnerability
        let blink = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.1),
            SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        ])
        let blinkTimes = SKAction.repeat(blink, count: Int(invulnerabilityDuration / 0.2))

        player.run(blinkTimes) { [weak self] in
            self?.isInvulnerable = false
        }
    }

    private func stopGameplayAndTransition(to newScene: SKScene, transitionDuration: TimeInterval = 0.5) {
        // Stop sounds and pause gameplay immediately
        SoundManager.shared.stopAllSounds()
        isPaused = true
        physicsWorld.speed = 0

        // Transition to new scene
        newScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: transitionDuration)
        view?.presentScene(newScene, transition: transition)

        // Clean up after transition completes
        DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration + 0.1) { [weak self] in
            self?.removeAllChildren()
        }
    }

    private func gameOver() {
        let gameOverScene = GameOverScene(size: size, score: score, level: currentLevel)
        stopGameplayAndTransition(to: gameOverScene, transitionDuration: 1.0)
    }

    private func createHitEffect(at position: CGPoint) {
        // Smaller hit effect for when enemy takes damage but isn't destroyed
        let hitContainer = SKNode()
        hitContainer.position = position
        hitContainer.zPosition = 500
        addChild(hitContainer)

        // Small flash
        let flash = SKShapeNode(circleOfRadius: 6)
        flash.fillColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.8)
        flash.strokeColor = .clear
        hitContainer.addChild(flash)

        let flashScale = SKAction.scale(to: 2.0, duration: 0.1)
        let flashFade = SKAction.fadeOut(withDuration: 0.1)
        flash.run(SKAction.group([flashScale, flashFade]))

        // Small sparks
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            let spark = SKShapeNode(circleOfRadius: 2)
            spark.fillColor = UIColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 1.0)
            spark.strokeColor = .clear
            hitContainer.addChild(spark)

            let distance: CGFloat = 15
            let targetX = cos(angle) * distance
            let targetY = sin(angle) * distance

            let move = SKAction.moveBy(x: targetX, y: targetY, duration: 0.2)
            let sparkFade = SKAction.fadeOut(withDuration: 0.2)
            spark.run(SKAction.group([move, sparkFade]))
        }

        // Remove container after animation
        hitContainer.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.3),
            SKAction.removeFromParent()
        ]))
    }

    private func createExplosion(at position: CGPoint) {
        // Enhanced multi-layered explosion effect
        let explosionContainer = SKNode()
        explosionContainer.position = position
        explosionContainer.zPosition = 500
        addChild(explosionContainer)

        // Core flash
        let coreFlash = SKShapeNode(circleOfRadius: 8)
        coreFlash.fillColor = UIColor(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0)
        coreFlash.strokeColor = .clear
        explosionContainer.addChild(coreFlash)

        let coreScale = SKAction.scale(to: 2.5, duration: 0.15)
        let coreFade = SKAction.fadeOut(withDuration: 0.15)
        coreFlash.run(SKAction.group([coreScale, coreFade]))

        // Main explosion ring
        let mainExplosion = SKShapeNode(circleOfRadius: 10)
        mainExplosion.fillColor = UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.9)
        mainExplosion.strokeColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
        mainExplosion.lineWidth = 3
        explosionContainer.addChild(mainExplosion)

        let mainScale = SKAction.scale(to: 4.0, duration: 0.4)
        let mainFade = SKAction.fadeOut(withDuration: 0.4)
        mainExplosion.run(SKAction.group([mainScale, mainFade]))

        // Outer shockwave
        let shockwave = SKShapeNode(circleOfRadius: 15)
        shockwave.fillColor = .clear
        shockwave.strokeColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 0.7)
        shockwave.lineWidth = 4
        explosionContainer.addChild(shockwave)

        let shockScale = SKAction.scale(to: 5.0, duration: 0.5)
        let shockFade = SKAction.fadeOut(withDuration: 0.5)
        shockwave.run(SKAction.group([shockScale, shockFade]))

        // Add explosion particles (debris)
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4
            let particle = SKShapeNode(circleOfRadius: 3)
            particle.fillColor = UIColor(red: 1.0, green: CGFloat.random(in: 0.3...0.8), blue: 0.0, alpha: 1.0)
            particle.strokeColor = .clear
            explosionContainer.addChild(particle)

            let distance: CGFloat = 40
            let targetX = cos(angle) * distance
            let targetY = sin(angle) * distance

            let move = SKAction.moveBy(x: targetX, y: targetY, duration: 0.4)
            let particleFade = SKAction.fadeOut(withDuration: 0.4)
            let particleScale = SKAction.scale(to: 0.3, duration: 0.4)
            particle.run(SKAction.group([move, particleFade, particleScale]))
        }

        // Glow effect
        GlowHelper.addEnhancedGlow(to: mainExplosion, color: UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0), intensity: 1.5)

        // Remove container after animation
        let removeAction = SKAction.removeFromParent()
        explosionContainer.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.6),
            removeAction
        ]))
    }

    override func update(_ currentTime: TimeInterval) {
        // Don't update game logic when paused or game hasn't started yet
        if isGamePaused || !isGameStarted { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }

        // Shoot only when touching and player is near touch location
        if isTouching && currentTime - lastShootTime > shootInterval {
            let distance = abs(player.position.x - touchLocation.x)
            if distance <= shootDistanceThreshold {
                shoot()
                lastShootTime = currentTime
            }
        }

        // Update enemy spawning
        enemyManager.update(currentTime: currentTime)

        // Update obstacle spawning
        obstacleManager.update(currentTime: currentTime)

        // Update powerup spawning
        powerUpManager.update(currentTime: currentTime)

        // Check level completion - simple approach
        checkLevelCompletion(currentTime: currentTime)

        lastUpdateTime = currentTime
    }

    private func checkLevelCompletion(currentTime: TimeInterval) {
        // Only check if all waves have been spawned
        guard enemyManager.areAllWavesSpawned() else {
            return
        }

        // Count remaining enemies on screen
        var remainingEnemies = 0
        enumerateChildNodes(withName: "enemy") { _, _ in
            remainingEnemies += 1
        }

        if remainingEnemies == 0 {
            // No enemies on screen
            if noEnemiesTime == nil {
                // First time we detected no enemies
                noEnemiesTime = currentTime
                print("Level \(currentLevel): No enemies detected, starting completion timer")
            } else {
                // Check if enough time has passed
                let timeWithoutEnemies = currentTime - noEnemiesTime!
                if timeWithoutEnemies >= levelCompletionDelay {
                    print("Level \(currentLevel): COMPLETE! (no enemies for \(timeWithoutEnemies)s)")
                    levelComplete()
                }
            }
        } else {
            // There are still enemies, reset timer
            if noEnemiesTime != nil {
                print("Level \(currentLevel): Enemies appeared again, resetting timer")
            }
            noEnemiesTime = nil
        }
    }

    private func levelComplete() {
        let levelCompleteScene = LevelCompleteScene(size: size, level: currentLevel, score: score)
        stopGameplayAndTransition(to: levelCompleteScene, transitionDuration: 1.0)
    }

    private func goToLevelSelect() {
        let levelSelectScene = LevelSelectScene(size: size)
        levelSelectScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(levelSelectScene, transition: transition)
    }
}
