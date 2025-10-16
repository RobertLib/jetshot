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
    static let barrier: UInt32 = 0b100000000 // 256
}

// Explosion sizes for camera shake intensity
enum ExplosionSize {
    case small    // Small enemies, bullets - minimal shake
    case normal   // Regular enemies - moderate shake
    case large    // Large enemies, asteroids - strong shake
    case huge     // Boss, player, nuke - maximum shake
}

/// Main game scene handling gameplay, collisions, and level progression.
/// Manages player, enemies, obstacles, power-ups, bosses, and scoring system.
class GameScene: SKScene, SKPhysicsContactDelegate {

    // Level system
    var currentLevel: Int = 1
    private var levelConfig: LevelConfig!

    // Starting weapon arsenal (loaded from previous level)
    var startingBulletCount: Int = 1
    var startingSideMissileCount: Int = 0

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
    private var lastCleanupTime: TimeInterval = 0  // For bullet cleanup optimization
    private let shootInterval: TimeInterval = 0.3
    private var currentShootInterval: TimeInterval {
        return player?.hasRapidFire == true ? 0.1 : shootInterval
    }

    // Weapon overheat system
    private var weaponHeat: CGFloat = 0.0 // 0.0 to 1.0
    private let maxHeat: CGFloat = 1.0
    private let heatPerShot: CGFloat = 0.005 // Heat added per shot (~200 shots to overheat)
    private let cooldownRate: CGFloat = 0.30 // Heat removed per second
    private let overheatCooldownTime: TimeInterval = 3.0 // Cooldown time when overheated
    private var isOverheated: Bool = false
    private var overheatStartTime: TimeInterval = 0
    private var heatBar: SKShapeNode?
    private var heatBarBackground: SKShapeNode?
    private var heatBarLabel: SKLabelNode?

    // PowerUp timers and states
    private var scoreMultiplier: Int = 1

    // PowerUp timer UI
    private var powerUpTimerBars: [String: SKNode] = [:] // Dictionary to store timer bars by powerup name

    // Performance optimization - cache active objects to avoid enumerateChildNodes every frame
    private var activeEnemies: [ObjectIdentifier: Enemy] = [:]
    private var activeCoins: [ObjectIdentifier: Coin] = [:]
    private var cachedEnemyCount: Int = 0
    private var lastSlowMotionUpdateTime: TimeInterval = 0
    private var lastMagnetUpdateTime: TimeInterval = 0

    // iPad optimization - reduce particle effects on larger screens
    private var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    private var particleMultiplier: CGFloat {
        return isIPad ? 0.6 : 1.0  // Reduce particles by 40% on iPad
    }

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

    // DEBUG: God mode for testing
    private let isGodModeEnabled = false // Set to false for normal gameplay

    // Level intro
    private var isGameStarted: Bool = false
    private var isPlayerExiting: Bool = false
    private var safeAreaBottom: CGFloat = 0

    override func didMove(to view: SKView) {
        // Load level configuration immediately (lightweight) - must be first!
        levelConfig = LevelManager.shared.getLevelConfig(for: currentLevel)

        // Validate level config
        guard levelConfig != nil else {
            print("ERROR: Failed to load level configuration for level \(currentLevel)")
            // Return to level select on error
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let levelSelectScene = LevelSelectScene(size: self.size)
                levelSelectScene.scaleMode = self.scaleMode
                self.view?.presentScene(levelSelectScene, transition: SKTransition.fade(withDuration: 0.5))
            }
            return
        }

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

            // Add parallax background (50% chance) - to game content node
            ParallaxBackgroundHelper.addParallaxBackground(to: self, parentNode: self.gameContentNode, levelNumber: self.currentLevel)

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
        let safeAreaBottomInset: CGFloat
        if let windowScene = view.window?.windowScene {
            safeAreaBottomInset = windowScene.windows.first?.safeAreaInsets.bottom ?? 0
        } else {
            safeAreaBottomInset = 0
        }
        safeAreaBottom = safeAreaBottomInset

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

    override func willMove(from view: SKView) {
        // Clean up all resources before scene is removed

        // Remove notification observers
        NotificationCenter.default.removeObserver(self)

        // Stop physics
        physicsWorld.contactDelegate = nil
        physicsWorld.speed = 0

        // Remove all actions from scene
        removeAllActions()
        gameContentNode?.removeAllActions()
        uiNode?.removeAllActions()

        // Remove all children (this also removes their actions)
        gameContentNode?.removeAllChildren()
        uiNode?.removeAllChildren()
        pauseOverlay?.removeAllChildren()
        pauseOverlay?.removeFromParent()

        // Clear manager references
        enemyManager = nil
        obstacleManager = nil
        powerUpManager = nil
        bossManager = nil
        asteroidManager = nil
        coinManager = nil

        // Clear active object caches
        activeEnemies.removeAll()
        activeCoins.removeAll()

        // Clear player reference
        player = nil

        // Reset game state
        isBossActive = false
        bossSpawned = false
        isGameStarted = false
        isTouching = false
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
        let safeAreaBottomInset: CGFloat
        if let windowScene = view.window?.windowScene {
            safeAreaBottomInset = windowScene.windows.first?.safeAreaInsets.bottom ?? 0
        } else {
            safeAreaBottomInset = 0
        }
        safeAreaBottom = safeAreaBottomInset

        player = Player(sceneSize: size, safeAreaBottom: safeAreaBottom)

        // Set starting weapon arsenal from previous level
        player.bulletCount = startingBulletCount
        player.sideMissileCount = startingSideMissileCount

        gameContentNode.addChild(player)
    }

    private func setupEnemyManager() {
        guard let config = levelConfig else {
            print("ERROR: Cannot setup EnemyManager - levelConfig is nil")
            return
        }
        enemyManager = EnemyManager(scene: self, waves: config.waves)
    }

    private func setupObstacleManager() {
        guard let config = levelConfig else {
            print("ERROR: Cannot setup ObstacleManager - levelConfig is nil")
            return
        }
        obstacleManager = ObstacleManager(scene: self, waves: config.obstacleWaves)
    }

