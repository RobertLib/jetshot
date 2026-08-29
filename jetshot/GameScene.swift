//
//  GameScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//
// WARNING: This file is large (~3900 lines) and still wants splitting up:
//  - CollisionHandler for physics collision logic
//  - PowerUpHandler for power-up activation/deactivation
//  - UIManager for UI setup and updates
//
// Three pieces have already gone this way: `WeaponHeatSystem` (the overheat rule and its
// gauge), `PowerUpTimerHUD` (the countdown bar stack) and `ExplosionFX` (the blast node).
// `WeaponHeatSystem` records why they are pulled out as collaborators owning their own
// state rather than as extensions on this class: `private` is file-scoped in Swift, so an
// extension in another file would force this class's ~50 private properties open to the
// whole module — against the convention here of justifying every non-private member.
//
// The three that remain are harder than the three that are done, and not for their size:
// they are entangled with `score`, `lives`, `player` and the spawn managers, so each is
// its own refactor with its own round of verification rather than a lift-and-shift.
//
// Two conventions worth knowing before editing:
//  - Gameplay nodes and visual effects belong under `gameContentNode` (see
//    `effectsParent`), never the scene: the scene keeps ticking while paused.
//  - Time-based logic uses `gameTime`, not the `currentTime` passed to update(_:),
//    which is absolute system time and runs through pauses and backgrounding.

import SpriteKit
import GameplayKit

