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
    /// The ship's pickup reach — a wide circle around the small core hitbox, so shrinking
    /// what can hurt the ship did not also shrink what it can collect.
    static let collector: UInt32 = 0b1000000000 // 512
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

    /// The endless best score as it stood when this run began, so "new record" is
    /// judged against the record the run set out to beat. The store itself cannot say:
    /// the run is written to it on every way out — the pause menu, the app leaving the
    /// foreground — so by game over it may already hold this run's own score.
    private var endlessBestAtStart = 0

    /// Whether this endless run got as far as live play, and so has a result worth
    /// recording. A run abandoned on its intro card has not.
    private var hasEndlessRunStarted = false

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

    /// Read-only views of the newer systems, for `jetshotTests` — the same reason as
    /// `currentScore`: each is the observable outcome of a rule that otherwise only
    /// surfaces as animation.
    var currentLives: Int { lives }
    var isOverdriveActive: Bool { overdrive.isActive }
    var overdriveCharge: Double { overdrive.charge }
    var liveShardCount: Int { shards?.liveCount ?? 0 }

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
        let base = player?.hasRapidFire == true ? GameConfiguration.rapidFireInterval : shootInterval
        let perked = base * PerkRules.fireIntervalScale(stacks: stacks(.fireRate))
        return overdrive.isActive ? perked * OverdriveRules.fireIntervalScale : perked
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

    /// The Overdrive meter and its gauge. See `OverdriveSystem` and `OverdriveRules`.
    private let overdrive = OverdriveSystem()

    /// Energy shards in flight. Built in `didMove(to:)`, once `gameContentNode` exists.
    private var shards: ShardSystem?

    /// The level an enemy spawned now should be as tough as. The campaign level, or for
    /// an endless run the level its current depth borrows hazards from. Read by `Enemy`'s
    /// initialiser.
    var enemyHealthLevel: Int {
        if isEndless {
            return EndlessRules.hazardLevel(forRound: max(1, endlessRound))
        }
        return currentLevel
    }

    // MARK: Time scale
    //
    // Hit-stop and slow-motion beats (see `HitStop`). The scale is applied to the
    // gameplay clock, the action speed of `gameContentNode` and the physics world
    // together, so everything that moves slows as one. It is restored from `update(_:)`
    // against `realPlayTime` — never from an action, which would keep running behind the
    // pause menu and could restore physics while the game is meant to be frozen.

    private var timeScale: CGFloat = 1.0
    private var timeScaleEndsAt: TimeInterval = 0
    /// Unscaled play time: advances like `gameTime` but ignores the time scale.
    private var realPlayTime: TimeInterval = 0

    // MARK: Medals
    //
    // What the level's medals are judged on. See `MedalRules`.

    /// Hits that reached the damage path, including ones a full Overdrive absorbed.
    private var hitsTaken = 0
    /// Enemies that appeared this level, counted once each (`Enemy.isTallied`).
    private var enemiesSeen = 0
    /// Enemies the player destroyed, by any weapon.
    private var enemiesDestroyed = 0
    /// Set once the chain medal's target has been announced, so it is said only once.
    private var chainMedalAnnounced = false

    /// The medals the level stands to award if it ended now. Read-only, for
    /// `jetshotTests` and for the level-complete hand-off.
    var medalsEarnedSoFar: MedalSet {
        return MedalRules.earned(
            level: currentLevel,
            hitsTaken: hitsTaken,
            bestChain: combo.bestChain,
            enemiesDestroyed: enemiesDestroyed,
            enemiesSeen: enemiesSeen
        )
    }

    // MARK: Endless perks

    /// Perks the endless run has taken, and how many times each.
    private(set) var perkStacks: [EndlessPerk: Int] = [:]

    private func stacks(_ perk: EndlessPerk) -> Int {
        return perkStacks[perk] ?? 0
    }

    // MARK: Graze

    private var grazeCount: Int = 0
    private var lastGrazeCue: TimeInterval = -1

    /// When the last non-lethal hit buzzed the phone. A dense stream lands far more hits
    /// than a haptic engine can usefully separate.
    private var lastHitHaptic: TimeInterval = -1

    // PowerUp timers and states
    private var scoreMultiplier: Int = 1

    /// The stack of power-up countdown bars. See `PowerUpTimerHUD`, which owns the bars
    /// and their layer; the "not while a boss is up" rule stays here, in
    /// `bossOwnsHUDCorner`.
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

    /// Intensity of the camera shake currently playing, so a weaker one cannot cut a
    /// stronger one short. See `shakeCamera(intensity:duration:)` for why this is safe
    /// to keep as plain state rather than reading it back off the action.
    private var activeShakeIntensity: CGFloat = 0

    /// Drop from the HUD margin to the centre of the chain meter.
    ///
    /// The meter is boxed in on both sides, which is what makes this a constant worth
    /// naming rather than a literal at the call site. Above it is the 44pt pause button
    /// — which carries a glow halo, so its apparent edge is lower than its outline —
    /// and below it is the boss health bar, whose right end runs under the meter at the
    /// same x. At a drop of 58 those gaps were 9pt and 4pt: the meter read as stuck to
    /// the pause button.
    ///
    /// Moving it down therefore had to move `Boss.healthBarDropBelowHUD` with it. Not
    /// private, like that constant and for the same reason: `HUDLayoutTests` asserts the
    /// two gaps rather than carrying its own copy of these numbers.
    static let chainMeterDropBelowHUD: CGFloat = 70

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
        tally(enemy)
        activeEnemies[ObjectIdentifier(enemy)] = enemy
        // Also cache vortex enemies for gravitational pull optimization
        if enemy.enemyType == .vortex {
            activeVortexEnemies[ObjectIdentifier(enemy)] = enemy
        }
    }

    /// Counts an enemy towards the hunter medal, once, however many times it passes
    /// through registration — `rebuildEntityCaches()` re-registers every live enemy.
    private func tally(_ enemy: Enemy) {
        guard !enemy.isTallied else { return }
        enemy.isTallied = true
        enemiesSeen += 1
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
        requestedGameplayPause = paused
        gameContentNode?.isPaused = paused
        powerUpTimers.isPaused = paused
        physicsWorld.speed = paused ? 0 : timeScale
        if paused {
            recentreCamera()
        }
    }

    /// Drops any camera shake in flight and puts the camera back on the centre.
    ///
    /// Run on every pause. The camera frames the whole scene, HUD and menus included,
    /// but it lives on the gameplay clock, so a pause mid-shake froze it up to 20pt off
    /// centre: the pause menu, the perk picker and the HUD all sat shifted, with an
    /// undimmed strip along one edge. `removeAllActions` rather than the shake's key:
    /// the lightning gun's jolt is unkeyed and relative, so it would play out its
    /// remaining moves from the recentred spot after the resume and end off centre.
    private func recentreCamera() {
        guard let camera = camera else { return }
        camera.removeAllActions()
        camera.position = CGPoint(x: size.width / 2, y: size.height / 2)
        activeShakeIntensity = 0
    }

    private var isGameplayPaused: Bool {
        return gameContentNode?.isPaused ?? false
    }

    /// What `setGameplayPaused` last asked for, as opposed to what `gameContentNode`
    /// reports right now.
    ///
    /// SpriteKit pauses the whole scene as the app resigns active and unpauses it as the
    /// app comes back, descendants included, and it does so before this scene's own
    /// lifecycle observers run. Reading the node there, the auto-pause saw "already
    /// paused" and did nothing, and the return saw "running" and carried on: the game
    /// never stopped for a phone call or the home screen, and came back live with no
    /// pause menu. The lifecycle handlers go by this instead.
    private var requestedGameplayPause = false

    /// Re-applies a gameplay pause that SpriteKit has lifted behind the game's back.
    ///
    /// On the way back to the foreground `SKView` unpauses the scene, and with it every
    /// descendant, twice: once from its own didBecomeActive observer, ahead of
    /// `appDidBecomeActive()`, which undoes it; and again on its first frame after the
    /// return (`-[SKView _update:]`), after every observer has run. Nothing undid the
    /// second one. The pause menu stayed up over a level whose actions were running
    /// again with its physics still at zero, and every tap went to the ship rather than
    /// the menu, because touch routing goes by `gameContentNode.isPaused`. The game
    /// could not be resumed, restarted or left.
    ///
    /// That frame calls `update(_:)` straight after unpausing and before it evaluates
    /// any action, so re-pausing from there undoes the unpause before anything has
    /// moved. Only once the level is under way: the intro also asks for a pause, but its
    /// entry animation relies on SpriteKit running the node (see `appDidBecomeActive()`).
    /// It only ever re-pauses. A pause SpriteKit adds on its own is lifted by SpriteKit.
    private func holdRequestedGameplayPause() {
        guard requestedGameplayPause, isGameStarted, !gameContentNode.isPaused else { return }
        setGameplayPaused(true)
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
    //
    // Steering is relative: the ship moves by however far the finger moves, from
    // wherever the finger first landed. It used to be absolute — a touch teleported the
    // ship to a point 50 pt above the finger, so the first thing every touch did was
    // yank the ship across the screen, often straight into fire, and the thumb had to
    // sit exactly under the ship to fly it. Relative drag is what touch shmups converge
    // on, and it lets the thumb rest wherever is comfortable.
    private var isTouching = false
    private var touchLocation: CGPoint = .zero
    /// The touch that is flying the ship. A second finger is not steering; it is a
    /// trigger (see `touchesBegan`).
    private var steeringTouch: UITouch?
    private var lastSteerLocation: CGPoint = .zero
    /// For the one-handed Overdrive trigger, a quick double tap.
    private var lastTapBegan: TimeInterval = -10
    private var lastTapEnded: TimeInterval = -10
    private var currentTapBegan: TimeInterval = 0

    // Pause system
    var gameContentNode: SKNode! // Node that gets paused (public for managers)
    private var uiNode: SKNode! // UI node that never gets paused
    private var pauseButton: SKShapeNode!
    private var pauseOverlay: SKNode?
    /// The live pause menu's column — tag, title, rule and buttons — in scene
    /// coordinates. A tap outside it resumes. See `handlePauseMenuTap(at:)`.
    private var pauseMenuFrame: CGRect = .null
    /// Set the moment a pause-menu button is pressed; cleared when that menu goes away,
    /// or for SETTINGS once its modal panel has taken over.
    ///
    /// Every button runs its action from the press animation's completion, 0.17 s
    /// later. Without the latch a second tap inside that window ran a second action:
    /// RESUME twice resumed and then paused again, and RETRY, LEVELS or MENU presented
    /// two scenes. It also holds off the tap-outside resume for the same window.
    private var isPauseMenuActionPending = false
    private var isInitialized = false

    /// The 3D world behind the playfield. See `GameBackdrop`.
    private var backdrop: GameBackdrop?

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

        // The films' near-black: the world behind is drawn in light, and light needs
        // a dark to read against.
        backgroundColor = UIColor(red: 0.004, green: 0.006, blue: 0.02, alpha: 1.0)

        // Setup camera for shake effects.
        //
        // Parented to `gameContentNode`, not the scene, for the same reason as
        // `effectsParent` and `BossManager`'s "bossCameraShakes" timeline: the scene
        // keeps ticking while the game is paused, so a shake started by an explosion
        // went on rattling the pause menu. `gameContentNode` is the clock that actually
        // stops.
        //
        // Safe because `gameContentNode` sits at the origin with an identity transform
        // and is never moved or scaled, so the camera's position still reads in scene
        // coordinates — which is what both the centring here and the recentring in
        // `didChangeSize(_:)` assume.
        let cameraNode = SKCameraNode()
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        gameContentNode.addChild(cameraNode)
        camera = cameraNode

        // A second finger is the Overdrive trigger, so the view has to report it.
        view.isMultipleTouchEnabled = true

        let shardSystem = ShardSystem(parent: gameContentNode)
        shardSystem.onCollect = { [weak self] position in
            self?.collectShard(at: position)
        }
        shards = shardSystem

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

            // The world behind the fight: the sector of the opening film's route this
            // level flies through. Under `gameContentNode` like everything else on the
            // gameplay clock, and driven from `update(_:)`.
            let backdrop = GameBackdrop(size: self.size, level: self.currentLevel, endless: self.isEndless)
            backdrop.zPosition = -20
            self.gameContentNode.addChild(backdrop)
            self.backdrop = backdrop

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

        // The world's camera frames itself from the viewport, so a new size is all it
        // needs to keep the horizon where it was.
        backdrop?.resize(to: size)

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

        shards?.removeAll()
        shards = nil
        overdrive.cancel()
        overdrive.removeHUD()
        steeringTouch = nil

        // Clear player reference
        player = nil
        backdrop = nil

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
        // When app goes to background, automatically pause if game is running. Not via
        // `togglePause()`, which reads the node — and SpriteKit has already paused it.
        // See `requestedGameplayPause`.
        if !requestedGameplayPause && isGameStarted {
            setGameplayPaused(true)
            showPauseOverlay()
        }

        // A backgrounded app may never come back: the system can end it, or the player
        // can swipe it away from the paused menu. An endless run's result is otherwise
        // only written at game over, so bank it here too.
        recordEndlessRun()
    }

    @objc private func appDidBecomeActive() {
        // When app returns from background, re-assert the whole gameplay clock so
        // physics speed and the power-up timer layer can't drift out of step with
        // gameContentNode — which SpriteKit has just unpaused on its own, so the game's
        // own request decides. Only once the level is under way: the intro asks for a
        // pause too, but its entry animation needs the node running (see `startGame()`'s
        // caller), so re-pausing here would freeze it for good. SpriteKit unpauses the
        // node once more on its next frame; `holdRequestedGameplayPause()` undoes that.
        if requestedGameplayPause && isGameStarted {
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
            if isGameStarted && pauseOverlay == nil && perkPicker == nil {
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
        ParticleTexture.clearCache()
        ProjectileFX.clearCaches()
        ShardSystem.clearCache()
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
            endlessBestAtStart = LevelManager.shared.getEndlessRecords().bestScore
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
        if isEndless {
            powerUpManager = PowerUpManager(scene: self, config: endlessPowerUpConfig(forRound: max(1, endlessRound)))
            return
        }
        guard let config = levelConfig else {
            assertionFailure("Cannot setup PowerUpManager - levelConfig is nil")
            return
        }
        powerUpManager = PowerUpManager(scene: self, config: config.powerUpConfig)
    }

    /// The power-up table an endless round draws from: the one of the campaign level its
    /// hazards come from (`EndlessRules.hazardLevel(forRound:)`).
    ///
    /// Endless never sets `currentLevel`, so it used to take level 1's table for the
    /// whole run — lightning, homing missiles, the barrier, the freeze bomb, slow motion,
    /// score x2 and the nuke never dropped at all, however deep the run went.
    private func endlessPowerUpConfig(forRound round: Int) -> PowerUpSpawnConfig {
        let level = EndlessRules.hazardLevel(forRound: round)
        return LevelManager.shared.getLevelConfig(for: level).powerUpConfig
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
        scoreLabel.fontSize = 24
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
            at: CGPoint(x: size.width - 62, y: size.height - topMargin - Self.chainMeterDropBelowHUD)
        )

        // Overdrive gauge, bottom left: under the off-hand thumb of a right-handed
        // player, and clear of the heat gauge in the middle. It doubles as a button.
        overdrive.installHUD(
            on: uiNode,
            at: Self.overdriveGaugePosition(safeAreaBottom: GameConfiguration.safeAreaBottom(in: view)),
            caption: L10n.HUD.overdrive
        )
    }

    /// Centre of the Overdrive gauge. A function of the inset alone so the layout test
    /// can check it clears the home indicator without building a scene.
    static func overdriveGaugePosition(safeAreaBottom: CGFloat) -> CGPoint {
        return CGPoint(x: 42, y: max(safeAreaBottom, 10) + 36)
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

        // The ship as the HUD draws it: dark glass in the hull's ice-blue edge, the
        // same light as the wireframe flying below.
        let ship = SKShapeNode(path: path)
        ship.fillColor = UIColor(red: 0.02, green: 0.08, blue: 0.14, alpha: 0.9)
        ship.strokeColor = UIColor(red: 0.55, green: 0.93, blue: 1.0, alpha: 1.0)
        ship.lineWidth = 1.3

        let cockpit = LightSprite.star(size: 9 * scale, color: .white)
        cockpit.position = CGPoint(x: 0, y: 6 * scale)
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

        // Level 1 holds fractionally longer than the rest: long enough to read the words
        // "LEVEL 1", not long enough to be a wait.
        // `currentLevel` is left at its default of 1 in endless, so the mode has to be
        // excluded explicitly or an endless run would inherit level 1's longer hold.
        let hold: TimeInterval = (currentLevel == 1 && !isEndless) ? 1.15 : 0.75
        let appearAt: TimeInterval = 0.15
        let appearFor: TimeInterval = 0.35
        let leaveFor: TimeInterval = 0.25

        // A title card the way the opening film sets its own: the picture letterboxed,
        // the world still flying behind it, the sector typed out above a tracked gold
        // title that draws a hairline under itself. No full-screen scrim — the world
        // is the point — only a soft pool of shade behind the type.
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let barDepth = max(size.height * 0.11, 70)
        let bars = Cinematic.letterbox(size: size, depth: barDepth, hold: appearAt + appearFor + hold - 0.2)
        introNode.addChild(bars)

        let frameRect = CGRect(x: 0, y: barDepth, width: size.width, height: size.height - barDepth * 2)
        let corners = Cinematic.viewfinder(in: frameRect, color: StoryPalette.cyan)
        corners.alpha = 0
        corners.run(.sequence([.wait(forDuration: 0.3), .fadeAlpha(to: 0.4, duration: 0.3)]))
        introNode.addChild(corners)

        let shade = Cinematic.shade(size: CGSize(width: size.width * 1.4, height: 360), alpha: 0)
        shade.position = centre
        shade.run(.fadeAlpha(to: 0.7, duration: 0.3))
        introNode.addChild(shade)

        let sector = isEndless ? 1 : (currentLevel - 1) / 5 + 1
        let tag = Cinematic.typewriter("\(L10n.Sector.label(sector))  ·  \(L10n.Sector.name(sector))",
                                       fontSize: 12, color: StoryPalette.cyan, tracking: 2.5,
                                       delay: 0.15, duration: 0.55, maxWidth: size.width - 40)
        tag.position = CGPoint(x: centre.x, y: centre.y + 54)
        introNode.addChild(tag)

        // Level number label: the film's title treatment.
        let levelLabel = Cinematic.title(isEndless ? L10n.HUD.endless : L10n.HUD.level(currentLevel),
                                         fontSize: 46, color: UITheme.Colors.primaryGold, glow: StoryPalette.gold,
                                         tracking: 9, maxWidth: size.width - 48, minimumSize: 26)
        levelLabel.position = CGPoint(x: centre.x, y: centre.y + 14)
        levelLabel.alpha = 0
        levelLabel.setScale(1.12)
        introNode.addChild(levelLabel)

        let rule = Cinematic.rule(width: min(size.width - 80, 240), color: UITheme.Colors.primaryGold,
                                  delay: appearAt + 0.2)
        rule.position = CGPoint(x: centre.x, y: centre.y - 16)
        introNode.addChild(rule)

        // The score to beat, whenever there is one. A target on the card gives a replay a
        // point beyond "clear it again", and it is the cheapest hook available: the
        // number is already stored per level to draw the level-select grid. Endless reads
        // its own record instead, which is the only goal that mode has.
        let target: Int? = isEndless
            ? { let best = LevelManager.shared.getEndlessRecords().bestScore; return best > 0 ? best : nil }()
            : LevelManager.shared.getLevelScore(level: currentLevel)

        if let best = target, best > 0 {
            let bestLabel = SKLabelNode(fontNamed: UITheme.Typography.fontNumeric)
            bestLabel.text = L10n.Common.best(best)
            bestLabel.fontSize = 15
            bestLabel.fontColor = UITheme.Colors.primaryGoldLight
            bestLabel.position = CGPoint(x: centre.x, y: centre.y - 44)
            bestLabel.alpha = 0
            introNode.addChild(bestLabel)
            bestLabel.run(.sequence([
                .wait(forDuration: appearAt + 0.3),
                .fadeIn(withDuration: 0.25)
            ]))
        }

        // The level's medals, as goals: the three things this level can still be asked
        // for, lit where an earlier run already earned them.
        if !isEndless {
            let held = LevelManager.shared.getLevelMedals(level: currentLevel)
            let row = SKNode()
            row.position = CGPoint(x: centre.x, y: centre.y - (target != nil ? 92 : 62))
            row.alpha = 0
            introNode.addChild(row)

            for (index, medal) in MedalSet.ordered.enumerated() {
                let x = CGFloat(index - 1) * 96
                let badge = MedalBadge.badge(for: medal, earned: held.contains(medal), radius: 13,
                                             level: currentLevel, glow: false)
                badge.position = CGPoint(x: x, y: 0)
                row.addChild(badge)

                let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
                label.text = MedalBadge.label(for: medal, level: currentLevel)
                label.fontSize = 10
                label.fontColor = held.contains(medal) ? MedalBadge.color(for: medal) : UIColor(white: 0.8, alpha: 1)
                label.verticalAlignmentMode = .center
                label.position = CGPoint(x: x, y: -24)
                UITheme.fitLabel(label, toWidth: 90, minimumFontSize: 8)
                row.addChild(label)
            }
            row.run(.sequence([.wait(forDuration: appearAt + 0.4), .fadeIn(withDuration: 0.25)]))
        }

        addChild(introNode)

        let appear = SKAction.group([
            SKAction.fadeIn(withDuration: appearFor),
            SKAction.scale(to: 1.0, duration: appearFor)
        ])
        appear.timingMode = .easeOut
        let disappear = SKAction.group([
            SKAction.fadeOut(withDuration: leaveFor),
            SKAction.scale(to: 1.08, duration: leaveFor)
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
        //
        // The bars are still opening when it ends, so the teardown waits them out —
        // still on this one timeline, after `startEntry` has already fired.
        let teardown = SKAction.run { [weak introNode] in
            introNode?.removeFromParent()
        }

        levelLabel.run(.sequence([
            .wait(forDuration: appearAt),
            appear,
            .wait(forDuration: hold),
            disappear,
            startEntry,
            .wait(forDuration: 0.4),
            teardown
        ]))

        // The type lifts alongside the title rather than after it, so the playfield is
        // already clear while the ship flies in. Everything but the bars fades; the
        // bars open on their own timeline above.
        for child in introNode.children where child !== levelLabel && child !== bars {
            child.run(.sequence([
                .wait(forDuration: appearAt + appearFor + hold),
                .fadeOut(withDuration: leaveFor)
            ]))
        }
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
        hasEndlessRunStarted = isEndless
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
        // A small lit frame in the same instrument language as the Overdrive gauge
        // across the screen: dark glass, a hairline, light on the corners and in the
        // glyph. It used to be a rounded, glowing tile — the one chunky shape left in a
        // HUD drawn otherwise in lines of light.
        let buttonSize: CGFloat = 44
        let accent = StoryPalette.cyan
        let pauseButton = SKShapeNode(rectOf: CGSize(width: buttonSize, height: buttonSize))
        pauseButton.fillColor = FilmUI.glass.withAlphaComponent(0.55)
        pauseButton.strokeColor = accent.withAlphaComponent(0.22)
        pauseButton.lineWidth = 1
        pauseButton.name = "pauseButton"

        // Position at the same height as hearts and score
        let rightMargin: CGFloat = 28
        pauseButton.position = CGPoint(x: size.width - rightMargin - 10, y: size.height - topMargin)
        pauseButton.zPosition = 100
        uiNode.addChild(pauseButton)

        FilmUI.addBrackets(to: pauseButton, size: CGSize(width: buttonSize, height: buttonSize),
                           arm: 8, color: accent, width: 1.3)
        for x in [-4.5, 4.5] as [CGFloat] {
            pauseButton.addChild(FilmUI.tube(CGPoint(x: x, y: -8), CGPoint(x: x, y: 8),
                                             width: 2.4, color: StoryPalette.ice))
        }

        self.pauseButton = pauseButton
    }

    private static let pauseOverlayName = "pauseOverlay"
    /// What a dismissed overlay is renamed to while it fades out. Not nil: the sweep in
    /// `showPauseOverlay()` has to be able to find it.
    private static let fadingPauseOverlayName = "pauseOverlayFading"

    /// The pause menu's buttons, in the order a tap is tested against them.
    private static let pauseMenuButtonNames = [
        "resumeButton", "pauseRetryButton", "pauseSettingsButton", "pauseLevelsButton", "pauseMenuButton"
    ]

    private func showPauseOverlay() {
        guard pauseOverlay == nil else { return }

        // Sweep away an overlay that is still playing its dismissal fade.
        // `hidePauseOverlay()` clears `pauseOverlay` up front so the game can be
        // re-paused immediately, but leaves the node in the tree for 0.4s to fade.
        // Tapping RESUME and then the pause button straight away therefore stacked a
        // fresh menu over a fading one — two dim layers. The outgoing overlay is found by
        // the name `hidePauseOverlay()` gives it; this used to look for the live name,
        // which the dismissal had already cleared, so the sweep never found anything.
        while let fading = uiNode?.childNode(withName: Self.fadingPauseOverlayName) {
            fading.removeFromParent()
        }
        isPauseMenuActionPending = false

        let overlay = SKNode()
        overlay.name = Self.pauseOverlayName
        overlay.zPosition = 10000

        // The picture dims behind the frame. Nothing here is hit-tested by node: a tap
        // anywhere off the menu column resumes — on the dimmed picture, on the letterbox
        // bars, on the corners — see `handlePauseMenuTap(at:)`.
        let background = SKSpriteNode(color: .black, size: size)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        background.alpha = 0
        background.name = "pauseOverlayBackground"
        overlay.addChild(background)
        background.run(SKAction.fadeAlpha(to: 0.55, duration: 0.25))

        // A freeze-frame: the letterbox closes over the stopped picture, the way the
        // films frame a held shot, with the run's score printed above it.
        let depths = FilmUI.Letterbox.depthsOverGameplay(size: size, view: view)
        let frame = FilmUI.Letterbox(size: size, top: depths.top, bottom: depths.bottom)
        frame.zPosition = 1
        overlay.addChild(frame)
        frame.addFurniture(left: "\(L10n.Common.score)  \(score.formatted())", right: nil, recording: true)

        let column = SKNode()
        column.position = CGPoint(x: size.width / 2, y: frame.picture.midY)
        column.setScale(FilmUI.uiScale(for: size))
        column.zPosition = 2
        overlay.addChild(column)

        let shade = Cinematic.shade(size: CGSize(width: size.width * 1.5, height: 560), alpha: 0.75)
        shade.zPosition = -1
        column.addChild(shade)

        let width = min(UITheme.Dimensions.buttonWidthXLarge, size.width / column.xScale - 64)
        let pairWidth = (width - UITheme.Dimensions.buttonPairGap) / 2
        let primaryHeight = UITheme.Dimensions.buttonHeight
        let secondaryHeight = UITheme.Dimensions.buttonHeightSecondary

        // Where the run is, typed out above the title the way the level card tags it.
        let sector = (currentLevel - 1) / 5 + 1
        let where_ = isEndless
            ? "\(L10n.HUD.endless)  ·  \(L10n.HUD.round(max(1, endlessRound)))"
            : "\(L10n.HUD.level(currentLevel))  ·  \(L10n.Sector.name(sector))"
        let tag = Cinematic.typewriter(where_, fontSize: 12, color: StoryPalette.cyan, tracking: 2.5,
                                       delay: 0.1, duration: 0.5, maxWidth: size.width - 48)

        let title = FilmUI.title(L10n.Pause.title, size: 46, color: UITheme.Colors.primaryCyanLight,
                                 glow: StoryPalette.cyan, tracking: 14, maxWidth: size.width - 48,
                                 bloom: 1.0)
        let rule = FilmUI.drawnRule(width: min(width, 220), color: StoryPalette.cyan, alpha: 0.6, delay: 0.15)

        let resumeButton = UITheme.createButton(text: L10n.Pause.resume, color: StoryPalette.cyan,
                                                width: width, name: "resumeButton", primary: true)
        let retryButton = UITheme.createButton(text: L10n.Common.retry, color: StoryPalette.gold,
                                               width: width, name: "pauseRetryButton")
        // Settings, reachable mid-level: muting only from the main menu would mean
        // abandoning a run to turn the music down.
        let settingsButton = UITheme.createButton(text: L10n.Pause.settings, color: FilmUI.neutral,
                                                  width: width, name: "pauseSettingsButton")
        let levelsButton = UITheme.createButton(text: L10n.Common.levels, color: FilmUI.neutral,
                                                width: pairWidth, name: "pauseLevelsButton")
        let menuButton = UITheme.createButton(text: L10n.Common.menu, color: FilmUI.neutral,
                                              width: pairWidth, name: "pauseMenuButton")

        // Top to bottom: the gap above each row, and its height.
        let rows: [(node: SKNode, gap: CGFloat, height: CGFloat)] = [
            (tag, 0, 14),
            (title, 14, title.frame.height),
            (rule, 14, 1),
            (resumeButton, 34, primaryHeight),
            (retryButton, 12, secondaryHeight),
            (settingsButton, 12, secondaryHeight),
            (levelsButton, 12, secondaryHeight)
        ]
        let total = rows.reduce(0) { $0 + $1.gap + $1.height }
        var cursor = total / 2
        for row in rows {
            cursor -= row.gap + row.height / 2
            row.node.position.y = cursor
            cursor -= row.height / 2
        }
        levelsButton.position.x = -(pairWidth + UITheme.Dimensions.buttonPairGap) / 2
        menuButton.position = CGPoint(x: (pairWidth + UITheme.Dimensions.buttonPairGap) / 2,
                                      y: levelsButton.position.y)

        for node in [tag, title, rule, resumeButton, retryButton, settingsButton, levelsButton, menuButton] {
            column.addChild(node)
        }

        // The menu's own footprint, measured before anything is animated: the column's
        // full width by the stack's height, with a margin so a tap that only just misses
        // a button does not throw the player back into the fight. The shade hung off the
        // column is deliberately not part of it — it reaches far past the menu, and the
        // picture it darkens is what "tap outside to resume" is about.
        let menuWidth = max(width, tag.frame.width, title.frame.width)
        let menuRect = CGRect(x: -menuWidth / 2, y: -total / 2, width: menuWidth, height: total)
            .insetBy(dx: -16, dy: -16)
        let scale = column.xScale
        pauseMenuFrame = CGRect(x: column.position.x + menuRect.minX * scale,
                                y: column.position.y + menuRect.minY * scale,
                                width: menuRect.width * scale, height: menuRect.height * scale)

        // The title settles in; the buttons follow it down.
        title.alpha = 0
        title.setScale(1.08)
        let settle = SKAction.scale(to: 1, duration: 0.5)
        settle.timingMode = .easeOut
        title.run(.group([.fadeIn(withDuration: 0.25), settle]))
        for (index, button) in [resumeButton, retryButton, settingsButton, levelsButton, menuButton].enumerated() {
            button.alpha = 0
            button.run(.sequence([.wait(forDuration: 0.12 + Double(min(index, 3)) * 0.05),
                                  .fadeIn(withDuration: 0.2)]))
        }

        pauseOverlay = overlay
        uiNode.addChild(overlay)
    }

    private func hidePauseOverlay() {
        guard let overlay = pauseOverlay else { return }
        pauseOverlay = nil
        pauseMenuFrame = .null
        isPauseMenuActionPending = false

        // Strip the names off the outgoing overlay before it fades: buttons that are
        // still in the tree but no longer the live overlay must stop answering to those
        // names. The overlay itself is renamed rather than cleared, so a quick re-pause
        // can find it and sweep it away (see `showPauseOverlay()`).
        overlay.name = Self.fadingPauseOverlayName
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

    /// The live pause menu's button under `location`, or nil.
    ///
    /// Measured against each button's own outline rather than asked of `nodes(at:)`:
    /// the overlay is layered — letterbox, viewfinder corners, the column's shade — and
    /// what `nodes(at:)` puts first depends on that draw order, not on what the player
    /// meant to press. A button still fading in is not yet a button.
    private func pauseMenuButton(at location: CGPoint) -> SKShapeNode? {
        guard let overlay = pauseOverlay else { return nil }
        for name in Self.pauseMenuButtonNames {
            guard let button: SKShapeNode = Self.descendant(of: overlay, named: name),
                  button.alpha > 0.05,
                  let bounds = button.path?.boundingBoxOfPath else { continue }
            if bounds.insetBy(dx: -4, dy: -4).contains(convert(location, to: button)) {
                return button
            }
        }
        return nil
    }

    /// First descendant of `node` — depth-first, `node` itself excluded — named `name`
    /// and of type `T`.
    ///
    /// Hand-rolled for the same reason `clearNames(underDescendantsOf:)` is: neither
    /// spelling of `childNode(withName:)` scopes a search to a subtree. A bare name
    /// matches *only immediate children*, and the pause buttons are grandchildren of the
    /// overlay (overlay → column → button), so `overlay.childNode(withName: "resumeButton")`
    /// returns nil. Prefixing `//` finds them, but by searching from the root of the whole
    /// tree — it only happened to be right because these names are unique to the live
    /// overlay and `hidePauseOverlay()` strips them off dismissed ones. That is a lot of
    /// weight for an accident to carry, so search the subtree properly instead.
    ///
    /// The type filter keeps the lookup to the button itself: the callers all want the
    /// shape they can run the press animation on.
    private static func descendant<T: SKNode>(of node: SKNode, named name: String) -> T? {
        for child in node.children {
            if child.name == name, let match = child as? T { return match }
            if let match: T = descendant(of: child, named: name) { return match }
        }
        return nil
    }

    /// Every tap while the pause menu is up: a button runs its action, anywhere off the
    /// menu column resumes, and a tap on the column between buttons does nothing.
    ///
    /// The HUD's pause button is not special here. While paused it sits under the top
    /// letterbox bar, and a tap on the bar is a tap outside the menu like any other.
    private func handlePauseMenuTap(at location: CGPoint) {
        // One action per menu: the press animation runs it 0.17 s after the tap, and a
        // second tap in that window must not queue another. See
        // `isPauseMenuActionPending`.
        guard !isPauseMenuActionPending else { return }

        if let button = pauseMenuButton(at: location), let name = button.name {
            isPauseMenuActionPending = true
            HapticManager.shared.lightTap()
            if name == "resumeButton" {
                SoundManager.shared.playResumeSound(on: self)
            } else {
                SoundManager.shared.playButtonClickSound(on: self)
            }
            button.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.runPauseMenuAction(named: name)
            })
            return
        }

        guard !pauseMenuFrame.contains(location) else { return }
        HapticManager.shared.lightTap()
        SoundManager.shared.playResumeSound(on: self)
        resumeFromPauseMenu()
    }

    private func runPauseMenuAction(named name: String) {
        switch name {
        case "resumeButton":
            resumeFromPauseMenu()
        case "pauseRetryButton":
            restartGame()
        case "pauseLevelsButton":
            goToLevelSelect()
        case "pauseMenuButton":
            goToMenu()
        case "pauseSettingsButton":
            showSettingsOverlay()
            // The panel is modal and takes every tap while it is up, so the menu can
            // answer again as soon as it is there — which is when the panel closes.
            isPauseMenuActionPending = false
        default:
            isPauseMenuActionPending = false
        }
    }

    /// Resumes from the pause menu, and only from it: a stale press or tap that lands
    /// after the game is already running must not pause it again, which is what a bare
    /// `togglePause()` would do.
    private func resumeFromPauseMenu() {
        guard isGameplayPaused, pauseOverlay != nil else { return }
        togglePause()
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
        recordEndlessRun()
        let menuScene = MenuScene(size: view.bounds.size)
        menuScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(menuScene, transition: transition)
    }

    private func restartGame() {
        guard let view = view else { return }
        // An endless run abandoned for a fresh one still counts towards the records.
        recordEndlessRun()
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

        // The settings panel is modal, so it takes every tap while it is up — before
        // the pause-menu handlers below, and before any gameplay touch.
        if let settings = uiNode?.childNode(withName: SettingsOverlay.nodeName) as? SettingsOverlay {
            settings.handleTap(at: location)
            return
        }

        // So is the endless perk picker — including over the pause button, which would
        // otherwise resume the frozen run out from under it.
        if let picker = perkPicker {
            picker.handleTap(at: location)
            return
        }

        // Paused: the pause menu, if it is up, takes the tap — the HUD's pause button
        // included, which is covered by the menu's letterbox. With no menu up (the level
        // intro) nothing in the game answers.
        if gameContentNode.isPaused {
            if pauseOverlay != nil {
                handlePauseMenuTap(at: location)
            }
            return
        }

        if !isGameStarted { return }

        if nodes(at: location).contains(where: { $0.name == "pauseButton" || $0.parent?.name == "pauseButton" }) {
            HapticManager.shared.lightTap()
            SoundManager.shared.playPauseSound(on: self)
            togglePause()
            return
        }

        for touch in touches {
            let location = touch.location(in: self)

            // The Overdrive gauge is a button while the meter is full. A touch that
            // lands on it then fires the overdrive and does not steer; on an empty
            // meter it is just more screen, so a thumb resting there still flies.
            if overdrive.isReady, nodes(at: location).contains(where: OverdriveSystem.isButton) {
                activateOverdrive()
                continue
            }

            guard steeringTouch == nil else {
                // A second finger while the first flies: the two-handed trigger.
                if overdrive.isReady { activateOverdrive() }
                continue
            }

            // One-handed trigger: a quick double tap. Both taps must be short, so a
            // player who lifts and re-plants a thumb mid-fight does not fire it by
            // accident — that is a long hold followed by a touch, not two taps.
            let now = CACurrentMediaTime()
            let isDoubleTap = now - lastTapEnded < 0.28 && lastTapEnded - lastTapBegan < 0.22
            currentTapBegan = now
            if isDoubleTap && overdrive.isReady {
                activateOverdrive()
            }

            steeringTouch = touch
            lastSteerLocation = location
            isTouching = true
            touchLocation = location
            spawnTouchRipple(at: location)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't handle game touches when paused or game hasn't started
        if gameContentNode.isPaused || !isGameStarted { return }

        // Only the steering finger flies the ship. Testing membership rather than
        // taking `touches.first` matters once a second finger is down: a moved event
        // for that finger alone must not be read as a drag.
        guard let steering = steeringTouch, touches.contains(steering) else { return }
        let location = steering.location(in: self)

        let sensitivity = GameConfiguration.dragSensitivity
        let delta = CGVector(
            dx: (location.x - lastSteerLocation.x) * sensitivity,
            dy: (location.y - lastSteerLocation.y) * sensitivity
        )
        lastSteerLocation = location
        isTouching = true
        touchLocation = location

        player.steer(by: delta, sceneWidth: size.width, sceneHeight: size.height, safeAreaBottom: safeAreaBottom)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseSteering(ifAmong: touches)
    }

    /// Ends the steering touch if it is among `touches`.
    ///
    /// Deliberately not gated on the pause the way the other handlers are: a finger
    /// lifted while the pause menu is up still lifted, and leaving the steering touch
    /// recorded would resume the game with the guns firing and nobody touching.
    private func releaseSteering(ifAmong touches: Set<UITouch>) {
        guard let steering = steeringTouch, touches.contains(steering) else { return }
        steeringTouch = nil
        isTouching = false
        lastTapBegan = currentTapBegan
        lastTapEnded = CACurrentMediaTime()
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
        releaseSteering(ifAmong: touches)
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
            // Lightning keeps the cadence it was balanced at. It strikes the whole
            // screen and fifteen boss hits per trigger-pull, so tying it to the new
            // bolt cadence would have more than doubled what it does.
            if gameTime - lastLightningTime >= 0.3 {
                lastLightningTime = gameTime
                shootLightning()
            }
            return
        }

        // Add heat from shooting. The shot that tips the gauge over still fires — see
        // `WeaponHeatSystem.registerShot(currentTime:)`. An overdrive does not heat the
        // guns: it is a few seconds of everything, and rationing it would undo the point.
        let isOverdrive = overdrive.isActive
        if !isOverdrive {
            // Rapid fire's faster stream runs at a fraction of the heat per volley, or the
            // power-up would cook the guns long before it ran out.
            let rapidScale = player.hasRapidFire ? GameConfiguration.rapidFireHeatScale : 1
            weaponHeat.registerShot(currentTime: gameTime,
                                    scale: CGFloat(PerkRules.heatScale(stacks: stacks(.coolant))) * rapidScale)
        }

        let rounds = player.shoot(overdrive: isOverdrive)

        // Play shoot sound
        SoundManager.shared.playShootSound(on: self)

        // Muzzle flash and a short recoil dip: firing should be felt, not just
        // observed. Both are extremely short so rapid fire doesn't turn strobey.
        let muzzle = NeonFX.flashPoint(
            at: CGPoint(x: player.position.x, y: player.position.y + 22),
            radius: isOverdrive ? 13 : 11,
            color: isOverdrive ? ProjectileFX.overdriveBolt : UIColor(red: 0.7, green: 1.0, blue: 0.95, alpha: 1.0),
            duration: 0.07,
            growTo: 1.5
        )
        muzzle.zPosition = 12
        gameContentNode.addChild(muzzle)

        player.applyRecoil()

        // Rounds fly at a fixed speed along their own heading. 1150 pt/s, up from about
        // 580: a fast round reads as a shot, a slow one as a thing drifting upwards.
        let speed = GameConfiguration.playerBulletSpeed
        for round in rounds {
            gameContentNode.addChild(round)

            // `zRotation` is the heading, clockwise-negative like everything else in
            // SpriteKit; a straight round has none.
            let heading = round.zRotation
            let travel: CGFloat
            let dx: CGFloat
            let dy: CGFloat
            if heading == 0 {
                travel = size.height + 40 - round.position.y
                dx = 0
                dy = travel
            } else {
                travel = 1600
                dx = -sin(heading) * travel
                dy = cos(heading) * travel
            }
            round.run(.sequence([
                .moveBy(x: dx, y: dy, duration: TimeInterval(max(travel, 1) / speed)),
                .removeFromParent()
            ]))
        }

        // Wing launchers fire on every third volley. They used to fire on every one,
        // which at the current cadence would be fifteen missiles a second; a missile is
        // worth three bolts instead.
        volleyCount += 1
        if player.sideMissileCount > 0 && volleyCount % 3 == 0 {
            SoundManager.shared.playMissileSound(on: self)
            for i in 0..<player.sideMissileCount {
                let side = i == 0 ? -1 : 1
                let missile = player.shootMissile(side: side)
                gameContentNode.addChild(missile)

                let travel = size.height + 40 - missile.position.y
                let move = SKAction.moveBy(x: 0, y: travel, duration: TimeInterval(travel / 900))
                move.timingMode = .easeIn
                missile.run(SKAction.sequence([move, .removeFromParent()]))
            }
        }
    }

    /// Volleys fired this level, for the wing launchers' cadence.
    private var volleyCount = 0

    /// Read-only, for `jetshotTests`: rounds leave the screen in well under a second
    /// now, so counting them in flight no longer measures the fire rate.
    var volleysFired: Int { volleyCount }

    /// The gameplay clock, read-only for `jetshotTests`: a fire rate is volleys over
    /// *this*, not over wall-clock time, which a hit-stop or a clamped frame skews.
    var gameplayClock: TimeInterval { gameTime }

    /// When lightning last struck, on the gameplay clock.
    private var lastLightningTime: TimeInterval = -1

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

        // Destroy every enemy on screen. Collected first: removing nodes from inside
        // the enumeration that is walking them is asking for trouble.
        var struck: [Enemy] = []
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy { struck.append(enemy) }
        }
        for enemy in struck {
            enemy.health = 0
            createExplosion(at: enemy.position, size: .small)
            rewardKill(of: enemy, at: enemy.position, label: false)
            enemy.markAsDestroyed()
            enemy.removeFromParent()
        }

        // Damage boss if present
        if bossManager.isBossActive() {
            // Fifteen authored hits' worth, scaled like the boss's health so lightning
            // keeps the share of a fight it was balanced to take.
            let result = bossManager.bossTakeDamage(amount: CombatRules.bossHealth(authored: 15))
            if result.defeated {
                // Boss defeated
                let awarded = self.addScore(result.points)

                // Same audio cue as a bullet kill — this path was silent.
                SoundManager.shared.playBossDefeatSound(on: self)
                if let position = bossManager.getBossPosition() {
                    // And the same bounty readout, which this path never showed.
                    showFloatingText("+\(awarded)", at: position,
                                     color: UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0), fontSize: 32)
                    celebrateBossDefeat(at: position)
                }

                // Wait for the boss defeat animation, on the gameplay clock so a
                // pause actually holds it.
                let wait = SKAction.wait(forDuration: 2.2)
                let afterDefeat = SKAction.run { [weak self] in
                    self?.handleBossDefeatAftermath()
                }
                runOnGameplayClock(SKAction.sequence([wait, afterDefeat]), withKey: "bossDefeatTransition")
            } else if result.phaseChanged, let position = bossManager.getBossPosition() {
                breakBossPhase(at: position)
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

        // A ship that is going down is out of the fight. Its bodies are pulled in
        // `playerDestroyed()`, but contacts already queued for this physics step still
        // arrive. `player` is the lowest category and `collector` the highest, so the
        // ship is always first or second respectively.
        if isShipDestroyed && (firstBody.categoryBitMask == PhysicsCategory.player
                               || secondBody.categoryBitMask == PhysicsCategory.collector) {
            return
        }

        // Bullet hit enemy
        if firstBody.categoryBitMask == PhysicsCategory.bullet &&
           secondBody.categoryBitMask == PhysicsCategory.enemy {
            // Check if it's a boss or regular enemy
            if let boss = secondBody.node as? Boss {
                bulletDidCollideWithBoss(bullet: firstBody.node, boss: boss)
            } else if let part = secondBody.node as? BossPart {
                bulletDidCollideWithBoss(bullet: firstBody.node, boss: part.boss, part: part)
            } else {
                bulletDidCollideWithEnemy(bullet: firstBody.node,
                                         enemy: secondBody.node as? Enemy)
            }
        }

        // Player hit enemy
        if firstBody.categoryBitMask == PhysicsCategory.player &&
           secondBody.categoryBitMask == PhysicsCategory.enemy {
            if secondBody.node is Boss || secondBody.node is BossPart {
                playerDidCollideWithBoss()
            } else {
                playerDidCollideWithEnemy(enemy: secondBody.node as? Enemy)
            }
        }

        // Player hit enemy bullet
        if firstBody.categoryBitMask == PhysicsCategory.player &&
           secondBody.categoryBitMask == PhysicsCategory.enemyBullet {
            playerDidCollideWithEnemyBullet(bullet: secondBody.node, at: contact.contactPoint)
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

            bulletDidCollideWithObstacle(bullet: firstBody.node,
                                        obstacle: obstacle,
                                        hitNode: hitNode)
        }

        // Pickups meet the ship's collector, not its core (see `PhysicsCategory.collector`).
        // `collector` outranks both, so the pickup is always `firstBody`.
        if firstBody.categoryBitMask == PhysicsCategory.powerUp &&
           secondBody.categoryBitMask == PhysicsCategory.collector {
            playerDidCollideWithPowerUp(powerUp: firstBody.node as? PowerUp)
        }

        if firstBody.categoryBitMask == PhysicsCategory.coin &&
           secondBody.categoryBitMask == PhysicsCategory.collector {
            playerDidCollideWithCoin(coin: firstBody.node as? Coin)
        }

        // Bullet hit asteroid
        if firstBody.categoryBitMask == PhysicsCategory.bullet &&
           secondBody.categoryBitMask == PhysicsCategory.asteroid {
            bulletDidCollideWithAsteroid(bullet: firstBody.node,
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
            barrierDidCollideWithEnemyBullet(bullet: firstBody.node, at: contact.contactPoint)
        }
    }

    private func bulletDidCollideWithEnemy(bullet: SKNode?, enemy: Enemy?) {
        guard let bullet = bullet, let enemy = enemy else { return }

        // SpriteKit delivers every contact of a physics step, including ones whose round
        // or enemy an earlier contact in the same step already used up. Without this, two
        // bolts landing together on a one-hit enemy paid the kill twice — and split a
        // splitter twice. A round that reached a hull already dead is spent on it all the
        // same: flying on, it would cut down the splitter's fragments as they appear.
        guard bullet.parent != nil else { return }
        guard enemy.parent != nil, enemy.health > 0 else {
            bullet.removeFromParent()
            return
        }

        // GHOST: phased out, it is not there to be hit. The round flies on through.
        if enemy.isGhostPhased { return }

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

        // MIRROR: Reflects bullets back at player.
        //
        // One in four, and at most one every 0.3 s per mirror. The old one-in-two was
        // tuned for a gun that fired three rounds a second; against today's stream it
        // would return a hose of fire at the ship, which is a punishment for shooting
        // rather than a reason to aim around the mirror.
        if enemy.enemyType == .mirror, enemy.canReflect(at: gameTime), Double.random(in: 0...1) < 0.25 {
            enemy.noteReflection(at: gameTime)
            reflectBullet(bullet, from: enemy)
            return
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

        let impactPoint = bullet.position
        let damage = Self.damage(of: bullet)
        bullet.removeFromParent()

        // Decrease enemy health
        enemy.health -= damage

        // Check if enemy is destroyed
        if enemy.health <= 0 {
            // Special handling for mine - explode with shrapnel when shot
            if enemy.enemyType == .mine {
                rewardKill(of: enemy, at: enemy.position)

                // Mine explodes prematurely when shot (armed or not)
                detonateMine(enemy)
                return
            } else if enemy.enemyType == .splitter {
                // SPLITTER: Splits into 2 smaller enemies when destroyed
                createExplosion(at: enemy.position, tint: enemy.enemyType.strokeColor)
                shatter(enemy)
                HapticManager.shared.mediumTap()
                rewardKill(of: enemy, at: enemy.position)

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
                createExplosion(at: enemy.position,
                                size: enemy.enemyType.maxHealth >= CombatRules.heavyKillHealth ? .large : .normal,
                                tint: enemy.enemyType.strokeColor)
                shatter(enemy)
                HapticManager.shared.mediumTap()
                rewardKill(of: enemy, at: enemy.position)

                // Mark enemy as destroyed to prevent completion callback
                enemy.markAsDestroyed()
                enemy.removeFromParent()
            }
        } else {
            // Took the round and lived: flash white, spark where it landed.
            effectsParent.addChild(ProjectileFX.impact(at: impactPoint, color: enemy.enemyType.strokeColor))
            enemy.flashDamage()
            hitHaptic()
        }
    }

    /// Hit points a player round takes off its target.
    private static func damage(of round: SKNode) -> Int {
        if let round = round as? PlayerRound { return round.damage }
        return CombatRules.boltDamage
    }

    /// Sets a mine off, however it was triggered — the full blast if it was armed — with
    /// the shake to match. `explodeMine` retires the mine itself.
    private func detonateMine(_ mine: Enemy) {
        mine.explodeMine(isFullExplosion: mine.isMineArmed, completion: {})
        if mine.isMineArmed {
            shakeCamera(intensity: 12.0, duration: 0.35)
            HapticManager.shared.heavyTap()
        } else {
            shakeCamera(intensity: 6.0, duration: 0.25)
            HapticManager.shared.mediumTap()
        }
    }

    /// A light buzz for a non-lethal hit, at most every 70 ms. A dense stream lands far
    /// more hits than a haptic engine can separate, and an unthrottled one just hums.
    private func hitHaptic() {
        guard realPlayTime - lastHitHaptic > 0.07 else { return }
        lastHitHaptic = realPlayTime
        HapticManager.shared.lightTap()
    }

    /// Everything a kill pays, whichever weapon made it: score and its floating label,
    /// the shard burst, and — for the heavy enemies — a hit-stop and a local bullet
    /// cancel.
    ///
    /// Every kill path used to assemble its own subset of this (the bullet path printed a
    /// label, lightning and the nuke did not, the barrier used its own colour), which is
    /// how they drift apart. Removal stays with the caller, because the mine and the
    /// splitter each retire their enemy in their own way.
    private func rewardKill(of enemy: Enemy, at position: CGPoint, label: Bool = true) {
        tally(enemy)
        enemiesDestroyed += 1
        let awarded = addScore(enemy.enemyType.points)
        if label {
            showFloatingText("+\(awarded)", at: position, color: UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0),
                             fontSize: enemy.enemyType.maxHealth >= CombatRules.heavyKillHealth ? 22 : 17)
        }

        let count = CombatRules.shardCount(forPoints: enemy.enemyType.points)
        shards?.spawn(at: position, count: count)

        // Judged on the type's base toughness, not the level-scaled figure, so which
        // kills count as heavy does not drift as the game goes on.
        if enemy.enemyType.maxHealth >= CombatRules.heavyKillHealth {
            hitStop(HitStop.heavyKill)
            cancelHostileFire(around: position, radius: CombatRules.heavyKillCancelRadius)
        }
    }

    private func bulletDidCollideWithBoss(bullet: SKNode?, boss: Boss?, part: BossPart? = nil) {
        guard let bullet = bullet, let boss = boss else { return }

        // A round can touch a part and the core in the same physics step, and both
        // contacts are delivered. Only the first may land.
        guard bullet.parent != nil else { return }

        // Check if boss is still alive before processing damage
        guard bossManager.isBossActive() else {
            bullet.removeFromParent()
            return
        }

        let impactPoint = bullet.position
        let damage = Self.damage(of: bullet)
        bullet.removeFromParent()

        // Boss takes damage
        let result = bossManager.bossTakeDamage(amount: damage, part: part)
        if result.partBonus > 0, let part = part {
            // Shooting a gun off the boss pays, and says so where it happened.
            let point = part.convert(CGPoint.zero, to: gameContentNode)
            let awarded = addScore(result.partBonus)
            showFloatingText("+\(awarded)", at: point, color: boss.telegraphColor, fontSize: 22)
            shards?.spawn(at: point, count: CombatRules.bossPhaseShards / 2, speed: 100...240)
            shakeCamera(intensity: 7, duration: 0.25)
        }

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
            celebrateBossDefeat(at: boss.position)

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
            effectsParent.addChild(ProjectileFX.impact(at: impactPoint, color: boss.telegraphColor,
                                                       scale: part == nil ? 1.2 : 1.0))
            SoundManager.shared.playBossHitSound(on: self)
            hitHaptic()

            if result.phaseChanged {
                breakBossPhase(at: boss.position)
            }
        }
    }

    /// A boss crossing into its next act: the fight stops for a beat, every round in the
    /// air dissolves into shards, and the armour sheds a shower of them.
    ///
    /// The cancel is the reward for getting there, and it is what makes the transition
    /// legible — the screen clears, then the harder pattern starts on a clean slate.
    private func breakBossPhase(at position: CGPoint) {
        hitStop(HitStop.bossPhase)
        cancelHostileFire(around: nil)
        shards?.spawn(at: position, count: CombatRules.bossPhaseShards, speed: 140...320)
        shakeCamera(intensity: 12, duration: 0.4)
        HapticManager.shared.heavyTap()
    }

    /// The boss going down: a long slow-motion beat, the screen cleared, and a fountain
    /// of shards to fly through while it burns.
    private func celebrateBossDefeat(at position: CGPoint) {
        protectShipAfterBossDefeat()
        hitStop(HitStop.bossDefeat)
        backdrop?.setAlert(false)
        backdrop?.pulse()
        cancelHostileFire(around: nil)
        shards?.spawn(at: position, count: CombatRules.bossDefeatShards, speed: 160...380)

        // The moment the film builds to: a white-out at the core, a lens streak across
        // the whole screen, and rings of light racing out through the world.
        let burst = ExplosionFX.burst(size: .huge, particleMultiplier: particleMultiplier, tint: StoryPalette.gold)
        burst.position = position
        effectsParent.addChild(burst)
        let streak = LightSprite.flare(length: size.width * 2.2, thickness: 14, color: StoryPalette.sun)
        streak.position = position
        streak.zPosition = 520
        streak.xScale = 0.1
        effectsParent.addChild(streak)
        streak.run(.sequence([.scaleX(to: 1, duration: 0.12), .group([.fadeOut(withDuration: 0.9), .scaleY(to: 0.3, duration: 0.9)]),
                              .removeFromParent()]))
        for (i, color) in [StoryPalette.sun, StoryPalette.gold, StoryPalette.ember].enumerated() {
            let ring = LightRing.wave(from: 20, to: max(size.width, size.height) * (0.7 + CGFloat(i) * 0.2),
                                      width: 2.6 - CGFloat(i) * 0.5, color: color,
                                      duration: 0.9 + Double(i) * 0.25, squash: i == 1 ? 0.42 : 1, segments: 40)
            ring.position = position
            ring.zPosition = 510
            effectsParent.addChild(ring)
        }
    }

    private func playerDidCollideWithEnemy(enemy: Enemy?) {
        // Already finished off by an earlier contact in this physics step.
        guard let enemy = enemy, enemy.parent != nil, enemy.health > 0 else { return }

        // A ship that cannot be hurt still kills what it flies into, and that is a kill
        // like any other. The invulnerable case used to delete the enemy without a trace
        // — no blast, no payout, a mine gone without going off, a nine-hit tank simply
        // vanishing — and neither case counted towards the hunter medal.
        if isInvulnerable || player.hasShield {
            destroyRammedEnemy(enemy)
            return
        }

        // Zeroed first, so a round landing on it later in this same step finds it dead.
        enemy.health = 0

        // Special handling for mine - should explode on player contact
        if enemy.enemyType == .mine {
            detonateMine(enemy)
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

    /// An enemy rammed by a shielded or invulnerable ship: destroyed the way a shot
    /// destroys it, and paid the same. A mine goes off.
    private func destroyRammedEnemy(_ enemy: Enemy) {
        enemy.health = 0
        HapticManager.shared.mediumTap()
        rewardKill(of: enemy, at: enemy.position)

        if enemy.enemyType == .mine {
            detonateMine(enemy)
            return
        }

        createExplosion(at: enemy.position,
                        size: enemy.enemyType.maxHealth >= CombatRules.heavyKillHealth ? .large : .normal,
                        tint: enemy.enemyType.strokeColor)
        shatter(enemy)
        enemy.markAsDestroyed()
        enemy.removeFromParent()
    }

    /// The ship flying into a boss's hull — the mantis diving onto it, or a ship that
    /// strayed too close to a big one. The boss is not hurt by it. A ship that stays in
    /// contact is hit again once its blink runs out; see `applySustainedContactDamage()`.
    private func playerDidCollideWithBoss() {
        guard bossManager.isBossActive() else { return }
        if isInvulnerable || player.hasShield {
            if player.hasShield {
                SoundManager.shared.playShieldHitSound(on: self)
                HapticManager.shared.mediumTap()
            }
            return
        }
        createExplosion(at: player.position, size: .small)
        handlePlayerDamage()
    }

    /// - Parameter point: where the contact happened, in scene coordinates. A round's
    ///   own position is the right place for its burst; a beam's is its emitter, up at
    ///   the boss, so a beam's burst goes where it met the ship instead.
    private func playerDidCollideWithEnemyBullet(bullet: SKNode?, at point: CGPoint) {
        // A round the barrier stopped earlier in this same physics step is spent.
        guard let bullet = bullet, bullet.parent != nil else { return }

        // A beam is not used up by what it hits; it keeps burning for its full length.
        let isBeam = Self.isBeam(bullet)
        let burstAt = isBeam ? point : bullet.position

        // Skip if player is invulnerable or has shield
        if isInvulnerable || player.hasShield {
            if player.hasShield {
                // Shield absorbs the hit - just create visual feedback
                createExplosion(at: burstAt, size: .small)
                SoundManager.shared.playShieldHitSound(on: self)
                HapticManager.shared.lightTap()
            }
            if !isBeam { bullet.removeFromParent() }
            return
        }

        // Small explosion effect
        createExplosion(at: burstAt, size: .small)
        if !isBeam { bullet.removeFromParent() }

        handlePlayerDamage()
    }

    /// The names a beam's hit volume goes by: `BossManager`'s, and the laser enemy's,
    /// which hangs off the enemy that fires it. Every beam check used to know only the
    /// boss's, so the laser enemy's beam was treated as a round — spent by the first
    /// ship it touched, shield or no shield, deleted by the barrier and left burning by
    /// the Overdrive and the nuke.
    private static let beamNames: [String] = ["bosslaser", "laserBeam"]

    private static func isBeam(_ node: SKNode) -> Bool {
        guard let name = node.name else { return false }
        return beamNames.contains(name)
    }

    /// Damage from what the ship can stay inside: a beam and a boss's hull.
    ///
    /// Physics reports a contact once, as it begins. A ship that entered a beam while
    /// invulnerable or shielded — or that stayed in it through the blink after the hit
    /// it took on the way in — was never touched again for as long as the beam burned,
    /// and the same went for a ship parked inside a boss. Rounds do not need this: the
    /// contact that begins spends them.
    ///
    /// Called every frame from `update(_:)`. Cheap: it reads the core's own contact
    /// list, which is empty almost all of the time, and only while the ship can be hurt.
    private func applySustainedContactDamage() {
        guard !isInvulnerable, !player.hasShield,
              let core = player.physicsBody else { return }

        for body in core.allContactedBodies() {
            guard let node = body.node else { continue }
            if body.categoryBitMask == PhysicsCategory.enemyBullet && Self.isBeam(node) {
                playerDidCollideWithEnemyBullet(bullet: node, at: player.position)
                return
            }
            if body.categoryBitMask == PhysicsCategory.enemy && (node is Boss || node is BossPart) {
                playerDidCollideWithBoss()
                return
            }
        }
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
        // Nothing lands on a ship that is already going down — extra hits used to replay
        // the hit sound and hit-stop over the death sequence and run the lives negative —
        // or on one whose boss is dead and whose level is as good as won.
        guard !isShipDestroyed, !isBossBeaten else { return }

        // Counted before the insurance below: the no-hit medal is about not being
        // touched, and an absorbed hit was still a hit.
        hitsTaken += 1

        // A full Overdrive meter is insurance: the hit that would have landed fires it
        // instead, and the overdrive's opening burst clears the screen and grants the
        // grace period. The charge is the price. See `OverdriveRules`.
        if overdrive.isReady {
            activateOverdrive(reflexive: true)
            return
        }

        SoundManager.shared.playHitSound(on: self)
        hitStop(HitStop.playerHit)
        backdrop?.glitch()
        // A red bleach on the hit: the one event the player must never miss.
        NeonFX.screenFlash(in: self, color: UIColor(red: 1.0, green: 0.15, blue: 0.2, alpha: 1.0), alpha: 0.22, duration: 0.3)

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
        // Two segments can touch the same enemy in one physics step; it dies once.
        guard let enemy = enemy, enemy.parent != nil, enemy.health > 0 else { return }
        enemy.health = 0

        // Create explosion effect
        createExplosion(at: enemy.position, size: .normal)
        HapticManager.shared.mediumTap()
        rewardKill(of: enemy, at: enemy.position)

        // Mark enemy as destroyed and remove
        enemy.markAsDestroyed()
        enemy.removeFromParent()
    }

    private func barrierDidCollideWithEnemyBullet(bullet: SKNode?, at point: CGPoint) {
        guard let bullet = bullet, bullet.parent != nil else { return }

        // The barrier stops rounds; a beam is not a round. Treating it as one deleted the
        // whole beam — boss to screen edge — the moment a segment grazed it. It sparks
        // where they cross and burns on. No sound or haptic: four segments sweep through
        // a beam several times a second.
        if Self.isBeam(bullet) {
            createSmallHitEffect(at: point)
            return
        }

        // Create small hit effect
        createSmallHitEffect(at: bullet.position)
        SoundManager.shared.playShieldHitSound(on: self)
        HapticManager.shared.lightTap()

        // Remove the bullet
        bullet.removeFromParent()
    }

    // New method specifically for bullet hitting destructible block
    private func bulletDidCollideWithObstacle(bullet: SKNode?, obstacle: Obstacle?, hitNode: SKNode?) {
        guard let bullet = bullet, bullet.parent != nil else { return }

        // Homing missiles fly over walls to reach their target. Their own contact mask
        // leaves obstacles out, but an obstacle tests against every `bullet`, so the
        // contact arrived anyway and the wall ate the missile.
        if bullet.name == Self.homingMissileName { return }

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

    private func bulletDidCollideWithAsteroid(bullet: SKNode?, asteroid: Asteroid?) {
        // Either side may already be spent by an earlier contact in this physics step:
        // two bolts meeting one large rock used to pay it and split it twice. As with
        // enemies, a round that reached a rock already broken is spent on it.
        guard let bullet = bullet, let asteroid = asteroid, bullet.parent != nil else { return }
        bullet.removeFromParent()
        guard asteroid.parent != nil else { return }

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
        guard let asteroid = asteroid, asteroid.parent != nil else { return }

        // Check if player is invulnerable or has shield
        if isInvulnerable || player.hasShield {
            if player.hasShield {
                // Shield absorbs the hit, but an asteroid strike consumes it outright
                // (unlike enemy contact, which the shield simply shrugs off).
                deactivateShield()
                HapticManager.shared.mediumTap()
                // The rock splits right on top of the ship, so without a moment's grace
                // the shield's last act was handing a piece of it a free hit.
                grantGrace(Self.shieldBreakGrace)
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
        showPowerUpTimer(name: "shield", duration: duration, color: UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1.0), icon: L10n.PowerUp.shield)

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
        showPowerUpTimer(name: "lightning", duration: duration, color: UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0), icon: L10n.PowerUp.lightning)

        schedulePowerUpExpiry(after: duration, key: "lightningDeactivation") { [weak self] in
            guard let player = self?.player, player.hasLightningWeapon else { return }
            player.hasLightningWeapon = false
        }
    }

    private func activateRapidFire() {
        player.hasRapidFire = true

        let duration = GameConfiguration.rapidFireDuration
        // Show timer
        showPowerUpTimer(name: "rapidFire", duration: duration, color: UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0), icon: L10n.PowerUp.rapidFire)

        schedulePowerUpExpiry(after: duration, key: "rapidFireDeactivation") { [weak self] in
            self?.player?.hasRapidFire = false
        }
    }

    private func activateMagnet() {
        player.hasMagnet = true

        let duration = GameConfiguration.magnetDuration
        // Show timer
        showPowerUpTimer(name: "magnet", duration: duration, color: UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0), icon: L10n.PowerUp.magnet)

        schedulePowerUpExpiry(after: duration, key: "magnetDeactivation") { [weak self] in
            self?.player?.hasMagnet = false
        }
    }

    private func activateSlowMotion() {
        player.hasSlowMotion = true

        let duration = GameConfiguration.slowMotionDuration
        // Show timer
        showPowerUpTimer(name: "slowMotion", duration: duration, color: UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1.0), icon: L10n.PowerUp.slowMotionShort)

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

    /// What a homing missile is called. Walls let it through; see
    /// `bulletDidCollideWithObstacle`.
    private static let homingMissileName = "homingMissile"

    private func launchHomingMissiles() {
        let missileCount = GameConfiguration.homingMissileCount

        // The closest enemies get a missile each.
        var enemies: [Enemy] = []
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy, enemy.health > 0 {
                enemies.append(enemy)
            }
        }
        let origin = player.position
        enemies.sort {
            hypot($0.position.x - origin.x, $0.position.y - origin.y)
                < hypot($1.position.x - origin.x, $1.position.y - origin.y)
        }
        var targets: [SKNode?] = Array(enemies.prefix(missileCount))

        // The boss takes every missile left over.
        if bossManager.isBossActive(), let boss = bossManager.getBoss() {
            while targets.count < missileCount { targets.append(boss) }
        }

        // Always the full salvo. Fewer targets than missiles used to mean fewer missiles —
        // one, against a lone enemy — while an empty screen got all six. The slots left
        // over lock on to whatever is nearest when they launch.
        while targets.count < missileCount { targets.append(nil) }

        for (index, target) in targets.enumerated() {
            let delay = SKAction.wait(forDuration: Double(index) * GameConfiguration.homingMissileLaunchDelay)
            let launch = SKAction.run { [weak self, weak target] in
                self?.launchHomingMissile(lockedOn: target)
            }
            runOnGameplayClock(SKAction.sequence([delay, launch]))
        }
    }

    /// One homing missile, locked on `target`, or with none on whatever is nearest.
    ///
    /// The lock is taken again whenever its target stops being one. A missile used to
    /// keep its first target to the end: when that died first the missile vanished in
    /// mid-flight, and a formation enemy — held by `FormationManager`, so the weak
    /// reference never cleared — drew it to the wreck's last position to hover there
    /// for the rest of its five seconds.
    private func launchHomingMissile(lockedOn target: SKNode?) {
        // Amber, the player's missile colour; pink is reserved for hostile fire. Built
        // by `ProjectileFX`, which also gives it its physics and its damage.
        let missile = ProjectileFX.missile(homing: true)
        missile.position = player.position
        gameContentNode.addChild(missile)

        weak var lock = target
        let homing = SKAction.customAction(withDuration: 5.0) { [weak self] node, _ in
            guard let self = self else {
                node.removeFromParent()
                return
            }
            if !self.isLiveMissileTarget(lock) {
                lock = self.nearestMissileTarget(to: node.position)
            }

            if let target = lock {
                let angle = atan2(target.position.y - node.position.y, target.position.x - node.position.x)
                let step: CGFloat = 300 * CGFloat(self.deltaTime)
                node.position.x += cos(angle) * step
                node.position.y += sin(angle) * step
                node.zRotation = angle - .pi / 2
            } else {
                // Nothing left to chase: carry on up and off the screen.
                node.position.y += 200 * CGFloat(self.deltaTime)
            }
        }
        missile.run(SKAction.sequence([homing, SKAction.removeFromParent()]))
    }

    /// Whether a missile's lock is still worth flying at: on the playfield and alive.
    private func isLiveMissileTarget(_ node: SKNode?) -> Bool {
        guard let node = node, node.parent != nil else { return false }
        if let enemy = node as? Enemy { return enemy.health > 0 }
        if let boss = node as? Boss { return boss.isAlive() }
        return false
    }

    private func nearestMissileTarget(to point: CGPoint) -> SKNode? {
        var candidates: [SKNode] = []
        gameContentNode.enumerateChildNodes(withName: "enemy") { node, _ in
            if let enemy = node as? Enemy, enemy.health > 0 {
                candidates.append(enemy)
            }
        }
        if bossManager.isBossActive(), let boss = bossManager.getBoss() {
            candidates.append(boss)
        }
        return candidates.min {
            hypot($0.position.x - point.x, $0.position.y - point.y)
                < hypot($1.position.x - point.x, $1.position.y - point.y)
        }
    }

    private func activateScoreMultiplier() {
        scoreMultiplier = 2
        player.hasScoreMultiplier = true

        let duration = GameConfiguration.scoreMultiplierDuration
        // Show timer
        showPowerUpTimer(name: "scoreMultiplier", duration: duration, color: UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0), icon: L10n.PowerUp.scoreDouble)

        schedulePowerUpExpiry(after: duration, key: "scoreMultiplierDeactivation") { [weak self] in
            self?.scoreMultiplier = 1
            self?.player?.hasScoreMultiplier = false
        }
    }

    private func activateBarrier() {
        player.hasBarrier = true

        let duration = GameConfiguration.barrierDuration
        // Show timer
        showPowerUpTimer(name: "barrier", duration: duration, color: UIColor(red: 0.2, green: 0.9, blue: 0.7, alpha: 1.0), icon: L10n.PowerUp.barrier)

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
        backdrop?.pulse()
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
                    // Skipped if something else got to it during the stagger.
                    guard enemy.parent != nil else { return }
                    self?.createExplosion(at: enemy.position, size: .normal, tint: enemy.enemyType.strokeColor)
                    self?.shatter(enemy)
                    self?.rewardKill(of: enemy, at: enemy.position, label: false)
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
                    // Skipped if something else got to it during the stagger, as for
                    // the enemies above — otherwise a rock already shot paid twice.
                    guard asteroid.parent != nil else { return }
                    asteroid.createExplosionEffect()
                    self?.addScore(asteroid.asteroidSize.points)
                    asteroid.markAsDestroyed()
                    asteroid.removeFromParent()
                }
            ])
            runOnGameplayClock(destroyAction)
        }

        // A nuke clears the air as well as the ships.
        cancelHostileFire(around: nil)

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
            checkChainMedal()
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
        label.zPosition = 200 // Above everything
        label.alpha = 0.0

        // Kept whole on screen: shrunk if it cannot fit at all, then slid in off the
        // edge. It used to be centred on the pickup and nothing else, so anything
        // collected near a side lost the ends of its caption — and the Czech ones run
        // long ("VÍCENÁSOBNÁ STŘELBA" is ~178pt at 18pt).
        let margin: CGFloat = 8
        UITheme.fitLabel(label, toWidth: size.width - margin * 2, minimumFontSize: 9)
        let halfWidth = label.frame.width / 2
        let x = min(max(position.x, margin + halfWidth), size.width - margin - halfWidth)
        label.position = CGPoint(x: x, y: position.y)

        // Add shadow for better visibility
        let shadow = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        shadow.text = text
        shadow.fontSize = label.fontSize
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
    /// The warning half closes a 2.8 s gap: the boss itself is not created until
    /// `showBossWarning`'s completion runs, and `powerUpManager` keeps spawning through
    /// the warning. A power-up grabbed in that window used to raise a fresh bar that then
    /// sat under the boss health bar for its entire duration.
    ///
    /// The health-bar half covers the boss from its first frame to the instant it dies.
    /// `isBossActive()` alone did not: it only turns true once the 2 s entrance has
    /// finished, and the warning is gone by then, so a bar picked up during the entrance
    /// overlapped the boss's name and health bar for the whole fight.
    private var bossOwnsHUDCorner: Bool {
        if bossManager?.getBoss()?.isHealthBarAttached == true { return true }
        // Only a boss sequence puts a warning up; skip the lookup in ordinary play,
        // where this is asked every frame.
        guard bossSpawned || isEndlessBossFight else { return false }
        return effectsParent.childNode(withName: "bossWarning") != nil
    }

    /// Shows a countdown bar for a power-up.
    ///
    /// The bars themselves live in `PowerUpTimerHUD`. The one piece of the rule that is
    /// the scene's business — no bars in sight while a boss owns the corner, because the
    /// boss health bar sits there — is applied to the whole stack from `update(_:)`, not
    /// here. A bar picked up during a boss is still made, hidden, and appears with its
    /// true remaining time once the corner is free; refusing it outright left a power-up
    /// that outlived the boss running with no bar at all.
    private func showPowerUpTimer(name: String, duration: TimeInterval, color: UIColor, icon: String) {
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
            self.setHostileRoundSpeed(node, to: 1.0)
        }
        bossManager?.setTimeScale(1.0)
    }

    /// Action-driven enemy rounds slow with `speed`. A mirror returns a player's
    /// round under physics control, so its velocity needs the same change of pace.
    /// Boss rounds keep their velocity scaling in `BossManager`.
    private func setHostileRoundSpeed(_ round: SKNode, to scale: CGFloat) {
        if round is PlayerRound, bossManager?.ownsRound(round) != true,
           round.speed != scale, let body = round.physicsBody {
            let ratio = scale / round.speed
            body.velocity = CGVector(dx: body.velocity.dx * ratio, dy: body.velocity.dy * ratio)
        }
        round.speed = scale
    }

    private var deltaTime: TimeInterval = 0

    /// Attracts coins towards player when magnet powerup is active
    /// Uses cached coin dictionary for optimal performance
    ///
    /// - Parameter elapsed: gameplay time since the previous pull. Not `deltaTime`: the
    ///   pull is throttled to `magnetUpdateInterval`, so it runs every second frame at
    ///   60 fps (every fourth at 120), and moving coins by one frame's worth pulled them
    ///   at a half or a quarter of `magnetSpeed`.
    private func attractCoins(elapsed: TimeInterval) {
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
                // Move coin towards player, never past it.
                let step = min(distance, GameConfiguration.magnetSpeed * CGFloat(elapsed))
                coin.position.x += (dx / distance) * step
                coin.position.y += (dy / distance) * step
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
            let bullet = node

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
            self.setHostileRoundSpeed(node, to: slowFactor)
        }

        // The boss, its volleys and its rounds, which `speed` alone does not slow: they
        // fly on velocity. Every tick, so a boss that arrives mid-effect is caught too.
        bossManager?.setTimeScale(slowFactor)
    }

    /// When the running invulnerability ends, on the gameplay clock, so a shorter grant
    /// arriving in the middle of it can tell that it would cut it short.
    private var invulnerableUntil: TimeInterval = 0

    /// Set once the last life is gone, for the death sequence: nothing more lands on the
    /// ship and nothing more is collected. See `playerDestroyed()`.
    private var isShipDestroyed = false

    /// Set by the boss's killing blow and held until the level is over: the fight is won,
    /// and whatever is still flying — the asteroids keep coming through the boss fight —
    /// may not take the last life or the no-hit medal in the 2 s before the ship leaves.
    /// See `protectShipAfterBossDefeat()`.
    private var isBossBeaten = false

    private func activateInvulnerability() {
        isInvulnerable = true
        invulnerableUntil = gameTime + invulnerabilityDuration

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

        // Disarm the ship for the death sequence. Clearing `isGameStarted` alone left both
        // bodies live for the ~1.5 s it takes: further hits replayed the hit sound, flash
        // and hit-stop (stalling the explosions) and ran the lives negative, and the
        // collector went on banking pickups — "EXTRA LIFE", then game over.
        isShipDestroyed = true
        player.physicsBody = nil
        player.childNode(withName: "collector")?.physicsBody = nil

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
        SoundManager.shared.playGameOverSound()

        // An endless run has no completion screen to persist it; game over is where it
        // ends in the ordinary way. See `recordEndlessRun()` for the others.
        let isEndlessRecord = recordEndlessRun()

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

    /// Banks an endless run's score and depth in the records, and reports whether the
    /// score beat the record the run started against.
    ///
    /// Called on every way a run can end: game over, the pause menu's RETRY, LEVELS and
    /// MENU, and the app leaving the foreground — which is the last chance before the
    /// system or the player ends the process. Calling it more than once per run is safe:
    /// `LevelManager.recordEndlessRun` keeps the best of each field and counts nothing,
    /// so a repeat write of the same or a lower result changes nothing.
    @discardableResult
    private func recordEndlessRun() -> Bool {
        guard isEndless, hasEndlessRunStarted, endlessRound > 0 else { return false }
        LevelManager.shared.recordEndlessRun(score: score, round: endlessRound)
        return score > endlessBestAtStart
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

        // Keyed, and gated on the shake already in flight.
        //
        // The steps below are absolute `move(to:)`s, so concurrent shakes do not add up
        // — they fight over the same position. An unkeyed `run` let them: `activateNuke`
        // staggers its explosions 0.05 s apart and every one of them calls in here with
        // a 0.3 s shake, which stacked six to ten sequences on the camera at once and
        // came out as jitter rather than the intended shake.
        //
        // A bare `withKey:` would fix the stacking but introduce a worse bug: the last
        // caller would always win, so one small enemy popping during the boss defeat
        // sequence would downgrade its 20-point shake to a 6-point one. Hence the
        // intensity gate — a weaker shake yields to a stronger one still playing, while
        // an equal or stronger one takes over and keeps a nuke shaking continuously.
        //
        // Checking the action first is what makes `activeShakeIntensity` self-healing:
        // once the sequence has ended (or been cleared by teardown) the recorded value
        // is stale and must not gate the next shake. Same idiom as the "heatPulse"
        // guard in `WeaponHeatSystem.updateHeatBar()`.
        if camera.action(forKey: "cameraShake") == nil {
            activeShakeIntensity = 0
        }
        guard intensity >= activeShakeIntensity else { return }
        activeShakeIntensity = intensity

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
        camera.run(shakeSequence, withKey: "cameraShake")
    }

    /// A frozen enemy's detonation at the end of a freeze bomb: the blast and the same
    /// payout as any other kill. The caller retires the enemy.
    func detonateFrozenEnemy(_ enemy: Enemy) {
        createExplosion(at: enemy.position, size: .normal, tint: enemy.enemyType.strokeColor)
        shatter(enemy)
        rewardKill(of: enemy, at: enemy.position, label: false)
    }

    /// The dead hull coming apart in lines of light. See `ExplosionFX.shatter`.
    private func shatter(_ enemy: Enemy) {
        guard let path = enemy.path else { return }
        effectsParent.addChild(ExplosionFX.shatter(path: path, color: enemy.enemyType.strokeColor,
                                                   at: enemy.position, rotation: enemy.zRotation, scale: enemy.xScale))
    }

    private func createExplosion(at position: CGPoint, size: ExplosionSize = .normal, tint: UIColor? = nil) {
        // Play explosion sound
        SoundManager.shared.playExplosionSound(on: self)

        // Camera shake based on explosion size (reduced on iPad)
        let shake = ExplosionFX.cameraShake(for: size, isIPad: isIPad)
        shakeCamera(intensity: shake.intensity, duration: shake.duration)

        // The burst itself. Parented to `effectsParent`, not the scene, so it freezes
        // with the gameplay clock — see `effectsParent`.
        let burst = ExplosionFX.burst(size: size, particleMultiplier: particleMultiplier, tint: tint)
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

        // Before anything below reads `gameContentNode.isPaused`.
        holdRequestedGameplayPause()

        // Check if player is exiting and off screen (must be before pause/start checks)
        if isPlayerExiting && player.position.y > size.height + 50 {
            isPlayerExiting = false
            levelComplete()
            return
        }

        // The world keeps flying under the level-intro card, which runs with gameplay
        // paused, but stops dead for the pause menu and the perk picker.
        if let backdrop = backdrop, !(isGameStarted && gameContentNode.isPaused) {
            let step = min(max(rawDelta, 0), GameConfiguration.maxFrameDelta) * TimeInterval(timeScale)
            if let player = player { backdrop.follow(x: player.position.x / max(1, size.width)) }
            if !isEndless, let enemyManager = enemyManager, enemyManager.totalEnemiesToSpawn > 0 {
                backdrop.setProgress(CGFloat(enemyManager.totalEnemiesSpawned) / CGFloat(enemyManager.totalEnemiesToSpawn))
            }
            backdrop.update(dt: step)
        }

        // Nothing advances while paused.
        if gameContentNode.isPaused { return }

        // Clamped delta drives both per-frame motion and the game clock, so a
        // dropped frame or a resumed pause can never translate into a huge step.
        let realDelta = min(max(rawDelta, 0), GameConfiguration.maxFrameDelta)
        realPlayTime += realDelta

        // Hit-stop / slow motion. Ended here, on the unscaled clock, rather than by an
        // action — see the note on `timeScale`. Ahead of the `isGameStarted` gate on
        // purpose: the hit that ends a run starts a beat and then ends the game in the
        // same breath, and a beat that could only be lifted while the game is running
        // would leave the death sequence playing at a tenth of its speed.
        if timeScale < 1, realPlayTime >= timeScaleEndsAt {
            timeScale = 1
            applyTimeScale()
        }

        // The countdown bars give way to the boss health bar. Derived every frame rather
        // than switched at the boss's comings and goings, so they are out of sight for
        // its warning and entrance and back the moment it dies — still counting, since
        // hiding them does not stop their clock. See `bossOwnsHUDCorner`.
        powerUpTimers.isHidden = bossOwnsHUDCorner

        // Don't update game logic before the level has started or after it has ended.
        if !isGameStarted {
            // Except the shards during the fly-out after a boss: they used to hang in
            // mid-air while the ship left, and `collectShard` already pays for them.
            if isPlayerExiting, let player = player {
                shards?.update(deltaTime: realDelta * TimeInterval(timeScale),
                               target: player.position, attractAll: player.hasMagnet)
            }
            return
        }

        deltaTime = realDelta * TimeInterval(timeScale)
        gameTime += deltaTime

        // Overdrive countdown, and the shards it and every kill throw out.
        if overdrive.update(currentTime: gameTime) {
            endOverdrive()
        }
        shards?.update(
            deltaTime: deltaTime,
            target: player.position,
            attractAll: player.hasMagnet || overdrive.isActive
        )
        updateGraze()
        applySustainedContactDamage()

        // Magnet effect - attract coins (limited to 30 FPS for performance)
        let magnetOn = player.hasMagnet || stacks(.magnet) > 0
        let sinceMagnetUpdate = gameTime - lastMagnetUpdateTime
        if magnetOn && sinceMagnetUpdate >= GameConfiguration.magnetUpdateInterval {
            lastMagnetUpdateTime = gameTime
            // Capped, or the first pull after a magnet comes back on would be paid for
            // all the time it was off and snap every coin in range onto the ship.
            attractCoins(elapsed: min(sinceMagnetUpdate, GameConfiguration.magnetUpdateInterval * 2))
        }

        // Vortex gravitational pull on player bullets
        applyVortexGravitationalPull()

        // Expire a lapsed kill chain. On the gameplay clock, so a pause never eats one.
        // An overdrive holds the chain: it is the moment the player cashes in, and
        // losing the multiplier to a gap between waves in the middle of it would turn
        // the reward into a trap.
        if overdrive.isActive {
            combo.hold(currentTime: gameTime)
        }
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
        //
        // With relative steering a held finger *is* the trigger, wherever it rests: the
        // old "within 50 pt of the ship" gate only made sense while the finger had to
        // sit under the ship to fly it.
        let isFiring = isTouching
        weaponHeat.update(deltaTime: deltaTime, currentTime: gameTime, isFiring: isFiring)

        let interval = currentShootInterval
        if isTouching && gameTime - lastShootTime >= interval {
            shoot()
            // Carried forward rather than reset to now, which rounded every interval up to
            // whole frames: at 60 fps 0.13 s fired every 0.133 s and an overdrive's 0.0845
            // every 0.1. A shot more than a frame late is a fresh press or a stall, not the
            // stream, so that one restarts the cadence — carrying it would fire a burst.
            let lateBy = gameTime - lastShootTime - interval
            lastShootTime = lateBy < deltaTime ? lastShootTime + interval : gameTime
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

    /// Queues one round: enemies from the director; hazards and the power-up table from
    /// the campaign level the run's depth corresponds to; and a fresh coin allowance. All
    /// of them have to be renewed, or the playfield would quietly empty of everything
    /// except ships a few rounds in.
    private func beginEndlessRound() {
        if stacks(.roundShield) > 0 {
            activateShield()
        }

        enemyManager.appendWaves(
            EndlessDirector.waves(forRound: endlessRound),
            currentTime: gameTime
        )

        // Replaced rather than appended, so the hazards are this round's and not the
        // tail of an earlier round's track. See `AsteroidManager.replaceWaves`.
        let hazards = LevelManager.shared.endlessHazardWaves(forRound: endlessRound)
        obstacleManager.replaceWaves(hazards.obstacles, currentTime: gameTime)
        asteroidManager?.replaceWaves(hazards.asteroids, currentTime: gameTime)

        powerUpManager.updateConfig(endlessPowerUpConfig(forRound: endlessRound))
        coinManager.refreshAllowance()

        announceEndlessRound()
        backdrop?.transition(to: .forEndlessRound(endlessRound))
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

    /// A boss round. Reuses a campaign level's boss entirely — its archetype, its tier
    /// and its phase escalation — touring up the roster as the run gets deeper. See
    /// `EndlessRules.bossLevel(forRound:)` and `BossConfig.roster`.
    private func spawnEndlessBoss() {
        isEndlessBossFight = true

        if stacks(.roundShield) > 0 {
            activateShield()
        }

        obstacleManager.stopSpawning()
        coinManager.setBossFight(true)
        // Hidden, not removed: a power-up still running when the boss dies gets its bar
        // back, with the time it really has left. `update(_:)` reveals them.
        powerUpTimers.isHidden = true

        let bossLevel = EndlessRules.bossLevel(forRound: endlessRound)

        showBossWarning(name: BossConfig.config(for: bossLevel).displayName) { [weak self] in
            guard let self = self else { return }
            SoundManager.shared.playBossAppearSound(on: self)
            self.bossManager.spawnBoss(level: bossLevel) { [weak self] in
                guard let self = self, self.isGameStarted, self.isEndlessBossFight,
                      self.bossManager.isBossActive(), self.stacks(.roundShield) > 0 else { return }
                // Keep the warning's protection against lingering hazards, then give
                // the perk its full duration when combat actually starts. A slowed
                // entrance can outlast the first shield entirely.
                self.activateShield()
            }
        }
    }

    /// Picks the run back up after an endless boss dies, instead of ending the level.
    private func resumeEndlessRunAfterBoss() {
        isEndlessBossFight = false
        bossManager.cleanup()
        coinManager.setBossFight(false)

        // Every boss pays out a choice before the next round begins.
        offerPerks { [weak self] in
            self?.beginRoundAfterBoss()
        }
    }

    /// The round after a boss round.
    ///
    /// The boss *is* its round, so the count moves on past it. It used to resume on the
    /// boss's own number: the round 5 boss was followed by a second "ROUND 5" banner and
    /// round 5's waves. Bosses still land every fifth round — the next advance from the
    /// screen clearing is 6 → 7, and so on to 10.
    private func beginRoundAfterBoss() {
        endlessRound += 1
        beginEndlessRound()
    }

    /// What each endless round renews besides its enemy waves — read-only, for
    /// `jetshotTests`. Both live in private managers and otherwise only show up as what
    /// drops out of the sky.
    var powerUpSpawnTable: PowerUpSpawnConfig? { powerUpManager?.spawnConfig }
    var queuedHazards: (obstacleWaves: Int, asteroids: Int) {
        let asteroids = asteroidManager.map { $0.totalAsteroidsToSpawn - $0.totalAsteroidsSpawned } ?? 0
        return (obstacleManager?.queuedWaveCount ?? 0, asteroids)
    }

    // MARK: - Endless Perks

    /// The picker, while it is up.
    private var perkPicker: PerkPickOverlay? {
        return uiNode?.childNode(withName: PerkPickOverlay.nodeName) as? PerkPickOverlay
    }

    /// Whether the run is stopped on the perk picker. Read-only, for `jetshotTests`.
    var isPerkPickerUp: Bool { perkPicker != nil }

    /// Freezes the run behind the "choose an upgrade" screen, applies the pick, and
    /// carries on with `resume`. With nothing left to offer it goes straight on.
    private func offerPerks(then resume: @escaping () -> Void) {
        let arsenalAtMax = player.bulletCount >= GameConfiguration.maxBulletCount
            && player.sideMissileCount >= GameConfiguration.maxSideMissileCount
        let eligible = PerkRules.eligible(
            stacks: perkStacks,
            livesAtMax: lives >= GameConfiguration.maxLives,
            arsenalAtMax: arsenalAtMax
        )
        var generator = SystemRandomNumberGenerator()
        let choices = PerkRules.offer(from: eligible, using: &generator)
        guard !choices.isEmpty, let uiNode = uiNode, perkPicker == nil else {
            resume()
            return
        }

        // The finger that was flying the ship is not flying it into the picker.
        steeringTouch = nil
        isTouching = false
        setGameplayPaused(true)

        let picker = PerkPickOverlay(
            sceneSize: size,
            perks: choices,
            stacks: perkStacks,
            round: endlessRound,
            frameDepths: FilmUI.Letterbox.depthsOverGameplay(size: size, view: view)
        ) { [weak self] perk in
            guard let self = self else { return }
            self.applyPerk(perk)
            self.setGameplayPaused(false)
            resume()
        }
        uiNode.addChild(picker)
    }

    private func applyPerk(_ perk: EndlessPerk) {
        perkStacks[perk, default: 0] += 1

        switch perk {
        case .chainKeeper:
            combo.windowBonus = PerkRules.chainWindowBonus(stacks: stacks(.chainKeeper))
        case .armor:
            lives = min(GameConfiguration.maxLives, lives + 1)
            SoundManager.shared.playExtraLifeSound(on: self)
        case .arsenal:
            player.bulletCount += 1
            player.sideMissileCount += 1
        default:
            // The rest are read where they apply: the fire interval, the heat per shot,
            // the Overdrive's charge and length, the graze ring, the magnet and the
            // start of every round.
            break
        }

        showFloatingText(L10n.Perk.name(perk),
                         at: CGPoint(x: player.position.x, y: player.position.y + 50),
                         color: PerkPickOverlay.accent(for: perk), fontSize: 18)
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

        // Hide the powerup timers during the boss fight (see `spawnEndlessBoss`)
        powerUpTimers.isHidden = true

        // Show warning before boss appears
        showBossWarning(name: BossConfig.config(for: currentLevel).displayName) { [weak self] in
            guard let self = self else { return }
            // Play boss appear sound
            SoundManager.shared.playBossAppearSound(on: self)
            // Spawn the boss after warning
            self.bossManager.spawnBoss(level: self.currentLevel) {
                // Boss entrance complete, attacks begin
            }
        }
    }

    private func showBossWarning(name: String, completion: @escaping () -> Void) {
        // Play warning sound
        SoundManager.shared.playWarningSound(on: self)
        backdrop?.setAlert(true)

        let warningNode = SKNode()
        warningNode.zPosition = 1500
        warningNode.name = "bossWarning"

        // The picture goes to red alert the way the film's frame would: letterbox bars
        // close, the edges burn red, a scan line runs down the screen, lock-on brackets
        // close on where the boss will come in, and the warning types itself out.
        let red = UIColor(red: 1.0, green: 0.2, blue: 0.16, alpha: 1.0)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let barDepth = max(size.height * 0.09, 60)
        // Everything in the warning finishes inside the 2.2 s it is up for (see the
        // end). The bars used to hold 1.4 s, ending at 2.25 s: they were still opening
        // when the node went, and popped off in a single frame.
        warningNode.addChild(Cinematic.letterbox(size: size, depth: barDepth, hold: 1.3))

        // Red vignette, pulsing.
        let overlay = NeonFX.gradeOverlay(size: size)
        overlay.color = red
        overlay.colorBlendFactor = 1
        overlay.blendMode = .add
        overlay.alpha = 0
        overlay.zPosition = -1
        warningNode.addChild(overlay)

        let frameRect = CGRect(x: 0, y: barDepth, width: size.width, height: size.height - barDepth * 2)
        let corners = Cinematic.viewfinder(in: frameRect, color: red, arm: 20)
        corners.run(.sequence([
            .repeat(.sequence([.fadeAlpha(to: 0.9, duration: 0.15), .fadeAlpha(to: 0.3, duration: 0.15)]), count: 6),
            .fadeOut(withDuration: 0.2)
        ]))
        warningNode.addChild(corners)

        // A line of light sweeping the screen top to bottom.
        let scan = LightSprite.tube(from: CGPoint(x: -size.width / 2, y: 0), to: CGPoint(x: size.width / 2, y: 0),
                                    width: 2.2, color: red)
        scan.position = CGPoint(x: centre.x, y: size.height - barDepth)
        let sweep = SKAction.moveTo(y: barDepth, duration: 1.1)
        sweep.timingMode = .easeInEaseOut
        scan.run(.sequence([sweep, .fadeOut(withDuration: 0.2)]))
        warningNode.addChild(scan)

        // Brackets locking on to the boss's entry point.
        let lock = Cinematic.lockOn(at: CGPoint(x: centre.x, y: size.height * 0.74), from: size.width * 0.42,
                                    to: 54, color: red, duration: 1.0)
        lock.alpha = 0
        lock.run(.sequence([.fadeIn(withDuration: 0.2), .wait(forDuration: 1.4),
                            .repeat(.sequence([.fadeAlpha(to: 0.2, duration: 0.08), .fadeAlpha(to: 1, duration: 0.08)]), count: 2),
                            .fadeOut(withDuration: 0.2)]))
        warningNode.addChild(lock)

        let shade = Cinematic.shade(size: CGSize(width: size.width * 1.4, height: 240), alpha: 0.6)
        shade.position = centre
        warningNode.addChild(shade)

        // WARNING text
        let warningLabel = Cinematic.title(L10n.HUD.warning, fontSize: 40, color: red, glow: red,
                                           tracking: 8, maxWidth: size.width - 40)
        warningLabel.position = CGPoint(x: centre.x, y: centre.y + 30)
        warningLabel.alpha = 0
        warningNode.addChild(warningLabel)

        // Danger approaching text, typed.
        let approachingLabel = Cinematic.typewriter(L10n.HUD.extremeDanger, fontSize: 16, color: .white,
                                                    tracking: 4, delay: 0.3, duration: 0.5,
                                                    maxWidth: size.width - 40)
        approachingLabel.position = CGPoint(x: centre.x, y: centre.y - 18)
        warningNode.addChild(approachingLabel)

        // Which machine it is, typed out once the danger line has finished.
        let nameLabel = Cinematic.typewriter(name, fontSize: 22, color: red, tracking: 7, delay: 0.85,
                                             duration: 0.45, maxWidth: size.width - 40)
        nameLabel.position = CGPoint(x: centre.x, y: centre.y - 54)
        warningNode.addChild(nameLabel)

        // Warning and its dismissal timer both live on gameContentNode so a pause
        // freezes them together; on the scene the countdown kept running and the boss
        // could spawn while the pause menu was up.
        effectsParent.addChild(warningNode)

        // Haptic feedback for drama
        HapticManager.shared.heavyTap()

        // Pulsing animation for overlay: 2.18 s in all, from 2.3.
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.85, duration: 0.28),
            SKAction.fadeAlpha(to: 0.35, duration: 0.28)
        ])
        overlay.run(SKAction.sequence([SKAction.fadeAlpha(to: 0.6, duration: 0.2), .repeat(pulse, count: 3),
                                       .fadeOut(withDuration: 0.3)]))

        // The title glitches in: a hard jitter while it lands, as the film's picture does
        // when reality resists.
        let jitter = SKAction.sequence((0..<6).map { i in
            SKAction.moveTo(x: centre.x + (i % 2 == 0 ? 1 : -1) * CGFloat(6 - i), duration: 0.04)
        })
        warningLabel.run(SKAction.sequence([
            .group([.fadeIn(withDuration: 0.15), jitter]),
            .moveTo(x: centre.x, duration: 0),
            .wait(forDuration: 1.25),
            .fadeOut(withDuration: 0.35)
        ]))
        approachingLabel.run(.sequence([.wait(forDuration: 1.75), .fadeOut(withDuration: 0.35)]))
        nameLabel.run(.sequence([.wait(forDuration: 1.75), .fadeOut(withDuration: 0.35)]))
        shade.run(.sequence([.wait(forDuration: 1.75), .fadeOut(withDuration: 0.35)]))

        // Remove warning and spawn boss
        let cleanup = SKAction.run {
            warningNode.removeFromParent()
            completion()
        }

        // 2.2 s, from 2.8: long enough to read and brace, short enough not to be the
        // slowest moment of the level.
        effectsParent.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.2),
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
            // The run fights on, so the protection the kill bought ends here.
            isBossBeaten = false
            isInvulnerable = false
            invulnerableUntil = gameTime
            resumeEndlessRunAfterBoss()
        } else {
            startPlayerExitAnimation()
        }
    }

    /// From the boss's killing blow until the level is over, nothing can hurt the ship.
    ///
    /// The fight is won by then, but the screen is not empty: the asteroid field keeps
    /// running through a boss fight, and in the 2.2 s before the exit flight a rock could
    /// still take the last life — game over beat the level-complete screen to it — or
    /// cost the no-hit medal on a level already cleared. No blink: nothing hit the ship,
    /// and the clear at the end of one would lift this early.
    private func protectShipAfterBossDefeat() {
        isBossBeaten = true
        isInvulnerable = true
        invulnerableUntil = .infinity
        player.removeAction(forKey: "invulnerability")
        player.alpha = 1
    }

    private func startPlayerExitAnimation() {
        // Disable player controls during exit
        isGameStarted = false
        isPlayerExiting = true
        steeringTouch = nil
        isTouching = false
        if overdrive.isActive {
            overdrive.cancel()
            endOverdrive()
        }

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
        SoundManager.shared.playLevelCompleteSound()

        let totalCoins = coinManager.getTotalCoinsForLevel()

        let levelCompleteScene = LevelCompleteScene(
            size: size,
            level: currentLevel,
            score: score,
            coinsCollected: coinsCollected,
            totalCoins: totalCoins,
            bulletCount: player.bulletCount,
            sideMissileCount: player.sideMissileCount,
            bestChain: combo.bestChain,
            grazes: grazeCount,
            medals: medalsEarnedSoFar
        )
        stopGameplayAndTransition(to: levelCompleteScene, transitionDuration: 1.0)
    }

    private func goToLevelSelect() {
        guard let view = view else { return }
        recordEndlessRun()
        let levelSelectScene = LevelSelectScene(size: view.bounds.size, startLevel: currentLevel)
        levelSelectScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(levelSelectScene, transition: transition)
    }

    // MARK: - Medals

    /// Announces the chain medal the moment the chain reaches its target, rather than
    /// leaving it for the results screen: it is the one medal won mid-flight, and saying
    /// so is what tells the player the medals exist. Only when it is news — a medal this
    /// level already holds is not worth stopping the fight for.
    private func checkChainMedal() {
        guard !isEndless, !chainMedalAnnounced else { return }
        guard combo.chain >= MedalRules.chainTarget(forLevel: currentLevel) else { return }
        chainMedalAnnounced = true

        guard !LevelManager.shared.getLevelMedals(level: currentLevel).contains(.chain) else { return }
        HapticManager.shared.success()
        showBanner(L10n.Medal.earned, color: MedalBadge.color(for: .chain),
                   detail: MedalBadge.label(for: .chain, level: currentLevel))
    }

    // MARK: - Overdrive

    /// Spends a full meter.
    ///
    /// - Parameter reflexive: true when a hit fired it (see `handlePlayerDamage`), which
    ///   only changes the label — the effect is the same, because the point of the
    ///   insurance is that it is the real thing.
    private func activateOverdrive(reflexive: Bool = false) {
        let duration = OverdriveRules.duration + PerkRules.overdriveBonus(stacks: stacks(.longOverdrive))
        guard isGameStarted, overdrive.activate(currentTime: gameTime, duration: duration) else { return }

        // The burst: every hostile round on screen dissolves into a shard.
        cancelHostileFire(around: nil)

        // Clean guns and a grace period, so the burst cannot be undone by a round
        // spawned on this very frame.
        weaponHeat.reset()
        grantGrace(OverdriveRules.activationGrace)

        hitStop(HitStop.overdrive)
        shakeCamera(intensity: 9, duration: 0.3)
        HapticManager.shared.heavyTap()
        SoundManager.shared.playLightningSound(on: self)
        SoundManager.shared.playPowerUpSound(on: self)

        effectsParent.addChild(NeonFX.shockwave(
            at: player.position, startRadius: 20, endRadius: max(size.width, size.height) * 0.75,
            color: OverdriveSystem.activeColor, lineWidth: 6, duration: 0.55
        ))
        effectsParent.addChild(NeonFX.shockwave(
            at: player.position, startRadius: 10, endRadius: size.width * 0.45,
            color: .white, lineWidth: 3, duration: 0.35
        ))
        NeonFX.screenFlash(in: self, color: OverdriveSystem.activeColor, alpha: 0.22, duration: 0.25)

        showBanner(reflexive ? L10n.HUD.overdriveSaved : L10n.HUD.overdrive,
                   color: OverdriveSystem.activeColor)
        player.setOverdriveAura(true)
        setSkyRush(true)
    }

    private func endOverdrive() {
        player.setOverdriveAura(false)
        setSkyRush(false)
    }

    private func setSkyRush(_ rushing: Bool) {
        backdrop?.setRush(rushing)
    }

    /// Grace after an asteroid breaks the shield: long enough for the pieces it splits
    /// into on top of the ship to clear.
    private static let shieldBreakGrace: TimeInterval = 0.5

    /// Invulnerability without the hit: the same flag and blink the damage path uses,
    /// for the overdrive's grace period.
    ///
    /// Never shortens protection already running. Both share the "invulnerability" key,
    /// so an overdrive fired half a second into the 2 s blink after a hit used to replace
    /// it with its own 1 s and hand back half a second less than the hit had given.
    private func grantGrace(_ duration: TimeInterval) {
        if isInvulnerable && invulnerableUntil >= gameTime + duration { return }
        isInvulnerable = true
        invulnerableUntil = gameTime + duration
        let blink = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 0.08),
            SKAction.fadeAlpha(to: 1.0, duration: 0.08)
        ])
        let clearFlag = SKAction.run { [weak self] in
            self?.isInvulnerable = false
        }
        player.run(SKAction.sequence([
            .repeat(blink, count: max(1, Int(duration / 0.16))),
            .fadeAlpha(to: 1.0, duration: 0),
            clearFlag
        ]), withKey: "invulnerability")
    }

    /// Dissolves hostile rounds into shards: every round on screen, or only those within
    /// `radius` of `centre`.
    ///
    /// A screen-wide cancel — the Overdrive burst, the nuke, a boss changing phase or
    /// dying — takes the beams with it. They are named apart from rounds (see
    /// `beamNames`), so the sweep below never saw them, and the Overdrive that promises
    /// a clear screen left a beam burning through it. A local cancel leaves them be: a
    /// beam is not "near" a kill in any useful sense.
    private func cancelHostileFire(around centre: CGPoint?, radius: CGFloat = 0) {
        if centre == nil {
            // Searched for through the whole tree: the laser enemy's beam hangs off the
            // enemy that fires it, not off the playfield.
            var beams: [SKNode] = []
            for name in Self.beamNames {
                enumerateChildNodes(withName: "//\(name)") { node, _ in beams.append(node) }
            }
            for beam in beams {
                // Disarmed at once and faded rather than cut. The name goes too, so every
                // node still called a beam is a live one. A beam owns its whole timeline
                // — `BossManager` keeps no reference to it — so ending its actions here
                // leaves nothing behind on the manager's side.
                beam.name = nil
                beam.physicsBody = nil
                beam.removeAllActions()
                beam.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
            }
        }

        var cancelled: [SKNode] = []
        gameContentNode.enumerateChildNodes(withName: "enemyBullet") { node, _ in
            if let centre = centre {
                let dx = node.position.x - centre.x
                let dy = node.position.y - centre.y
                guard dx * dx + dy * dy <= radius * radius else { return }
            }
            cancelled.append(node)
        }
        guard !cancelled.isEmpty else { return }

        for node in cancelled {
            let position = node.position
            node.removeFromParent()
            // Only rounds still on the playfield become shards; one already off the
            // bottom edge would only ever be collected by the magnet.
            guard position.y > -10, position.y < size.height + 10 else { continue }
            effectsParent.addChild(ProjectileFX.cancelPop(at: position))
            shards?.spawn(at: position, count: 1, speed: 20...60)
        }
    }

    /// Collecting one shard: score, Overdrive charge and a tick of light on the ship.
    ///
    /// Silent on purpose. Shards pour in by the dozen, and a chime on each one was a
    /// constant tinkle over the whole level; the meter filling still has its own cue.
    private func collectShard(at position: CGPoint) {
        guard isGameStarted || isPlayerExiting else { return }

        let multiplier = overdrive.isActive ? OverdriveRules.shardScoreMultiplier : 1
        addScore(CombatRules.shardScore * multiplier, chainsCombo: false)

        if overdrive.add(OverdriveRules.chargePerShard * PerkRules.chargeScale(stacks: stacks(.capacitor))) {
            announceOverdriveReady()
        }

        let flash = NeonFX.flashPoint(at: player.position, radius: 10, color: ShardSystem.color,
                                      duration: 0.12, growTo: 1.8)
        flash.zPosition = 14
        effectsParent.addChild(flash)
    }

    /// The meter just filled. The first time in a level (or an endless run) the banner
    /// also says how to use it; after that a short cue is enough.
    private func announceOverdriveReady() {
        HapticManager.shared.success()
        SoundManager.shared.playScoreMultiplierSound(on: self)
        showBanner(L10n.HUD.overdriveReady, color: OverdriveSystem.chargingColor,
                   detail: overdrive.timesFilled <= 1 ? L10n.HUD.overdriveHint : nil)
    }

    /// A short centred banner over the playfield.
    private func showBanner(_ text: String, color: UIColor, detail: String? = nil) {
        effectsParent.childNode(withName: "centreBanner")?.removeFromParent()

        let banner = SKNode()
        banner.name = "centreBanner"
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.56)
        banner.zPosition = 700
        banner.alpha = 0
        effectsParent.addChild(banner)

        let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        label.text = text
        label.fontSize = 28
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        UITheme.fitLabel(label, toWidth: size.width - 40, minimumFontSize: 16)
        banner.addChild(label)
        NeonFX.addTextBloom(to: label, color: color)

        if let detail = detail {
            let small = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
            small.text = detail
            small.fontSize = 13
            small.fontColor = UIColor(white: 1.0, alpha: 0.85)
            small.verticalAlignmentMode = .center
            small.horizontalAlignmentMode = .center
            small.position = CGPoint(x: 0, y: -28)
            UITheme.fitLabel(small, toWidth: size.width - 40, minimumFontSize: 9)
            banner.addChild(small)
        }

        banner.setScale(1.25)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.0, duration: 0.18)]),
            .wait(forDuration: detail == nil ? 0.8 : 1.6),
            .fadeOut(withDuration: 0.35),
            .removeFromParent()
        ]))
    }

    // MARK: - Graze

    /// Pays out for hostile rounds passing close by the core without touching it, and
    /// lights the hitbox marker while any are near.
    ///
    /// Each round grazes once. The flag is the sprite's own `userData`, set only on a
    /// graze, so the common case — a round nowhere near the ship — allocates nothing.
    private func updateGraze() {
        guard let player = player else { return }
        let core = CGPoint(x: player.position.x + Player.hitboxCenter.x,
                           y: player.position.y + Player.hitboxCenter.y)
        let canGraze = !isInvulnerable && !player.hasShield
        var danger = false
        var grazed: [SKNode] = []
        let ring = GrazeRules.radius * CGFloat(PerkRules.grazeRadiusScale(stacks: stacks(.daredevil)))
        let reach = ring + 12

        gameContentNode.enumerateChildNodes(withName: "enemyBullet") { node, _ in
            let dx = node.position.x - core.x
            let dy = node.position.y - core.y
            // Cheap reject before the square root.
            guard abs(dx) < 70, abs(dy) < 70 else { return }
            danger = true
            guard canGraze, abs(dx) < reach, abs(dy) < reach else { return }
            if node.userData?["grazed"] != nil { return }

            // One nominal radius for every kind of round: the graze ring is generous
            // enough that a point either way is not something a player can feel.
            let distance = (dx * dx + dy * dy).squareRoot()
            if GrazeRules.isGraze(distance: distance, bulletRadius: 5, hitboxRadius: Player.hitboxRadius, ring: ring) {
                grazed.append(node)
            }
        }

        player.setDangerProximity(danger)

        for node in grazed {
            if node.userData == nil { node.userData = NSMutableDictionary() }
            node.userData?["grazed"] = true
            graze(node, from: core)
        }
    }

    private func graze(_ bullet: SKNode, from core: CGPoint) {
        grazeCount += 1
        addScore(GrazeRules.score * PerkRules.grazeScoreScale(stacks: stacks(.daredevil)), chainsCombo: false)
        weaponHeat.cool(by: GrazeRules.heatRelief)
        if overdrive.add(OverdriveRules.chargePerGraze * PerkRules.chargeScale(stacks: stacks(.capacitor))) {
            announceOverdriveReady()
        }

        // A white scrape on the side of the ship the round passed.
        let angle = atan2(bullet.position.y - core.y, bullet.position.x - core.x)
        let point = CGPoint(x: core.x + cos(angle) * 12, y: core.y + sin(angle) * 12)
        let spark = NeonFX.sparks(at: point, count: 3, color: .white, speed: 30,
                                  spreadAngle: .pi * 0.6, baseAngle: angle, length: 6, lifetime: 0.16)
        spark.zPosition = 15
        effectsParent.addChild(spark)

        if realPlayTime - lastGrazeCue > 0.09 {
            lastGrazeCue = realPlayTime
            HapticManager.shared.selection()
        }
    }

    // MARK: - Time scale

    /// Runs a hit-stop or slow-motion beat.
    ///
    /// A beat already in progress is replaced only by one that outlasts it. The short
    /// beats are the frequent ones, so letting a short one take over would either cut a
    /// long beat short (a heavy kill ending a boss's death slow-motion) or — had the end
    /// time been kept — stretch a near-freeze across the whole of the long one.
    private func hitStop(_ beat: HitStop.Beat) {
        let endsAt = realPlayTime + beat.duration
        if timeScale < 1, endsAt <= timeScaleEndsAt { return }
        timeScale = beat.timeScale
        timeScaleEndsAt = endsAt
        applyTimeScale()
    }

    private func applyTimeScale() {
        gameContentNode?.speed = timeScale
        // The bars count down the expiries scheduled on `gameContentNode`, so they keep
        // its time. See `PowerUpTimerHUD.speed`.
        powerUpTimers.speed = timeScale
        if !isGameplayPaused {
            physicsWorld.speed = timeScale
        }
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

    private func reflectBullet(_ bullet: SKNode, from mirror: Enemy) {
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
        //
        // `convertToHostile` also swaps the art: a reflected round has to read as
        // hostile the instant it turns, so it becomes a pink needle like a sniper's.
        ProjectileFX.convertToHostile(bullet)

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

        // A reflection born during SLOW MO leaves at the effect's pace immediately,
        // rather than flying at full speed until the next periodic sweep.
        if player.hasSlowMotion {
            setHostileRoundSpeed(bullet, to: 0.5)
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

    private func isHittingShield(bullet: SKNode, enemy: Enemy) -> Bool {
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
            fragment.restingScale = 0.6 // Smaller than original; the hit squash returns here
            fragment.setScale(0.6)
            // Fragments are debris, not fighters: one round each, whatever the level.
            fragment.maxHealth = 1
            fragment.health = 1

            // Must live in gameContentNode, not on the scene: fragments parented to
            // the scene root kept flying and shooting through a pause, were invisible
            // to every `gameContentNode` enemy sweep (nuke, freeze bomb, lightning,
            // homing missiles, slow motion) and never counted towards level completion.
            gameContentNode.addChild(fragment)
            registerEnemy(fragment)

            // Launch fragments in opposite directions
            let angle: CGFloat = i == 0 ? -.pi/4 : .pi/4
            let dx = sin(angle) * 150
            let dy = -cos(angle) * 150 - 100 // Both pieces fall towards the player

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
        // Recursive: an enemy laser's beam is a child of the ship that fires it.
        var found: [CGPoint] = []
        gameContentNode.enumerateChildNodes(withName: ".//\(name)") { node, _ in
            guard let parent = node.parent else { return }
            let position = parent === self.gameContentNode
                ? node.position
                : parent.convert(node.position, to: self.gameContentNode)
            if position.y > minY { found.append(position) }
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
    ///
    /// The medal check is the one thing a real kill does that `registerKill` does not.
    /// Left to the next real kill, a seeded chain announced its medal whenever the bot
    /// next destroyed something — on a boss level, where the screen is cleared for the
    /// boss, nine seconds in and straight across the preview's Overdrive clip.
    func debugSeedChain(_ chain: Int) {
        for _ in 0..<chain {
            combo.registerKill(currentTime: gameTime)
        }
        checkChainMedal()
    }

    /// Puts the perk picker up, as an endless boss's defeat would, for the screenshot
    /// harness and `jetshotTests`. The pick resumes the run with a fresh round.
    func debugOfferPerks() {
        offerPerks { [weak self] in
            self?.beginRoundAfterBoss()
        }
    }

    /// Pauses the run with the pause menu up, and the settings panel over it if asked,
    /// for the screenshot harness.
    func debugOpenPauseMenu(withSettings: Bool) {
        if !isGameplayPaused { togglePause() }
        if withSettings {
            run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in self?.showSettingsOverlay() }]))
        }
    }

    /// The perk picker's card centres in scene space, so a test can tap one for real.
    func debugPerkCardCentre(_ index: Int) -> CGPoint? {
        return perkPicker?.cardCentre(index)
    }

    /// Tops the Overdrive meter up, for the screenshot harness.
    func debugFillOverdrive() {
        if overdrive.add(1.0) {
            announceOverdriveReady()
        }
    }

    /// Empties the heat gauge, for the screenshot harness. See `DebugLaunch.holdPose`.
    func debugCoolGuns() {
        weaponHeat.reset()
    }

    /// Fires the Overdrive as if the player had, filling it first if need be.
    func debugTriggerOverdrive() {
        debugFillOverdrive()
        activateOverdrive()
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

    /// Exercises a mirror's return without its random reflection chance.
    func debugMirrorReflection(_ round: PlayerRound, from mirror: Enemy) {
        reflectBullet(round, from: mirror)
    }

    /// Applies a specific choice through the same path as the endless perk picker.
    func debugApplyPerk(_ perk: EndlessPerk) {
        applyPerk(perk)
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
                guard let boss = self.bossManager.getBoss() else { return }
                let maxHealth = boss.maxHealthPoints
                let target = max(1, Int(CGFloat(maxHealth) * healthFraction))
                if maxHealth > target {
                    _ = self.bossManager.bossTakeDamage(amount: maxHealth - target)
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