    private func setupPowerUpManager() {
        guard let config = levelConfig else {
            print("ERROR: Cannot setup PowerUpManager - levelConfig is nil")
            return
        }
        powerUpManager = PowerUpManager(scene: self, config: config.powerUpConfig)
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
        guard let config = levelConfig else {
            print("ERROR: Cannot setup AsteroidManager - levelConfig is nil")
            return
        }
        if !config.asteroidWaves.isEmpty {
            asteroidManager = AsteroidManager(scene: self, waves: config.asteroidWaves)
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
        heatBar?.removeFromParent()
        heatBarBackground?.removeFromParent()
        heatBarLabel?.removeFromParent()

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

        // Setup heat bar
        setupHeatBar(topMargin: topMargin)
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
        guard let view = view else { return }
        let menuScene = MenuScene(size: view.bounds.size)
        menuScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(menuScene, transition: transition)
    }

    private func restartGame() {
        guard let view = view else { return }
        let gameScene = GameScene(size: view.bounds.size)
        gameScene.scaleMode = scaleMode
        gameScene.currentLevel = currentLevel
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(gameScene, transition: transition)
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
        player.moveTo(x: location.x, y: location.y, sceneWidth: size.width, sceneHeight: size.height, safeAreaBottom: safeAreaBottom)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused or game hasn't started
        if gameContentNode.isPaused || !isGameStarted { return }

        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        isTouching = true
        touchLocation = location

        // Move player instantly to follow touch smoothly
        player.moveToInstant(x: location.x, y: location.y, sceneWidth: size.width, sceneHeight: size.height, safeAreaBottom: safeAreaBottom)
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
        // Check if weapons are overheated
        if isOverheated {
            return
        }

        // If lightning weapon is active, use lightning attack
        if player.hasLightningWeapon {
            shootLightning()
            return
        }

        // Add heat from shooting
        weaponHeat += heatPerShot
        if weaponHeat >= maxHeat {
            weaponHeat = maxHeat
            triggerOverheat()
            return
        }

        updateHeatBar()

        let bullets = player.shoot()

        // Play shoot sound
        SoundManager.shared.playShootSound(on: self)

        for bullet in bullets {
            gameContentNode.addChild(bullet)

            // Check if bullet has angle (bullets 5-8)
            if let angle = bullet.userData?["angle"] as? CGFloat {
                // Calculate movement with angle
                let angleRad = angle * .pi / 180
                let distance: CGFloat = 2000
                let dx = distance * sin(angleRad)
                let dy = distance * cos(angleRad)

                let moveAction = SKAction.moveBy(x: dx, y: dy, duration: 1.5)
                let removeAction = SKAction.removeFromParent()
                bullet.run(SKAction.sequence([moveAction, removeAction]))
            } else {
                // Move bullet straight upwards (bullets 1-4)
                let moveAction = SKAction.moveTo(y: size.height + 20, duration: 1.5)
                let removeAction = SKAction.removeFromParent()
                bullet.run(SKAction.sequence([moveAction, removeAction]))
            }
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
                self.createExplosion(at: enemy.position, size: .small)

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

        // Barrier hit enemy
        if firstBody.categoryBitMask == PhysicsCategory.barrier &&
           secondBody.categoryBitMask == PhysicsCategory.enemy {
            barrierDidCollideWithEnemy(enemy: secondBody.node as? Enemy)
        }

        // Barrier hit enemy bullet
        if firstBody.categoryBitMask == PhysicsCategory.barrier &&
           secondBody.categoryBitMask == PhysicsCategory.enemyBullet {
            barrierDidCollideWithEnemyBullet(bullet: secondBody.node as? SKShapeNode)
        }
    }

    private func bulletDidCollideWithEnemy(bullet: SKShapeNode?, enemy: Enemy?) {
        guard let bullet = bullet, let enemy = enemy else { return }

        // VORTEX: Absorbs bullets (30% chance to absorb, otherwise damages vortex)
        if enemy.enemyType == .vortex {
            if Double.random(in: 0...1) < 0.3 {
                // Bullet absorbed - create absorption effect
                createVortexAbsorptionEffect(at: bullet.position, vortex: enemy)
                bullet.removeFromParent()
                return
            }
            // If not absorbed, bullet damages vortex normally (continue below)
        }

        // MIRROR: Reflects bullets back at player (50% chance)
        if enemy.enemyType == .mirror {
            if Double.random(in: 0...1) < 0.5 {
                // Reflect bullet back
                reflectBullet(bullet, from: enemy)
                return
            }
            // If not reflected, bullet damages mirror normally (continue below)
        }

        // SHIELD: Check if bullet hits the shield
        if enemy.enemyType == .shield {
            if isHittingShield(bullet: bullet, enemy: enemy) {
                // Bullet blocked by shield - just remove it
                createSparkEffect(at: bullet.position)
                SoundManager.shared.playShieldBlockSound(on: self)
                bullet.removeFromParent()
                return
            }
            // If not hitting shield, bullet damages enemy normally (continue below)
        }

        bullet.removeFromParent()

        // Decrease enemy health
        enemy.health -= 1

        // Check if enemy is destroyed
        if enemy.health <= 0 {
            // Special handling for mine - explode with shrapnel when shot
            if enemy.enemyType == .mine {
                // Add score
                let points = enemy.enemyType.points
                addScore(points)

                // Show floating score
                let scoreText = "+\(points * scoreMultiplier)"
                showFloatingText(scoreText, at: enemy.position, color: UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0))

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
            } else if enemy.enemyType == .splitter {
                // SPLITTER: Splits into 2 smaller enemies when destroyed
                // Explosion effect
                createExplosion(at: enemy.position)
                HapticManager.shared.mediumTap()

                // Add score based on enemy type
                let points = enemy.enemyType.points
                addScore(points)

                // Show floating score
                let scoreText = "+\(points * scoreMultiplier)"
                showFloatingText(scoreText, at: enemy.position, color: UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0))

                // Play splitter split sound
                SoundManager.shared.playSplitterSplitSound(on: self)

                // Create 2 smaller splitter enemies
                createSplitterFragments(at: enemy.position)

                // Mark enemy as destroyed to prevent completion callback
                enemy.markAsDestroyed()
                enemy.removeFromParent()
                return
            } else {
                // Normal enemy destruction
                // Explosion effect
                createExplosion(at: enemy.position, size: .normal)
                HapticManager.shared.mediumTap()

                // Add score based on enemy type
                let points = enemy.enemyType.points
                addScore(points)

                // Show floating score
                let scoreText = "+\(points * scoreMultiplier)"
                showFloatingText(scoreText, at: enemy.position, color: UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0))

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

            // Show floating score
            let scoreText = "+\(result.points)"
            showFloatingText(scoreText, at: boss.position, color: UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0), fontSize: 32)

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
                createExplosion(at: enemy.position, size: .small)
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

            // Check if player has any powerups
            if player.hasAnyPowerUps() {
                // Player has powerups - degrade them but don't lose life
                player.degradePowerUps()
            } else {
                // No powerups - lose a life (unless god mode is enabled)
                if !isGodModeEnabled {
                    lives -= 1
                }

                // Check for game over
                if lives <= 0 {
                    playerDestroyed()
                    return
                }
            }

            // Cancel powerup timers only for powerups that were removed
            if !player.hasShield {
                removeAction(forKey: "shieldDeactivation")
            }
            if !player.hasLightningWeapon {
                removeAction(forKey: "lightningDeactivation")
            }
            if !player.hasRapidFire {
                removeAction(forKey: "rapidFireDeactivation")
            }
            if !player.hasMagnet {
                removeAction(forKey: "magnetDeactivation")
            }
            if !player.hasSlowMotion {
                removeAction(forKey: "slowMotionDeactivation")
                // Reset speeds only if slow motion was removed
                resetEntitySpeeds()
            }
            if !player.hasScoreMultiplier {
                removeAction(forKey: "scoreMultiplierDeactivation")
                // Reset score multiplier only if it was removed
                scoreMultiplier = 1
            }
            if !player.hasBarrier {
                removeAction(forKey: "barrierDeactivation")
            }

            // Play hit animation and activate invulnerability
            player.playHitAnimation()
            activateInvulnerability()

            return
        }

