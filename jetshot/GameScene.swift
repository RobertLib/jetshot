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
    static let asteroid: UInt32 = 0b1000000 // 64
    static let coin: UInt32 = 0b10000000   // 128
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
    private var bossManager: BossManager!
    private var asteroidManager: AsteroidManager?
    private var coinManager: CoinManager!
    private var scoreLabel: SKLabelNode!
    private var score: Int = 0 {
        didSet {
            scoreLabel.text = "Score: \(score)"
        }
    }

    // Coin tracking
    private var coinsCollected: Int = 0

    // Boss system
    private var isBossActive: Bool = false
    private var bossSpawned: Bool = false

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
    private var currentShootInterval: TimeInterval {
        return player?.hasRapidFire == true ? 0.1 : shootInterval
    }

    // PowerUp timers and states
    private var scoreMultiplier: Int = 1

    // Touch tracking
    private var isTouching = false
    private var touchLocation: CGPoint = .zero
    private let shootDistanceThreshold: CGFloat = 50 // Distance within which shooting is allowed

    // Pause system
    var gameContentNode: SKNode! // Node that gets paused (public for managers)
    private var uiNode: SKNode! // UI node that never gets paused
    private var pauseButton: SKShapeNode!
    private var pauseOverlay: SKNode?
    private var isInitialized = false

    // Level intro
    private var isGameStarted: Bool = false
    private var isPlayerExiting: Bool = false

    override func didMove(to view: SKView) {
        // Setup physics
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        // Create game content node (this will be paused)
        gameContentNode = SKNode()
        gameContentNode.name = "gameContent"
        addChild(gameContentNode)

        // Create UI node (this will never be paused)
        uiNode = SKNode()
        uiNode.name = "uiNode"
        uiNode.zPosition = 100
        addChild(uiNode)

        // Register for app lifecycle notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // Dark background for better glow contrast
        backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.12, alpha: 1.0)

        // Setup camera for shake effects
        let cameraNode = SKCameraNode()
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraNode)
        camera = cameraNode

        // Load level configuration immediately (lightweight)
        levelConfig = LevelManager.shared.getLevelConfig(for: currentLevel)

        // Setup critical components first - add to game content node
        setupPlayer(view: view)

        // Setup UI on UI node
        setupUI(view: view)

        // Defer heavy initialization to avoid FPS drop
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Add starfield (particle effect) - to game content node
            self.gameContentNode.addChild(StarfieldHelper.createStarfield(for: self))

            // Add shooting stars and meteors for visual variety - to game content node
            self.gameContentNode.addChild(StarfieldHelper.createShootingStars(for: self))
            self.gameContentNode.addChild(StarfieldHelper.createMeteors(for: self))

            // Add planets to background - to game content node
            PlanetHelper.startPlanetGeneration(in: self, parentNode: self.gameContentNode)

            // Setup managers sequentially with small delays
            self.setupEnemyManager()
            self.setupObstacleManager()
            self.setupPowerUpManager()
            self.setupCoinManager()
            self.setupAsteroidManager()
            self.setupBossManager()

            self.isInitialized = true

            // Pause the game and show level intro after everything is ready
            self.gameContentNode.isPaused = true
            self.physicsWorld.speed = 0
            self.showLevelIntro()

            // Start background music for current level
            SoundManager.shared.setMusicForLevel(self.currentLevel)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized, let view = view else { return }

        // Update camera position to center of new size
        camera?.position = CGPoint(x: size.width / 2, y: size.height / 2)

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

        // Update shooting stars and meteors position
        if let shootingStars = childNode(withName: "shootingStars") as? SKEmitterNode {
            StarfieldHelper.updateShootingStars(shootingStars, for: self)
        }
        if let meteors = childNode(withName: "meteors") as? SKEmitterNode {
            StarfieldHelper.updateMeteors(meteors, for: self)
        }

        // Update pause overlay if it exists (when view resizes)
        if let overlay = pauseOverlay {
            overlay.removeFromParent()
            pauseOverlay = nil
            if gameContentNode.isPaused {
                showPauseOverlay()
            }
        }
    }

    // MARK: - App Lifecycle

    @objc private func appWillResignActive() {
        // When app goes to background, automatically pause if game is running
        if !gameContentNode.isPaused && isGameStarted {
            togglePause()
        }
    }

    @objc private func appDidBecomeActive() {
        // When app returns from background, ensure physics world speed matches pause state
        if gameContentNode.isPaused {
            // If game is paused, ensure physics is also stopped
            physicsWorld.speed = 0
            // Show pause overlay if missing
            if pauseOverlay == nil {
                showPauseOverlay()
            }
        } else if isGameStarted {
            // If game is running, ensure physics is active
            physicsWorld.speed = 1.0
        }

        // Hide overlay if game is not paused but overlay is showing (edge case)
        if pauseOverlay != nil && !gameContentNode.isPaused {
            hidePauseOverlay()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        PlanetHelper.stopPlanetGeneration()
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
        gameContentNode.addChild(player)
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

    private func setupCoinManager() {
        // Configure coin spawning - balanced frequency
        let coinConfig = CoinSpawnConfig(
            spawnInterval: 5.0,        // Every 5 seconds
            spawnProbability: 0.5,     // 50% chance
            minCoins: 10,              // At least 10 coins per level
            maxCoins: 18               // At most 18 coins per level
        )
        coinManager = CoinManager(scene: self, config: coinConfig)
    }

    private func setupAsteroidManager() {
        if !levelConfig.asteroidWaves.isEmpty {
            asteroidManager = AsteroidManager(scene: self, waves: levelConfig.asteroidWaves)
        }
    }

    private func setupBossManager() {
        bossManager = BossManager(scene: self)
        bossManager.setPlayer(player)
    }

    private func setupUI(view: SKView) {
        // Remove old UI elements if they exist
        scoreLabel?.removeFromParent()
        pauseButton?.removeFromParent()
        livesNodes.forEach { $0.removeFromParent() }
        livesNodes.removeAll()

        scoreLabel = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        scoreLabel.fontSize = UITheme.Typography.sizeRegular
        scoreLabel.fontColor = UITheme.Colors.textPrimary
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
        uiNode.addChild(scoreLabel)

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
            uiNode.addChild(ship)
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
        // Position player below screen for entry animation
        let originalPlayerY = player.position.y
        player.position.y = -50

        let introNode = SKNode()
        introNode.zPosition = 2000
        introNode.speed = 1.0 // Always animate at normal speed even when scene is paused
        introNode.name = "levelIntro"

        // Semi-transparent background
        let background = SKSpriteNode(color: UIColor(white: 0, alpha: 0.65), size: size)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        introNode.addChild(background)

        // Level number label
        let levelLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        levelLabel.text = "LEVEL \(currentLevel)"
        levelLabel.fontSize = 44
        levelLabel.fontColor = .white
        levelLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 60)
        levelLabel.alpha = 0
        levelLabel.setScale(0.5)
        introNode.addChild(levelLabel)

        // For level 1, add tutorial instructions
        if currentLevel == 1 {
            let instructionLabel = SKLabelNode(fontNamed: "Arial")
            instructionLabel.text = "Drag to move"
            instructionLabel.fontSize = 22
            instructionLabel.fontColor = UIColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0)
            instructionLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 10)
            instructionLabel.alpha = 0
            introNode.addChild(instructionLabel)

            let shootLabel = SKLabelNode(fontNamed: "Arial")
            shootLabel.text = "Auto-fire enabled"
            shootLabel.fontSize = 22
            shootLabel.fontColor = UIColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0)
            shootLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 40)
            shootLabel.alpha = 0
            introNode.addChild(shootLabel)

            let objectiveLabel = SKLabelNode(fontNamed: "Arial")
            objectiveLabel.text = "Collect stars and destroy enemies!"
            objectiveLabel.fontSize = 20
            objectiveLabel.fontColor = UIColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 1.0)
            objectiveLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 80)
            objectiveLabel.alpha = 0
            introNode.addChild(objectiveLabel)

            let luckLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
            luckLabel.text = "Good luck pilot!"
            luckLabel.fontSize = 26
            luckLabel.fontColor = UIColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1.0)
            luckLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 130)
            luckLabel.alpha = 0
            introNode.addChild(luckLabel)

            // Animate instructions
            let fadeIn = SKAction.fadeIn(withDuration: 0.5)
            let wait = SKAction.wait(forDuration: 4) // Longer wait for level 1
            let fadeOut = SKAction.fadeOut(withDuration: 0.4)
            let sequence = SKAction.sequence([
                SKAction.wait(forDuration: 0.6),
                fadeIn,
                wait,
                fadeOut
            ])

            instructionLabel.run(sequence)
            shootLabel.run(SKAction.sequence([SKAction.wait(forDuration: 0.7), fadeIn, wait, fadeOut]))
            objectiveLabel.run(SKAction.sequence([SKAction.wait(forDuration: 0.8), fadeIn, wait, fadeOut]))
            luckLabel.run(SKAction.sequence([SKAction.wait(forDuration: 0.9), fadeIn, wait, fadeOut]))
        }

        addChild(introNode)

        // Animation sequence for level label
        let fadeIn = SKAction.fadeIn(withDuration: 0.4)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.4)
        let appear = SKAction.group([fadeIn, scaleUp])

        let wait = SKAction.wait(forDuration: currentLevel == 1 ? 4.5 : 1.5) // Longer for level 1

        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let scaleDown = SKAction.scale(to: 1.2, duration: 0.3)
        let disappear = SKAction.group([fadeOut, scaleDown])

        let startGame = SKAction.run { [weak self] in
            guard let self = self else { return }
            if self.currentLevel == 1 {
                // Show countdown for level 1
                self.showCountdown(in: introNode, background: background, completion: {
                    self.startPlayerEntryAnimation(targetY: originalPlayerY)
                })
            } else {
                // Start immediately for other levels
                self.startPlayerEntryAnimation(targetY: originalPlayerY)
            }
        }

        let remove = SKAction.removeFromParent()

        let sequence = SKAction.sequence([appear, wait, disappear, startGame, remove])
        levelLabel.run(sequence)

        // Fade out background
        if currentLevel == 1 {
            // Keep background for countdown
            // It will be removed after countdown completes
        } else {
            let backgroundFade = SKAction.sequence([
                SKAction.wait(forDuration: 2.2),
                SKAction.fadeOut(withDuration: 0.3)
            ])
            background.run(backgroundFade)
        }
    }

    private func showCountdown(in parentNode: SKNode, background: SKSpriteNode, completion: @escaping () -> Void) {
        let countdownLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        countdownLabel.fontSize = 80
        countdownLabel.fontColor = .white
        countdownLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        countdownLabel.zPosition = 10
        parentNode.addChild(countdownLabel)

        // Play countdown sound once at the beginning (contains "3 2 1" audio, ~3 seconds)
        SoundManager.shared.playCountdownSound(on: self)

        var countdownActions: [SKAction] = []

        // Each number shows for ~1 second to match the audio
        let numberDuration: TimeInterval = 1.0

        // Show 3
        let show3 = SKAction.run {
            countdownLabel.text = "3"
            countdownLabel.alpha = 0
            countdownLabel.setScale(0.5)
            HapticManager.shared.mediumTap()
        }
        let fadeIn3 = SKAction.fadeIn(withDuration: 0.15)
        let scaleUp3 = SKAction.scale(to: 1.2, duration: 0.15)
        let appear3 = SKAction.group([fadeIn3, scaleUp3])
        let wait3 = SKAction.wait(forDuration: numberDuration - 0.25)
        let fadeOut3 = SKAction.fadeOut(withDuration: 0.1)

        // Show 2
        let show2 = SKAction.run {
            countdownLabel.text = "2"
            countdownLabel.alpha = 0
            countdownLabel.setScale(0.5)
            HapticManager.shared.mediumTap()
        }
        let fadeIn2 = SKAction.fadeIn(withDuration: 0.15)
        let scaleUp2 = SKAction.scale(to: 1.2, duration: 0.15)
        let appear2 = SKAction.group([fadeIn2, scaleUp2])
        let wait2 = SKAction.wait(forDuration: numberDuration - 0.25)
        let fadeOut2 = SKAction.fadeOut(withDuration: 0.1)

        // Show 1
        let show1 = SKAction.run {
            countdownLabel.text = "1"
            countdownLabel.alpha = 0
            countdownLabel.setScale(0.5)
            HapticManager.shared.mediumTap()
        }
        let fadeIn1 = SKAction.fadeIn(withDuration: 0.15)
        let scaleUp1 = SKAction.scale(to: 1.2, duration: 0.15)
        let appear1 = SKAction.group([fadeIn1, scaleUp1])
        let wait1 = SKAction.wait(forDuration: numberDuration - 0.25)
        let fadeOut1 = SKAction.fadeOut(withDuration: 0.1)

        // Show "GO!"
        let showGo = SKAction.run {
            countdownLabel.text = "GO!"
            countdownLabel.alpha = 0
            countdownLabel.setScale(0.5)
            HapticManager.shared.heavyTap()
        }
        let fadeInGo = SKAction.fadeIn(withDuration: 0.15)
        let scaleUpGo = SKAction.scale(to: 1.3, duration: 0.15)
        let appearGo = SKAction.group([fadeInGo, scaleUpGo])
        let waitGo = SKAction.wait(forDuration: 0.4)
        let fadeOutGo = SKAction.fadeOut(withDuration: 0.15)

        // Build sequence: 3, 2, 1, GO!
        countdownActions.append(show3)
        countdownActions.append(appear3)
        countdownActions.append(wait3)
        countdownActions.append(fadeOut3)

        countdownActions.append(show2)
        countdownActions.append(appear2)
        countdownActions.append(wait2)
        countdownActions.append(fadeOut2)

        countdownActions.append(show1)
        countdownActions.append(appear1)
        countdownActions.append(wait1)
        countdownActions.append(fadeOut1)

        countdownActions.append(showGo)
        countdownActions.append(appearGo)
        countdownActions.append(waitGo)
        countdownActions.append(fadeOutGo)

        // Fade out background
        let fadeBackground = SKAction.run {
            let fade = SKAction.fadeOut(withDuration: 0.3)
            background.run(fade)
        }

        // Complete
        let complete = SKAction.run {
            parentNode.removeFromParent()
            completion()
        }

        countdownActions.append(fadeBackground)
        countdownActions.append(complete)

        countdownLabel.run(SKAction.sequence(countdownActions))
    }

    private func startPlayerEntryAnimation(targetY: CGFloat) {
        // Play player spawn sound
        SoundManager.shared.playPlayerSpawnSound(on: self)

        // Animate player entering from bottom
        let moveUp = SKAction.moveTo(y: targetY, duration: 0.8)
        moveUp.timingMode = .easeOut

        player.run(moveUp) { [weak self] in
            self?.startGame()
        }
    }

    private func startGame() {
        isGameStarted = true
        gameContentNode.isPaused = false
        physicsWorld.speed = 1.0

        // Play level start sound
        SoundManager.shared.playLevelStartSound(on: self)
    }

    private func setupPauseButton(topMargin: CGFloat) {
        // Create enhanced pause button with outlined style
        let buttonSize: CGFloat = 44
        let pauseButton = SKShapeNode(rectOf: CGSize(width: buttonSize, height: buttonSize), cornerRadius: 10)
        // Subtle background tint with border color
        let pauseColor = UIColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1.0)
        pauseButton.fillColor = pauseColor.withAlphaComponent(0.06)
        pauseButton.strokeColor = pauseColor
        pauseButton.lineWidth = 3
        pauseButton.name = "pauseButton"

        // Position at the same height as hearts and score
        let rightMargin: CGFloat = 28
        pauseButton.position = CGPoint(x: size.width - rightMargin - 10, y: size.height - topMargin)
        pauseButton.zPosition = 100
        uiNode.addChild(pauseButton)

        // Add enhanced pause icon (two vertical bars with rounded ends)
        let barWidth: CGFloat = 6
        let barHeight: CGFloat = 18
        let barSpacing: CGFloat = 7

        let leftBar = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        leftBar.fillColor = UIColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1.0)
        leftBar.strokeColor = .clear
        leftBar.position = CGPoint(x: -barSpacing / 2, y: 0)
        pauseButton.addChild(leftBar)

        let rightBar = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        rightBar.fillColor = UIColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1.0)
        rightBar.strokeColor = .clear
        rightBar.position = CGPoint(x: barSpacing / 2, y: 0)
        pauseButton.addChild(rightBar)

        // Add subtle glow
        GlowHelper.addEnhancedGlow(to: pauseButton, color: UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0), intensity: 0.5)

        self.pauseButton = pauseButton
    }

    private func showPauseOverlay() {
        guard pauseOverlay == nil else { return }

        let overlay = SKNode()
        overlay.zPosition = 10000

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
        resumeButton.position = CGPoint(x: 0, y: 24)
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
        let secondaryButtonY: CGFloat = -108

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
        uiNode.addChild(overlay)
    }

    private func createPauseMenuButton(text: String, color: UIColor, width: CGFloat, name: String) -> SKShapeNode {
        let button = SKShapeNode(rectOf: CGSize(width: width, height: 50), cornerRadius: 12)
        // Subtle background tint with border color
        button.fillColor = color.withAlphaComponent(0.15)
        button.strokeColor = color
        button.lineWidth = 3
        button.name = name

        // Add shadow effect with lower opacity for outlined style
        let shadow = SKShapeNode(rectOf: CGSize(width: width, height: 50), cornerRadius: 12)
        shadow.fillColor = .clear
        shadow.strokeColor = .black
        shadow.alpha = 0.2
        shadow.lineWidth = 3
        shadow.position = CGPoint(x: 0, y: -2)
        shadow.zPosition = -1
        button.addChild(shadow)

        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = text
        label.fontSize = 20
        label.fontColor = color
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
        // Toggle pause state on game content node
        gameContentNode.isPaused.toggle()

        if gameContentNode.isPaused {
            // Pause physics world to stop all physics-based movement
            physicsWorld.speed = 0
            // Show pause overlay when paused
            showPauseOverlay()
        } else {
            // Resume physics world
            physicsWorld.speed = 1.0
            // Hide pause overlay when resumed
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
                SoundManager.shared.playPauseSound(on: self)
                togglePause()
                return
            }

            // Check pause overlay buttons
            if gameContentNode.isPaused {
                if node.name == "resumeButton" || node.parent?.name == "resumeButton" {
                    HapticManager.shared.lightTap()
                    SoundManager.shared.playResumeSound(on: self)
                    handleResumeButton()
                    return
                }
                if node.name == "pauseRetryButton" || node.parent?.name == "pauseRetryButton" {
                    HapticManager.shared.lightTap()
                    SoundManager.shared.playButtonClickSound(on: self)
                    handlePauseRetryButton()
                    return
                }
                if node.name == "pauseLevelsButton" || node.parent?.name == "pauseLevelsButton" {
                    HapticManager.shared.lightTap()
                    SoundManager.shared.playButtonClickSound(on: self)
                    handlePauseLevelsButton()
                    return
                }
                if node.name == "pauseMenuButton" || node.parent?.name == "pauseMenuButton" {
                    HapticManager.shared.lightTap()
                    SoundManager.shared.playButtonClickSound(on: self)
                    handlePauseMenuButton()
                    return
                }
            }
        }

        // If paused and no button was clicked, check if background overlay was tapped (close menu)
        // Only close if we clicked directly on background, not on panel or its children
        if gameContentNode.isPaused {
            let topNode = nodesAtPoint.first
            if topNode?.name == "pauseOverlayBackground" {
                HapticManager.shared.lightTap()
                SoundManager.shared.playResumeSound(on: self)
                togglePause()
                return
            }
        }

        // Don't handle game touches when paused or game hasn't started
        if gameContentNode.isPaused || !isGameStarted { return }

        isTouching = true
        touchLocation = location

        // Move player to touch location with animation
        player.moveTo(x: location.x, sceneWidth: size.width)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused or game hasn't started
        if gameContentNode.isPaused || !isGameStarted { return }

        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        isTouching = true
        touchLocation = location

        // Move player instantly to follow touch smoothly
        player.moveToInstant(x: location.x, sceneWidth: size.width)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused or game hasn't started
        if gameContentNode.isPaused || !isGameStarted { return }
        isTouching = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused or game hasn't started
        if gameContentNode.isPaused || !isGameStarted { return }
        isTouching = false
    }

    private func shoot() {
        // If lightning weapon is active, use lightning attack
        if player.hasLightningWeapon {
            shootLightning()
            return
        }

        let bullets = player.shoot()

        // Play shoot sound
        SoundManager.shared.playShootSound(on: self)

        for bullet in bullets {
            gameContentNode.addChild(bullet)

            // Move bullet upwards
            let moveAction = SKAction.moveTo(y: size.height + 20, duration: 1.5)
            let removeAction = SKAction.removeFromParent()
            bullet.run(SKAction.sequence([moveAction, removeAction]))
        }

        // Shoot missiles if available
        if player.sideMissileCount > 0 {
            SoundManager.shared.playMissileSound(on: self)
            for i in 0..<player.sideMissileCount {
                let side = i == 0 ? -1 : 1
                let missile = player.shootMissile(side: side)
                gameContentNode.addChild(missile)

                // Move missile upwards
                let moveAction = SKAction.moveTo(y: size.height + 20, duration: 1.2)
                let removeAction = SKAction.removeFromParent()
                missile.run(SKAction.sequence([moveAction, removeAction]))
            }
        }
    }

    private func shootLightning() {
        // Play lightning sound
        SoundManager.shared.playLightningSound(on: self)

        // Create screen-wide lightning attack
        let lightning = LightningHelper.createScreenWideLightning(
            at: player.position,
            sceneSize: size,
            count: Int.random(in: 4...6)
        )
        addChild(lightning)

        // Damage all enemies on screen
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy {
                // Instantly destroy enemy
                enemy.health = 0

                // Explosion effect
                self.createExplosion(at: enemy.position)

                // Add score
                self.addScore(enemy.enemyType.points)

                // Mark enemy as destroyed
                enemy.markAsDestroyed()
                enemy.removeFromParent()
            }
        }

        // Damage boss if present
        if bossManager.isBossActive() {
            // Deal significant damage to boss (15 hits worth)
            for _ in 0..<15 {
                // Check if boss is still alive before each hit
                guard bossManager.isBossActive() else { break }

                let result = bossManager.bossTakeDamage()
                if result.defeated {
                    // Boss defeated
                    self.addScore(result.points)

                    // Wait for boss defeat animation using SKAction (respects pause)
                    let wait = SKAction.wait(forDuration: 2.2)
                    let startExit = SKAction.run { [weak self] in
                        self?.startPlayerExitAnimation()
                    }
                    run(SKAction.sequence([wait, startExit]), withKey: "bossDefeatTransition")
                    break
                }
            }

            // Create hit effect at boss position if available
            if let bossPos = bossManager.getBossPosition() {
                self.createHitEffect(at: bossPos)
            }
        }

        // Screen shake effect
        let shakeAmount: CGFloat = 5
        let shakeDuration: TimeInterval = 0.15

        let moveLeft = SKAction.moveBy(x: -shakeAmount, y: 0, duration: shakeDuration / 4)
        let moveRight = SKAction.moveBy(x: shakeAmount * 2, y: 0, duration: shakeDuration / 2)
        let moveBack = SKAction.moveBy(x: -shakeAmount, y: 0, duration: shakeDuration / 4)
        let shake = SKAction.sequence([moveLeft, moveRight, moveBack])

        camera?.run(shake)
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
            // Check if it's a boss or regular enemy
            if let boss = secondBody.node as? Boss {
                bulletDidCollideWithBoss(bullet: firstBody.node as? SKShapeNode, boss: boss)
            } else {
                bulletDidCollideWithEnemy(bullet: firstBody.node as? SKShapeNode,
                                         enemy: secondBody.node as? Enemy)
            }
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
            // Find the obstacle - could be direct parent or grandparent (for destructible blocks)
            var obstacle: Obstacle?
            if let directObstacle = secondBody.node as? Obstacle {
                obstacle = directObstacle
            } else if let parentObstacle = secondBody.node?.parent as? Obstacle {
                obstacle = parentObstacle
            } else if let grandparentObstacle = secondBody.node?.parent?.parent as? Obstacle {
                obstacle = grandparentObstacle
            }

            playerDidCollideWithObstacle(obstacle: obstacle)
        }

        // Bullet hit obstacle
        if firstBody.categoryBitMask == PhysicsCategory.bullet &&
           secondBody.categoryBitMask == PhysicsCategory.obstacle {
            // Find the obstacle - could be direct parent or grandparent (for destructible blocks)
            var obstacle: Obstacle?
            let hitNode: SKNode? = secondBody.node

            if let directObstacle = secondBody.node as? Obstacle {
                obstacle = directObstacle
            } else if let parentObstacle = secondBody.node?.parent as? Obstacle {
                obstacle = parentObstacle
            } else if let grandparentObstacle = secondBody.node?.parent?.parent as? Obstacle {
                obstacle = grandparentObstacle
            }

            bulletDidCollideWithObstacle(bullet: firstBody.node as? SKShapeNode,
                                        obstacle: obstacle,
                                        hitNode: hitNode)
        }

        // Player hit powerup
        if firstBody.categoryBitMask == PhysicsCategory.player &&
           secondBody.categoryBitMask == PhysicsCategory.powerUp {
            playerDidCollideWithPowerUp(powerUp: secondBody.node as? PowerUp)
        }

        // Player hit coin
        if firstBody.categoryBitMask == PhysicsCategory.player &&
           secondBody.categoryBitMask == PhysicsCategory.coin {
            playerDidCollideWithCoin(coin: secondBody.node as? Coin)
        }

        // Bullet hit asteroid
        if firstBody.categoryBitMask == PhysicsCategory.bullet &&
           secondBody.categoryBitMask == PhysicsCategory.asteroid {
            bulletDidCollideWithAsteroid(bullet: firstBody.node as? SKShapeNode,
                                        asteroid: secondBody.node as? Asteroid)
        }

        // Player hit asteroid
        if firstBody.categoryBitMask == PhysicsCategory.player &&
           secondBody.categoryBitMask == PhysicsCategory.asteroid {
            playerDidCollideWithAsteroid(asteroid: secondBody.node as? Asteroid)
        }
    }

    private func bulletDidCollideWithEnemy(bullet: SKShapeNode?, enemy: Enemy?) {
        guard let bullet = bullet, let enemy = enemy else { return }

        bullet.removeFromParent()

        // Decrease enemy health
        enemy.health -= 1

        // Check if enemy is destroyed
        if enemy.health <= 0 {
            // Special handling for mine - explode with shrapnel when shot
            if enemy.enemyType == .mine {
                // Add score
                addScore(enemy.enemyType.points)

                // Mine explodes prematurely when shot (armed or not)
                // explodeMine will handle marking as destroyed and removal
                enemy.explodeMine(isFullExplosion: enemy.isMineArmed, completion: {
                    // Mine has been removed
                })

                // Camera shake for mine explosion (bigger if armed)
                if enemy.isMineArmed {
                    shakeCamera(intensity: 12.0, duration: 0.35)
                    HapticManager.shared.heavyTap()
                } else {
                    shakeCamera(intensity: 6.0, duration: 0.25)
                    HapticManager.shared.mediumTap()
                }

                // Don't return here - the completion callback in explodeMine handles removal
                return
            } else {
                // Normal enemy destruction
                // Explosion effect
                createExplosion(at: enemy.position)
                HapticManager.shared.mediumTap()

                // Add score based on enemy type
                addScore(enemy.enemyType.points)

                // Mark enemy as destroyed to prevent completion callback
                enemy.markAsDestroyed()
                enemy.removeFromParent()
            }
        } else {
            // Enemy took damage but is still alive (Tank)
            // Small hit effect without destroying
            createHitEffect(at: enemy.position)
            HapticManager.shared.lightTap()

            // Flash effect to show damage
            let flash = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.3, duration: 0.1),
                SKAction.fadeAlpha(to: 1.0, duration: 0.1)
            ])
            enemy.run(flash)
        }
    }

    private func bulletDidCollideWithBoss(bullet: SKShapeNode?, boss: Boss?) {
        guard let bullet = bullet, let boss = boss else { return }

        // Check if boss is still alive before processing damage
        guard bossManager.isBossActive() else {
            bullet.removeFromParent()
            return
        }

        bullet.removeFromParent()

        // Boss takes damage
        let result = bossManager.bossTakeDamage()

        if result.defeated {
            // Boss defeated - add points
            addScore(result.points)

            // Play boss defeat sound
            SoundManager.shared.playBossDefeatSound(on: self)

            // Wait for boss defeat animation to complete using SKAction (respects pause)
            // (8 explosions * 0.2s + final explosion fade 0.5s = 2.1s)
            let wait = SKAction.wait(forDuration: 2.2)
            let startExit = SKAction.run { [weak self] in
                self?.startPlayerExitAnimation()
            }
            run(SKAction.sequence([wait, startExit]), withKey: "bossDefeatToExit")
        } else {
            // Boss took damage but still alive
            createHitEffect(at: boss.position)
            SoundManager.shared.playBossHitSound(on: self)
            HapticManager.shared.mediumTap()
        }
    }

    private func playerDidCollideWithEnemy(enemy: Enemy?) {
        guard let enemy = enemy else { return }

        // Skip if player is invulnerable or has shield
        if isInvulnerable || player.hasShield {
            if player.hasShield {
                // Shield absorbs the hit - create visual feedback
                createExplosion(at: enemy.position)
                HapticManager.shared.mediumTap()

                // Special handling for mine - should explode even with shield
                if enemy.enemyType == .mine {
                    enemy.explodeMine(isFullExplosion: enemy.isMineArmed, completion: {
                        // Mine has been removed
                    })
                    // Camera shake for mine explosion
                    if enemy.isMineArmed {
                        shakeCamera(intensity: 12.0, duration: 0.35)
                        HapticManager.shared.heavyTap()
                    } else {
                        shakeCamera(intensity: 6.0, duration: 0.25)
                        HapticManager.shared.mediumTap()
                    }
                    return
                }
            }

            // Mark enemy as destroyed and remove
            enemy.markAsDestroyed()
            enemy.removeFromParent()

            return
        }

        // Special handling for mine - should explode on player contact
        if enemy.enemyType == .mine {
            // Mine explodes on contact
            enemy.explodeMine(isFullExplosion: enemy.isMineArmed, completion: {
                // Mine has been removed
            })

            // Camera shake for mine explosion (bigger if armed)
            if enemy.isMineArmed {
                shakeCamera(intensity: 12.0, duration: 0.35)
                HapticManager.shared.heavyTap()
            } else {
                shakeCamera(intensity: 6.0, duration: 0.25)
                HapticManager.shared.mediumTap()
            }

            // Play hit sound
            SoundManager.shared.playHitSound(on: self)

            // Lose a life
            lives -= 1

            // Check for game over
            if lives <= 0 {
                playerDestroyed()
                return
            }

            // Reset powerups on life loss
            player.resetPowerUps()

            // Cancel all powerup timers
            removeAction(forKey: "shieldDeactivation")
            removeAction(forKey: "lightningDeactivation")
            removeAction(forKey: "rapidFireDeactivation")
            removeAction(forKey: "magnetDeactivation")
            removeAction(forKey: "slowMotionDeactivation")
            removeAction(forKey: "scoreMultiplierDeactivation")
            removeAction(forKey: "barrierDeactivation")

            // Reset score multiplier
            scoreMultiplier = 1

            // Reset speeds for all entities
            resetEntitySpeeds()

            // Play hit animation and activate invulnerability
            player.playHitAnimation()
            activateInvulnerability()

            return
        }

        // Normal enemy collision
        // Explosion effect
        createExplosion(at: enemy.position)
        HapticManager.shared.mediumTap()

        // Mark enemy as destroyed to prevent completion callback
        enemy.markAsDestroyed()
        enemy.removeFromParent()

        // Play hit sound
        SoundManager.shared.playHitSound(on: self)

        // Lose a life
        lives -= 1

        // Check for game over
        if lives <= 0 {
            playerDestroyed()
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
                // Shield absorbs the hit - just create visual feedback
                createExplosion(at: bullet.position)
                SoundManager.shared.playShieldHitSound(on: self)
                HapticManager.shared.lightTap()
            }
            bullet.removeFromParent()
            return
        }

        // Small explosion effect
        createExplosion(at: bullet.position)
        bullet.removeFromParent()

        // Play hit sound
        SoundManager.shared.playHitSound(on: self)

        // Lose a life
        lives -= 1

        // Check for game over
        if lives <= 0 {
            playerDestroyed()
            return
        }

        // Reset powerups on life loss
        player.resetPowerUps()

        // Cancel all powerup timers
        removeAction(forKey: "shieldDeactivation")
        removeAction(forKey: "lightningDeactivation")
        removeAction(forKey: "rapidFireDeactivation")
        removeAction(forKey: "magnetDeactivation")
        removeAction(forKey: "slowMotionDeactivation")
        removeAction(forKey: "scoreMultiplierDeactivation")
        removeAction(forKey: "barrierDeactivation")

        // Reset score multiplier
        scoreMultiplier = 1

        // Reset speeds for all entities
        resetEntitySpeeds()

        // Play hit animation and activate invulnerability
        player.playHitAnimation()
        activateInvulnerability()
    }

    private func playerDidCollideWithObstacle(obstacle: Obstacle?) {
        guard obstacle != nil else { return }

        // Skip if player is invulnerable or has shield
        if isInvulnerable || player.hasShield {
            if player.hasShield {
                // Shield absorbs the hit - just create visual feedback
                createExplosion(at: player.position)
                HapticManager.shared.heavyTap()
            }
            return
        }

        // Create explosion effect at player position with camera shake
        createExplosion(at: player.position)
        shakeCamera(intensity: 15.0, duration: 0.4)
        HapticManager.shared.heavyTap()

        // Play hit sound
        SoundManager.shared.playHitSound(on: self)

        // Lose a life
        lives -= 1

        // Check for game over
        if lives <= 0 {
            playerDestroyed()
            return
        }

        // Reset powerups on life loss
        player.resetPowerUps()

        // Cancel all powerup timers
        removeAction(forKey: "shieldDeactivation")
        removeAction(forKey: "lightningDeactivation")
        removeAction(forKey: "rapidFireDeactivation")
        removeAction(forKey: "magnetDeactivation")
        removeAction(forKey: "slowMotionDeactivation")
        removeAction(forKey: "scoreMultiplierDeactivation")
        removeAction(forKey: "barrierDeactivation")

        // Reset score multiplier
        scoreMultiplier = 1

        // Reset speeds for all entities
        resetEntitySpeeds()

        // Play hit animation and activate invulnerability
        player.playHitAnimation()
        activateInvulnerability()
    }

    private func bulletDidCollideWithObstacle(bullet: SKShapeNode?) {
        guard let bullet = bullet else { return }

        // Simply remove the bullet - no explosion for bullet hitting obstacle
        bullet.removeFromParent()
    }

    // New method specifically for bullet hitting destructible block
    private func bulletDidCollideWithObstacle(bullet: SKShapeNode?, obstacle: Obstacle?, hitNode: SKNode?) {
        guard let bullet = bullet else { return }

        // Check if this is a destructible wall
        if let obstacle = obstacle, obstacle.type == .destructibleWall {
            // Destroy the specific block that was hit
            let blockDestroyed = obstacle.destroyBlock(hitNode: hitNode)

            if blockDestroyed {
                // Small hit effect for destroying block
                createSmallHitEffect(at: bullet.position)

                // Play obstacle hit sound
                SoundManager.shared.playObstacleHitSound(on: self)
            }
        }

        // Remove the bullet
        bullet.removeFromParent()
    }    // Helper method for small hit effect (less intense than enemy explosion)
    private func createSmallHitEffect(at position: CGPoint) {
        // Create small particles
        for _ in 0..<3 {
            let particle = SKShapeNode(circleOfRadius: 2)
            particle.fillColor = UIColor(red: 1.0, green: 0.9, blue: 0.6, alpha: 1.0)
            particle.strokeColor = .clear
            particle.position = position
            particle.zPosition = 100

            addChild(particle)

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 10...20)
            let dx = cos(angle) * distance
            let dy = sin(angle) * distance

            let move = SKAction.moveBy(x: dx, y: dy, duration: 0.2)
            let fadeOut = SKAction.fadeOut(withDuration: 0.2)
            let group = SKAction.group([move, fadeOut])
            let remove = SKAction.removeFromParent()

            particle.run(SKAction.sequence([group, remove]))
        }
    }

    private func playerDidCollideWithPowerUp(powerUp: PowerUp?) {
        guard let powerUp = powerUp else { return }

        // Check if already collected (prevent multiple calls)
        if powerUp.physicsBody == nil { return }

        // Immediately disable physics to prevent multiple collisions
        powerUp.physicsBody = nil

        // Play power-up sound
        SoundManager.shared.playPowerUpSound(on: self)

        // Add score for collecting powerup (no multiplier for powerup points)
        score += powerUp.powerUpType.points

        // Apply powerup effect based on type
        switch powerUp.powerUpType {
        case .extraLife:
            if lives < 4 {
                lives += 1
                SoundManager.shared.playExtraLifeSound(on: self)
                HapticManager.shared.heavyTap()
            }

        case .multiShot:
            if player.bulletCount < 4 {
                player.bulletCount += 1
                SoundManager.shared.playMultiShotActivateSound(on: self)
                HapticManager.shared.lightTap()
            }

        case .sideMissiles:
            if player.sideMissileCount < 2 {
                player.sideMissileCount += 1
                SoundManager.shared.playMissileSound(on: self)
                HapticManager.shared.lightTap()
            }

        case .shield:
            activateShield()
            SoundManager.shared.playShieldActivateSound(on: self)
            HapticManager.shared.heavyTap()

        case .lightning:
            activateLightningWeapon()
            SoundManager.shared.playLightningSound(on: self)
            HapticManager.shared.heavyTap()

        case .rapidFire:
            activateRapidFire()
            SoundManager.shared.playRapidFireActivateSound(on: self)
            HapticManager.shared.mediumTap()

        case .magnet:
            activateMagnet()
            SoundManager.shared.playMagnetActivateSound(on: self)
            HapticManager.shared.mediumTap()

        case .slowMotion:
            activateSlowMotion()
            SoundManager.shared.playSlowMotionActivateSound(on: self)
            HapticManager.shared.heavyTap()

        case .freezeBomb:
            activateFreezeBomb()
            HapticManager.shared.heavyTap()

        case .homingMissiles:
            launchHomingMissiles()
            SoundManager.shared.playMissileSound(on: self)
            HapticManager.shared.heavyTap()

        case .scoreMultiplier:
            activateScoreMultiplier()
            SoundManager.shared.playScoreMultiplierSound(on: self)
            HapticManager.shared.mediumTap()

        case .barrier:
            activateBarrier()
            SoundManager.shared.playBarrierActivateSound(on: self)
            HapticManager.shared.heavyTap()

        case .nuke:
            activateNuke()
            HapticManager.shared.heavyTap()
        }

        // Animate powerup collection
        powerUp.collect()
    }

    private func playerDidCollideWithCoin(coin: Coin?) {
        guard let coin = coin else { return }

        // Check if already collected (prevent multiple calls)
        if coin.physicsBody == nil { return }

        // Immediately disable physics to prevent multiple collisions
        coin.physicsBody = nil

        // Play coin sound
        SoundManager.shared.playCoinSound(on: self)

        // Add score for collecting coin
        addScore(coin.pointValue)

        // Track coin collection
        coinsCollected += 1

        // Light haptic feedback
        HapticManager.shared.lightTap()

        // Animate coin flying to score label
        coin.collect(scorePosition: scoreLabel.position)
    }

    private func bulletDidCollideWithAsteroid(bullet: SKShapeNode?, asteroid: Asteroid?) {
        guard let bullet = bullet, let asteroid = asteroid else { return }

        bullet.removeFromParent()

        // Create explosion effect
        asteroid.createExplosionEffect()
        HapticManager.shared.mediumTap()

        // Play asteroid hit sound
        SoundManager.shared.playAsteroidHitSound(on: self)

        // Add score based on asteroid size
        addScore(asteroid.asteroidSize.points)

        // Split asteroid if it has a next size
        // (AsteroidManager handles adding split pieces to scene and starting their movement)
        asteroidManager?.splitAsteroid(asteroid)

        // Mark asteroid as destroyed and remove it
        asteroid.markAsDestroyed()
        asteroid.removeFromParent()
    }

    private func playerDidCollideWithAsteroid(asteroid: Asteroid?) {
        guard let asteroid = asteroid else { return }

        // Check if player is invulnerable or has shield
        if isInvulnerable || player.hasShield {
            if player.hasShield {
                // Shield absorbs the hit
                player.hasShield = false
                HapticManager.shared.mediumTap()
            }

            // Still destroy the asteroid
            createExplosion(at: asteroid.position)

            // Split asteroid (AsteroidManager handles adding split pieces to scene)
            asteroidManager?.splitAsteroid(asteroid)

            asteroid.markAsDestroyed()
            asteroid.removeFromParent()
            return
        }

        // Explosion effect
        createExplosion(at: asteroid.position)
        HapticManager.shared.mediumTap()

        // Split asteroid even on player collision
        // (AsteroidManager handles adding split pieces to scene)
        asteroidManager?.splitAsteroid(asteroid)

        // Mark asteroid as destroyed
        asteroid.markAsDestroyed()
        asteroid.removeFromParent()

        // Play hit sound
        SoundManager.shared.playHitSound(on: self)

        // Lose a life
        lives -= 1

        // Check for game over
        if lives <= 0 {
            playerDestroyed()
            return
        }

        // Reset powerups on life loss
        player.resetPowerUps()

        // Cancel all powerup timers
        removeAction(forKey: "shieldDeactivation")
        removeAction(forKey: "lightningDeactivation")
        removeAction(forKey: "rapidFireDeactivation")
        removeAction(forKey: "magnetDeactivation")
        removeAction(forKey: "slowMotionDeactivation")
        removeAction(forKey: "scoreMultiplierDeactivation")
        removeAction(forKey: "barrierDeactivation")

        // Reset score multiplier
        scoreMultiplier = 1

        // Reset speeds for all entities
        resetEntitySpeeds()

        // Play hit animation and activate invulnerability
        player.playHitAnimation()
        activateInvulnerability()
    }

    private func activateShield() {
        player.hasShield = true

        // Cancel any previous shield deactivation
        removeAction(forKey: "shieldDeactivation")

        // Deactivate shield after duration using SKAction (respects pause)
        let wait = SKAction.wait(forDuration: 5.0)
        let deactivate = SKAction.run { [weak self] in
            guard let self = self else { return }
            if self.player.hasShield {
                self.player.hasShield = false
                // Play shield deactivate sound
                SoundManager.shared.playShieldDeactivateSound(on: self)
            }
        }
        run(SKAction.sequence([wait, deactivate]), withKey: "shieldDeactivation")
    }

    private func activateLightningWeapon() {
        player.hasLightningWeapon = true

        // Cancel any previous lightning weapon deactivation
        removeAction(forKey: "lightningDeactivation")

        // Deactivate lightning weapon after duration (7 seconds) using SKAction (respects pause)
        let wait = SKAction.wait(forDuration: 7.0)
        let deactivate = SKAction.run { [weak self] in
            guard let self = self else { return }
            if self.player.hasLightningWeapon {
                self.player.hasLightningWeapon = false
            }
        }
        run(SKAction.sequence([wait, deactivate]), withKey: "lightningDeactivation")
    }

    private func activateRapidFire() {
        player.hasRapidFire = true

        // Cancel any previous rapid fire deactivation
        removeAction(forKey: "rapidFireDeactivation")

        // Deactivate after 8 seconds
        let wait = SKAction.wait(forDuration: 8.0)
        let deactivate = SKAction.run { [weak self] in
            self?.player.hasRapidFire = false
        }
        run(SKAction.sequence([wait, deactivate]), withKey: "rapidFireDeactivation")
    }

    private func activateMagnet() {
        player.hasMagnet = true

        // Cancel any previous magnet deactivation
        removeAction(forKey: "magnetDeactivation")

        // Deactivate after 10 seconds
        let wait = SKAction.wait(forDuration: 10.0)
        let deactivate = SKAction.run { [weak self] in
            self?.player.hasMagnet = false
        }
        run(SKAction.sequence([wait, deactivate]), withKey: "magnetDeactivation")
    }

    private func activateSlowMotion() {
        player.hasSlowMotion = true

        // Cancel any previous slow motion deactivation
        removeAction(forKey: "slowMotionDeactivation")

        // Deactivate after 6 seconds
        let wait = SKAction.wait(forDuration: 6.0)
        let deactivate = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.player.hasSlowMotion = false

            // Reset speed for all enemies, asteroids and bullets
            self.gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
                node.speed = 1.0
            }
            self.gameContentNode.enumerateChildNodes(withName: "asteroid") { node, _ in
                node.speed = 1.0
            }
            self.gameContentNode.enumerateChildNodes(withName: "enemyBullet") { node, _ in
                node.speed = 1.0
            }
        }
        run(SKAction.sequence([wait, deactivate]), withKey: "slowMotionDeactivation")
    }

    private func activateFreezeBomb() {
        // Freeze all enemies for 3 seconds
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy {
                enemy.freeze(duration: 3.0)
            }
        }

        // Visual feedback - flash effect
        let flash = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        flash.fillColor = UIColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 0.3)
        flash.strokeColor = .clear
        flash.zPosition = 50
        gameContentNode.addChild(flash)

        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        flash.run(SKAction.sequence([fadeOut, remove]))
    }

    private func launchHomingMissiles() {
        // Find up to 3 closest enemies
        var enemies: [Enemy] = []
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy {
                enemies.append(enemy)
            }
        }

        // Sort by distance and take closest 3
        enemies.sort { enemy1, enemy2 in
            let dist1 = hypot(enemy1.position.x - player.position.x, enemy1.position.y - player.position.y)
            let dist2 = hypot(enemy2.position.x - player.position.x, enemy2.position.y - player.position.y)
            return dist1 < dist2
        }

        let targets = Array(enemies.prefix(3))

        // If no enemies found, target boss if active
        if targets.isEmpty && bossManager.isBossActive() {
            if let _ = bossManager.getBoss() {
                for i in 0..<3 {
                    let delay = SKAction.wait(forDuration: Double(i) * 0.2)
                    let launch = SKAction.run { [weak self] in
                        self?.createHomingMissileForBoss()
                    }
                    run(SKAction.sequence([delay, launch]))
                }
            }
            return
        }

        // Launch a homing missile for each target
        for (index, target) in targets.enumerated() {
            let delay = SKAction.wait(forDuration: Double(index) * 0.2)
            let launch = SKAction.run { [weak self] in
                self?.createHomingMissile(target: target)
            }
            run(SKAction.sequence([delay, launch]))
        }
    }

    private func createHomingMissile(target: Enemy) {
        let missile = SKShapeNode(rectOf: CGSize(width: 8, height: 20), cornerRadius: 4)
        missile.fillColor = UIColor(red: 1.0, green: 0.2, blue: 0.5, alpha: 1.0)
        missile.strokeColor = UIColor(red: 1.0, green: 0.5, blue: 0.7, alpha: 1.0)
        missile.lineWidth = 2
        missile.position = player.position
        missile.name = "homingMissile"
        missile.zPosition = 10
        gameContentNode.addChild(missile)

        // Add glow
        GlowHelper.addEnhancedGlow(to: missile, color: UIColor(red: 1.0, green: 0.3, blue: 0.6, alpha: 1.0), intensity: 1.2)

        // Physics body
        missile.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 8, height: 20))
        missile.physicsBody?.isDynamic = true
        missile.physicsBody?.categoryBitMask = PhysicsCategory.bullet
        missile.physicsBody?.contactTestBitMask = PhysicsCategory.enemy
        missile.physicsBody?.collisionBitMask = PhysicsCategory.none

        // Homing behavior
        let homingAction = SKAction.customAction(withDuration: 5.0) { [weak self, weak target, weak missile] node, elapsedTime in
            guard let self = self, let target = target, let missile = missile else {
                node.removeFromParent()
                return
            }

            // Calculate direction to target
            let dx = target.position.x - missile.position.x
            let dy = target.position.y - missile.position.y
            let angle = atan2(dy, dx)

            // Move towards target
            let speed: CGFloat = 300 * CGFloat(self.deltaTime)
            missile.position.x += cos(angle) * speed
            missile.position.y += sin(angle) * speed

            // Rotate missile to face direction
            missile.zRotation = angle - .pi / 2
        }

        let remove = SKAction.removeFromParent()
        missile.run(SKAction.sequence([homingAction, remove]))
    }

    private func createHomingMissileForBoss() {
        guard let boss = bossManager.getBoss() else { return }

        let missile = SKShapeNode(rectOf: CGSize(width: 8, height: 20), cornerRadius: 4)
        missile.fillColor = UIColor(red: 1.0, green: 0.2, blue: 0.5, alpha: 1.0)
        missile.strokeColor = UIColor(red: 1.0, green: 0.5, blue: 0.7, alpha: 1.0)
        missile.lineWidth = 2
        missile.position = player.position
        missile.name = "homingMissile"
        missile.zPosition = 10
        gameContentNode.addChild(missile)

        // Add glow
        GlowHelper.addEnhancedGlow(to: missile, color: UIColor(red: 1.0, green: 0.3, blue: 0.6, alpha: 1.0), intensity: 1.2)

        // Physics body - use bullet category so it triggers boss collision
        missile.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 8, height: 20))
        missile.physicsBody?.isDynamic = true
        missile.physicsBody?.categoryBitMask = PhysicsCategory.bullet
        missile.physicsBody?.contactTestBitMask = PhysicsCategory.enemy
        missile.physicsBody?.collisionBitMask = PhysicsCategory.none

        // Homing behavior targeting boss
        let homingAction = SKAction.customAction(withDuration: 5.0) { [weak self, weak boss, weak missile] node, elapsedTime in
            guard let self = self, let missile = missile else {
                node.removeFromParent()
                return
            }

            // Check if boss is still alive
            guard self.bossManager.isBossActive(), let boss = boss else {
                node.removeFromParent()
                return
            }

            // Calculate direction to boss
            let dx = boss.position.x - missile.position.x
            let dy = boss.position.y - missile.position.y
            let angle = atan2(dy, dx)

            // Move towards boss
            let speed: CGFloat = 300 * CGFloat(self.deltaTime)
            missile.position.x += cos(angle) * speed
            missile.position.y += sin(angle) * speed

            // Rotate missile to face direction
            missile.zRotation = angle - .pi / 2
        }

        let remove = SKAction.removeFromParent()
        missile.run(SKAction.sequence([homingAction, remove]))
    }

    private func activateScoreMultiplier() {
        scoreMultiplier = 2
        player.hasScoreMultiplier = true

        // Cancel any previous multiplier deactivation
        removeAction(forKey: "scoreMultiplierDeactivation")

        // Deactivate after 12 seconds
        let wait = SKAction.wait(forDuration: 12.0)
        let deactivate = SKAction.run { [weak self] in
            self?.scoreMultiplier = 1
            self?.player.hasScoreMultiplier = false
        }
        run(SKAction.sequence([wait, deactivate]), withKey: "scoreMultiplierDeactivation")
    }

    private func activateBarrier() {
        player.hasBarrier = true

        // Cancel any previous barrier deactivation
        removeAction(forKey: "barrierDeactivation")

        // Wait a frame for barrier visuals to be created, then setup physics
        let waitForVisuals = SKAction.wait(forDuration: 0.01)
        let setupPhysics = SKAction.run { [weak self] in
            guard let self = self else { return }

            // Setup physics for barrier segments
            self.player.enumerateChildNodes(withName: "barrierSegment") { node, _ in
                if node.physicsBody == nil {
                    node.physicsBody = SKPhysicsBody(circleOfRadius: 8)
                    node.physicsBody?.isDynamic = false
                    node.physicsBody?.categoryBitMask = PhysicsCategory.player
                    node.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.enemyBullet
                    node.physicsBody?.collisionBitMask = PhysicsCategory.none
                }
            }
        }
        run(SKAction.sequence([waitForVisuals, setupPhysics]), withKey: "barrierPhysicsSetup")

        // Deactivate after 8 seconds
        let wait = SKAction.wait(forDuration: 8.0)
        let deactivate = SKAction.run { [weak self] in
            self?.player.hasBarrier = false
        }
        run(SKAction.sequence([wait, deactivate]), withKey: "barrierDeactivation")
    }

    private func activateNuke() {
        // Destroy all enemies except bosses
        var enemiesToDestroy: [Enemy] = []
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy {
                enemiesToDestroy.append(enemy)
            }
        }

        // Destroy each enemy with explosion
        for (index, enemy) in enemiesToDestroy.enumerated() {
            let delay = Double(index) * 0.05
            let destroyAction = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    self?.createExplosion(at: enemy.position)
                    self?.addScore(enemy.enemyType.points)
                    enemy.markAsDestroyed()
                    enemy.removeFromParent()
                }
            ])
            run(destroyAction)
        }

        // Destroy all asteroids
        var asteroidsToDestroy: [Asteroid] = []
        gameContentNode.enumerateChildNodes(withName: "asteroid") { node, _ in
            if let asteroid = node as? Asteroid {
                asteroidsToDestroy.append(asteroid)
            }
        }

        for (index, asteroid) in asteroidsToDestroy.enumerated() {
            let delay = Double(index) * 0.05
            let destroyAction = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    asteroid.createExplosionEffect()
                    self?.addScore(asteroid.asteroidSize.points)
                    asteroid.markAsDestroyed()
                    asteroid.removeFromParent()
                }
            ])
            run(destroyAction)
        }

        // Visual effect - big flash
        let flash = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        flash.fillColor = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 0.6)
        flash.strokeColor = .clear
        flash.zPosition = 50
        gameContentNode.addChild(flash)

        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.1),
            SKAction.fadeAlpha(to: 0.6, duration: 0.1),
            SKAction.fadeAlpha(to: 0.0, duration: 0.3)
        ])
        let remove = SKAction.removeFromParent()
        flash.run(SKAction.sequence([pulse, remove]))

        // Screen shake
        shakeCamera(intensity: 15)
    }

    private func addScore(_ points: Int) {
        score += points * scoreMultiplier
    }

    private func resetEntitySpeeds() {
        // Reset speed for all enemies, asteroids and bullets to normal
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            node.speed = 1.0
        }
        gameContentNode.enumerateChildNodes(withName: "asteroid") { node, _ in
            node.speed = 1.0
        }
        gameContentNode.enumerateChildNodes(withName: "enemyBullet") { node, _ in
            node.speed = 1.0
        }
    }

    private var deltaTime: TimeInterval = 0

    private func attractCoins() {
        let magnetRadius: CGFloat = 200
        gameContentNode.enumerateChildNodes(withName: "coin") { [weak self] node, _ in
            guard let self = self, let coin = node as? Coin else { return }

            let dx = self.player.position.x - coin.position.x
            let dy = self.player.position.y - coin.position.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance < magnetRadius && distance > 0 {
                // Move coin towards player
                let speed: CGFloat = 300
                let moveX = (dx / distance) * speed * CGFloat(self.deltaTime)
                let moveY = (dy / distance) * speed * CGFloat(self.deltaTime)
                coin.position.x += moveX
                coin.position.y += moveY
            }
        }
    }

    private func applySlowMotion() {
        let slowFactor: CGFloat = 0.5

        // Slow down enemies
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if node.speed != slowFactor {
                node.speed = slowFactor
            }
        }

        // Slow down asteroids
        gameContentNode.enumerateChildNodes(withName: "asteroid") { node, _ in
            if node.speed != slowFactor {
                node.speed = slowFactor
            }
        }

        // Slow down enemy bullets
        gameContentNode.enumerateChildNodes(withName: "enemyBullet") { node, _ in
            if node.speed != slowFactor {
                node.speed = slowFactor
            }
        }
    }

    private func activateInvulnerability() {
        isInvulnerable = true

        // Play invulnerability sound
        SoundManager.shared.playInvulnerabilitySound(on: self)

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
        // Pause gameplay immediately
        gameContentNode.isPaused = true
        physicsWorld.speed = 0

        // Transition to new scene
        newScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: transitionDuration)
        view?.presentScene(newScene, transition: transition)

        // Clean up after transition completes using SKAction
        // Note: This still runs even after scene change, but that's intentional for cleanup
        let wait = SKAction.wait(forDuration: transitionDuration + 0.1)
        let cleanup = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.removeAllChildren()
        }
        run(SKAction.sequence([wait, cleanup]))
    }

    private func playerDestroyed() {
        // Prevent multiple calls
        if !isGameStarted { return }
        isGameStarted = false

        // Stop all player actions and shooting
        player.removeAllActions()

        // Create sequence of explosion actions
        var explosionActions: [SKAction] = []
        let explosionCount = 6

        for i in 0..<explosionCount {
            let wait = SKAction.wait(forDuration: 0.15)
            let explode = SKAction.run { [weak self] in
                guard let self = self else { return }

                let offsetX = CGFloat.random(in: -15...15)
                let offsetY = CGFloat.random(in: -15...15)
                let explosionPos = CGPoint(x: self.player.position.x + offsetX,
                                          y: self.player.position.y + offsetY)

                self.createExplosion(at: explosionPos)
                HapticManager.shared.mediumTap()

                // Camera shake for each explosion
                self.shakeCamera(intensity: 8.0, duration: 0.2)
            }

            if i > 0 {
                explosionActions.append(wait)
            }
            explosionActions.append(explode)
        }

        // Final large explosion and fade out player
        let finalWait = SKAction.wait(forDuration: 0.15)
        let finalExplosion = SKAction.run { [weak self] in
            guard let self = self else { return }

            // Large explosion at player center
            self.createExplosion(at: self.player.position)
            HapticManager.shared.heavyTap()
            self.shakeCamera(intensity: 15.0, duration: 0.4)

            // Fade out player
            let fadeOut = SKAction.fadeOut(withDuration: 0.3)
            self.player.run(fadeOut)
        }

        explosionActions.append(finalWait)
        explosionActions.append(finalExplosion)

        // Call game over after final explosion and fade
        let gameOverWait = SKAction.wait(forDuration: 0.5)
        let callGameOver = SKAction.run { [weak self] in
            self?.gameOver()
        }
        explosionActions.append(gameOverWait)
        explosionActions.append(callGameOver)

        // Run the entire sequence
        run(SKAction.sequence(explosionActions), withKey: "playerDestruction")
    }

    private func gameOver() {
        // Play game over sound
        SoundManager.shared.playGameOverSound(on: self)

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

    // Camera shake effect for explosions
    func shakeCamera(intensity: CGFloat = 10.0, duration: TimeInterval = 0.3) {
        guard let camera = camera else { return }

        // Original position is always the center of the scene
        let originalPosition = CGPoint(x: size.width / 2, y: size.height / 2)

        // Create shake sequence
        var shakeActions: [SKAction] = []
        let shakeSteps = 8

        for _ in 0..<shakeSteps {
            let randomX = CGFloat.random(in: -intensity...intensity)
            let randomY = CGFloat.random(in: -intensity...intensity)
            let shakeMove = SKAction.move(to: CGPoint(x: originalPosition.x + randomX,
                                                       y: originalPosition.y + randomY),
                                          duration: duration / Double(shakeSteps))
            shakeActions.append(shakeMove)
        }

        // Return to original position
        let returnMove = SKAction.move(to: originalPosition, duration: 0.05)
        shakeActions.append(returnMove)

        // Run shake sequence on camera
        let shakeSequence = SKAction.sequence(shakeActions)
        camera.run(shakeSequence)
    }

    private func createExplosion(at position: CGPoint) {
        // Play explosion sound
        SoundManager.shared.playExplosionSound(on: self)

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
        // Check if player is exiting and off screen (must be before pause/start checks)
        if isPlayerExiting && player.position.y > size.height + 50 {
            isPlayerExiting = false
            levelComplete()
            return
        }

        // Don't update game logic when paused or game hasn't started yet
        if gameContentNode.isPaused || !isGameStarted { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }

        // Calculate delta time for smooth animations
        deltaTime = currentTime - lastUpdateTime

        // Magnet effect - attract coins
        if player.hasMagnet {
            attractCoins()
        }

        // Shoot only when touching and player is near touch location
        if isTouching && currentTime - lastShootTime > currentShootInterval {
            let distance = abs(player.position.x - touchLocation.x)
            if distance <= shootDistanceThreshold {
                shoot()
                lastShootTime = currentTime
            }
        }

        // Update enemy spawning (with slow motion modifier)
        enemyManager.update(currentTime: currentTime)

        // Update obstacle spawning
        obstacleManager.update(currentTime: currentTime)

        // Update powerup spawning
        powerUpManager.update(currentTime: currentTime)

        // Update coin spawning
        coinManager.update(currentTime: currentTime)

        // Update asteroid spawning
        asteroidManager?.update(currentTime: currentTime)

        // Apply slow motion to enemies, asteroids, and bullets if active
        if player.hasSlowMotion {
            applySlowMotion()
        }

        // Check level completion - simple approach
        checkLevelCompletion(currentTime: currentTime)

        lastUpdateTime = currentTime
    }

    private func checkLevelCompletion(currentTime: TimeInterval) {
        // If boss is active, don't check for level completion
        // (level completes when boss is defeated)
        if isBossActive || bossSpawned {
            return
        }

        // Only check if all waves have been spawned
        guard enemyManager.areAllWavesSpawned() else {
            return
        }

        // Check if all asteroid waves are spawned and cleared (if manager exists)
        if let asteroidMgr = asteroidManager {
            guard asteroidMgr.allAsteroidsCleared else {
                return
            }
        }

        // Count actual Enemy nodes in the scene - 100% reliable
        var enemyCount = 0
        enumerateChildNodes(withName: "//*") { node, _ in
            if node is Enemy {
                enemyCount += 1
            }
        }

        if enemyCount == 0 {
            // No enemies on screen
            if noEnemiesTime == nil {
                // First time we detected no enemies
                noEnemiesTime = currentTime
            } else {
                // Check if enough time has passed
                let timeWithoutEnemies = currentTime - noEnemiesTime!
                if timeWithoutEnemies >= levelCompletionDelay {
                    // Spawn boss instead of completing level
                    spawnBoss()
                }
            }
        } else {
            // There are still enemies, reset timer
            noEnemiesTime = nil
        }
    }

    private func spawnBoss() {
        guard !bossSpawned else { return }

        bossSpawned = true
        isBossActive = true

        // Stop spawning regular enemies, obstacles, and coins
        enemyManager.stopSpawning()
        obstacleManager.stopSpawning()
        coinManager.setBossFight(true)

        // Show warning before boss appears
        showBossWarning {
            // Play boss appear sound
            SoundManager.shared.playBossAppearSound(on: self)
            // Spawn the boss after warning
            self.bossManager.spawnBoss(level: self.currentLevel) {
                // Boss entrance complete, attacks begin
            }
        }
    }

    private func showBossWarning(completion: @escaping () -> Void) {
        // Play warning sound
        SoundManager.shared.playWarningSound(on: self)

        let warningNode = SKNode()
        warningNode.zPosition = 1500
        warningNode.name = "bossWarning"

        // Red pulsing background overlay
        let overlay = SKSpriteNode(color: UIColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 0.3), size: size)
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.alpha = 0
        warningNode.addChild(overlay)

        // WARNING text
        let warningLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        warningLabel.text = "! WARNING !"
        warningLabel.fontSize = 40
        warningLabel.fontColor = UIColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 1.0)
        warningLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 40)
        warningLabel.alpha = 0
        warningNode.addChild(warningLabel)

        // Danger approaching text
        let approachingLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        approachingLabel.text = "EXTREME DANGER"
        approachingLabel.fontSize = 28
        approachingLabel.fontColor = .white
        approachingLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
        approachingLabel.alpha = 0
        warningNode.addChild(approachingLabel)

        addChild(warningNode)

        // Haptic feedback for drama
        HapticManager.shared.heavyTap()

        // Pulsing animation for overlay
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 0.3),
            SKAction.fadeAlpha(to: 0.2, duration: 0.3)
        ])
        let repeatPulse = SKAction.repeat(pulse, count: 4)
        overlay.run(SKAction.sequence([SKAction.fadeIn(withDuration: 0.2), repeatPulse]))

        // Warning text animation
        let scaleUp = SKAction.scale(to: 1.1, duration: 0.2)
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.2)
        let shake = SKAction.sequence([scaleUp, scaleDown])
        let repeatShake = SKAction.repeat(shake, count: 4)

        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
        let wait = SKAction.wait(forDuration: 2.0)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)

        warningLabel.run(SKAction.sequence([fadeIn, repeatShake, fadeOut]))
        approachingLabel.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.2),
            fadeIn,
            wait,
            fadeOut
        ]))

        // Remove warning and spawn boss
        let cleanup = SKAction.run {
            warningNode.removeFromParent()
            completion()
        }

        run(SKAction.sequence([
            SKAction.wait(forDuration: 2.8),
            cleanup
        ]))
    }

    private func startPlayerExitAnimation() {
        // Disable player controls during exit
        isGameStarted = false
        isPlayerExiting = true

        // Play player exit sound
        SoundManager.shared.playPlayerExitSound(on: self)

        // Animate player exiting upward with smooth easeIn for acceleration
        let targetY = size.height + 150
        let moveUp = SKAction.moveTo(y: targetY, duration: 1.8)
        moveUp.timingMode = .easeIn // Smooth acceleration
        player.run(moveUp)

        // The update() method will now check if player is off screen
    }

    private func levelComplete() {
        // Play level complete sound
        SoundManager.shared.playLevelCompleteSound(on: self)

        let totalCoins = coinManager.getTotalCoinsForLevel()

        let levelCompleteScene = LevelCompleteScene(
            size: size,
            level: currentLevel,
            score: score,
            coinsCollected: coinsCollected,
            totalCoins: totalCoins
        )
        stopGameplayAndTransition(to: levelCompleteScene, transitionDuration: 1.0)
    }

    private func goToLevelSelect() {
        let levelSelectScene = LevelSelectScene(size: size)
        levelSelectScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(levelSelectScene, transition: transition)
    }
}
