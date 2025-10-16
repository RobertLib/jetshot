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
}

class GameScene: SKScene, SKPhysicsContactDelegate {

    // Level system
    var currentLevel: Int = 1
    private var levelConfig: LevelConfig!
    private var levelTimer: TimeInterval = 0

    // Game objects
    private var player: Player!
    private var enemyManager: EnemyManager!
    private var scoreLabel: SKLabelNode!
    private var score: Int = 0 {
        didSet {
            scoreLabel.text = "Score: \(score)"
        }
    }

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

    override func didMove(to view: SKView) {
        // Setup physics
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)

        // Load level configuration
        levelConfig = LevelManager.shared.getLevelConfig(for: currentLevel)
        levelTimer = levelConfig.duration

        addChild(StarfieldHelper.createStarfield(for: self))
        setupPlayer(view: view)
        setupEnemyManager()
        setupUI(view: view)
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
        enemyManager = EnemyManager(scene: self)
    }

    private func setupUI(view: SKView) {
        scoreLabel = SKLabelNode(fontNamed: "Arial")
        scoreLabel.fontSize = 24
        scoreLabel.fontColor = .white

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
        let topMargin = max(safeAreaTop + 30, 50)

        // Position label below safe area
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height - topMargin)
        scoreLabel.text = "Score: 0"
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

        // Create heart shapes for each life
        let heartSize: CGFloat = 20
        let spacing: CGFloat = 10
        let leftMargin: CGFloat = 20

        // Position hearts at the same height as score label
        for i in 0..<lives {
            let heart = createHeart(size: heartSize)
            heart.position = CGPoint(x: leftMargin + CGFloat(i) * (heartSize + spacing),
                                    y: size.height - topMargin)
            heart.fillColor = .red
            heart.strokeColor = .white
            heart.lineWidth = 2
            heart.zPosition = 100
            addChild(heart)
            livesNodes.append(heart)
        }
    }

    private func createHeart(size: CGFloat) -> SKShapeNode {
        // Create heart shape using bezier path
        let path = CGMutablePath()
        let halfSize = size / 2

        // Start at bottom point
        path.move(to: CGPoint(x: 0, y: -halfSize))

        // Left curve
        path.addCurve(
            to: CGPoint(x: -halfSize, y: halfSize * 0.3),
            control1: CGPoint(x: -halfSize, y: -halfSize * 0.3),
            control2: CGPoint(x: -halfSize * 1.2, y: halfSize * 0.1)
        )

        // Left top arc
        path.addArc(
            center: CGPoint(x: -halfSize * 0.5, y: halfSize * 0.5),
            radius: halfSize * 0.5,
            startAngle: .pi,
            endAngle: 0,
            clockwise: false
        )

        // Right top arc
        path.addArc(
            center: CGPoint(x: halfSize * 0.5, y: halfSize * 0.5),
            radius: halfSize * 0.5,
            startAngle: .pi,
            endAngle: 0,
            clockwise: false
        )

        // Right curve
        path.addCurve(
            to: CGPoint(x: 0, y: -halfSize),
            control1: CGPoint(x: halfSize * 1.2, y: halfSize * 0.1),
            control2: CGPoint(x: halfSize, y: -halfSize * 0.3)
        )

        return SKShapeNode(path: path)
    }

    private func setupPauseButton(topMargin: CGFloat) {
        // Create pause button (two vertical bars icon)
        let buttonSize: CGFloat = 40
        let pauseButton = SKShapeNode(rectOf: CGSize(width: buttonSize, height: buttonSize), cornerRadius: 8)
        let fillColor = UIColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.8)
        pauseButton.fillColor = fillColor
        pauseButton.strokeColor = UIColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1.0)
        pauseButton.lineWidth = 3
        pauseButton.name = "pauseButton"

        // Position at the same height as score label
        let rightMargin: CGFloat = 30
        pauseButton.position = CGPoint(x: size.width - rightMargin, y: size.height - topMargin)
        pauseButton.zPosition = 100
        addChild(pauseButton)

        // Add pause icon (two vertical bars)
        let barWidth: CGFloat = 5
        let barHeight: CGFloat = 16
        let barSpacing: CGFloat = 6

        let leftBar = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight))
        leftBar.fillColor = .white
        leftBar.strokeColor = .clear
        leftBar.position = CGPoint(x: -barSpacing / 2, y: 0)
        pauseButton.addChild(leftBar)

        let rightBar = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight))
        rightBar.fillColor = .white
        rightBar.strokeColor = .clear
        rightBar.position = CGPoint(x: barSpacing / 2, y: 0)
        pauseButton.addChild(rightBar)

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

        // Pause panel
        let panelWidth: CGFloat = min(size.width - 60, 300)
        let panelHeight: CGFloat = 280
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 25)
        panel.fillColor = UIColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 0.95)
        panel.strokeColor = UIColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1.0)
        panel.lineWidth = 4
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.alpha = 0
        panel.setScale(0.8)
        overlay.addChild(panel)

        // Animate panel entrance - same as GameOverScene
        panel.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.2),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.4),
                SKAction.scale(to: 1.0, duration: 0.4)
            ])
        ]))

        // "PAUSED" title
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "PAUSED"
        title.fontSize = 36
        title.fontColor = UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        title.position = CGPoint(x: 0, y: panelHeight / 2 - 60)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        panel.addChild(title)

        // Resume button
        let resumeButton = createPauseMenuButton(
            text: "RESUME",
            color: UIColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1.0),
            name: "resumeButton"
        )
        resumeButton.position = CGPoint(x: 0, y: -5)
        panel.addChild(resumeButton)

        // Menu button
        let menuButton = createPauseMenuButton(
            text: "MENU",
            color: UIColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1.0),
            name: "pauseMenuButton"
        )
        menuButton.position = CGPoint(x: 0, y: -70)
        panel.addChild(menuButton)

        pauseOverlay = overlay
        addChild(overlay)
    }

    private func createPauseMenuButton(text: String, color: UIColor, name: String) -> SKShapeNode {
        let button = SKShapeNode(rectOf: CGSize(width: 220, height: 50), cornerRadius: 12)
        button.fillColor = color

        // Calculate lighter border color based on fill color
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        button.strokeColor = UIColor(hue: hue, saturation: max(0, saturation - 0.2), brightness: min(1, brightness + 0.3), alpha: alpha)

        button.lineWidth = 3
        button.name = name

        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = text
        label.fontSize = 20
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.name = name // Set name on label too for easier touch detection
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

    private func togglePause() {
        isGamePaused.toggle()

        if isGamePaused {
            enemyManager.pauseSpawning()
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
            hidePauseOverlay()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check if pause button was tapped
        let nodesAtPoint = nodes(at: location)

        // First check for interactive elements (buttons)
        for node in nodesAtPoint {
            if node.name == "pauseButton" || node.parent?.name == "pauseButton" {
                togglePause()
                return
            }

            // Check pause overlay buttons
            if isGamePaused {
                if node.name == "resumeButton" || node.parent?.name == "resumeButton" {
                    handleResumeButton()
                    return
                }
                if node.name == "pauseMenuButton" || node.parent?.name == "pauseMenuButton" {
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
                togglePause()
                return
            }
        }

        // Don't handle game touches when paused
        if isGamePaused { return }

        isTouching = true
        touchLocation = location

        // Move player to touch location with animation
        player.moveTo(x: location.x, sceneWidth: size.width)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused
        if isGamePaused { return }

        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        isTouching = true
        touchLocation = location

        // Move player instantly to follow touch smoothly
        player.moveToInstant(x: location.x, sceneWidth: size.width)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused
        if isGamePaused { return }
        isTouching = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused
        if isGamePaused { return }
        isTouching = false
    }

    private func shoot() {
        let bullet = player.shoot()
        addChild(bullet)

        // Play shoot sound
        SoundManager.shared.playShoot()

        // Move bullet upwards
        let moveAction = SKAction.moveTo(y: size.height + 20, duration: 1.5)
        let removeAction = SKAction.removeFromParent()
        bullet.run(SKAction.sequence([moveAction, removeAction]))
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
    }

    private func bulletDidCollideWithEnemy(bullet: SKShapeNode?, enemy: Enemy?) {
        guard let bullet = bullet, let enemy = enemy else { return }

        // Explosion effect and sound
        createExplosion(at: enemy.position)
        SoundManager.shared.playExplosion()

        bullet.removeFromParent()
        enemy.removeFromParent()
        score += 10
    }

    private func playerDidCollideWithEnemy(enemy: Enemy?) {
        guard let enemy = enemy else { return }

        // Skip if player is invulnerable
        if isInvulnerable {
            return
        }

        // Explosion effect and sound
        createExplosion(at: enemy.position)
        SoundManager.shared.playHit()
        enemy.removeFromParent()

        // Lose a life
        lives -= 1

        // Check for game over
        if lives <= 0 {
            gameOver()
            return
        }

        // Play hit animation and activate invulnerability
        player.playHitAnimation()
        activateInvulnerability()
    }

    private func playerDidCollideWithEnemyBullet(bullet: SKShapeNode?) {
        guard let bullet = bullet else { return }

        // Skip if player is invulnerable
        if isInvulnerable {
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

        // Play hit animation and activate invulnerability
        player.playHitAnimation()
        activateInvulnerability()
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
        let gameOverScene = GameOverScene(size: size, score: score)
        stopGameplayAndTransition(to: gameOverScene, transitionDuration: 1.0)
    }

    private func createExplosion(at position: CGPoint) {
        // Simple explosion - expanding circle
        let explosion = SKShapeNode(circleOfRadius: 5)
        explosion.fillColor = .orange
        explosion.strokeColor = .yellow
        explosion.position = position
        addChild(explosion)

        let scaleAction = SKAction.scale(to: 3.0, duration: 0.3)
        let fadeAction = SKAction.fadeOut(withDuration: 0.3)
        let removeAction = SKAction.removeFromParent()

        explosion.run(SKAction.sequence([
            SKAction.group([scaleAction, fadeAction]),
            removeAction
        ]))
    }

    override func update(_ currentTime: TimeInterval) {
        // Don't update game logic when paused
        if isGamePaused { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }

        let deltaTime = currentTime - lastUpdateTime

        // Update level timer (silently, without displaying)
        levelTimer -= deltaTime

        // Check if level is complete
        if levelTimer <= 0 {
            levelComplete()
            return
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

        lastUpdateTime = currentTime
    }

    private func levelComplete() {
        let levelCompleteScene = LevelCompleteScene(size: size, level: currentLevel, score: score)
        stopGameplayAndTransition(to: levelCompleteScene, transitionDuration: 1.0)
    }

    private func goToMenu() {
        let menuScene = MenuScene(size: size)
        menuScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(menuScene, transition: transition)
    }
}