        // Normal enemy collision
        // Explosion effect
        createExplosion(at: enemy.position, size: .normal)
        HapticManager.shared.mediumTap()

        // Mark enemy as destroyed to prevent completion callback
        enemy.markAsDestroyed()
        enemy.removeFromParent()

        // Play hit sound
        SoundManager.shared.playHitSound(on: self)

        // Check if player has any powerups
        if player.hasAnyPowerUps() {
            // Player has powerups - degrade them but don't lose life
            player.degradePowerUps()
        } else {
            // No powerups - lose a life (unless god mode is enabled)
            if !isGodModeEnabled {
                lives -= 1
            }

            // Check for game over
            if lives <= 0 {
                playerDestroyed()
                return
            }
        }

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
                createExplosion(at: bullet.position, size: .small)
                SoundManager.shared.playShieldHitSound(on: self)
                HapticManager.shared.lightTap()
            }
            bullet.removeFromParent()
            return
        }

        // Small explosion effect
        createExplosion(at: bullet.position, size: .small)
        bullet.removeFromParent()

        // Play hit sound
        SoundManager.shared.playHitSound(on: self)

        // Check if player has any powerups
        if player.hasAnyPowerUps() {
            // Player has powerups - degrade them but don't lose life
            player.degradePowerUps()
        } else {
            // No powerups - lose a life (unless god mode is enabled)
            if !isGodModeEnabled {
                lives -= 1
            }

            // Check for game over
            if lives <= 0 {
                playerDestroyed()
                return
            }
        }

        // Cancel powerup timers only for powerups that were removed
        if !player.hasShield {
            removeAction(forKey: "shieldDeactivation")
        }
        if !player.hasLightningWeapon {
            removeAction(forKey: "lightningDeactivation")
        }
        if !player.hasRapidFire {
            removeAction(forKey: "rapidFireDeactivation")
        }
        if !player.hasMagnet {
            removeAction(forKey: "magnetDeactivation")
        }
        if !player.hasSlowMotion {
            removeAction(forKey: "slowMotionDeactivation")
            resetEntitySpeeds()
        }
        if !player.hasScoreMultiplier {
            removeAction(forKey: "scoreMultiplierDeactivation")
            scoreMultiplier = 1
        }
        if !player.hasBarrier {
            removeAction(forKey: "barrierDeactivation")
        }

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
                createExplosion(at: player.position, size: .small)
                HapticManager.shared.heavyTap()
            }
            return
        }

        // Create explosion effect at player position
        createExplosion(at: player.position, size: .huge)
        HapticManager.shared.heavyTap()

        // Play hit sound
        SoundManager.shared.playHitSound(on: self)

        // Check if player has any powerups
        if player.hasAnyPowerUps() {
            // Player has powerups - degrade them but don't lose life
            player.degradePowerUps()
        } else {
            // No powerups - lose a life (unless god mode is enabled)
            if !isGodModeEnabled {
                lives -= 1
            }

            // Check for game over
            if lives <= 0 {
                playerDestroyed()
                return
            }
        }

        // Cancel powerup timers only for powerups that were removed
        if !player.hasShield {
            removeAction(forKey: "shieldDeactivation")
        }
        if !player.hasLightningWeapon {
            removeAction(forKey: "lightningDeactivation")
        }
        if !player.hasRapidFire {
            removeAction(forKey: "rapidFireDeactivation")
        }
        if !player.hasMagnet {
            removeAction(forKey: "magnetDeactivation")
        }
        if !player.hasSlowMotion {
            removeAction(forKey: "slowMotionDeactivation")
            resetEntitySpeeds()
        }
        if !player.hasScoreMultiplier {
            removeAction(forKey: "scoreMultiplierDeactivation")
            scoreMultiplier = 1
        }
        if !player.hasBarrier {
            removeAction(forKey: "barrierDeactivation")
        }

        // Play hit animation and activate invulnerability
        player.playHitAnimation()
        activateInvulnerability()
    }

    private func bulletDidCollideWithObstacle(bullet: SKShapeNode?) {
        guard let bullet = bullet else { return }

        // Simply remove the bullet - no explosion for bullet hitting obstacle
        bullet.removeFromParent()
    }

    private func barrierDidCollideWithEnemy(enemy: Enemy?) {
        guard let enemy = enemy else { return }

        // Create explosion effect
        createExplosion(at: enemy.position, size: .normal)
        SoundManager.shared.playExplosionSound(on: self)
        HapticManager.shared.mediumTap()

        // Add score for destroying enemy with barrier
        addScore(enemy.enemyType.points)

        // Show floating score
        let scoreText = "+\(enemy.enemyType.points * scoreMultiplier)"
        showFloatingText(scoreText, at: enemy.position, color: UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0), fontSize: 16)

        // Mark enemy as destroyed and remove
        enemy.markAsDestroyed()
        enemy.removeFromParent()
    }

    private func barrierDidCollideWithEnemyBullet(bullet: SKShapeNode?) {
        guard let bullet = bullet else { return }

        // Create small hit effect
        createSmallHitEffect(at: bullet.position)
        SoundManager.shared.playShieldHitSound(on: self)
        HapticManager.shared.lightTap()

        // Remove the bullet
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
                showFloatingText("+1 LIFE", at: powerUp.position, color: UIColor(red: 0.0, green: 1.0, blue: 0.3, alpha: 1.0), fontSize: 18)
            }

        case .multiShot:
            if player.bulletCount < 8 {
                player.bulletCount += 1
                SoundManager.shared.playMultiShotActivateSound(on: self)
                HapticManager.shared.lightTap()
                showFloatingText("MULTI SHOT", at: powerUp.position, color: UIColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 1.0), fontSize: 18)
            }

        case .sideMissiles:
            if player.sideMissileCount < 2 {
                player.sideMissileCount += 1
                SoundManager.shared.playMissileSound(on: self)
                HapticManager.shared.lightTap()
                showFloatingText("SIDE MISSILES", at: powerUp.position, color: UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0), fontSize: 18)
            }

        case .shield:
            activateShield()
            SoundManager.shared.playShieldActivateSound(on: self)
            HapticManager.shared.heavyTap()
            showFloatingText("SHIELD", at: powerUp.position, color: UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1.0), fontSize: 18)

        case .lightning:
            activateLightningWeapon()
            SoundManager.shared.playLightningSound(on: self)
            HapticManager.shared.heavyTap()
            showFloatingText("LIGHTNING", at: powerUp.position, color: UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0), fontSize: 18)

        case .rapidFire:
            activateRapidFire()
            SoundManager.shared.playRapidFireActivateSound(on: self)
            HapticManager.shared.mediumTap()
            showFloatingText("RAPID FIRE", at: powerUp.position, color: UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0), fontSize: 18)

        case .magnet:
            activateMagnet()
            SoundManager.shared.playMagnetActivateSound(on: self)
            HapticManager.shared.mediumTap()
            showFloatingText("MAGNET", at: powerUp.position, color: UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0), fontSize: 18)

        case .slowMotion:
            activateSlowMotion()
            SoundManager.shared.playSlowMotionActivateSound(on: self)
            HapticManager.shared.heavyTap()
            showFloatingText("SLOW MOTION", at: powerUp.position, color: UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1.0), fontSize: 18)

        case .freezeBomb:
            activateFreezeBomb()
            HapticManager.shared.heavyTap()
            showFloatingText("FREEZE BOMB", at: powerUp.position, color: UIColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 1.0), fontSize: 18)

        case .homingMissiles:
            launchHomingMissiles()
            SoundManager.shared.playMissileSound(on: self)
            HapticManager.shared.heavyTap()
            showFloatingText("HOMING MISSILES", at: powerUp.position, color: UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0), fontSize: 18)

        case .scoreMultiplier:
            activateScoreMultiplier()
            SoundManager.shared.playScoreMultiplierSound(on: self)
            HapticManager.shared.mediumTap()
            showFloatingText("SCORE x2", at: powerUp.position, color: UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0), fontSize: 18)

        case .barrier:
            activateBarrier()
            SoundManager.shared.playBarrierActivateSound(on: self)
            HapticManager.shared.heavyTap()
            showFloatingText("BARRIER", at: powerUp.position, color: UIColor(red: 0.2, green: 0.9, blue: 0.7, alpha: 1.0), fontSize: 18)

        case .nuke:
            activateNuke()
            HapticManager.shared.heavyTap()
            showFloatingText("NUKE", at: powerUp.position, color: UIColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 1.0), fontSize: 18)
        }

        // Create 3D vector burst effect
        let burstEffect = VectorFX3D.createPowerUpBurst(
            at: powerUp.position,
            color: powerUp.powerUpType.color,
            particleCount: 50
        )
        addChild(burstEffect)

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
        let points = coin.pointValue
        addScore(points)

        // Show floating score
        let scoreText = "+\(points * scoreMultiplier)"
        showFloatingText(scoreText, at: coin.position, color: UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0), fontSize: 16)

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
        let points = asteroid.asteroidSize.points
        addScore(points)

        // Show floating score
        let scoreText = "+\(points * scoreMultiplier)"
        showFloatingText(scoreText, at: asteroid.position, color: UIColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1.0))

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
            createExplosion(at: asteroid.position, size: .normal)

            // Split asteroid (AsteroidManager handles adding split pieces to scene)
            asteroidManager?.splitAsteroid(asteroid)

            asteroid.markAsDestroyed()
            asteroid.removeFromParent()
            return
        }

        // Explosion effect
        createExplosion(at: asteroid.position, size: .large)
        HapticManager.shared.mediumTap()

        // Split asteroid even on player collision
        // (AsteroidManager handles adding split pieces to scene)
        asteroidManager?.splitAsteroid(asteroid)

        // Mark asteroid as destroyed
        asteroid.markAsDestroyed()
        asteroid.removeFromParent()

        // Play hit sound
        SoundManager.shared.playHitSound(on: self)

        // Check if player has any powerups
        if player.hasAnyPowerUps() {
            // Player has powerups - degrade them but don't lose life
            player.degradePowerUps()
        } else {
            // No powerups - lose a life (unless god mode is enabled)
            if !isGodModeEnabled {
                lives -= 1
            }

            // Check for game over
            if lives <= 0 {
                playerDestroyed()
                return
            }
        }

        // Cancel powerup timers only for powerups that were removed
        if !player.hasShield {
            removeAction(forKey: "shieldDeactivation")
        }
        if !player.hasLightningWeapon {
            removeAction(forKey: "lightningDeactivation")
        }
        if !player.hasRapidFire {
            removeAction(forKey: "rapidFireDeactivation")
        }
        if !player.hasMagnet {
            removeAction(forKey: "magnetDeactivation")
        }
        if !player.hasSlowMotion {
            removeAction(forKey: "slowMotionDeactivation")
            resetEntitySpeeds()
        }
        if !player.hasScoreMultiplier {
            removeAction(forKey: "scoreMultiplierDeactivation")
            scoreMultiplier = 1
        }
        if !player.hasBarrier {
            removeAction(forKey: "barrierDeactivation")
        }

        // Play hit animation and activate invulnerability
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

        // Show timer
        showPowerUpTimer(name: "shield", duration: 5.0, color: UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1.0), icon: "SHIELD")

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

        // Show timer
        showPowerUpTimer(name: "lightning", duration: 7.0, color: UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0), icon: "LIGHTNING")

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

        // Show timer
        showPowerUpTimer(name: "rapidFire", duration: 8.0, color: UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0), icon: "RAPID FIRE")

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

        // Show timer
        showPowerUpTimer(name: "magnet", duration: 10.0, color: UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0), icon: "MAGNET")

        // Cancel any previous magnet deactivation
        removeAction(forKey: "magnetDeactivation")

        // Deactivate after 10 seconds
        let wait = SKAction.wait(forDuration: 10.0)
        let deactivate = SKAction.run { [weak self] in
            self?.player.hasMagnet = false
            self?.activeCoins.removeAll()  // Clear cache when magnet deactivates
        }
        run(SKAction.sequence([wait, deactivate]), withKey: "magnetDeactivation")
    }

    private func activateSlowMotion() {
        player.hasSlowMotion = true

        // Show timer
        showPowerUpTimer(name: "slowMotion", duration: 6.0, color: UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1.0), icon: "SLOW MO")

        // Cancel any previous slow motion deactivation
        removeAction(forKey: "slowMotionDeactivation")

        // Deactivate after 6 seconds
        let wait = SKAction.wait(forDuration: 6.0)
        let deactivate = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.player.hasSlowMotion = false

            // Reset speed for all cached enemies
            for (_, enemy) in self.activeEnemies {
                if enemy.parent != nil {
                    enemy.speed = 1.0
                }
            }
            self.activeEnemies.removeAll()  // Clear cache when slow motion deactivates

            // Reset speed for asteroids and bullets (still need enumerate for these)
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
        // Freeze all enemies for 2.5 seconds, then they explode
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy {
                enemy.freeze(duration: 2.5)
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
        let missileCount = 6 // Always launch 6 missiles
        var targets: [Any] = []

        // Find up to 6 closest enemies
        var enemies: [Enemy] = []
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy {
                enemies.append(enemy)
            }
        }

        // Sort by distance and take closest ones
        enemies.sort { enemy1, enemy2 in
            let dist1 = hypot(enemy1.position.x - player.position.x, enemy1.position.y - player.position.y)
            let dist2 = hypot(enemy2.position.x - player.position.x, enemy2.position.y - player.position.y)
            return dist1 < dist2
        }

        // Add enemies to targets
        targets.append(contentsOf: Array(enemies.prefix(missileCount)))

        // If we have fewer than 6 targets and boss is active, add boss targets
        if targets.count < missileCount && bossManager.isBossActive() {
            if let boss = bossManager.getBoss() {
                // Fill remaining slots with boss
                while targets.count < missileCount {
                    targets.append(boss)
                }
            }
        }

        // If still no targets, just launch missiles that will seek any enemy
        if targets.isEmpty {
            for i in 0..<missileCount {
                let delay = SKAction.wait(forDuration: Double(i) * 0.15)
                let launch = SKAction.run { [weak self] in
                    self?.createSeekingMissile()
                }
                run(SKAction.sequence([delay, launch]))
            }
            return
        }

        // Launch a homing missile for each target
        for (index, target) in targets.enumerated() {
            let delay = SKAction.wait(forDuration: Double(index) * 0.15)
            let launch = SKAction.run { [weak self] in
                if let enemy = target as? Enemy {
                    self?.createHomingMissile(target: enemy)
                } else if let boss = target as? Boss {
                    self?.createHomingMissileForBoss(boss: boss)
                }
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

    private func createHomingMissileForBoss(boss: Boss) {

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

    private func createSeekingMissile() {
        // Missile that seeks any nearby enemy
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

        // Seeking behavior - finds closest enemy each frame
        let seekingAction = SKAction.customAction(withDuration: 5.0) { [weak self, weak missile] node, elapsedTime in
            guard let self = self, let missile = missile else {
                node.removeFromParent()
                return
            }

            // Find closest enemy or boss
            var closestTarget: SKNode?
            var closestDistance: CGFloat = .infinity

            // Check enemies
            self.gameContentNode.enumerateChildNodes(withName: "enemy") { enemyNode, _ in
                if let enemy = enemyNode as? Enemy {
                    let distance = hypot(enemy.position.x - missile.position.x,
                                       enemy.position.y - missile.position.y)
                    if distance < closestDistance {
                        closestDistance = distance
                        closestTarget = enemy
                    }
                }
            }

            // Check boss
            if self.bossManager.isBossActive(), let boss = self.bossManager.getBoss() {
                let distance = hypot(boss.position.x - missile.position.x,
                                   boss.position.y - missile.position.y)
                if distance < closestDistance {
                    closestDistance = distance
                    closestTarget = boss
                }
            }

            if let target = closestTarget {
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
            } else {
                // No target - move upward slowly
                missile.position.y += 200 * CGFloat(self.deltaTime)
            }
        }

        let remove = SKAction.removeFromParent()
        missile.run(SKAction.sequence([seekingAction, remove]))
    }

    private func activateScoreMultiplier() {
        scoreMultiplier = 2
        player.hasScoreMultiplier = true

        // Show timer
        showPowerUpTimer(name: "scoreMultiplier", duration: 12.0, color: UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0), icon: "SCORE x2")

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

        // Show timer
        showPowerUpTimer(name: "barrier", duration: 8.0, color: UIColor(red: 0.2, green: 0.9, blue: 0.7, alpha: 1.0), icon: "BARRIER")

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
                    node.physicsBody?.categoryBitMask = PhysicsCategory.barrier
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
                    self?.createExplosion(at: enemy.position, size: .normal)
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

        // No additional camera shake - createExplosion handles it
    }

    func addScore(_ points: Int) {
        score += points * scoreMultiplier
    }

    private func showFloatingText(_ text: String, at position: CGPoint, color: UIColor = .white, fontSize: CGFloat = 20) {
        // Create floating text label
        let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.position = position
        label.zPosition = 200 // Above everything
        label.alpha = 0.0

        // Add shadow for better visibility
        let shadow = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        shadow.text = text
        shadow.fontSize = fontSize
        shadow.fontColor = .black
        shadow.alpha = 0.5
        shadow.position = CGPoint(x: 2, y: -2)
        shadow.zPosition = -1
        label.addChild(shadow)

        addChild(label)

        // Animate: fade in, move up, fade out
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        let moveUp = SKAction.moveBy(x: 0, y: 80, duration: 1.2)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()

        let moveAndFade = SKAction.group([moveUp, SKAction.sequence([
            SKAction.wait(forDuration: 0.9),
            fadeOut
        ])])

        label.run(SKAction.sequence([fadeIn, moveAndFade, remove]))
    }

    private func showPowerUpTimer(name: String, duration: TimeInterval, color: UIColor, icon: String) {
        // Don't show timers during boss fight
        if isBossActive {
            return
        }

        // Remove existing timer for this powerup if any
        powerUpTimerBars[name]?.removeFromParent()

        // Calculate position based on number of active timers (smaller, more compact)
        let timerHeight: CGFloat = 28
        let timerSpacing: CGFloat = 6
        let existingTimers = powerUpTimerBars.count
        let yPosition = size.height - currentTopMargin - 50 - CGFloat(existingTimers) * (timerHeight + timerSpacing)

        // Create container for timer
        let container = SKNode()
        container.position = CGPoint(x: 12, y: yPosition)
        container.zPosition = 100
        container.alpha = 0.7 // More subtle
        uiNode.addChild(container)
        powerUpTimerBars[name] = container

        // Background - minimal and subtle
        let bgWidth: CGFloat = 150
        let background = SKShapeNode(rectOf: CGSize(width: bgWidth, height: timerHeight), cornerRadius: 7)
        background.fillColor = UIColor(white: 0.05, alpha: 0.6)
        background.strokeColor = UIColor(white: 0.4, alpha: 0.3)
        background.lineWidth = 1
        background.position = CGPoint(x: bgWidth / 2, y: 0)
        container.addChild(background)

        // Icon label - smaller and more subtle
        let iconLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        iconLabel.text = icon
        iconLabel.fontSize = 12
        iconLabel.fontColor = UIColor(white: 0.9, alpha: 0.9)
        iconLabel.verticalAlignmentMode = .center
        iconLabel.horizontalAlignmentMode = .left
        iconLabel.position = CGPoint(x: 7, y: 0.5)
        container.addChild(iconLabel)

        // Progress bar container (on the right side) - smaller
        let barWidth: CGFloat = 55
        let barHeight: CGFloat = 7
        let barX: CGFloat = bgWidth - barWidth - 6

        // Progress bar background
        let barBackground = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        barBackground.fillColor = UIColor(white: 0.2, alpha: 0.5)
        barBackground.strokeColor = .clear
        barBackground.position = CGPoint(x: barX + barWidth / 2, y: 0)
        container.addChild(barBackground)

        // Progress bar fill (anchor at left edge for proper scaling)
        let barFillContainer = SKNode()
        barFillContainer.position = CGPoint(x: barX, y: 0)
        container.addChild(barFillContainer)

        let barFill = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        barFill.fillColor = color.withAlphaComponent(0.8)
        barFill.strokeColor = .clear
        barFill.position = CGPoint(x: barWidth / 2, y: 0)
        barFill.name = "progressFill"
        barFillContainer.addChild(barFill)

        // Animate progress bar from full to empty
        let scaleDown = SKAction.scaleX(to: 0.0, duration: duration)
        let remove = SKAction.run { [weak self] in
            self?.powerUpTimerBars.removeValue(forKey: name)
            container.removeFromParent()
        }
        barFillContainer.run(SKAction.sequence([scaleDown, remove]))

        // Fade out near the end
        let waitBeforeFade = SKAction.wait(forDuration: max(0, duration - 1.0))
        let fadeOut = SKAction.fadeAlpha(to: 0.25, duration: 1.0)
        container.run(SKAction.sequence([waitBeforeFade, fadeOut]))
    }

    private func hideAllPowerUpTimers() {
        // Immediately remove all powerup timer bars without animation
        for (_, timerNode) in powerUpTimerBars {
            timerNode.removeAllActions()
            timerNode.removeFromParent()
        }
        powerUpTimerBars.removeAll()
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
        // Refresh cached coins periodically instead of every frame
        if activeCoins.isEmpty {
            gameContentNode.enumerateChildNodes(withName: "coin") { [weak self] node, _ in
                if let coin = node as? Coin {
                    self?.activeCoins[ObjectIdentifier(coin)] = coin
                }
            }
        }

        // Remove destroyed coins from cache and update positions
        var toRemove: [ObjectIdentifier] = []
        for (id, coin) in activeCoins {
            guard coin.parent != nil else {
                toRemove.append(id)
                continue
            }

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

        // Clean up destroyed coins
        for id in toRemove {
            activeCoins.removeValue(forKey: id)
        }
    }

    private func applyVortexGravitationalPull() {
        // Find all active vortex enemies
        var vortexEnemies: [Enemy] = []
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy, enemy.enemyType == .vortex {
                vortexEnemies.append(enemy)
            }
        }

        // If no vortex enemies, nothing to do
        guard !vortexEnemies.isEmpty else { return }

        let vortexGravityRadius: CGFloat = 150 // Radius of gravitational influence
        let pullStrength: CGFloat = 5.0 // Strength of the pull

        // Apply gravitational pull to all player bullets
        gameContentNode.enumerateChildNodes(withName: "bullet") { node, _ in
            guard let bullet = node as? SKShapeNode,
                  let bulletBody = bullet.physicsBody else { return }

            // Check each vortex
            for vortex in vortexEnemies {
                let dx = vortex.position.x - bullet.position.x
                let dy = vortex.position.y - bullet.position.y
                let distance = sqrt(dx * dx + dy * dy)

                // Apply pull if bullet is within gravity radius
                if distance < vortexGravityRadius && distance > 0 {
                    // Calculate pull force inversely proportional to distance
                    let pullForce = pullStrength * (1.0 - distance / vortexGravityRadius)
                    let forceX = (dx / distance) * pullForce * 100
                    let forceY = (dy / distance) * pullForce * 100

                    // Apply impulse to bullet
                    bulletBody.applyImpulse(CGVector(dx: forceX, dy: forceY))
                }
            }
        }
    }

    private func applySlowMotion(currentTime: TimeInterval) {
        // Only update every 0.1 seconds to reduce performance impact
        guard currentTime - lastSlowMotionUpdateTime >= 0.1 else { return }
        lastSlowMotionUpdateTime = currentTime

        let slowFactor: CGFloat = 0.5

        // Slow down enemies - use cached dictionary when possible
        if activeEnemies.isEmpty {
            gameContentNode.enumerateChildNodes(withName: "enemy") { [weak self] node, _ in
                if let enemy = node as? Enemy {
                    self?.activeEnemies[ObjectIdentifier(enemy)] = enemy
                    if enemy.speed != slowFactor {
                        enemy.speed = slowFactor
                    }
                }
            }
        } else {
            var toRemove: [ObjectIdentifier] = []
            for (id, enemy) in activeEnemies {
                guard enemy.parent != nil else {
                    toRemove.append(id)
                    continue
                }
                if enemy.speed != slowFactor {
                    enemy.speed = slowFactor
                }
            }
            // Clean up destroyed enemies
            for id in toRemove {
                activeEnemies.removeValue(forKey: id)
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

                self.createExplosion(at: explosionPos, size: .normal)
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
            self.createExplosion(at: self.player.position, size: .huge)
            HapticManager.shared.heavyTap()

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

    func createExplosionForFrozenEnemy(at position: CGPoint) {
        // Use standard explosion effect for frozen enemies
        createExplosion(at: position, size: .normal)
    }

    private func createExplosion(at position: CGPoint, size: ExplosionSize = .normal) {
        // Play explosion sound
        SoundManager.shared.playExplosionSound(on: self)

        // Camera shake based on explosion size (reduced on iPad)
        let shakeMultiplier: CGFloat = isIPad ? 0.7 : 1.0
        switch size {
        case .small:
            shakeCamera(intensity: 3.0 * shakeMultiplier, duration: 0.15)
        case .normal:
            shakeCamera(intensity: 6.0 * shakeMultiplier, duration: 0.25)
        case .large:
            shakeCamera(intensity: 10.0 * shakeMultiplier, duration: 0.35)
        case .huge:
            shakeCamera(intensity: 15.0 * shakeMultiplier, duration: 0.45)
        }

        // Enhanced multi-layered explosion effect
        let explosionContainer = SKNode()
        explosionContainer.position = position
        explosionContainer.zPosition = 500
        addChild(explosionContainer)

        // Scale factors based on size
        let sizeMultiplier: CGFloat
        switch size {
        case .small:
            sizeMultiplier = 0.6
        case .normal:
            sizeMultiplier = 1.0
        case .large:
            sizeMultiplier = 1.4
        case .huge:
            sizeMultiplier = 2.0
        }

        // Core flash
        let coreFlash = SKShapeNode(circleOfRadius: 8 * sizeMultiplier)
        coreFlash.fillColor = UIColor(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0)
        coreFlash.strokeColor = .clear
        explosionContainer.addChild(coreFlash)

        let coreScale = SKAction.scale(to: 2.5, duration: 0.15)
        let coreFade = SKAction.fadeOut(withDuration: 0.15)
        coreFlash.run(SKAction.group([coreScale, coreFade]))

        // Main explosion ring
        let mainExplosion = SKShapeNode(circleOfRadius: 10 * sizeMultiplier)
        mainExplosion.fillColor = UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.9)
        mainExplosion.strokeColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
        mainExplosion.lineWidth = 3
        explosionContainer.addChild(mainExplosion)

        let mainScale = SKAction.scale(to: 4.0, duration: 0.4)
        let mainFade = SKAction.fadeOut(withDuration: 0.4)
        mainExplosion.run(SKAction.group([mainScale, mainFade]))

        // Outer shockwave
        let shockwave = SKShapeNode(circleOfRadius: 15 * sizeMultiplier)
        shockwave.fillColor = .clear
        shockwave.strokeColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 0.7)
        shockwave.lineWidth = 4
        explosionContainer.addChild(shockwave)

        let shockScale = SKAction.scale(to: 5.0, duration: 0.5)
        let shockFade = SKAction.fadeOut(withDuration: 0.5)
        shockwave.run(SKAction.group([shockScale, shockFade]))

        // Add explosion particles (debris) - reduced count on iPad for performance
        let baseParticleCount = Int(8 * sizeMultiplier)
        let particleCount = Int(CGFloat(baseParticleCount) * particleMultiplier)
        for i in 0..<particleCount {
            let angle = CGFloat(i) * .pi * 2 / CGFloat(particleCount)
            let particle = SKShapeNode(circleOfRadius: 3 * sizeMultiplier)
            particle.fillColor = UIColor(red: 1.0, green: CGFloat.random(in: 0.3...0.8), blue: 0.0, alpha: 1.0)
            particle.strokeColor = .clear
            explosionContainer.addChild(particle)

            let distance: CGFloat = 40 * sizeMultiplier
            let targetX = cos(angle) * distance
            let targetY = sin(angle) * distance

            let move = SKAction.moveBy(x: targetX, y: targetY, duration: 0.4)
            let particleFade = SKAction.fadeOut(withDuration: 0.4)
            let particleScale = SKAction.scale(to: 0.3, duration: 0.4)
            particle.run(SKAction.group([move, particleFade, particleScale]))
        }

        // Glow effect (skip on iPad for better performance)
        if !isIPad {
            GlowHelper.addEnhancedGlow(to: mainExplosion, color: UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0), intensity: 1.5)
        }

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

        // Magnet effect - attract coins (limited to 30 FPS for performance)
        if player.hasMagnet && currentTime - lastMagnetUpdateTime >= 0.033 {
            lastMagnetUpdateTime = currentTime
            attractCoins()
        }

        // Vortex gravitational pull on player bullets
        applyVortexGravitationalPull()

        // Update weapon cooling
        updateWeaponCooling(deltaTime: deltaTime, currentTime: currentTime)

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
            applySlowMotion(currentTime: currentTime)
        }

        // Clean up off-screen bullets to prevent memory buildup (but not every frame)
        let cleanupInterval: TimeInterval = isIPad ? 0.3 : 0.5  // More frequent cleanup on iPad
        if currentTime - lastCleanupTime >= cleanupInterval {
            cleanupOffScreenBullets()
            lastCleanupTime = currentTime
        }

        // Check level completion - simple approach
        checkLevelCompletion(currentTime: currentTime)

        lastUpdateTime = currentTime
    }

    private func cleanupOffScreenBullets() {
        // Remove enemy bullets that are off-screen to prevent memory buildup
        // Check both above and below screen, plus some margin on sides
        let margin: CGFloat = 100
        let minY = -margin
        let maxY = size.height + margin
        let minX = -margin
        let maxX = size.width + margin

        gameContentNode.enumerateChildNodes(withName: "enemybullet") { node, _ in
            let pos = node.position
            if pos.y < minY || pos.y > maxY || pos.x < minX || pos.x > maxX {
                node.removeFromParent()
            }
        }

        // Also clean up player bullets that are off-screen
        gameContentNode.enumerateChildNodes(withName: "bullet") { node, _ in
            let pos = node.position
            if pos.y > maxY || pos.x < minX || pos.x > maxX {
                node.removeFromParent()
            }
        }
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

        // Count Enemy nodes efficiently - use cached count and only enumerate periodically
        if activeEnemies.isEmpty {
            gameContentNode.enumerateChildNodes(withName: "enemy") { [weak self] node, _ in
                if let enemy = node as? Enemy {
                    self?.activeEnemies[ObjectIdentifier(enemy)] = enemy
                }
            }
        } else {
            // Clean up destroyed enemies from cache
            var toRemove: [ObjectIdentifier] = []
            for (id, enemy) in activeEnemies {
                if enemy.parent == nil {
                    toRemove.append(id)
                }
            }
            for id in toRemove {
                activeEnemies.removeValue(forKey: id)
            }
        }

        let enemyCount = activeEnemies.count

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

        // Hide all powerup timers during boss fight
        hideAllPowerUpTimers()

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
            totalCoins: totalCoins,
            bulletCount: player.bulletCount,
            sideMissileCount: player.sideMissileCount
        )
        stopGameplayAndTransition(to: levelCompleteScene, transitionDuration: 1.0)
    }

    private func goToLevelSelect() {
        guard let view = view else { return }
        let levelSelectScene = LevelSelectScene(size: view.bounds.size, startLevel: currentLevel)
        levelSelectScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(levelSelectScene, transition: transition)
    }

    // MARK: - Special Enemy Abilities

    private func createVortexAbsorptionEffect(at position: CGPoint, vortex: Enemy) {
        // Create swirling particle effect towards vortex
        let particles = SKEmitterNode()
        particles.position = position

        // Create circular particle texture programmatically
        let particleSize = CGSize(width: 8, height: 8)
        let particleRenderer = UIGraphicsImageRenderer(size: particleSize)
        let particleImage = particleRenderer.image { context in
            let rect = CGRect(origin: .zero, size: particleSize)
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: rect)
        }
        particles.particleTexture = SKTexture(image: particleImage)

        particles.particleBirthRate = 50
        particles.numParticlesToEmit = 20
        particles.particleLifetime = 0.5
        particles.particleSpeed = 100
        particles.particleSpeedRange = 50
        particles.emissionAngle = 0
        particles.emissionAngleRange = .pi * 2
        particles.particleScale = 0.15
        particles.particleScaleRange = 0.1
        particles.particleAlpha = 0.8
        particles.particleAlphaSpeed = -1.6
        particles.particleColor = .purple
        particles.particleColorBlendFactor = 1.0
        addChild(particles)

        // Move particles toward vortex center
        let moveToVortex = SKAction.move(to: vortex.position, duration: 0.3)
        particles.run(SKAction.sequence([
            moveToVortex,
            SKAction.removeFromParent()
        ]))

        SoundManager.shared.playAbsorbSound(on: self)
    }

    private func reflectBullet(_ bullet: SKShapeNode, from mirror: Enemy) {
        // Change bullet to enemy bullet
        bullet.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
        bullet.physicsBody?.contactTestBitMask = PhysicsCategory.player
        bullet.fillColor = .red

        // Reverse velocity
        if let velocity = bullet.physicsBody?.velocity {
            bullet.physicsBody?.velocity = CGVector(dx: -velocity.dx, dy: -velocity.dy * 1.2)
        }

        // Flash effect on mirror
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 0.05),
            SKAction.fadeAlpha(to: 1.0, duration: 0.05)
        ])
        mirror.run(flash)

        SoundManager.shared.playReflectSound(on: self)
    }

    private func isHittingShield(bullet: SKShapeNode, enemy: Enemy) -> Bool {
        // Get shield rotation angle (shield rotates around enemy)
        guard let shieldNode = enemy.childNode(withName: "shield") else { return false }

        // Calculate angle from enemy to bullet
        let dx = bullet.position.x - enemy.position.x
        let dy = bullet.position.y - enemy.position.y
        let bulletAngle = atan2(dy, dx)

        // Get current shield rotation (normalized to 0-2π)
        var shieldAngle = shieldNode.zRotation
        while shieldAngle < 0 { shieldAngle += .pi * 2 }
        while shieldAngle >= .pi * 2 { shieldAngle -= .pi * 2 }

        // Shield covers 120 degrees (π/3 radians on each side)
        let shieldCoverage: CGFloat = .pi / 1.5

        // Calculate angle difference
        var angleDiff = abs(bulletAngle - shieldAngle)
        if angleDiff > .pi { angleDiff = .pi * 2 - angleDiff }

        return angleDiff < shieldCoverage / 2
    }

    private func createSplitterFragments(at position: CGPoint) {
        // Create 2 smaller basic enemies that fly off in different directions
        for i in 0..<2 {
            let fragment = Enemy(sceneSize: size, scene: self, type: .basic)
            fragment.position = position
            fragment.setScale(0.6) // Smaller than original
            addChild(fragment)

            // Launch fragments in opposite directions
            let angle: CGFloat = i == 0 ? -.pi/4 : .pi/4
            let dx = cos(angle) * 150
            let dy = sin(angle) * 150 - 100 // Also move down

            let launch = SKAction.moveBy(x: dx, y: dy, duration: 0.8)
            let fall = SKAction.moveTo(y: -20, duration: 3.0)

            fragment.run(SKAction.sequence([launch, fall, SKAction.removeFromParent()]))

            // Make fragments shoot
            fragment.startShooting()
        }
    }

    private func createSparkEffect(at position: CGPoint) {
        for _ in 0..<8 {
            let spark = SKShapeNode(circleOfRadius: 2)
            spark.fillColor = .white
            spark.strokeColor = .yellow
            spark.position = position
            spark.alpha = 1.0
            addChild(spark)

            let angle = CGFloat.random(in: 0...(.pi * 2))
            let distance = CGFloat.random(in: 10...30)
            let dx = cos(angle) * distance
            let dy = sin(angle) * distance

            let move = SKAction.moveBy(x: dx, y: dy, duration: 0.3)
            let fade = SKAction.fadeOut(withDuration: 0.3)
            spark.run(SKAction.group([move, fade])) {
                spark.removeFromParent()
            }
        }
    }

    // MARK: - Weapon Overheat System

    private func setupHeatBar(topMargin: CGFloat) {
        let barWidth: CGFloat = 120
        let barHeight: CGFloat = 8
        let bottomMargin: CGFloat = 30 // Moved lower to avoid player starting position

        // Background bar
        let background = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 4)
        background.fillColor = UIColor(white: 0.2, alpha: 0.6)
        background.strokeColor = UIColor(white: 0.4, alpha: 0.8)
        background.lineWidth = 1
        background.position = CGPoint(x: size.width / 2, y: bottomMargin)
        background.zPosition = 100
        background.alpha = 0.0 // Hidden initially
        uiNode.addChild(background)
        heatBarBackground = background

        // Heat bar (foreground)
        let heat = SKShapeNode(rectOf: CGSize(width: 0, height: barHeight - 2), cornerRadius: 3)
        heat.fillColor = UIColor(red: 0.0, green: 1.0, blue: 0.8, alpha: 0.9)
        heat.strokeColor = .clear
        heat.position = CGPoint(x: size.width / 2 - barWidth / 2, y: bottomMargin)
        heat.zPosition = 101
        uiNode.addChild(heat)
        heatBar = heat

        // Label
        let label = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        label.fontSize = 11
        label.fontColor = UIColor(white: 0.8, alpha: 0.9)
        label.text = "HEAT"
        label.position = CGPoint(x: size.width / 2, y: bottomMargin + 14)
        label.zPosition = 100
        label.alpha = 0.0 // Hidden initially
        uiNode.addChild(label)
        heatBarLabel = label
    }

    private func updateHeatBar() {
        guard let heatBar = heatBar, let background = heatBarBackground, let label = heatBarLabel else { return }

        // Hide heat bar when heat is low (below 15%)
        let shouldShow = weaponHeat > 0.15
        background.alpha = shouldShow ? 1.0 : 0.0
        label.alpha = shouldShow ? 1.0 : 0.0

        let barWidth: CGFloat = 120
        let currentWidth = barWidth * weaponHeat

        // Update bar width
        let newBar = SKShapeNode(rectOf: CGSize(width: currentWidth, height: 6), cornerRadius: 3)

        // Color changes based on heat level
        if weaponHeat < 0.5 {
            // Green to yellow
            let green = 1.0 - (weaponHeat * 2)
            newBar.fillColor = UIColor(red: weaponHeat * 2, green: green, blue: 0.0, alpha: 0.9)
        } else if weaponHeat < 0.8 {
            // Yellow to orange
            let progress = (weaponHeat - 0.5) / 0.3
            newBar.fillColor = UIColor(red: 1.0, green: 1.0 - (progress * 0.5), blue: 0.0, alpha: 0.9)
        } else {
            // Orange to red
            let progress = (weaponHeat - 0.8) / 0.2
            newBar.fillColor = UIColor(red: 1.0, green: 0.5 - (progress * 0.5), blue: 0.0, alpha: 0.9)
        }

        newBar.strokeColor = .clear
        newBar.position = CGPoint(x: size.width / 2 - barWidth / 2 + currentWidth / 2, y: background.position.y)
        newBar.zPosition = 101

        heatBar.removeFromParent()
        uiNode.addChild(newBar)
        self.heatBar = newBar

        // Pulse effect when near overheating
        if weaponHeat > 0.85 && !isOverheated {
            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.15, duration: 0.15),
                SKAction.scale(to: 1.0, duration: 0.15)
            ])
            background.run(pulse)
        }
    }

    private func updateWeaponCooling(deltaTime: TimeInterval, currentTime: TimeInterval) {
        // If overheated, check if cooldown period is over
        if isOverheated {
            if currentTime - overheatStartTime >= overheatCooldownTime {
                isOverheated = false
                weaponHeat = 0.0
                updateHeatBar()

                // Visual feedback - flash green
                if let background = heatBarBackground {
                    let flash = SKAction.sequence([
                        SKAction.run { background.fillColor = UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.8) },
                        SKAction.wait(forDuration: 0.2),
                        SKAction.run { background.fillColor = UIColor(white: 0.2, alpha: 0.6) }
                    ])
                    background.run(flash)
                }

                SoundManager.shared.playPowerUpSound(on: self)
            }
            return
        }

        // Cool down when not shooting
        if !isTouching && weaponHeat > 0 {
            weaponHeat -= cooldownRate * CGFloat(deltaTime)
            if weaponHeat < 0 {
                weaponHeat = 0
            }
            updateHeatBar()
        }
    }

    private func triggerOverheat() {
        isOverheated = true
        overheatStartTime = lastUpdateTime

        // Visual feedback
        if let background = heatBarBackground, let label = heatBarLabel {
            // Flash red
            let flash = SKAction.sequence([
                SKAction.run {
                    background.fillColor = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.9)
                    label.text = "OVERHEATED!"
                    label.fontColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
                },
                SKAction.wait(forDuration: 0.3),
                SKAction.run {
                    background.fillColor = UIColor(white: 0.2, alpha: 0.6)
                },
                SKAction.wait(forDuration: 0.3)
            ])

            let flashSequence = SKAction.repeat(flash, count: 3)
            let reset = SKAction.run {
                label.text = "HEAT"
                label.fontColor = UIColor(white: 0.8, alpha: 0.9)
            }

            background.run(SKAction.sequence([flashSequence, reset]))
        }

        // Haptic feedback
        HapticManager.shared.heavyTap()

        // Sound effect
        SoundManager.shared.playExplosionSound(on: self)
    }
}
