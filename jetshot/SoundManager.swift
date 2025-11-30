//
//  SoundManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 30.11.2025.
//

import SpriteKit
import AVFoundation

class SoundManager {

    static let shared = SoundManager()

    // Preloaded sound effects - Existing sounds
    private var shootSound: SKAction?
    private var explosionSound: SKAction?
    private var powerUpSound: SKAction?
    private var coinSound: SKAction?
    private var hitSound: SKAction?
    private var gameOverSound: SKAction?
    private var levelCompleteSound: SKAction?

    // Preloaded sound effects - New sounds (to be added later)
    private var buttonClickSound: SKAction?
    private var buttonHoverSound: SKAction?
    private var menuSelectSound: SKAction?
    private var pauseSound: SKAction?
    private var resumeSound: SKAction?
    private var shieldActivateSound: SKAction?
    private var shieldDeactivateSound: SKAction?
    private var shieldHitSound: SKAction?
    private var extraLifeSound: SKAction?
    private var bossAppearSound: SKAction?
    private var bossDefeatSound: SKAction?
    private var bossHitSound: SKAction?
    private var enemyShootSound: SKAction?
    private var missileSound: SKAction?
    private var lightningSound: SKAction?
    private var warningSound: SKAction?
    private var countdownSound: SKAction?
    private var levelStartSound: SKAction?
    private var playerSpawnSound: SKAction?
    private var playerExitSound: SKAction?
    private var asteroidHitSound: SKAction?
    private var obstacleHitSound: SKAction?
    private var magnetActivateSound: SKAction?
    private var slowMotionActivateSound: SKAction?
    private var rapidFireActivateSound: SKAction?
    private var multiShotActivateSound: SKAction?
    private var barrierActivateSound: SKAction?
    private var scoreMultiplierSound: SKAction?
    private var invulnerabilitySound: SKAction?