// Physics categories for collision detection.
//
// `nonisolated` for the same reason as GameConfiguration: these are constants.
nonisolated struct PhysicsCategory {
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
nonisolated enum ExplosionSize {
    case small    // Small enemies, bullets - minimal shake
    case normal   // Regular enemies - moderate shake
    case large    // Large enemies, asteroids - strong shake
    case huge     // Boss, player, nuke - maximum shake
}

/// Main game scene handling gameplay, collisions, and level progression.
/// Manages player, enemies, obstacles, power-ups, bosses, and scoring system.
class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Level System

    var currentLevel: Int = 1
    private var levelConfig: LevelConfig!

    /// Runs the scene as an endless survival run instead of an authored level.
    ///
    /// Endless reuses this scene wholesale — the same spawner, combat, power-ups, chain
    /// scoring and bosses — and changes only where the waves come from and what "the end"
    /// means. There is no completion: `EndlessDirector` tops the queue up a round at a
    /// time forever, a boss arrives every fifth round, and the run finishes when the
    /// player does.
    var isEndless: Bool = false

    /// Rounds survived in an endless run. Also the run's headline result, alongside score.
    private(set) var endlessRound: Int = 0

    /// Set while an endless boss round is being fought, so its defeat resumes the run
    /// rather than ending the level.
    private var isEndlessBossFight: Bool = false

    // Starting weapon arsenal (loaded from previous level)
    var startingBulletCount: Int = 1
    var startingSideMissileCount: Int = 0

    // Game objects
    private var player: Player!
    private var enemyManager: EnemyManager!
    private var obstacleManager: ObstacleManager!
    private var powerUpManager: PowerUpManager!
    /// Not private so `jetshotTests` can put a boss on screen directly.
    ///
    /// In play the only route here is `spawnBoss()`, which fires once every wave of the
    /// level has spawned *and* the playfield has stayed clear for
    /// `levelCompletionDelay` — minutes of real time per level. Without this seam the
    /// entire boss fight, and with it the completion gate for all 50 levels, is
    /// unreachable from a test.
    var bossManager: BossManager!
    private var asteroidManager: AsteroidManager?
    private var coinManager: CoinManager!
    private var scoreLabel: SKLabelNode!
    private var scoreHUD: SKNode?
    private var score: Int = 0 {
        didSet {
            scoreLabel.text = "\(score)"
            // A short overshoot on every gain makes scoring feel earned.
            scoreLabel.removeAction(forKey: "scorePunch")
            let up = SKAction.scale(to: 1.22, duration: 0.07)
            up.timingMode = .easeOut
            let down = SKAction.scale(to: 1.0, duration: 0.16)
            down.timingMode = .easeOut
            scoreLabel.run(.sequence([up, down]), withKey: "scorePunch")
        }
    }

    /// Read-only score, for `jetshotTests`.
    ///
    /// Scoring is the observable outcome of most gameplay rules — kills, multipliers,
    /// the boss payout — and the only other place it surfaces is `scoreLabel`, which is
    /// unnamed and carries a formatted string mid-animation.
    var currentScore: Int {
        return score
    }

    // Coin tracking
    private var coinsCollected: Int = 0

    // Boss system
    //
    // Only the "has the boss been spawned at all" latch lives here. Whether a boss is
    // currently alive is `bossManager.isBossActive()`, which is what every other call
    // site already asks. A second `isBossActive` field used to shadow it: set true in
    // spawnBoss() and cleared only in willMove(from:), so from the moment the boss
    // appeared it stayed true for the rest of the scene — silently suppressing every
    // power-up HUD bar via showPowerUpTimer(), including in the window after the boss
    // was already dead.
    private var bossSpawned: Bool = false

    /// Freezes the level's own progression — wave spawning and the completion/boss
    /// check — while leaving physics, input, scoring and every manager fully live.
    ///
    /// A seam for `jetshotTests`, in the same spirit as `bossManager` and `currentScore`
    /// above, and it earns its keep for a specific reason. Several gameplay suites assert
    /// that the scene's enemy cache returns to empty once the enemies *they* placed are
    /// destroyed, which is only a meaningful claim while nothing else is adding any. They
    /// used to get that quiet window purely by accident: the level intro ran for three
    /// seconds and the first authored wave took another 1.4 s on top of it, so a
    /// two-second test was always over before the spawner woke up. Both of those numbers
    /// are gameplay tuning — the intro is now 1.75 s and the first wave lands at 0.9 s —
    /// and the moment they were tightened those tests began racing a wave they never
    /// meant to include, failing on a cache that was working perfectly.
    ///
    /// `EnemyManager.stopSpawning()` is deliberately not the seam used for this: it works
    /// by marking every wave as already spawned, which satisfies `areAllWavesSpawned()`
    /// and hands the level straight to `spawnBoss()` two seconds later.
    var isLevelProgressionSuspended: Bool = false

    // Level completion tracking
    private var noEnemiesTime: TimeInterval?
    private let levelCompletionDelay: TimeInterval = GameConfiguration.levelCompletionDelay

    // Lives system
    private var lives: Int = GameConfiguration.defaultLives {
        didSet {
            updateLivesDisplay(topMargin: currentTopMargin)
        }
    }
    private var livesNodes: [SKShapeNode] = []
    private var currentTopMargin: CGFloat = 50
    private var isInvulnerable: Bool = false
    private let invulnerabilityDuration: TimeInterval = GameConfiguration.invulnerabilityDuration

    // Timers
    //
    // Everything below is measured against `gameTime`, an accumulated clock that
    // only advances while the game is actually running and never jumps by more
    // than `GameConfiguration.maxFrameDelta` in a single frame. The raw
    // `currentTime` handed to update(_:) is absolute system time and keeps
    // running through pauses and backgrounding, so using it directly made every
    // interval below fire at once on resume.
    private var gameTime: TimeInterval = 0
    private var lastFrameTime: TimeInterval = 0
    private var lastShootTime: TimeInterval = 0
    private var lastCleanupTime: TimeInterval = 0  // For bullet cleanup optimization
    private let shootInterval: TimeInterval = GameConfiguration.defaultShootInterval
    private var currentShootInterval: TimeInterval {
        return player?.hasRapidFire == true ? GameConfiguration.rapidFireInterval : shootInterval
    }

    /// Weapon overheat rule and its HEAT gauge. See `WeaponHeatSystem` for why this is a
    /// collaborator rather than an extension on this class.
    ///
    /// `lazy` so it can hand the scene to the system's `weak` back-reference, and a
    /// non-optional so it cannot be read after teardown: unlike the spawn managers, this
    /// is touched from `update(_:)` on every frame, and `willMove(from:)` clearing it
    /// would open a window for a nil dereference. Its HUD nodes hang off `uiNode` and are
    /// torn down with it.
    private lazy var weaponHeat = WeaponHeatSystem(scene: self)

    /// Chain-kill scoring and the meter that reports it. See `ComboSystem` for the
    /// mechanic; the collaborator arrangement and the `lazy` are the same trade
    /// `weaponHeat` above makes, for the same reasons.
    private lazy var combo = ComboSystem(scene: self)

    // PowerUp timers and states
    private var scoreMultiplier: Int = 1

    /// The stack of power-up countdown bars. See `PowerUpTimerHUD`, which owns the bars
    /// and their layer; the "not while a boss is up" rule stays here, in
    /// `showPowerUpTimer(name:duration:color:icon:)`.
    ///
    /// `lazy` so the anchor closure can capture the scene. The closure is read on every
    /// re-flow rather than cached, because the anchor moves with the scene height and the
    /// top margin — see the note on `PowerUpTimerHUD.anchorY`.
    private lazy var powerUpTimers = PowerUpTimerHUD(anchorY: { [weak self] in
        guard let self = self else { return 0 }
        return self.size.height - self.currentTopMargin - 50
    })

    // Performance optimization - cache active objects to avoid enumerateChildNodes every frame
    private var activeEnemies: [ObjectIdentifier: Enemy] = [:]
    private var activeCoins: [ObjectIdentifier: Coin] = [:]
    private var activeVortexEnemies: [ObjectIdentifier: Enemy] = [:]
    private var lastSlowMotionUpdateTime: TimeInterval = 0
    private var lastMagnetUpdateTime: TimeInterval = 0
    // No throttle stamp for the vortex: `applyVortexGravitationalPull()` deliberately
    // runs every frame (see the note there), so the one that used to sit here was never
    // read.

    // MARK: - Cache Management

    /// Number of enemies currently held in the cache.
    ///
    /// Exposed so `jetshotTests` can assert that every despawn path unregisters. The
    /// cache holds *strong* references, so a path that forgets is a silent node leak —
    /// which is exactly the bug `Enemy.despawn()` was introduced to close.
    var activeEnemyCount: Int {
        return activeEnemies.count
    }

    /// Register enemy in cache for optimized updates
    func registerEnemy(_ enemy: Enemy) {
        activeEnemies[ObjectIdentifier(enemy)] = enemy
        // Also cache vortex enemies for gravitational pull optimization
        if enemy.enemyType == .vortex {
            activeVortexEnemies[ObjectIdentifier(enemy)] = enemy
        }
    }

    /// Unregister enemy from cache
    func unregisterEnemy(_ enemy: Enemy) {
        let id = ObjectIdentifier(enemy)
        activeEnemies.removeValue(forKey: id)
        // Also remove from vortex cache if applicable
        if enemy.enemyType == .vortex {
            activeVortexEnemies.removeValue(forKey: id)
        }
    }

    /// Register coin in cache for optimized magnet updates.
    ///
    /// There is no matching unregister: coins are evicted by `pruneCoinCache()` once
    /// they leave the scene, because a coin has no reliable moment at which to remove
    /// itself (its deinit cannot run while the cache still holds it).
    func registerCoin(_ coin: Coin) {
        activeCoins[ObjectIdentifier(coin)] = coin
    }

    // MARK: - Gameplay Clock

    /// Single switch for "is the gameplay clock advancing".
    ///
    /// Pauses the three things that must stop together: `gameContentNode` (gameplay
    /// nodes and effects), the power-up countdown bars and the physics
    /// world. `uiNode` itself deliberately keeps running so the pause menu stays live.
    private func setGameplayPaused(_ paused: Bool) {
        gameContentNode?.isPaused = paused
        powerUpTimers.isPaused = paused
        physicsWorld.speed = paused ? 0 : 1.0
    }

    private var isGameplayPaused: Bool {
        return gameContentNode?.isPaused ?? false
    }

    /// Schedules a power-up expiry on the gameplay clock.
    ///
    /// These used to be scheduled on the scene, whose actions keep advancing while the
    /// game is paused — only `gameContentNode` is paused — so opening the pause menu
    /// with a shield up burned the shield. `gameContentNode` is the clock that actually
    /// stops, which is the same reason `Enemy.freeze(duration:)` hosts its detonation
    /// timer there. Cancelling has to go through `cancelPowerUpExpiry(key:)` so both
    /// sides agree on the host node.
    private func schedulePowerUpExpiry(after duration: TimeInterval, key: String, action: @escaping () -> Void) {
        guard let host = gameContentNode else { return }
        host.removeAction(forKey: key)
        let wait = SKAction.wait(forDuration: duration)
        let deactivate = SKAction.run(action)
        host.run(SKAction.sequence([wait, deactivate]), withKey: key)
    }

    private func cancelPowerUpExpiry(key: String) {
        gameContentNode?.removeAction(forKey: key)
    }

    /// Runs a gameplay-timed action on the clock that actually stops when paused.
    ///
    /// `run(_:)` on the scene does *not* respect the pause — `setGameplayPaused(_:)`
    /// pauses `gameContentNode`, the power-up countdown bars and the physics world, never the
    /// scene itself, precisely so the pause menu stays live. Several delayed gameplay
    /// effects were scheduled straight onto the scene anyway (two of them carrying a
    /// comment claiming the opposite), so they kept firing behind the pause menu: the
    /// clearest case was grabbing a nuke and pausing immediately, which went on
    /// destroying enemies and adding score while the game was supposedly frozen.
    ///
    /// Falls back to the scene only if teardown has already cleared the node, matching
    /// `effectsParent`.
    private func runOnGameplayClock(_ action: SKAction, withKey key: String? = nil) {
        let host = effectsParent
        if let key = key {
            host.run(action, withKey: key)
        } else {
            host.run(action)
        }
    }

    /// Parent for gameplay visual effects.
    ///
    /// Effects must hang off `gameContentNode` rather than the scene. The scene keeps
    /// running while the game is paused, so explosions, floating score, hit sparks,
    /// lightning and touch ripples all used to carry on animating behind the pause
    /// menu. Falls back to the scene if teardown has already cleared the node.
    private var effectsParent: SKNode {
        return gameContentNode ?? self
    }

    // iPad optimization - reduce particle effects on larger screens
    private var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    private var particleMultiplier: CGFloat {
        return GameConfiguration.particleMultiplier(for: UIDevice.current.userInterfaceIdiom)
    }

    // Touch tracking
    private var isTouching = false
    private var touchLocation: CGPoint = .zero
    private let shootDistanceThreshold: CGFloat = GameConfiguration.shootDistanceThreshold

    // Pause system
    var gameContentNode: SKNode! // Node that gets paused (public for managers)
    private var uiNode: SKNode! // UI node that never gets paused
    private var pauseButton: SKShapeNode!
    private var pauseOverlay: SKNode?
    private var isInitialized = false

    // Level intro
    private var isGameStarted: Bool = false
    private var isPlayerExiting: Bool = false
    private var safeAreaBottom: CGFloat = 0

    // MARK: - Lifecycle Methods

    override func didMove(to view: SKView) {
        // Load level configuration immediately (lightweight) - must be first!
        //
        // getLevelConfig(for:) returns a non-optional LevelConfig and covers all 50
        // levels explicitly, so there is nothing to validate here. The nil check that
        // used to guard this (plus its on-screen error panel and bounce back to level
        // select) could never run — `levelConfig != nil` is always true once a
        // non-optional has been assigned to an implicitly unwrapped property.
        levelConfig = LevelManager.shared.getLevelConfig(for: currentLevel)

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

        // Layer for the power-up countdown bars, paused in step with gameplay.
        powerUpTimers.install(on: uiNode)

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

        // Register for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
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

        // Vignette between the playfield and the HUD: darkens the corners so the
        // neon in the centre reads as bright instead of washed out.
        NeonFX.attachGrade(to: self)

        // Setup UI on UI node
        setupUI(view: view)

        // Defer heavy initialization to avoid FPS drop
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.view != nil else {
                // Scene was deallocated or removed from view, abort initialization
                return
            }

            // Re-lay the HUD now that the view has been through a layout pass;
            // `safeAreaInsets` is still zero back in didMove(to:).
            self.setupUI(view: view)

            // Add starfield (particle effect) - to game content node
            StarfieldHelper.addDepthLayers(to: self, parentNode: self.gameContentNode)
            self.gameContentNode.addChild(
                StarfieldHelper.createStarfield(for: self, parentNode: self.gameContentNode)
            )

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

            // Verify scene is still valid after async operations
            guard self.view != nil else { return }

            self.isInitialized = true

            #if DEBUG
            print("[INFO] GameScene initialized for level \(self.currentLevel)")
            #endif

            // Pause the game and show level intro after everything is ready
            self.setGameplayPaused(true)
            self.showLevelIntro()

            // After the intro card exists, so `-nointro` has something to fast-forward.
            // Compiled out of Release along with the whole harness.
            #if DEBUG
            DebugLaunch.apply(to: self)
            #endif

            // Start background music for current level
            SoundManager.shared.setMusicForLevel(self.currentLevel)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized, let view = view else { return }

        // Update camera position to center of new size
        camera?.position = CGPoint(x: size.width / 2, y: size.height / 2)

        safeAreaBottom = GameConfiguration.safeAreaBottom(in: view)

        // Update player bounds
        player.updateBounds(sceneSize: size, safeAreaBottom: safeAreaBottom)

        // Re-render the vignette for the new size
        NeonFX.attachGrade(to: self)

        // Reposition UI elements
        setupUI(view: view)

        // Re-stack any live power-up bars. Their slots are derived from `size.height`
        // and `currentTopMargin`, and `setupUI(view:)` above is what refreshes the
        // margin — but it does not own the bars, so without this they keep the
        // positions they were given for the *old* screen height and drift out from
        // under the HUD they are supposed to hang below.
        powerUpTimers.layout(animated: false)

        // Same for a boss health bar mid-fight: it hangs below the HUD margin too, and it
        // was the one element in here that kept its spawn-time placement.
        bossManager?.getBoss()?.layoutHealthBar(in: self)

        // Update starfield, shooting stars and meteors for the new size.
        //
        // Looked up inside `gameContentNode`, which is where didMove(to:) parents them.
        // These three used to be `childNode(withName:)` on the *scene*, and a name with
        // no `//` prefix only matches immediate children — so all three lookups always
        // returned nil and the whole resize path was dead. Every emitter kept the old
        // screen's width and spawn line after a rotation or an iPad Split View resize.
        if let background = gameContentNode {
            if let starfield = background.childNode(withName: "starfield") as? SKEmitterNode {
                StarfieldHelper.updateStarfield(starfield, for: self)
            }
            if let shootingStars = background.childNode(withName: "shootingStars") as? SKEmitterNode {
                StarfieldHelper.updateShootingStars(shootingStars, for: self)
            }
            if let meteors = background.childNode(withName: "meteors") as? SKEmitterNode {
                StarfieldHelper.updateMeteors(meteors, for: self)
            }
            // The slower depth layers carry the same width and spawn line. Rebuilt
            // rather than tweaked: addDepthLayers replaces them by name.
            StarfieldHelper.addDepthLayers(to: self, parentNode: background)
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
        #if DEBUG
        print("[INFO] GameScene willMove - cleaning up resources")
        #endif

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

        // CRITICAL: Stop all repeatForever actions in child nodes before removing.
        //
        // The search string must be "//*", not "//": SpriteKit needs a name pattern
        // after the recursive-search prefix, and "//" on its own matches *nothing*.
        // This block silently did no work at all, which left every node whose
        // repeating action strongly captured itself alive for the life of the process.
        //
        // Note "//" searches from the *root* of the tree, not from the receiver, so
        // both calls below sweep the entire scene. Harmless here — teardown wants
        // everything stopped — but never use "//*" to mean "just my own subtree".
        gameContentNode?.enumerateChildNodes(withName: "//*") { node, _ in
            node.removeAllActions()
        }
        uiNode?.enumerateChildNodes(withName: "//*") { node, _ in
            node.removeAllActions()
        }

        // Remove all children (this also removes their actions)
        gameContentNode?.removeAllChildren()
        uiNode?.removeAllChildren()
        pauseOverlay?.removeAllChildren()
        pauseOverlay?.removeFromParent()

        // Tear the boss down explicitly before dropping the manager. This used to be
        // left to BossManager's deinit, which ran at an arbitrary moment and touched
        // SKNode state from a nonisolated context; doing it here keeps it on the main
        // actor at a known point in teardown.
        bossManager?.cleanup()

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
        activeVortexEnemies.removeAll()

        // Clear player reference
        player = nil

        // Reset game state
        bossSpawned = false
        isGameStarted = false
        isTouching = false
        // Also clears the guard on didChangeSize, which dereferences `player` — that
        // has just been torn down, so a late resize must not be allowed through.
        isInitialized = false
    }

    // MARK: - App Lifecycle

    @objc private func appWillResignActive() {
        // When app goes to background, automatically pause if game is running
        if !isGameplayPaused && isGameStarted {
            togglePause()
        }
    }

    @objc private func appDidBecomeActive() {
        // When app returns from background, re-assert the whole gameplay clock so
        // physics speed and the power-up timer layer can't drift out of step with
        // gameContentNode.
        if isGameplayPaused {
            setGameplayPaused(true)
            // Only restore the pause menu for a genuine player-initiated pause.
            //
            // The `isGameStarted` guard matters: the level intro also runs with
            // gameplay paused, and backgrounding the app during it used to land here
            // with no overlay present, so the pause menu was raised over the intro.
            // The intro then finished and startGame() unpaused without hiding it,
            // leaving a full-screen scrim and a PAUSED panel sitting on top of live
            // gameplay — with dead buttons, because every handler in touchesBegan is
            // gated on gameContentNode.isPaused.
            if isGameStarted && pauseOverlay == nil {
                showPauseOverlay()
            }
        } else if isGameStarted {
            setGameplayPaused(false)
        }

        // Hide overlay if game is not paused but overlay is showing (edge case)
        if pauseOverlay != nil && !isGameplayPaused {
            hidePauseOverlay()
        }
    }

    @objc private func handleMemoryWarning() {
        // Clear texture caches to free up memory
        ParallaxBackgroundHelper.clearTextureCache()
        ParticleTexture.clearCache()
        NeonFX.clearCaches()
        SurfaceFX.clearCaches()
        UITheme.clearCaches()

        // Clean up off-screen objects immediately
        cleanupOffScreenBullets()

        // Rebuild the entity caches from the live node tree.
        //
        // These only ever cache nodes that are already children of gameContentNode, so
        // emptying them frees nothing — and leaving them empty broke things: unlike the
        // enemy and coin caches, `activeVortexEnemies` has no "rebuild when empty" path
        // of its own, so a memory warning used to switch off vortex bullet attraction
        // for the rest of the level.
        rebuildEntityCaches()

        #if DEBUG
        print("⚠️ Memory warning received - cleared texture caches and rebuilt entity caches")
        #endif
    }

    /// Re-derives `activeEnemies`, `activeVortexEnemies` and `activeCoins` from the
    /// nodes currently in the scene.
    private func rebuildEntityCaches() {
        activeEnemies.removeAll()
        activeVortexEnemies.removeAll()
        activeCoins.removeAll()

        gameContentNode?.enumerateChildNodes(withName: "enemy") { [weak self] node, _ in
            if let enemy = node as? Enemy {
                self?.registerEnemy(enemy)
            }
        }
        gameContentNode?.enumerateChildNodes(withName: "coin") { [weak self] node, _ in
            if let coin = node as? Coin {
                self?.registerCoin(coin)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Planet generation needs no explicit stop: the repeating action is keyed on
        // gameContentNode, so it dies with the scene. The old
        // PlanetHelper.stopPlanetGeneration() call was an empty no-op anyway.
    }

    // MARK: - Setup Methods

    private func setupPlayer(view: SKView) {
        safeAreaBottom = GameConfiguration.safeAreaBottom(in: view)

        player = Player(sceneSize: size, safeAreaBottom: safeAreaBottom)

        // Set starting weapon arsenal from previous level
        player.bulletCount = startingBulletCount
        player.sideMissileCount = startingSideMissileCount

        gameContentNode.addChild(player)
    }

    private func setupEnemyManager() {
        if isEndless {
            // Round one only. Every later round is appended by `updateEndlessRun` as the
            // queue drains, which is what makes the mode endless.
            endlessRound = 1
            enemyManager = EnemyManager(scene: self, waves: EndlessDirector.waves(forRound: 1))
            return
        }

        guard let config = levelConfig else {
            assertionFailure("Cannot setup EnemyManager - levelConfig is nil")
            return
        }
        enemyManager = EnemyManager(scene: self, waves: config.waves)
    }

    private func setupObstacleManager() {
        guard let config = levelConfig else {
            assertionFailure("Cannot setup ObstacleManager - levelConfig is nil")
            return
        }
        obstacleManager = ObstacleManager(scene: self, waves: config.obstacleWaves)
    }

    private func setupPowerUpManager() {
        guard let config = levelConfig else {
            assertionFailure("Cannot setup PowerUpManager - levelConfig is nil")
            return
        }
        powerUpManager = PowerUpManager(scene: self, config: config.powerUpConfig)
    }

    private func setupCoinManager() {
        // Configure coin spawning - balanced frequency
        let coinConfig = CoinSpawnConfig(
            spawnInterval: GameConfiguration.coinSpawnInterval,
            spawnProbability: GameConfiguration.coinSpawnProbability,
            minCoins: GameConfiguration.minCoinsPerLevel,
            maxCoins: GameConfiguration.maxCoinsPerLevel
        )
        coinManager = CoinManager(scene: self, config: coinConfig)
    }

    private func setupAsteroidManager() {
        guard let config = levelConfig else {
            assertionFailure("Cannot setup AsteroidManager - levelConfig is nil")
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
        uiNode.childNode(withName: "hudScrim")?.removeFromParent()
        pauseButton?.removeFromParent()
        livesNodes.forEach { $0.removeFromParent() }
        livesNodes.removeAll()
        weaponHeat.removeHUD()
        combo.removeHUD()

        scoreHUD?.removeFromParent()

        // Calculate consistent top margin for all UI elements.
        //
        // `GameConfiguration.safeAreaTop(in:)` reads the inset from the view itself
        // before falling back to its window: `view.window` is still nil while the scene
        // is first presented, and falling back to 0 used to park the score at 40pt
        // dead-centre — directly underneath the Dynamic Island, where it was completely
        // invisible on every notched iPhone. `Boss` shared that bug until the same helper
        // took over there too.
        let topMargin = GameConfiguration.topMargin(in: view)

        // Scrim behind the HUD. Planets and nebulae drift through the top of the
        // playfield, and instrumentation has to stay readable over all of them.
        let scrim = SKSpriteNode(
            texture: UITheme.topScrimTexture(width: size.width, height: topMargin + 46),
            size: CGSize(width: size.width, height: topMargin + 46)
        )
        scrim.name = "hudScrim"
        scrim.position = CGPoint(x: size.width / 2, y: size.height - (topMargin + 46) / 2)
        scrim.zPosition = -1
        uiNode.addChild(scrim)

        // Score sits in its own framed capsule so it reads as instrumentation
        // rather than floating text, and is clear of the sensor housing.
        let hud = SKNode()
        hud.position = CGPoint(x: size.width / 2, y: size.height - topMargin)
        hud.zPosition = 100
        uiNode.addChild(hud)
        scoreHUD = hud

        scoreLabel = SKLabelNode(fontNamed: UITheme.Typography.fontNumeric)
        scoreLabel.fontSize = UITheme.Typography.sizeRegular
        scoreLabel.fontColor = UITheme.Colors.primaryCyanLight
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.text = "\(score)"
        scoreLabel.zPosition = 2
        hud.addChild(scoreLabel)

        let scoreCaption = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        scoreCaption.text = L10n.Common.score
        scoreCaption.fontSize = 9
        scoreCaption.fontColor = UITheme.Colors.primaryCyan.withAlphaComponent(0.65)
        scoreCaption.verticalAlignmentMode = .center
        scoreCaption.position = CGPoint(x: 0, y: 19)
        scoreCaption.zPosition = 2
        hud.addChild(scoreCaption)

        // Setup lives display (same height as score)
        updateLivesDisplay(topMargin: topMargin)

        // Setup pause button (same height as score)
        setupPauseButton(topMargin: topMargin)

        // Setup heat bar
        weaponHeat.installHUD(on: uiNode, sceneWidth: size.width)

        // Chain meter, under the pause button and clear of the power-up stack on the
        // left. It stays hidden until the first tier unlocks, so it costs nothing
        // visually until it is earned. See `ComboSystem.installHUD(on:at:)`.
        combo.installHUD(
            on: uiNode,
            at: CGPoint(x: size.width - 62, y: size.height - topMargin - 58)
        )
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

    /// The card that opens a level: the level number, the score to beat, and — on level
    /// one — nothing else, because the coaching has moved into the playfield.
    ///
    /// This used to be the slowest thing in the game. Level 1 held a full-screen scrim
    /// for about 9.6 seconds before the player could touch anything: 0.4 s for the title
    /// to appear, a 4.5 s hold, a wall of four stacked instruction labels, a blocking
    /// "3 2 1 GO" countdown with its own voice clip, and finally a 0.8 s entry animation
    /// — all of it in front of somebody who had just tapped PLAY for the first time and
    /// had, so far, played nothing at all. Every later level paid 3.0 s of the same
    /// ceremony on every single retry.
    ///
    /// It is now 2.25 s on level 1 and 1.75 s elsewhere, the countdown is gone, and
    /// the level-1 instructions run over live gameplay in `showTutorialHints()`, where
    /// they can actually be acted on while reading them.
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
        levelLabel.text = isEndless ? L10n.HUD.endless : L10n.HUD.level(currentLevel)
        levelLabel.fontSize = 44
        levelLabel.fontColor = .white
        levelLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 20)
        levelLabel.alpha = 0
        UITheme.fitLabel(levelLabel, toWidth: size.width - 48, minimumFontSize: 26)
        levelLabel.setScale(0.5)
        introNode.addChild(levelLabel)

        // The score to beat, whenever there is one. A target on the card gives a replay a
        // point beyond "clear it again", and it is the cheapest hook available: the
        // number is already stored per level to draw the level-select grid. Endless reads
        // its own record instead, which is the only goal that mode has.
        let target: Int? = isEndless
            ? { let best = LevelManager.shared.getEndlessRecords().bestScore; return best > 0 ? best : nil }()
            : LevelManager.shared.getLevelScore(level: currentLevel)

        if let best = target, best > 0 {
            let bestLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
            bestLabel.text = L10n.Common.best(best)
            bestLabel.fontSize = 20
            bestLabel.fontColor = UITheme.Colors.primaryGoldLight
            bestLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 26)
            bestLabel.alpha = 0
            introNode.addChild(bestLabel)
            bestLabel.run(.sequence([
                .wait(forDuration: 0.2),
                .fadeIn(withDuration: 0.25)
            ]))
        }

        addChild(introNode)

        // Level 1 holds fractionally longer than the rest: long enough to read the words
        // "LEVEL 1", not long enough to be a wait.
        // `currentLevel` is left at its default of 1 in endless, so the mode has to be
        // excluded explicitly or an endless run would inherit level 1's longer hold.
        let hold: TimeInterval = (currentLevel == 1 && !isEndless) ? 1.2 : 0.7

        let appear = SKAction.group([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.scale(to: 1.0, duration: 0.3)
        ])
        let disappear = SKAction.group([
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.scale(to: 1.2, duration: 0.25)
        ])
        let startEntry = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.startPlayerEntryAnimation(targetY: originalPlayerY)
        }

        // The card tears itself down at the end of *this* sequence, rather than on a
        // second timeline of its own. Both would finish on the same frame, and
        // `levelLabel` is a child of `introNode`: if SpriteKit happened to run the
        // parent's removal first, the child's remaining actions — `startEntry` among
        // them — would be dropped, `startGame()` would never be reached, and the level
        // would sit on a paused playfield forever. One timeline cannot race itself.
        let teardown = SKAction.run { [weak introNode] in
            introNode?.removeFromParent()
        }

        levelLabel.run(.sequence([
            appear,
            .wait(forDuration: hold),
            disappear,
            startEntry,
            teardown
        ]))

        // The scrim lifts alongside the title rather than after it, so the playfield is
        // already clear while the ship flies in — the entry animation reads as the start
        // of the level instead of as one more thing to sit through. Fade only; the
        // removal above is what actually takes it off the scene.
        introNode.run(.sequence([
            .wait(forDuration: 0.3 + hold),
            .fadeOut(withDuration: 0.25)
        ]))
    }

    /// Level-one coaching, delivered over live gameplay.
    ///
    /// Replaces the four-label wall that used to sit on the intro scrim behind a 4 s
    /// hold. Nothing here blocks input: the player is already flying and already
    /// shooting, and each line arrives at roughly the moment it becomes worth knowing —
    /// the controls immediately, coins once the first ones are drifting past, the chain
    /// once there have been enough kills for it to mean something.
    private func showTutorialHints() {
        let hints: [(text: String, delay: TimeInterval, color: UIColor)] = [
            (L10n.Tutorial.move, 0.4, UITheme.Colors.primaryCyanLight),
            (L10n.Tutorial.coins, 7.0, UITheme.Colors.primaryGoldLight),
            (L10n.Tutorial.chain, 14.0, ComboSystem.tierColor(forMultiplier: 2))
        ]

        for hint in hints {
            let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
            label.text = hint.text
            label.fontSize = 17
            label.fontColor = hint.color
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: size.width / 2, y: size.height * 0.28)
            label.alpha = 0
            label.zPosition = 500
            effectsParent.addChild(label)

            label.run(.sequence([
                .wait(forDuration: hint.delay),
                .fadeIn(withDuration: 0.3),
                .wait(forDuration: 2.8),
                .fadeOut(withDuration: 0.5),
                .removeFromParent()
            ]))
        }
    }

    private func startPlayerEntryAnimation(targetY: CGFloat) {
        // Play player spawn sound
        SoundManager.shared.playPlayerSpawnSound(on: self)

        // Animate player entering from bottom
        let moveUp = SKAction.moveTo(y: targetY, duration: 0.5)
        moveUp.timingMode = .easeOut

        player.run(moveUp) { [weak self] in
            self?.startGame()
        }
    }

    private func startGame() {
        isGameStarted = true
        setGameplayPaused(false)

        // Never hand control back with a pause menu still on screen. Nothing should be
        // able to put one there before the level starts, but the overlay's buttons are
        // all gated on gameContentNode.isPaused, so an overlay that outlives the pause
        // is unreachable dead UI covering the playfield — cheap to rule out here.
        if pauseOverlay != nil {
            hidePauseOverlay()
        }

        // Play level start sound
        SoundManager.shared.playLevelStartSound(on: self)

        // Coaching runs over live gameplay now, so it starts with the level rather than
        // in front of it. Not in endless: `currentLevel` is 1 there by default, and
        // nobody arrives at a survival mode needing to be told what a coin is.
        if currentLevel == 1 && !isEndless {
            showTutorialHints()
        }
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

    private static let pauseOverlayName = "pauseOverlay"

    private func showPauseOverlay() {
        guard pauseOverlay == nil else { return }

        // Sweep away an overlay that is still playing its dismissal fade.
        // `hidePauseOverlay()` clears `pauseOverlay` up front so the game can be
        // re-paused immediately, but leaves the node in the tree for 0.4s to fade.
        // Tapping RESUME and then the pause button straight away therefore stacked a
        // fresh panel underneath a fading scrim.
        uiNode?.childNode(withName: Self.pauseOverlayName)?.removeFromParent()

        let overlay = SKNode()
        overlay.name = Self.pauseOverlayName
        overlay.zPosition = 10000

        // Semi-transparent background
        let background = SKSpriteNode(color: UIColor(white: 0, alpha: 0), size: size)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        background.name = "pauseOverlayBackground"
        overlay.addChild(background)

        // Fade in background
        background.run(SKAction.fadeAlpha(to: 0.7, duration: 0.3))

        // Pause panel - height accommodates retry and settings buttons
        let panelWidth: CGFloat = min(size.width - 60, 300)
        let panelHeight: CGFloat = 410
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
        title.text = L10n.Pause.title
        title.fontSize = 36
        title.fontColor = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
        title.position = CGPoint(x: 0, y: panelHeight / 2 - 50)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        panel.addChild(title)

        // Level info
        let levelInfo = SKLabelNode(fontNamed: "Arial")
        levelInfo.text = L10n.Pause.level(currentLevel)
        levelInfo.fontSize = 22
        levelInfo.fontColor = UIColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0)
        levelInfo.position = CGPoint(x: 0, y: panelHeight / 2 - 90)
        levelInfo.horizontalAlignmentMode = .center
        levelInfo.verticalAlignmentMode = .center
        panel.addChild(levelInfo)

        // Resume button
        let resumeButton = createPauseMenuButton(
            text: L10n.Pause.resume,
            color: UIColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1.0),
            width: 220,
            name: "resumeButton"
        )
        resumeButton.position = CGPoint(x: 0, y: 54)
        panel.addChild(resumeButton)

        // Retry button
        let retryButton = createPauseMenuButton(
            text: L10n.Common.retry,
            color: UIColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1.0),
            width: 220,
            name: "pauseRetryButton"
        )
        retryButton.position = CGPoint(x: 0, y: -12)
        panel.addChild(retryButton)

        // Settings, reachable mid-level: muting only from the main menu would mean
        // abandoning a run to turn the music down.
        let settingsButton = createPauseMenuButton(
            text: L10n.Pause.settings,
            color: UIColor(red: 0.35, green: 0.6, blue: 0.75, alpha: 1.0),
            width: 220,
            name: "pauseSettingsButton"
        )
        settingsButton.position = CGPoint(x: 0, y: -78)
        panel.addChild(settingsButton)

        // Secondary buttons container
        let secondaryButtonY: CGFloat = -144

        let levelsButton = createPauseMenuButton(
            text: L10n.Common.levels,
            color: UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0),
            width: 105,
            name: "pauseLevelsButton"
        )
        levelsButton.position = CGPoint(x: -57, y: secondaryButtonY)
        panel.addChild(levelsButton)

        let menuButton = createPauseMenuButton(
            text: L10n.Common.menu,
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
        UITheme.fitLabel(label, toWidth: width - 20)
        button.addChild(label)

        return button
    }

    private func hidePauseOverlay() {
        guard let overlay = pauseOverlay else { return }
        pauseOverlay = nil

        // Strip the names off the outgoing overlay before it fades. Touch dispatch in
        // this scene is name-based (`nodes(at:)` + name matching), so a scrim and six
        // buttons that are still in the tree but no longer the live overlay must stop
        // answering to those names.
        overlay.name = nil
        Self.clearNames(underDescendantsOf: overlay)

        // Animate panel exit - just fade out, no scaling to avoid position change
        overlay.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
    }

    /// Clears `name` on every descendant of `node`, and nothing else.
    ///
    /// Hand-rolled on purpose. This used to be
    /// `overlay.enumerateChildNodes(withName: "//*")`, but the `//` prefix makes
    /// SpriteKit search from the *root* of the tree rather than from the receiver, so
    /// the call walked the whole scene and wiped the name off every node in it — the
    /// pause button first among them. Touch dispatch is name-based, so dismissing the
    /// pause menu once left the button unable to pause ever again (and broke every
    /// other name lookup in the scene: `player`, `enemy`, `starfield`, the settings
    /// panel).
    private static func clearNames(underDescendantsOf node: SKNode) {
        for child in node.children {
            child.name = nil
            clearNames(underDescendantsOf: child)
        }
    }

    /// The live pause menu's button with this name, or nil if the menu is not up.
    private func pauseMenuButton(named name: String) -> SKShapeNode? {
        guard let overlay = pauseOverlay else { return nil }
        return Self.descendant(of: overlay, named: name)
    }

    /// First descendant of `node` — depth-first, `node` itself excluded — named `name`
    /// and of type `T`.
    ///
    /// Hand-rolled for the same reason `clearNames(underDescendantsOf:)` is: neither
    /// spelling of `childNode(withName:)` scopes a search to a subtree. A bare name
    /// matches *only immediate children*, and the pause buttons are grandchildren of the
    /// overlay (overlay → panel → button), so `overlay.childNode(withName: "resumeButton")`
    /// returns nil. Prefixing `//` finds them, but by searching from the root of the whole
    /// tree — it only happened to be right because these names are unique to the live
    /// overlay and `hidePauseOverlay()` strips them off dismissed ones. That is a lot of
    /// weight for an accident to carry, so search the subtree properly instead.
    ///
    /// The type filter is load-bearing, not decoration: `createPauseMenuButton` puts the
    /// same name on the button *and* on its label, and the callers all want the shape.
    private static func descendant<T: SKNode>(of node: SKNode, named name: String) -> T? {
        for child in node.children {
            if child.name == name, let match = child as? T { return match }
            if let match: T = descendant(of: child, named: name) { return match }
        }
        return nil
    }

    private func handleResumeButton() {
        // Button press animation
        if let resumeButton = pauseMenuButton(named: "resumeButton") {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            resumeButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.togglePause()
            }
        }
    }

    private func handlePauseRetryButton() {
        // Button press animation
        if let retryButton = pauseMenuButton(named: "pauseRetryButton") {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            retryButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.restartGame()
            }
        }
    }

    private func handlePauseLevelsButton() {
        // Button press animation
        if let levelsButton = pauseMenuButton(named: "pauseLevelsButton") {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            levelsButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.goToLevelSelect()
            }
        }
    }

    private func handlePauseMenuButton() {
        // Button press animation
        if let menuButton = pauseMenuButton(named: "pauseMenuButton") {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            menuButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.goToMenu()
            }
        }
    }

    private func handlePauseSettingsButton() {
        // Button press animation
        if let settingsButton = pauseMenuButton(named: "pauseSettingsButton") {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            settingsButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.showSettingsOverlay()
            }
        }
    }

    /// Presents the settings panel over the pause menu.
    ///
    /// Hosted on `uiNode`, which is deliberately never paused — the panel has to stay
    /// interactive while gameplay is frozen.
    private func showSettingsOverlay() {
        guard let uiNode = uiNode,
              uiNode.childNode(withName: SettingsOverlay.nodeName) == nil else { return }
        uiNode.addChild(SettingsOverlay(sceneSize: size))
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

        // Carry the arsenal over, the same way every other route into GameScene does
        // (GameOverScene, LevelSelectScene, LevelCompleteScene, StoryScene). Without
        // this, retrying from the pause menu silently dropped the player back to one
        // bullet and no side missiles, while retrying after dying kept them.
        gameScene.startingBulletCount = startingBulletCount
        gameScene.startingSideMissileCount = startingSideMissileCount
        // Retrying an endless run has to stay an endless run; without this the pause
        // menu's RETRY quietly dropped the player into level 1 of the campaign.
        gameScene.isEndless = isEndless

        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(gameScene, transition: transition)
    }

    private func togglePause() {
        let willPause = !isGameplayPaused
        setGameplayPaused(willPause)

        if willPause {
            showPauseOverlay()
        } else {
            hidePauseOverlay()
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check if pause button was tapped (only when game has started)
        let nodesAtPoint = nodes(at: location)

        // The settings panel is modal, so it takes every tap while it is up — before
        // the pause-menu handlers below, and before any gameplay touch.
        if let settings = uiNode?.childNode(withName: SettingsOverlay.nodeName) as? SettingsOverlay {
            let topName = nodesAtPoint.first(where: { $0.name != nil })?.name
            settings.handleTap(named: topName)
            return
        }

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
                if node.name == "pauseSettingsButton" || node.parent?.name == "pauseSettingsButton" {
                    HapticManager.shared.lightTap()
                    SoundManager.shared.playButtonClickSound(on: self)
                    handlePauseSettingsButton()
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

        spawnTouchRipple(at: location)

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

        spawnTouchRipple(at: location)

        // Move player instantly to follow touch smoothly
        player.moveToInstant(x: location.x, y: location.y, sceneWidth: size.width, sceneHeight: size.height, safeAreaBottom: safeAreaBottom)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused or game hasn't started
        if gameContentNode.isPaused || !isGameStarted { return }
        isTouching = false
    }

    // Negative sentinel so the very first tap of a level still gets a ripple:
    // `gameTime` starts at 0, so a 0 here would swallow it.
    private var lastRippleTime: TimeInterval = -1

    private func spawnTouchRipple(at position: CGPoint) {
        let now = gameTime
        // Throttle to avoid spawning too many rings during drag
        guard now - lastRippleTime > 0.08 else { return }
        lastRippleTime = now

        let ring = SKShapeNode(circleOfRadius: 10)
        ring.position = position
        ring.strokeColor = UIColor(white: 1.0, alpha: 0.45)
        ring.fillColor = UIColor(white: 1.0, alpha: 0.05)
        ring.lineWidth = 1.2
        ring.zPosition = 1000
        effectsParent.addChild(ring)

        let expand = SKAction.scale(to: 2.5, duration: 0.35)
        let fade   = SKAction.fadeOut(withDuration: 0.35)
        let group  = SKAction.group([expand, fade])
        let remove = SKAction.removeFromParent()
        ring.run(SKAction.sequence([group, remove]))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused or game hasn't started
        if gameContentNode.isPaused || !isGameStarted { return }
        isTouching = false
    }

    private func shoot() {
        // Check if weapons are overheated
        if weaponHeat.isOverheated {
            return
        }

        // If lightning weapon is active, use lightning attack.
        //
        // Returns before `registerShot`, so lightning is deliberately exempt from the
        // overheat rule — the one weapon that is. It is a short-lived power-up that clears
        // the screen and lands 15 boss hits per trigger-pull, and its whole point is that
        // it is not rationed; the gauge exists to ration *sustained* fire from the
        // default guns. Left where the lockout check above still covers it, so a
        // pre-existing overheat is not cancelled by picking one up.
        //
        // Note the gauge freezes rather than drains while lightning fires: `isFiring` in
        // update(_:) is true, so `WeaponHeatSystem.update` skips cooling. Any heat carried
        // in resumes cooling the moment the trigger is released.
        if player.hasLightningWeapon {
            shootLightning()
            return
        }

        // Add heat from shooting. The shot that tips the gauge over still fires — see
        // `WeaponHeatSystem.registerShot(currentTime:)`.
        weaponHeat.registerShot(currentTime: gameTime)

        let bullets = player.shoot()

        // Play shoot sound
        SoundManager.shared.playShootSound(on: self)

        // Muzzle flash and a short recoil dip: firing should be felt, not just
        // observed. Both are extremely short so rapid fire doesn't turn strobey.
        let muzzle = NeonFX.flashPoint(
            at: CGPoint(x: player.position.x, y: player.position.y + 20),
            radius: 13,
            color: UIColor(red: 0.7, green: 1.0, blue: 0.95, alpha: 1.0),
            duration: 0.1,
            growTo: 1.5
        )
        muzzle.zPosition = 12
        gameContentNode.addChild(muzzle)

        player.applyRecoil()

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
        effectsParent.addChild(lightning)

        // Damage all enemies on screen
        gameContentNode.enumerateChildNodes(withName: "enemy") { [weak self] node, _ in
            guard let self = self else { return }
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

                    // Same audio cue as a bullet kill — this path was silent.
                    SoundManager.shared.playBossDefeatSound(on: self)

                    // Wait for the boss defeat animation, on the gameplay clock so a
                    // pause actually holds it.
                    let wait = SKAction.wait(forDuration: 2.2)
                    let afterDefeat = SKAction.run { [weak self] in
                        self?.handleBossDefeatAftermath()
                    }
                    runOnGameplayClock(SKAction.sequence([wait, afterDefeat]), withKey: "bossDefeatTransition")
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

    // MARK: - Collision Detection

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
        //
        // `barrier` (256) outranks every other category, so the sort above always puts
        // it in `secondBody` — never in `firstBody`. Testing it as `firstBody` (the
        // previous shape of these two branches) could not match, which left the whole
        // barrier power-up as decoration: four rotating segments that destroyed nothing
        // and blocked nothing, despite the physics bodies being wired up correctly.
        if firstBody.categoryBitMask == PhysicsCategory.enemy &&
           secondBody.categoryBitMask == PhysicsCategory.barrier {
            // A Boss also carries the `enemy` category but is not an `Enemy`, so the
            // cast fails and a boss shrugs the barrier off instead of dying to it.
            barrierDidCollideWithEnemy(enemy: firstBody.node as? Enemy)
        }

        // Barrier hit enemy bullet
        if firstBody.categoryBitMask == PhysicsCategory.enemyBullet &&
           secondBody.categoryBitMask == PhysicsCategory.barrier {
            barrierDidCollideWithEnemyBullet(bullet: firstBody.node as? SKShapeNode)
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
                let awarded = addScore(points)

                // Show floating score
                let scoreText = "+\(awarded)"
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
                let awarded = addScore(points)

                // Show floating score
                let scoreText = "+\(awarded)"
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
                let awarded = addScore(points)

                // Show floating score
                let scoreText = "+\(awarded)"
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

            enemy.flashDamage()
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
            let awarded = addScore(result.points)

            // Show floating score.
            //
            // Printed from what `addScore` actually credited, not recomputed: this line
            // used to print the raw points, so with SCORE x2 up the kill that ended the
            // level reported half of what it paid. The chain multiplier would have made
            // the same mistake eight times worse.
            let scoreText = "+\(awarded)"
            showFloatingText(scoreText, at: boss.position, color: UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0), fontSize: 32)

            // Play boss defeat sound
            SoundManager.shared.playBossDefeatSound(on: self)

            // Wait for the boss defeat animation to complete, on the gameplay clock so
            // a pause actually holds it.
            // (8 explosions * 0.2s + final explosion fade 0.5s = 2.1s)
            let wait = SKAction.wait(forDuration: 2.2)
            let afterDefeat = SKAction.run { [weak self] in
                self?.handleBossDefeatAftermath()
            }
            runOnGameplayClock(SKAction.sequence([wait, afterDefeat]), withKey: "bossDefeatToExit")
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

            handlePlayerDamage()
            return
        }

        // Normal enemy collision
        // Explosion effect
        createExplosion(at: enemy.position, size: .normal)
        HapticManager.shared.mediumTap()

        // Mark enemy as destroyed to prevent completion callback
        enemy.markAsDestroyed()
        enemy.removeFromParent()

        handlePlayerDamage()
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

        handlePlayerDamage()
    }

    private func cancelRemovedPowerUpTimers() {
        // Cancel the pending expiry AND drop the HUD bar for every power-up that is
        // no longer active. Previously only the action was cancelled, so a bar for a
        // power-up lost to degradePowerUps() kept counting down on screen.
        if !player.hasShield {
            cancelPowerUpExpiry(key: "shieldDeactivation")
            removePowerUpTimer(named: "shield")
        }
        if !player.hasLightningWeapon {
            cancelPowerUpExpiry(key: "lightningDeactivation")
            removePowerUpTimer(named: "lightning")
        }
        if !player.hasRapidFire {
            cancelPowerUpExpiry(key: "rapidFireDeactivation")
            removePowerUpTimer(named: "rapidFire")
        }
        if !player.hasMagnet {
            cancelPowerUpExpiry(key: "magnetDeactivation")
            removePowerUpTimer(named: "magnet")
        }
        if !player.hasSlowMotion {
            cancelPowerUpExpiry(key: "slowMotionDeactivation")
            removePowerUpTimer(named: "slowMotion")
            resetEntitySpeeds()
        }
        if !player.hasScoreMultiplier {
            cancelPowerUpExpiry(key: "scoreMultiplierDeactivation")
            removePowerUpTimer(named: "scoreMultiplier")
            scoreMultiplier = 1
        }
        if !player.hasBarrier {
            cancelPowerUpExpiry(key: "barrierDeactivation")
            removePowerUpTimer(named: "barrier")
        }
    }

    // Central helper method for handling player damage
    private func handlePlayerDamage() {
        SoundManager.shared.playHitSound(on: self)

        // Taking a hit costs the chain as well as the life or the power-up stack. That
        // second cost is what makes a good run worth protecting on levels where lives
        // are plentiful.
        combo.breakChain()

        if player.hasAnyPowerUps() {
            // Player has powerups - degrade them but don't lose life
            player.degradePowerUps()
            cancelRemovedPowerUpTimers()
        } else {
            // No powerups - lose a life
            lives -= 1

            // Check for game over
            if lives <= 0 {
                playerDestroyed()
                return
            }
        }

        // Activate invulnerability. The separate `player.playHitAnimation()` call that
        // used to sit here ran a second, unkeyed blink over the same `alpha` as the
        // invulnerability blink below, so the two fought for the first 0.6s.
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

        handlePlayerDamage()
    }

    private func barrierDidCollideWithEnemy(enemy: Enemy?) {
        guard let enemy = enemy else { return }

        // Create explosion effect
        createExplosion(at: enemy.position, size: .normal)
        SoundManager.shared.playExplosionSound(on: self)
        HapticManager.shared.mediumTap()

        // Add score for destroying enemy with barrier
        let awarded = addScore(enemy.enemyType.points)

        // Show floating score
        let scoreText = "+\(awarded)"
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
        // Sparks fan back toward the shooter, which is what a deflected round
        // actually does and reads far better than particles going every way.
        let spark = NeonFX.sparks(
            at: position,
            count: Int(6 * particleMultiplier),
            color: UIColor(red: 1.0, green: 0.88, blue: 0.5, alpha: 1.0),
            speed: 26,
            spreadAngle: .pi * 1.1,
            baseAngle: -.pi / 2,
            length: 5,
            lifetime: 0.22
        )
        spark.zPosition = 100
        effectsParent.addChild(spark)

        let flash = NeonFX.flashPoint(
            at: position,
            radius: 7,
            color: UIColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 1.0),
            duration: 0.13
        )
        flash.zPosition = 100
        effectsParent.addChild(flash)
    }

    // MARK: - PowerUp System

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
        // The three stacking power-ups below can be picked up while already maxed out.
        // They used to be swallowed in complete silence, which reads as the pickup
        // having failed to register; `showMaxedOutFeedback` says "MAX" instead so the
        // player knows the cap — not a dropped input — is what happened.
        case .extraLife:
            if lives < GameConfiguration.maxLives {
                lives += 1
                SoundManager.shared.playExtraLifeSound(on: self)
                HapticManager.shared.heavyTap()
                showFloatingText(L10n.PowerUp.extraLife, at: powerUp.position, color: UIColor(red: 0.0, green: 1.0, blue: 0.3, alpha: 1.0), fontSize: 18)
            } else {
                showMaxedOutFeedback(L10n.PowerUp.livesMax, at: powerUp.position)
            }

        case .multiShot:
            if player.bulletCount < GameConfiguration.maxBulletCount {
                player.bulletCount += 1
                SoundManager.shared.playMultiShotActivateSound(on: self)
                HapticManager.shared.lightTap()
                showFloatingText(L10n.PowerUp.multiShot, at: powerUp.position, color: UIColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 1.0), fontSize: 18)
            } else {
                showMaxedOutFeedback(L10n.PowerUp.gunsMax, at: powerUp.position)
            }

        case .sideMissiles:
            // Was a hardcoded 2 while every other cap reads from GameConfiguration —
            // changing maxSideMissileCount silently had no effect here.
            if player.sideMissileCount < GameConfiguration.maxSideMissileCount {
                player.sideMissileCount += 1
                SoundManager.shared.playMissileSound(on: self)
                HapticManager.shared.lightTap()
                showFloatingText(L10n.PowerUp.sideMissiles, at: powerUp.position, color: UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0), fontSize: 18)
            } else {
                showMaxedOutFeedback(L10n.PowerUp.missilesMax, at: powerUp.position)
            }

        case .shield:
            activateShield()
            SoundManager.shared.playShieldActivateSound(on: self)
            HapticManager.shared.heavyTap()
            showFloatingText(L10n.PowerUp.shield, at: powerUp.position, color: UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1.0), fontSize: 18)

        case .lightning:
            activateLightningWeapon()
            SoundManager.shared.playLightningSound(on: self)
            HapticManager.shared.heavyTap()
            showFloatingText(L10n.PowerUp.lightning, at: powerUp.position, color: UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0), fontSize: 18)

        case .rapidFire:
            activateRapidFire()
            SoundManager.shared.playRapidFireActivateSound(on: self)
            HapticManager.shared.mediumTap()
            showFloatingText(L10n.PowerUp.rapidFire, at: powerUp.position, color: UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0), fontSize: 18)

        case .magnet:
            activateMagnet()
            SoundManager.shared.playMagnetActivateSound(on: self)
            HapticManager.shared.mediumTap()
            showFloatingText(L10n.PowerUp.magnet, at: powerUp.position, color: UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0), fontSize: 18)

        case .slowMotion:
            activateSlowMotion()
            SoundManager.shared.playSlowMotionActivateSound(on: self)
            HapticManager.shared.heavyTap()
            showFloatingText(L10n.PowerUp.slowMotion, at: powerUp.position, color: UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1.0), fontSize: 18)

        case .freezeBomb:
            activateFreezeBomb()
            HapticManager.shared.heavyTap()
            showFloatingText(L10n.PowerUp.freezeBomb, at: powerUp.position, color: UIColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 1.0), fontSize: 18)

        case .homingMissiles:
            launchHomingMissiles()
            SoundManager.shared.playMissileSound(on: self)
            HapticManager.shared.heavyTap()
            showFloatingText(L10n.PowerUp.homingMissiles, at: powerUp.position, color: UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0), fontSize: 18)

        case .scoreMultiplier:
            activateScoreMultiplier()
            SoundManager.shared.playScoreMultiplierSound(on: self)
            HapticManager.shared.mediumTap()
            showFloatingText(L10n.PowerUp.scoreDouble, at: powerUp.position, color: UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0), fontSize: 18)

        case .barrier:
            activateBarrier()
            SoundManager.shared.playBarrierActivateSound(on: self)
            HapticManager.shared.heavyTap()
            showFloatingText(L10n.PowerUp.barrier, at: powerUp.position, color: UIColor(red: 0.2, green: 0.9, blue: 0.7, alpha: 1.0), fontSize: 18)

        case .nuke:
            activateNuke()
            HapticManager.shared.heavyTap()
            showFloatingText(L10n.PowerUp.nuke, at: powerUp.position, color: UIColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 1.0), fontSize: 18)
        }

        // Create 3D vector burst effect
        let burstEffect = VectorFX3D.createPowerUpBurst(
            at: powerUp.position,
            color: powerUp.powerUpType.color,
            particleCount: 50
        )
        effectsParent.addChild(burstEffect)

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
        let awarded = addScore(points, chainsCombo: false)

        // Show floating score
        let scoreText = "+\(awarded)"
        showFloatingText(scoreText, at: coin.position, color: UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0), fontSize: 16)

        // Track coin collection
        coinsCollected += 1

        // Light haptic feedback
        HapticManager.shared.lightTap()

        // Animate coin flying to score label
        coin.collect(scorePosition: scoreHUD?.position ?? CGPoint(x: size.width / 2, y: size.height - currentTopMargin))
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
        let awarded = addScore(points)

        // Show floating score
        let scoreText = "+\(awarded)"
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
                // Shield absorbs the hit, but an asteroid strike consumes it outright
                // (unlike enemy contact, which the shield simply shrugs off).
                deactivateShield()
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

        handlePlayerDamage()
    }

    private func activateShield() {
        player.hasShield = true

        let duration = GameConfiguration.shieldDuration
        // Show timer
        showPowerUpTimer(name: "shield", duration: duration, color: UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1.0), icon: "SHIELD")

        schedulePowerUpExpiry(after: duration, key: "shieldDeactivation") { [weak self] in
            self?.deactivateShield()
        }
    }

    /// Single exit point for the shield, so every path that drops it also cancels the
    /// pending expiry and clears its HUD bar. Asteroid collisions used to flip
    /// `player.hasShield` directly, which left the countdown bar ticking down on a
    /// shield that no longer existed and let the stale expiry action fire later.
    private func deactivateShield() {
        guard player.hasShield else { return }

        player.hasShield = false
        cancelPowerUpExpiry(key: "shieldDeactivation")
        removePowerUpTimer(named: "shield")
        SoundManager.shared.playShieldDeactivateSound(on: self)
    }

    private func activateLightningWeapon() {
        player.hasLightningWeapon = true

        let duration = GameConfiguration.lightningDuration
        // Show timer
        showPowerUpTimer(name: "lightning", duration: duration, color: UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0), icon: "LIGHTNING")

        schedulePowerUpExpiry(after: duration, key: "lightningDeactivation") { [weak self] in
            guard let player = self?.player, player.hasLightningWeapon else { return }
            player.hasLightningWeapon = false
        }
    }

    private func activateRapidFire() {
        player.hasRapidFire = true

        let duration = GameConfiguration.rapidFireDuration
        // Show timer
        showPowerUpTimer(name: "rapidFire", duration: duration, color: UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0), icon: "RAPID FIRE")

        schedulePowerUpExpiry(after: duration, key: "rapidFireDeactivation") { [weak self] in
            self?.player?.hasRapidFire = false
        }
    }

    private func activateMagnet() {
        player.hasMagnet = true

        let duration = GameConfiguration.magnetDuration
        // Show timer
        showPowerUpTimer(name: "magnet", duration: duration, color: UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0), icon: "MAGNET")

        schedulePowerUpExpiry(after: duration, key: "magnetDeactivation") { [weak self] in
            self?.player?.hasMagnet = false
        }
    }

    private func activateSlowMotion() {
        player.hasSlowMotion = true

        let duration = GameConfiguration.slowMotionDuration
        // Show timer
        showPowerUpTimer(name: "slowMotion", duration: duration, color: UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1.0), icon: "SLOW MO")

        schedulePowerUpExpiry(after: duration, key: "slowMotionDeactivation") { [weak self] in
            guard let self = self else { return }
            self.player?.hasSlowMotion = false
            // `resetEntitySpeeds()` already restores enemies, asteroids and bullets.
            // The old inline copy of it also cleared `activeEnemies`, which left every
            // enemy already on screen missing from the cache until the next rebuild.
            self.resetEntitySpeeds()
        }
    }

    private func activateFreezeBomb() {
        // Freeze all enemies for 2.5 seconds, then they explode
        let duration = GameConfiguration.freezeBombDuration
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy {
                enemy.freeze(duration: duration)
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
        let missileCount = GameConfiguration.homingMissileCount
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
                let delay = SKAction.wait(forDuration: Double(i) * GameConfiguration.homingMissileLaunchDelay)
                let launch = SKAction.run { [weak self] in
                    self?.createSeekingMissile()
                }
                runOnGameplayClock(SKAction.sequence([delay, launch]))
            }
            return
        }

        // Launch a homing missile for each target
        for (index, target) in targets.enumerated() {
            let delay = SKAction.wait(forDuration: Double(index) * GameConfiguration.homingMissileLaunchDelay)
            let launch = SKAction.run { [weak self] in
                if let enemy = target as? Enemy {
                    self?.createHomingMissile(target: enemy)
                } else if let boss = target as? Boss {
                    self?.createHomingMissileForBoss(boss: boss)
                }
            }
            runOnGameplayClock(SKAction.sequence([delay, launch]))
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

        // Physics body - uses bullet category to trigger standard collision handling
        // This allows homing missiles to interact with enemies using existing bullet/enemy collision logic
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

        // Physics body - uses bullet category to work with boss collision detection
        // Boss nodes check for bullet contacts, so homing missiles need bullet category

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

        let duration = GameConfiguration.scoreMultiplierDuration
        // Show timer
        showPowerUpTimer(name: "scoreMultiplier", duration: duration, color: UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0), icon: "SCORE x2")

        schedulePowerUpExpiry(after: duration, key: "scoreMultiplierDeactivation") { [weak self] in
            self?.scoreMultiplier = 1
            self?.player?.hasScoreMultiplier = false
        }
    }

    private func activateBarrier() {
        player.hasBarrier = true

        let duration = GameConfiguration.barrierDuration
        // Show timer
        showPowerUpTimer(name: "barrier", duration: duration, color: UIColor(red: 0.2, green: 0.9, blue: 0.7, alpha: 1.0), icon: "BARRIER")

        // Give the segments their physics bodies. `player.hasBarrier = true` above runs
        // updateBarrierVisuals() synchronously through its didSet, so the segments
        // already exist by this point — no need to wait a frame for them.
        // Barrier blocks both enemies and enemy bullets.
        player.enumerateChildNodes(withName: "barrierSegment") { node, _ in
            if node.physicsBody == nil {
                node.physicsBody = SKPhysicsBody(circleOfRadius: 8)
                node.physicsBody?.isDynamic = false
                node.physicsBody?.categoryBitMask = PhysicsCategory.barrier
                node.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.enemyBullet
                node.physicsBody?.collisionBitMask = PhysicsCategory.none
            }
        }

        // Deactivate after the configured duration. This used to be a hardcoded 8.0
        // while the timer bar above used the config value, so the two would drift
        // apart the moment barrierDuration changed.
        schedulePowerUpExpiry(after: duration, key: "barrierDeactivation") { [weak self] in
            self?.player?.hasBarrier = false
        }
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
            runOnGameplayClock(destroyAction)
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
            runOnGameplayClock(destroyAction)
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

    /// Awards `points` scaled by both multipliers, and reports what was actually
    /// credited so callers can label their floating text with the real figure rather
    /// than recomputing it — which is how the boss payout once came to print half of
    /// what it paid.
    ///
    /// `chainsCombo` is false only for pickups. A coin is still *paid* at the current
    /// chain rate, but collecting one must not *extend* the chain: coins drift in on
    /// their own timer, so ticking the deadline from them would let a player park at the
    /// bottom of the screen and hold a high multiplier without shooting anything.
    @discardableResult
    func addScore(_ points: Int, chainsCombo: Bool = true) -> Int {
        // Before the award, so the kill that unlocks a tier is paid at the new rate.
        // Paying it at the old one reads as the meter lying about itself: the number
        // flips to x3 while a "+20" from that same explosion floats past it.
        if chainsCombo {
            combo.registerKill(currentTime: gameTime)
        }

        let awarded = points * scoreMultiplier * combo.multiplier
        score += awarded
        return awarded
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

        effectsParent.addChild(label)

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

    /// Acknowledges a pickup that could not be applied because it is already at its cap.
    private func showMaxedOutFeedback(_ text: String, at position: CGPoint) {
        SoundManager.shared.playCoinSound(on: self)
        HapticManager.shared.lightTap()
        showFloatingText(text, at: position, color: UIColor(white: 0.75, alpha: 1.0), fontSize: 15)
    }

    /// Whether the boss health bar owns the top-left corner the countdown bars want.
    ///
    /// Both halves are derived from live state rather than a cached flag, so bars work
    /// again in the window between the boss dying and the level ending — the bug the note
    /// on `bossSpawned` records.
    ///
    /// The warning half closes a 2.8 s gap. `spawnBoss()` hides the live bars, but the
    /// boss itself is not created until `showBossWarning`'s completion runs, so
    /// `isBossActive()` stays false for the whole warning — and `powerUpManager` keeps
    /// spawning through it. A power-up grabbed in that window used to raise a fresh bar
    /// that then sat under the boss health bar for its entire duration.
    private var bossOwnsHUDCorner: Bool {
        if bossManager?.isBossActive() == true { return true }
        return effectsParent.childNode(withName: "bossWarning") != nil
    }

    /// Shows a countdown bar for a power-up, unless a boss owns that corner.
    ///
    /// The bars themselves live in `PowerUpTimerHUD`. This wrapper keeps the one piece of
    /// the rule that is the scene's business: no bars while a boss owns the corner,
    /// because the boss health bar sits there.
    private func showPowerUpTimer(name: String, duration: TimeInterval, color: UIColor, icon: String) {
        if bossOwnsHUDCorner { return }
        powerUpTimers.show(name: name, duration: duration, color: color, icon: icon)
    }

    private func removePowerUpTimer(named name: String) {
        powerUpTimers.remove(named: name)
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

    /// Attracts coins towards player when magnet powerup is active
    /// Uses cached coin dictionary for optimal performance
    private func attractCoins() {
        let magnetRadius = GameConfiguration.magnetRadius

        // Note: Coins are automatically registered in cache when spawned
        // Only refresh if cache is empty (e.g., after scene restart)
        if activeCoins.isEmpty {
            gameContentNode.enumerateChildNodes(withName: "coin") { [weak self] node, _ in
                if let coin = node as? Coin {
                    self?.activeCoins[ObjectIdentifier(coin)] = coin
                }
            }
        }

        pruneCoinCache()

        for (_, coin) in activeCoins {
            let dx = self.player.position.x - coin.position.x
            let dy = self.player.position.y - coin.position.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance < magnetRadius && distance > 0 {
                // Move coin towards player
                let speed = GameConfiguration.magnetSpeed
                let moveX = (dx / distance) * speed * CGFloat(self.deltaTime)
                let moveY = (dy / distance) * speed * CGFloat(self.deltaTime)
                coin.position.x += moveX
                coin.position.y += moveY
            }
        }
    }

    /// Drops enemies that have left the scene from the cache.
    ///
    /// `Enemy.despawn()` unregisters at the source, so this should normally find
    /// nothing. It runs on the periodic cleanup tick anyway because `activeEnemies`
    /// holds *strong* references: any despawn path that forgets to go through
    /// `markAsDestroyed()` turns into a silent node leak that lasts until the wave
    /// list is exhausted. Cheap insurance against exactly the bug this replaced.
    private func pruneEnemyCache() {
        guard !activeEnemies.isEmpty else { return }
        var toRemove: [ObjectIdentifier] = []
        for (id, enemy) in activeEnemies where enemy.parent == nil {
            toRemove.append(id)
        }
        for id in toRemove {
            activeEnemies.removeValue(forKey: id)
        }
    }

    /// Drops coins that have left the scene from the cache.
    ///
    /// `activeCoins` holds strong references, so a coin cannot deallocate while it is
    /// still listed — which is also why `Coin` cannot unregister itself from its own
    /// deinit. This used to run only from `attractCoins()`, i.e. only while the magnet
    /// power-up was active, so on a magnet-free level every coin ever spawned was held
    /// alive until the scene tore down. Now it runs on the periodic cleanup tick too.
    private func pruneCoinCache() {
        guard !activeCoins.isEmpty else { return }
        var toRemove: [ObjectIdentifier] = []
        for (id, coin) in activeCoins where coin.parent == nil || coin.scene == nil {
            toRemove.append(id)
        }
        for id in toRemove {
            activeCoins.removeValue(forKey: id)
        }
    }

    /// Applies gravitational pull from vortex enemies to player bullets
    /// Vortex enemies can absorb or deflect bullets based on proximity
    private func applyVortexGravitationalPull() {
        // Use cached vortex enemies for better performance
        // Clean up destroyed vortex enemies from cache
        //
        // There is deliberately no "rebuild when empty" fallback here, unlike the enemy
        // and coin caches: this runs every frame, and on the majority of levels — which
        // contain no vortex at all — that fallback would mean enumerating every enemy
        // node every frame for nothing. The cache is kept correct at the source instead,
        // by registerEnemy/unregisterEnemy plus rebuildEntityCaches().
        var toRemove: [ObjectIdentifier] = []
        for (id, vortex) in activeVortexEnemies {
            if vortex.parent == nil {
                toRemove.append(id)
            }
        }
        for id in toRemove {
            activeVortexEnemies.removeValue(forKey: id)
        }

        // If no vortex enemies, nothing to do
        guard !activeVortexEnemies.isEmpty else { return }

        let vortexEnemies = Array(activeVortexEnemies.values)

        let vortexGravityRadius = GameConfiguration.vortexGravityRadius
        let pullStrength = GameConfiguration.vortexPullStrength

        // Deflect player bullets by moving them directly, the same way attractCoins()
        // moves coins.
        //
        // This used to call `bulletBody.applyImpulse(...)`, which had no visible
        // effect: player bullets are flown by an SKAction (`moveTo`/`moveBy` from
        // shoot()) and their physics bodies exist only for contact tests, so the
        // action re-drove the position every frame and overwrote whatever the impulse
        // had integrated. Nudging the position is the only thing that survives
        // alongside the move action, so the pull is now actually felt.
        gameContentNode.enumerateChildNodes(withName: "bullet") { [weak self] node, _ in
            guard let self = self else { return }
            guard let bullet = node as? SKShapeNode else { return }

            // Check each vortex
            for vortex in vortexEnemies {
                let dx = vortex.position.x - bullet.position.x
                let dy = vortex.position.y - bullet.position.y
                let distance = sqrt(dx * dx + dy * dy)

                // Apply pull if bullet is within gravity radius
                if distance < vortexGravityRadius && distance > 0 {
                    // Pull strength falls off linearly towards the edge of the radius.
                    let pullForce = pullStrength * (1.0 - distance / vortexGravityRadius)
                    // Scaled by delta time so the deflection is frame-rate independent.
                    let step = pullForce * 30 * CGFloat(self.deltaTime)
                    bullet.position.x += (dx / distance) * step
                    bullet.position.y += (dy / distance) * step
                }
            }
        }
    }

    private func applySlowMotion(currentTime: TimeInterval) {
        // Only update every 0.1 seconds to reduce performance impact
        guard currentTime - lastSlowMotionUpdateTime >= 0.1 else { return }
        lastSlowMotionUpdateTime = currentTime

        let slowFactor: CGFloat = 0.5

        // Slow down enemies - use cached dictionary only for performance
        var toRemove: [ObjectIdentifier] = []
        for (id, enemy) in activeEnemies {
            // Validate enemy still exists in scene hierarchy
            guard enemy.parent != nil, enemy.scene != nil else {
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

        // Blinking animation during invulnerability.
        //
        // Keyed, and the flag is cleared by the sequence itself rather than by a
        // completion handler: `player.removeAllActions()` (playerDestroyed) discards
        // completion blocks, which would leave `isInvulnerable` stuck true, and a keyed
        // action can't be stacked on top of itself by a second activation.
        let blink = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.1),
            SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        ])
        let blinkTimes = SKAction.repeat(blink, count: Int(invulnerabilityDuration / 0.2))
        let clearFlag = SKAction.run { [weak self] in
            self?.isInvulnerable = false
        }
        // Alpha is restored explicitly: if the sequence is ever cut short the ship
        // must not be left semi-transparent.
        let restoreAlpha = SKAction.fadeAlpha(to: 1.0, duration: 0)

        player.run(SKAction.sequence([blinkTimes, restoreAlpha, clearFlag]),
                   withKey: "invulnerability")
    }

    private func stopGameplayAndTransition(to newScene: SKScene, transitionDuration: TimeInterval = 0.5) {
        // Pause gameplay immediately
        setGameplayPaused(true)

        // Transition to new scene
        newScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: transitionDuration)
        view?.presentScene(newScene, transition: transition)

        // No post-transition cleanup action here: a scene's actions stop advancing once
        // it is no longer the presented scene, so the "transitionCleanup" sequence that
        // used to live here could never fire. willMove(from:) does the real teardown.
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

        // Run the entire sequence on the gameplay clock, like every other delayed
        // gameplay effect. Nothing can pause during the death animation today
        // (playerDestroyed() clears isGameStarted, which gates both the pause button
        // and the auto-pause on resign-active), but hosting it here keeps the timeline
        // consistent if that ever changes.
        runOnGameplayClock(SKAction.sequence(explosionActions), withKey: "playerDestruction")
    }

    private func gameOver() {
        // Play game over sound
        SoundManager.shared.playGameOverSound(on: self)

        // An endless run has no completion screen to persist it, so this is the only
        // place its result is ever recorded.
        var isEndlessRecord = false
        if isEndless {
            isEndlessRecord = LevelManager.shared.recordEndlessRun(score: score, round: endlessRound)
        }

        let gameOverScene = GameOverScene(
            size: size,
            score: score,
            level: currentLevel,
            isEndless: isEndless,
            endlessRound: endlessRound,
            isEndlessRecord: isEndlessRecord
        )
        stopGameplayAndTransition(to: gameOverScene, transitionDuration: 1.0)
    }

    private func createHitEffect(at position: CGPoint) {
        // Smaller hit effect for when enemy takes damage but isn't destroyed
        let hitContainer = SKNode()
        hitContainer.position = position
        hitContainer.zPosition = 500
        effectsParent.addChild(hitContainer)

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
        let shake = ExplosionFX.cameraShake(for: size, isIPad: isIPad)
        shakeCamera(intensity: shake.intensity, duration: shake.duration)

        // The burst itself. Parented to `effectsParent`, not the scene, so it freezes
        // with the gameplay clock — see `effectsParent`.
        let burst = ExplosionFX.burst(size: size, particleMultiplier: particleMultiplier)
        burst.position = position
        effectsParent.addChild(burst)

        ExplosionFX.screenFlash(for: size, in: self)
    }

    // MARK: - Game Update Loop

    override func update(_ currentTime: TimeInterval) {
        // Advance the frame reference on every tick, including paused ones, so the
        // first running frame after a resume sees one ordinary frame's worth of
        // elapsed time rather than the whole pause.
        let rawDelta = lastFrameTime == 0 ? 0 : currentTime - lastFrameTime
        lastFrameTime = currentTime

        // Check if player is exiting and off screen (must be before pause/start checks)
        if isPlayerExiting && player.position.y > size.height + 50 {
            isPlayerExiting = false
            levelComplete()
            return
        }

        // Don't update game logic when paused or game hasn't started yet
        if gameContentNode.isPaused || !isGameStarted { return }

        // Clamped delta drives both per-frame motion and the game clock, so a
        // dropped frame or a resumed pause can never translate into a huge step.
        deltaTime = min(max(rawDelta, 0), GameConfiguration.maxFrameDelta)
        gameTime += deltaTime

        // Magnet effect - attract coins (limited to 30 FPS for performance)
        if player.hasMagnet && gameTime - lastMagnetUpdateTime >= GameConfiguration.magnetUpdateInterval {
            lastMagnetUpdateTime = gameTime
            attractCoins()
        }

        // Vortex gravitational pull on player bullets
        applyVortexGravitationalPull()

        // Expire a lapsed kill chain. On the gameplay clock, so a pause never eats one.
        combo.update(currentTime: gameTime)

        // Fly the ship for the App Store preview recordings. Placed here, ahead of the
        // firing block, because the bot steers through `isTouching` / `touchLocation`
        // and this frame's shot has to see the lane it just moved into.
        #if DEBUG
        DebugLaunch.steer(self, deltaTime: deltaTime)
        #endif

        // Update weapon cooling.
        //
        // `isFiring` has to mirror the firing condition below rather than just
        // `isTouching`: heat used to freeze while the player held a drag outside firing
        // range — not shooting, but not cooling either.
        let isFiring = isTouching && abs(player.position.x - touchLocation.x) <= shootDistanceThreshold
        weaponHeat.update(deltaTime: deltaTime, currentTime: gameTime, isFiring: isFiring)

        // Shoot only when touching and player is near touch location
        if isTouching && gameTime - lastShootTime > currentShootInterval {
            let distance = abs(player.position.x - touchLocation.x)
            if distance <= shootDistanceThreshold {
                shoot()
                lastShootTime = gameTime
            }
        }

        // Update enemy spawning (with slow motion modifier)
        if !isLevelProgressionSuspended {
            enemyManager.update(currentTime: gameTime)
        }

        // Update obstacle spawning
        obstacleManager.update(currentTime: gameTime)

        // Update powerup spawning
        powerUpManager.update(currentTime: gameTime)

        // Update coin spawning
        coinManager.update(currentTime: gameTime)

        // Update asteroid spawning
        asteroidManager?.update(currentTime: gameTime)

        // Apply slow motion to enemies, asteroids, and bullets if active
        if player.hasSlowMotion {
            applySlowMotion(currentTime: gameTime)
        }

        // Clean up off-screen bullets to prevent memory buildup (but not every frame)
        let cleanupInterval: TimeInterval = isIPad
            ? GameConfiguration.cleanupIntervalPad
            : GameConfiguration.cleanupIntervalPhone
        if gameTime - lastCleanupTime >= cleanupInterval {
            cleanupOffScreenBullets()
            pruneCoinCache()
            pruneEnemyCache()
            lastCleanupTime = gameTime
        }

        // Check level completion - simple approach
        if !isLevelProgressionSuspended {
            if isEndless {
                updateEndlessRun()
            } else {
                checkLevelCompletion(currentTime: gameTime)
            }
        }
    }

    /// Removes bullets that are off-screen to prevent memory buildup
    /// Note: This is a performance-critical method called periodically, not every frame
    private func cleanupOffScreenBullets() {
        // Remove enemy bullets that are off-screen to prevent memory buildup
        // Check both above and below screen, plus some margin on sides
        let margin: CGFloat = 100
        let minY = -margin
        let maxY = size.height + margin
        let minX = -margin
        let maxX = size.width + margin

        gameContentNode.enumerateChildNodes(withName: "enemyBullet") { node, _ in
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

    /// Checks if level is complete by counting remaining enemies
    /// Uses cached enemy count to avoid expensive enumeration every frame
    /// Note: Performance-critical - called every frame
    private func checkLevelCompletion(currentTime: TimeInterval) {
        // Once the boss has spawned, completion is driven by its defeat rather than
        // by the enemy count, so there is nothing to check here.
        if bossSpawned {
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
            pruneEnemyCache()
        }

        let enemyCount = activeEnemies.count

        if enemyCount == 0 {
            // No enemies on screen
            if noEnemiesTime == nil {
                // First time we detected no enemies
                noEnemiesTime = currentTime
            } else {
                // Check if enough time has passed
                guard let noEnemiesTime = noEnemiesTime else { return }
                let timeWithoutEnemies = currentTime - noEnemiesTime
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

    // MARK: - Endless Run

    /// Advances an endless run: when the playfield is clear and the queue is drained, the
    /// next round is either a boss or a fresh batch of waves.
    ///
    /// Deliberately gated on the screen being *empty* rather than on a timer, so a player
    /// who clears fast is rewarded with the next round immediately and a player who is
    /// struggling is never buried under two rounds at once.
    private func updateEndlessRun() {
        guard !isEndlessBossFight, !bossManager.isBossActive() else { return }
        guard enemyManager.areAllWavesSpawned() else { return }

        pruneEnemyCache()
        guard activeEnemies.isEmpty else { return }

        endlessRound += 1

        if EndlessRules.isBossRound(endlessRound) {
            spawnEndlessBoss()
        } else {
            beginEndlessRound()
        }
    }

    /// Queues one round: enemies from the director, hazards from the campaign level the
    /// run's depth corresponds to. Both have to be topped up, or the playfield would
    /// quietly empty of everything except ships a few rounds in.
    private func beginEndlessRound() {
        enemyManager.appendWaves(
            EndlessDirector.waves(forRound: endlessRound),
            currentTime: gameTime
        )

        let hazards = LevelManager.shared.endlessHazardWaves(forRound: endlessRound)
        obstacleManager.appendWaves(hazards.obstacles, currentTime: gameTime)
        asteroidManager?.appendWaves(hazards.asteroids, currentTime: gameTime)

        announceEndlessRound()
    }

    /// The round banner. Endless has no level-complete screen, so this is the only place
    /// the run reports progress back to the player.
    private func announceEndlessRound() {
        let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        label.text = L10n.HUD.round(endlessRound)
        label.fontSize = 26
        label.fontColor = UITheme.Colors.primaryCyanLight
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        label.alpha = 0
        label.zPosition = 500
        effectsParent.addChild(label)

        label.run(.sequence([
            .group([.fadeIn(withDuration: 0.2), .scale(to: 1.15, duration: 0.2)]),
            .scale(to: 1.0, duration: 0.15),
            .wait(forDuration: 0.9),
            .fadeOut(withDuration: 0.4),
            .removeFromParent()
        ]))
    }

    /// A boss round. Reuses the campaign's boss entirely — including the phase escalation
    /// and the per-milestone attack signatures — touring up through the authored
    /// milestones as the run gets deeper. See `EndlessRules.bossLevel(forRound:)`.
    private func spawnEndlessBoss() {
        isEndlessBossFight = true

        obstacleManager.stopSpawning()
        coinManager.setBossFight(true)
        powerUpTimers.hideAll()

        let bossLevel = EndlessRules.bossLevel(forRound: endlessRound)

        showBossWarning { [weak self] in
            guard let self = self else { return }
            SoundManager.shared.playBossAppearSound(on: self)
            self.bossManager.spawnBoss(level: bossLevel) {
                // Boss entrance complete, attacks begin
            }
        }
    }

    /// Picks the run back up after an endless boss dies, instead of ending the level.
    private func resumeEndlessRunAfterBoss() {
        isEndlessBossFight = false
        bossManager.cleanup()
        coinManager.setBossFight(false)

        beginEndlessRound()
    }

    private func spawnBoss() {
        guard !bossSpawned else {
            #if DEBUG
            print("[WARNING] Attempted to spawn boss but boss already spawned")
            #endif
            return
        }

        bossSpawned = true

        // Stop spawning regular enemies, obstacles, and coins
        enemyManager.stopSpawning()
        obstacleManager.stopSpawning()
        coinManager.setBossFight(true)

        // Hide all powerup timers during boss fight
        powerUpTimers.hideAll()

        // Show warning before boss appears
        showBossWarning { [weak self] in
            guard let self = self else { return }
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
        warningLabel.text = L10n.HUD.warning
        warningLabel.fontSize = 40
        warningLabel.fontColor = UIColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 1.0)
        warningLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 40)
        warningLabel.alpha = 0
        warningNode.addChild(warningLabel)

        // Danger approaching text
        let approachingLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        approachingLabel.text = L10n.HUD.extremeDanger
        approachingLabel.fontSize = 28
        approachingLabel.fontColor = .white
        approachingLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
        approachingLabel.alpha = 0
        warningNode.addChild(approachingLabel)

        // Warning and its dismissal timer both live on gameContentNode so a pause
        // freezes them together; on the scene the countdown kept running and the boss
        // could spawn while the pause menu was up.
        effectsParent.addChild(warningNode)

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

        effectsParent.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.8),
            cleanup
        ]))
    }

    /// What a dead boss means, which differs by mode: the end of an authored level, or
    /// just the end of one endless round.
    ///
    /// Both boss-defeat paths — a bullet kill and a lightning kill — route through here so
    /// the two cannot drift apart, which they already had once over the defeat sound.
    private func handleBossDefeatAftermath() {
        if isEndless {
            resumeEndlessRunAfterBoss()
        } else {
            startPlayerExitAnimation()
        }
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
            sideMissileCount: player.sideMissileCount,
            bestChain: combo.bestChain
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

        particles.particleTexture = ParticleTexture.solidCircle(diameter: 8)

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
        effectsParent.addChild(particles)

        // Move particles toward vortex center
        let moveToVortex = SKAction.move(to: vortex.position, duration: 0.3)
        particles.run(SKAction.sequence([
            moveToVortex,
            SKAction.removeFromParent()
        ]))

        SoundManager.shared.playAbsorbSound(on: self)
    }

    private func reflectBullet(_ bullet: SKShapeNode, from mirror: Enemy) {
        // Cancel the outbound flight first.
        //
        // Player bullets are driven by an SKAction (`moveTo(y: size.height + 20)` in
        // shoot()), not by physics velocity — their bodies exist purely for contact
        // tests. So setting `velocity` alone changed nothing: the move action kept
        // dragging the bullet up the screen and simply overrode the physics each
        // frame. The bullet turned red, swapped category, and then flew away from the
        // player exactly as before, which made the Mirror's signature ability a
        // no-op. Reflection has to take the position back under physics control.
        bullet.removeAllActions()

        // Change bullet to enemy bullet. The name has to change too, or the reflected
        // bullet stays outside every "enemyBullet" sweep (slow motion, speed reset)
        // and gets treated as a player bullet by the off-screen cleanup — which only
        // checks the top edge, never the bottom, so a bullet heading down at the
        // player would never be collected.
        bullet.name = "enemyBullet"
        bullet.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
        bullet.physicsBody?.contactTestBitMask = PhysicsCategory.player
        bullet.physicsBody?.collisionBitMask = PhysicsCategory.none
        bullet.physicsBody?.linearDamping = 0
        bullet.fillColor = .red

        // Aim back at the player rather than just negating the outbound vector: the
        // bullet had no meaningful velocity to negate (see above), and a mirror that
        // returns fire at whoever shot it is what the enemy is for.
        let dx = player.position.x - bullet.position.x
        let dy = player.position.y - bullet.position.y
        let distance = hypot(dx, dy)
        let reflectSpeed: CGFloat = 320

        if distance > 0 {
            bullet.physicsBody?.velocity = CGVector(
                dx: dx / distance * reflectSpeed,
                dy: dy / distance * reflectSpeed
            )
            bullet.zRotation = atan2(dy, dx) - .pi / 2
        } else {
            // Degenerate case only: bullet is exactly on the player.
            bullet.physicsBody?.velocity = CGVector(dx: 0, dy: -reflectSpeed)
        }

        // Give it a lifetime, since removeAllActions() above threw away the sequence
        // that used to remove it.
        bullet.run(SKAction.sequence([
            SKAction.wait(forDuration: 6.0),
            SKAction.removeFromParent()
        ]), withKey: "bulletLifetime")

        // Flash effect on mirror
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 0.05),
            SKAction.fadeAlpha(to: 1.0, duration: 0.05)
        ])
        mirror.run(flash)

        SoundManager.shared.playReflectSound(on: self)
    }

    private func isHittingShield(bullet: SKShapeNode, enemy: Enemy) -> Bool {
        // The shield sweeps around the enemy, so what matters is where it is pointing
        // at the moment of impact.
        guard let shieldNode = enemy.childNode(withName: "shield") else { return false }

        let dx = bullet.position.x - enemy.position.x
        let dy = bullet.position.y - enemy.position.y

        return ShieldArc.isBlocking(
            bulletAngle: atan2(dy, dx),
            shieldAngle: shieldNode.zRotation
        )
    }

    private func createSplitterFragments(at position: CGPoint) {
        // Create 2 smaller basic enemies that fly off in different directions
        for i in 0..<2 {
            let fragment = Enemy(sceneSize: size, scene: self, type: .basic)
            fragment.position = position
            fragment.setScale(0.6) // Smaller than original

            // Must live in gameContentNode, not on the scene: fragments parented to
            // the scene root kept flying and shooting through a pause, were invisible
            // to every `gameContentNode` enemy sweep (nuke, freeze bomb, lightning,
            // homing missiles, slow motion) and never counted towards level completion.
            gameContentNode.addChild(fragment)
            registerEnemy(fragment)

            // Launch fragments in opposite directions
            let angle: CGFloat = i == 0 ? -.pi/4 : .pi/4
            let dx = cos(angle) * 150
            let dy = sin(angle) * 150 - 100 // Also move down

            let launch = SKAction.moveBy(x: dx, y: dy, duration: 0.8)
            let fall = SKAction.moveTo(y: -20, duration: 3.0)
            let despawn = SKAction.run { [weak fragment] in
                // Unregister via the normal destruction path so the fragment leaves
                // the activeEnemies cache instead of waiting to be swept out.
                // markAsDestroyed() clears this very sequence, so the removal has to
                // happen here rather than as a following action.
                fragment?.markAsDestroyed()
                fragment?.removeFromParent()
            }

            fragment.run(SKAction.sequence([launch, fall, despawn]))

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
            effectsParent.addChild(spark)

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
}

// MARK: - Debug Launch Seams

#if DEBUG

/// The playfield state `DebugLaunch` needs in order to pose a screenshot or fly a
/// preview clip, gathered into one narrow surface.
///
/// An extension rather than a scattering of relaxed `private`s, and in this file
/// rather than beside `DebugLaunch`, because Swift's `private` is file-scoped for
/// extensions of the same type — so everything here reaches the real state while the
/// class body keeps its access control exactly as it was for the shipping build.
/// The whole extension compiles out of Release along with its only caller.
extension GameScene {

    var debugPlayer: Player { player }

    var debugSafeAreaBottom: CGFloat { safeAreaBottom }

    /// Drives the ship through the same pair a real drag sets, so auto-fire, weapon
    /// heat and the chain all behave as they do for a player. See `DebugLaunch.steer`.
    func debugDrag(to location: CGPoint) {
        isTouching = true
        touchLocation = location
        player.moveToInstant(
            x: location.x,
            y: location.y,
            sceneWidth: size.width,
            sceneHeight: size.height,
            safeAreaBottom: safeAreaBottom
        )
    }

    func debugSetInvulnerable(_ invulnerable: Bool) {
        isInvulnerable = invulnerable
    }

    /// Positions of every live `name` node sitting above `minY`.
    ///
    /// Returns points rather than taking a callback because `enumerateChildNodes` is
    /// imported with an escaping closure, and an escaping seam here would be an odd
    /// shape for what is only ever "where are the bullets right now".
    func debugPositions(named name: String, above minY: CGFloat) -> [CGPoint] {
        var found: [CGPoint] = []
        gameContentNode.enumerateChildNodes(withName: name) { node, _ in
            if node.position.y > minY { found.append(node.position) }
        }
        return found
    }

    /// Lets the level actually begin, and optionally fast-forwards the intro card.
    ///
    /// The unpause is not a shortcut, it is the fix for a deadlock this route would
    /// otherwise hit every single time. `showLevelIntro()` ends by animating the player
    /// up from below and calling `startGame()` from that action's completion — but the
    /// player lives inside `gameContentNode`, which the intro has just paused, so the
    /// action is frozen and the completion never fires. In the shipped app it runs
    /// anyway: every route into `GameScene` presents it with an `SKTransition`,
    /// SpriteKit pauses the incoming scene for the duration and unpausing the *scene*
    /// afterwards clears `isPaused` on its descendants, `gameContentNode` included.
    /// `DebugLaunch` presents the scene straight from `GameViewController` with no
    /// transition, so nothing ever clears it. `GameplayHarness` in jetshotTests hits the
    /// same wall for the same reason and resolves it the same way — see the comment at
    /// the top of that file, which is where this one comes from.
    ///
    /// The fast-forward, when asked for, raises the card's own `speed` rather than
    /// tearing it down: `showLevelIntro()` hangs the entry animation, the unpause and
    /// the card's removal off one action sequence and the comment there explains why
    /// they may not be split, so running that sequence at 25x skips nothing.
    func debugReleaseIntro(fastForward: Bool) {
        setGameplayPaused(false)
        if fastForward {
            childNode(withName: "levelIntro")?.speed = 25
        }
    }

    /// Puts the chain meter at a given length by registering the kills that would have
    /// built it. Going through `registerKill` rather than writing the counter is what
    /// makes the meter, its colour, its decay bar and its multiplier agree.
    func debugSeedChain(_ chain: Int) {
        for _ in 0..<chain {
            combo.registerKill(currentTime: gameTime)
        }
    }

    func debugActivatePowerUp(_ type: PowerUpType) {
        switch type {
        case .shield: activateShield()
        case .barrier: activateBarrier()
        case .rapidFire: activateRapidFire()
        case .magnet: activateMagnet()
        case .lightning: activateLightningWeapon()
        case .slowMotion: activateSlowMotion()
        case .scoreMultiplier: activateScoreMultiplier()
        default: break
        }
    }

    /// Jumps an endless run to `round`.
    ///
    /// Queues the round the same way the run itself would, boss rounds included, so
    /// `updateEndlessRun()` picks the sequence up at `round + 1` when the screen clears.
    /// `stopSpawning()` first because `setupEnemyManager()` has already queued round one:
    /// without it a run started at round 24 would spend its first half-minute working
    /// through round one's two enemy types.
    func debugSetEndlessRound(_ round: Int) {
        endlessRound = round
        debugWhen({ [weak self] in self?.isGameStarted == true }) { [weak self] in
            guard let self = self else { return }
            self.enemyManager.stopSpawning()
            if EndlessRules.isBossRound(round) {
                self.spawnEndlessBoss()
            } else {
                self.beginEndlessRound()
            }
        }
    }

    /// Re-shows the round banner, which is the only place an endless run says out loud
    /// which round it is on — it is a banner, not a HUD element, so a screenshot taken
    /// thirty seconds in would have no way to tell endless apart from a campaign level.
    /// The number it prints is the run's real `endlessRound`.
    func debugAnnounceEndlessRound() {
        announceEndlessRound()
    }

    /// Skips to the boss and damages it down to `healthFraction` of its health.
    ///
    /// The two waits are why this is not four lines: `spawnBoss()` needs a started
    /// level, and the boss only exists to be damaged once its warning and entrance have
    /// played. Polling for both beats guessing at a delay, which would go stale the next
    /// time either animation is retimed.
    func debugForceBoss(healthFraction: CGFloat) {
        debugWhen({ [weak self] in self?.isGameStarted == true }) { [weak self] in
            guard let self = self else { return }

            // A boss shot wants the boss, not the wave that happened to be on screen
            // when the run was hijacked.
            self.gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
                node.removeFromParent()
            }
            self.pruneEnemyCache()
            self.spawnBoss()

            self.debugWhen({ [weak self] in self?.bossManager.isBossActive() == true }) {
                [weak self] in
                guard let self = self else { return }
                let level = self.isEndless
                    ? EndlessRules.bossLevel(forRound: self.endlessRound)
                    : self.currentLevel
                let maxHealth = BossConfig.config(for: level).maxHealth
                let target = max(1, Int(CGFloat(maxHealth) * healthFraction))
                for _ in 0..<(maxHealth - target) {
                    guard self.bossManager.isBossActive() else { break }
                    _ = self.bossManager.bossTakeDamage()
                }
            }
        }
    }

    /// Runs `body` on the first tick at which `condition` holds, then stops polling.
    /// One shared helper because both of `debugForceBoss`'s waits want it.
    private func debugWhen(_ condition: @escaping () -> Bool, run body: @escaping () -> Void) {
        var fired = false
        let key = "debugWhen-\(UUID().uuidString)"
        let poll = SKAction.repeatForever(.sequence([
            .wait(forDuration: 0.1),
            .run { [weak self] in
                guard !fired, condition() else { return }
                fired = true
                self?.removeAction(forKey: key)
                body()
            }
        ]))
        run(poll, withKey: key)
    }
}

#endif