    // Sound settings
    var isSoundEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSoundEnabled, forKey: "soundEnabled")
        }
    }

    var soundVolume: Float = 1.0 {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: "soundVolume")
        }
    }

    private init() {
        loadSettings()
        preloadSounds()
    }

    private func loadSettings() {
        if UserDefaults.standard.object(forKey: "soundEnabled") != nil {
            isSoundEnabled = UserDefaults.standard.bool(forKey: "soundEnabled")
        }
        if UserDefaults.standard.object(forKey: "soundVolume") != nil {
            soundVolume = UserDefaults.standard.float(forKey: "soundVolume")
        }
    }

    private func preloadSounds() {
        // Preload existing sounds
        shootSound = SKAction.playSoundFileNamed("retro-laser.mp3", waitForCompletion: false)
        explosionSound = SKAction.playSoundFileNamed("retro-explode.mp3", waitForCompletion: false)
        powerUpSound = SKAction.playSoundFileNamed("retro-powerup.mp3", waitForCompletion: false)
        coinSound = SKAction.playSoundFileNamed("retro-coin.mp3", waitForCompletion: false)
        hitSound = SKAction.playSoundFileNamed("retro-hurt.mp3", waitForCompletion: false)
        gameOverSound = SKAction.playSoundFileNamed("game-over-arcade.mp3", waitForCompletion: false)
        levelCompleteSound = SKAction.playSoundFileNamed("level-completed.mp3", waitForCompletion: false)

        // Preload new sounds (uncomment when sound files are added)
        // buttonClickSound = SKAction.playSoundFileNamed("button-click.mp3", waitForCompletion: false)
        // buttonHoverSound = SKAction.playSoundFileNamed("button-hover.mp3", waitForCompletion: false)
        // menuSelectSound = SKAction.playSoundFileNamed("menu-select.mp3", waitForCompletion: false)
        // pauseSound = SKAction.playSoundFileNamed("pause.mp3", waitForCompletion: false)
        // resumeSound = SKAction.playSoundFileNamed("resume.mp3", waitForCompletion: false)
        // shieldActivateSound = SKAction.playSoundFileNamed("shield-activate.mp3", waitForCompletion: false)
        // shieldDeactivateSound = SKAction.playSoundFileNamed("shield-deactivate.mp3", waitForCompletion: false)
        // shieldHitSound = SKAction.playSoundFileNamed("shield-hit.mp3", waitForCompletion: false)
        // extraLifeSound = SKAction.playSoundFileNamed("extra-life.mp3", waitForCompletion: false)
        // bossAppearSound = SKAction.playSoundFileNamed("boss-appear.mp3", waitForCompletion: false)
        // bossDefeatSound = SKAction.playSoundFileNamed("boss-defeat.mp3", waitForCompletion: false)
        // bossHitSound = SKAction.playSoundFileNamed("boss-hit.mp3", waitForCompletion: false)
        // enemyShootSound = SKAction.playSoundFileNamed("enemy-shoot.mp3", waitForCompletion: false)
        // missileSound = SKAction.playSoundFileNamed("missile.mp3", waitForCompletion: false)
        // lightningSound = SKAction.playSoundFileNamed("lightning.mp3", waitForCompletion: false)
        // warningSound = SKAction.playSoundFileNamed("warning.mp3", waitForCompletion: false)
        // countdownSound = SKAction.playSoundFileNamed("countdown.mp3", waitForCompletion: false)
        // levelStartSound = SKAction.playSoundFileNamed("level-start.mp3", waitForCompletion: false)
        // playerSpawnSound = SKAction.playSoundFileNamed("player-spawn.mp3", waitForCompletion: false)
        // playerExitSound = SKAction.playSoundFileNamed("player-exit.mp3", waitForCompletion: false)
        // asteroidHitSound = SKAction.playSoundFileNamed("asteroid-hit.mp3", waitForCompletion: false)
        // obstacleHitSound = SKAction.playSoundFileNamed("obstacle-hit.mp3", waitForCompletion: false)
        // magnetActivateSound = SKAction.playSoundFileNamed("magnet-activate.mp3", waitForCompletion: false)
        // slowMotionActivateSound = SKAction.playSoundFileNamed("slow-motion.mp3", waitForCompletion: false)
        // rapidFireActivateSound = SKAction.playSoundFileNamed("rapid-fire.mp3", waitForCompletion: false)
        // multiShotActivateSound = SKAction.playSoundFileNamed("multi-shot.mp3", waitForCompletion: false)
        // barrierActivateSound = SKAction.playSoundFileNamed("barrier-activate.mp3", waitForCompletion: false)
        // scoreMultiplierSound = SKAction.playSoundFileNamed("score-multiplier.mp3", waitForCompletion: false)
        // invulnerabilitySound = SKAction.playSoundFileNamed("invulnerability.mp3", waitForCompletion: false)
    }

    // MARK: - Existing Sound Effects

    func playShootSound(on node: SKNode) {
        guard isSoundEnabled, let sound = shootSound else { return }
        node.run(sound)
    }

    func playExplosionSound(on node: SKNode) {
        guard isSoundEnabled, let sound = explosionSound else { return }
        node.run(sound)
    }

    func playPowerUpSound(on node: SKNode) {
        guard isSoundEnabled, let sound = powerUpSound else { return }
        node.run(sound)
    }

    func playCoinSound(on node: SKNode) {
        guard isSoundEnabled, let sound = coinSound else { return }
        node.run(sound)
    }

    func playHitSound(on node: SKNode) {
        guard isSoundEnabled, let sound = hitSound else { return }
        node.run(sound)
    }

    func playGameOverSound(on node: SKNode) {
        guard isSoundEnabled, let sound = gameOverSound else { return }
        node.run(sound)
    }

    func playLevelCompleteSound(on node: SKNode) {
        guard isSoundEnabled, let sound = levelCompleteSound else { return }
        node.run(sound)
    }

    // MARK: - UI Sound Effects

    func playButtonClickSound(on node: SKNode) {
        guard isSoundEnabled, let sound = buttonClickSound else { return }
        node.run(sound)
    }

    func playButtonHoverSound(on node: SKNode) {
        guard isSoundEnabled, let sound = buttonHoverSound else { return }
        node.run(sound)
    }

    func playMenuSelectSound(on node: SKNode) {
        guard isSoundEnabled, let sound = menuSelectSound else { return }
        node.run(sound)
    }

    func playPauseSound(on node: SKNode) {
        guard isSoundEnabled, let sound = pauseSound else { return }
        node.run(sound)
    }

    func playResumeSound(on node: SKNode) {
        guard isSoundEnabled, let sound = resumeSound else { return }
        node.run(sound)
    }

    // MARK: - Shield Sound Effects

    func playShieldActivateSound(on node: SKNode) {
        guard isSoundEnabled, let sound = shieldActivateSound else { return }
        node.run(sound)
    }

    func playShieldDeactivateSound(on node: SKNode) {
        guard isSoundEnabled, let sound = shieldDeactivateSound else { return }
        node.run(sound)
    }

    func playShieldHitSound(on node: SKNode) {
        guard isSoundEnabled, let sound = shieldHitSound else { return }
        node.run(sound)
    }

    // MARK: - Life & Power-up Sound Effects

    func playExtraLifeSound(on node: SKNode) {
        guard isSoundEnabled, let sound = extraLifeSound else { return }
        node.run(sound)
    }

    func playMagnetActivateSound(on node: SKNode) {
        guard isSoundEnabled, let sound = magnetActivateSound else { return }
        node.run(sound)
    }

    func playSlowMotionActivateSound(on node: SKNode) {
        guard isSoundEnabled, let sound = slowMotionActivateSound else { return }
        node.run(sound)
    }

    func playRapidFireActivateSound(on node: SKNode) {
        guard isSoundEnabled, let sound = rapidFireActivateSound else { return }
        node.run(sound)
    }

    func playMultiShotActivateSound(on node: SKNode) {
        guard isSoundEnabled, let sound = multiShotActivateSound else { return }
        node.run(sound)
    }

    func playBarrierActivateSound(on node: SKNode) {
        guard isSoundEnabled, let sound = barrierActivateSound else { return }
        node.run(sound)
    }

    func playScoreMultiplierSound(on node: SKNode) {
        guard isSoundEnabled, let sound = scoreMultiplierSound else { return }
        node.run(sound)
    }

    func playInvulnerabilitySound(on node: SKNode) {
        guard isSoundEnabled, let sound = invulnerabilitySound else { return }
        node.run(sound)
    }

    // MARK: - Boss Sound Effects

    func playBossAppearSound(on node: SKNode) {
        guard isSoundEnabled, let sound = bossAppearSound else { return }
        node.run(sound)
    }

    func playBossDefeatSound(on node: SKNode) {
        guard isSoundEnabled, let sound = bossDefeatSound else { return }
        node.run(sound)
    }

    func playBossHitSound(on node: SKNode) {
        guard isSoundEnabled, let sound = bossHitSound else { return }
        node.run(sound)
    }

    // MARK: - Weapon Sound Effects

    func playEnemyShootSound(on node: SKNode) {
        guard isSoundEnabled, let sound = enemyShootSound else { return }
        node.run(sound)
    }

    func playMissileSound(on node: SKNode) {
        guard isSoundEnabled, let sound = missileSound else { return }
        node.run(sound)
    }

    func playLightningSound(on node: SKNode) {
        guard isSoundEnabled, let sound = lightningSound else { return }
        node.run(sound)
    }

    // MARK: - Game Event Sound Effects

    func playWarningSound(on node: SKNode) {
        guard isSoundEnabled, let sound = warningSound else { return }
        node.run(sound)
    }

    func playCountdownSound(on node: SKNode) {
        guard isSoundEnabled, let sound = countdownSound else { return }
        node.run(sound)
    }

    func playLevelStartSound(on node: SKNode) {
        guard isSoundEnabled, let sound = levelStartSound else { return }
        node.run(sound)
    }

    func playPlayerSpawnSound(on node: SKNode) {
        guard isSoundEnabled, let sound = playerSpawnSound else { return }
        node.run(sound)
    }

    func playPlayerExitSound(on node: SKNode) {
        guard isSoundEnabled, let sound = playerExitSound else { return }
        node.run(sound)
    }

    // MARK: - Obstacle Sound Effects

    func playAsteroidHitSound(on node: SKNode) {
        guard isSoundEnabled, let sound = asteroidHitSound else { return }
        node.run(sound)
    }

    func playObstacleHitSound(on node: SKNode) {
        guard isSoundEnabled, let sound = obstacleHitSound else { return }
        node.run(sound)
    }
}
