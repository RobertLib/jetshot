//
//  SoundManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 30.11.2025.
//

import SpriteKit
import AVFoundation

/// Manages all game audio including background music and sound effects.
/// Handles music/sound enable/disable settings and audio playback.
class SoundManager: NSObject {

    static let shared = SoundManager()

    // Background music
    private var musicPlayer: AVAudioPlayer?
    private var currentMusicTrack: Int = 0
    private let musicTracks = ["music-1.mp3", "music-2.mp3", "music-3.mp3", "music-4.mp3", "music-5.mp3", "music-6.mp3", "music-7.mp3"]

    var isMusicEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "isMusicEnabled") // Default is false, so we use inverted logic below
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isMusicEnabled")
            if newValue {
                resumeMusic()
            } else {
                pauseMusic()
            }
        }
    }

    var musicVolume: Float = 0.3 {
        didSet {
            musicPlayer?.volume = musicVolume
        }
    }

    // Preloaded sound effects
    private var shootSound: SKAction?
    private var explosionSound: SKAction?
    private var powerUpSound: SKAction?
    private var coinSound: SKAction?
    private var hitSound: SKAction?
    private var gameOverSound: SKAction?
    private var levelCompleteSound: SKAction?
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
    private var teleportSound: SKAction?
    private var ghostPhaseSound: SKAction?
    private var mineCountdownSound: SKAction?
    private var mineArmSound: SKAction?
    private var splitterSplitSound: SKAction?
    private var bouncerBounceSound: SKAction?
    private var turretDockSound: SKAction?
    private var absorbSound: SKAction?
    private var reflectSound: SKAction?
    private var shieldBlockSound: SKAction?
    private var laserChargeSound: SKAction?
    private var laserFireSound: SKAction?

    // Sound settings
    var isSoundEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "isSoundEnabled") // Default is false, so we use inverted logic below
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isSoundEnabled")
        }
    }


    private override init() {
        super.init()
        // Set default values if not already set
        if !UserDefaults.standard.bool(forKey: "hasSetSoundDefaults") {
            UserDefaults.standard.set(true, forKey: "isMusicEnabled")
            UserDefaults.standard.set(true, forKey: "isSoundEnabled")
            UserDefaults.standard.set(true, forKey: "hasSetSoundDefaults")
        }
        preloadSounds()
    }

    // Helper function to create sound action
    // Note: SKAction.playSoundFileNamed doesn't support volume control - volume must be adjusted in the audio files themselves
    private func createSoundAction(fileName: String) -> SKAction {
        return SKAction.playSoundFileNamed(fileName, waitForCompletion: false)
    }

    private func preloadSounds() {
        // Preload sound effects
        shootSound = createSoundAction(fileName: "shoot-sound.mp3")
        explosionSound = createSoundAction(fileName: "explosion.mp3")
        powerUpSound = createSoundAction(fileName: "power-up.mp3")
        coinSound = createSoundAction(fileName: "coin.mp3")
        hitSound = createSoundAction(fileName: "hit.mp3")
        gameOverSound = createSoundAction(fileName: "game-over.mp3")
        levelCompleteSound = createSoundAction(fileName: "level-complete.mp3")
        buttonClickSound = createSoundAction(fileName: "button-click.mp3")
        buttonHoverSound = createSoundAction(fileName: "button-hover.mp3")
        menuSelectSound = createSoundAction(fileName: "menu-select.mp3")
        pauseSound = createSoundAction(fileName: "pause.mp3")
        resumeSound = createSoundAction(fileName: "resume.mp3")
        shieldActivateSound = createSoundAction(fileName: "shield-activate.mp3")
        shieldDeactivateSound = createSoundAction(fileName: "shield-deactivate.mp3")
        shieldHitSound = createSoundAction(fileName: "shield-hit.mp3")
        extraLifeSound = createSoundAction(fileName: "extra-life.mp3")
        bossAppearSound = createSoundAction(fileName: "boss-appear.mp3")
        bossDefeatSound = createSoundAction(fileName: "boss-defeat.mp3")
        bossHitSound = createSoundAction(fileName: "boss-hit.mp3")
        enemyShootSound = createSoundAction(fileName: "enemy-shoot.mp3")
        missileSound = createSoundAction(fileName: "missile.mp3")
        lightningSound = createSoundAction(fileName: "lightning.mp3")
        warningSound = createSoundAction(fileName: "warning.mp3")
        countdownSound = createSoundAction(fileName: "countdown.mp3")
        levelStartSound = createSoundAction(fileName: "level-start.mp3")
        playerSpawnSound = createSoundAction(fileName: "player-spawn.mp3")
        playerExitSound = createSoundAction(fileName: "player-exit.mp3")
        asteroidHitSound = createSoundAction(fileName: "asteroid-hit.mp3")
        obstacleHitSound = createSoundAction(fileName: "obstacle-hit.mp3")
        magnetActivateSound = createSoundAction(fileName: "magnet-activate.mp3")
        slowMotionActivateSound = createSoundAction(fileName: "slow-motion.mp3")
        rapidFireActivateSound = createSoundAction(fileName: "rapid-fire.mp3")
        multiShotActivateSound = createSoundAction(fileName: "multi-shot.mp3")
        barrierActivateSound = createSoundAction(fileName: "barrier-activate.mp3")
        scoreMultiplierSound = createSoundAction(fileName: "score-multiplier.mp3")
        invulnerabilitySound = createSoundAction(fileName: "invulnerability.mp3")
        teleportSound = createSoundAction(fileName: "teleport.mp3")
        ghostPhaseSound = createSoundAction(fileName: "ghost-phase.mp3")
        mineCountdownSound = createSoundAction(fileName: "mine-countdown.mp3")
        mineArmSound = createSoundAction(fileName: "mine-arm.mp3")
        splitterSplitSound = createSoundAction(fileName: "splitter-split.mp3")
        bouncerBounceSound = createSoundAction(fileName: "bouncer-bounce.mp3")
        turretDockSound = createSoundAction(fileName: "turret-dock.mp3")
        absorbSound = createSoundAction(fileName: "absorb.wav")
        reflectSound = createSoundAction(fileName: "reflect.wav")
        shieldBlockSound = createSoundAction(fileName: "shield_block.wav")
        laserChargeSound = createSoundAction(fileName: "laser_charge.wav")
        laserFireSound = createSoundAction(fileName: "laser_fire.wav")
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

    // MARK: - Special Enemy Sound Effects

    func playAbsorbSound(on node: SKNode) {
        guard isSoundEnabled, let sound = absorbSound else { return }
        node.run(sound)
    }

    func playReflectSound(on node: SKNode) {
        guard isSoundEnabled, let sound = reflectSound else { return }
        node.run(sound)
    }

    func playShieldBlockSound(on node: SKNode) {
        guard isSoundEnabled, let sound = shieldBlockSound else { return }
        node.run(sound)
    }

    func playLaserChargeSound(on node: SKNode) {
        guard isSoundEnabled, let sound = laserChargeSound else { return }
        node.run(sound)
    }

    func playLaserFireSound(on node: SKNode) {
        guard isSoundEnabled, let sound = laserFireSound else { return }
        node.run(sound)
    }

    func playTeleportSound(on node: SKNode) {
        // Teleporter teleporting
        guard isSoundEnabled, let sound = teleportSound else { return }
        node.run(sound)
    }

    func playGhostPhaseSound(on node: SKNode) {
        // Ghost phasing in/out
        guard isSoundEnabled, let sound = ghostPhaseSound else { return }
        node.run(sound)
    }

    func playMineCountdownSound(on node: SKNode) {
        // Mine countdown tick
        guard isSoundEnabled, let sound = mineCountdownSound else { return }
        node.run(sound)
    }

    func playMineArmSound(on node: SKNode) {
        // Mine arming
        guard isSoundEnabled, let sound = mineArmSound else { return }
        node.run(sound)
    }

    func playSplitterSplitSound(on node: SKNode) {
        // Splitter splitting
        guard isSoundEnabled, let sound = splitterSplitSound else { return }
        node.run(sound)
    }

    func playBouncerBounceSound(on node: SKNode) {
        // Bouncer bouncing off edge
        guard isSoundEnabled, let sound = bouncerBounceSound else { return }
        node.run(sound)
    }

    func playTurretDockSound(on node: SKNode) {
        // Turret docking
        guard isSoundEnabled, let sound = turretDockSound else { return }
        node.run(sound)
    }

    // MARK: - Background Music

    func startBackgroundMusic() {
        #if DEBUG
        print("🎵 startBackgroundMusic called - isMusicEnabled: \(isMusicEnabled)")
        #endif
        guard isMusicEnabled else {
            #if DEBUG
            print("⚠️ Music is disabled")
            #endif
            return
        }
        playMusicTrack(index: currentMusicTrack)
    }

    func setMusicForLevel(_ level: Int) {
        let trackIndex = (level - 1) % musicTracks.count
        currentMusicTrack = trackIndex

        if isMusicEnabled {
            stopBackgroundMusic()
            playMusicTrack(index: trackIndex)
        }
    }

    func playSpecificMusic(filename: String) {
        let resourceName = filename.replacingOccurrences(of: ".mp3", with: "")

        #if DEBUG
        print("🎵 Attempting to load specific music: \(filename)")
        #endif

        // Try multiple methods to find the music file
        var musicURL: URL?

        // Method 1: Try subdirectory "Music"
        musicURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3", subdirectory: "Music")

        if musicURL == nil {
            // Method 2: Try root directory
            musicURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3")

            if musicURL == nil {
                // Method 3: Try jetshot/Music path
                musicURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3", subdirectory: "jetshot/Music")
            }
        }

        if let musicURL = musicURL {
            do {
                // Configure audio session for background music
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)

                musicPlayer?.stop()
                musicPlayer = try AVAudioPlayer(contentsOf: musicURL)
                musicPlayer?.volume = musicVolume
                musicPlayer?.delegate = self
                musicPlayer?.numberOfLoops = -1 // Loop indefinitely
                musicPlayer?.prepareToPlay()

                if isMusicEnabled {
                    musicPlayer?.play()
                }

                #if DEBUG
                print("✅ Successfully playing specific music: \(filename)")
                #endif
            } catch {
                #if DEBUG
                print("❌ Could not load music file: \(filename), error: \(error)")
                #endif
            }
        } else {
            #if DEBUG
            print("❌ Could not find music file: \(filename) anywhere in bundle")
            #endif
        }
    }

    func stopBackgroundMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
    }

    func pauseMusic() {
        musicPlayer?.pause()
    }

    func resumeMusic() {
        guard isMusicEnabled else { return }
        if musicPlayer == nil {
            startBackgroundMusic()
        } else {
            musicPlayer?.play()
        }
    }

    private func playMusicTrack(index: Int) {
        guard index < musicTracks.count else { return }

        let trackName = musicTracks[index]
        let resourceName = trackName.replacingOccurrences(of: ".mp3", with: "")

        #if DEBUG
        print("🎵 Attempting to load music: \(trackName)")
        #endif

        // Try multiple methods to find the music file
        var musicURL: URL?

        // Method 1: Try subdirectory "Music"
        musicURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3", subdirectory: "Music")
        #if DEBUG
        if musicURL != nil {
            print("✅ Found music in Music subdirectory")
        } else {
            print("⚠️ Not found in Music subdirectory, trying root...")
        }
        #endif

        if musicURL == nil {
            // Method 2: Try root directory
            musicURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3")
            #if DEBUG
            if musicURL != nil {
                print("✅ Found music in root directory")
            } else {
                print("⚠️ Not found in root, trying jetshot/Music...")
            }
            #endif

            if musicURL == nil {
                // Method 3: Try jetshot/Music path
                musicURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3", subdirectory: "jetshot/Music")
                #if DEBUG
                if musicURL != nil {
                    print("✅ Found music in jetshot/Music")
                }
                #endif
            }
        }

        // Get the path to the music file
        if let musicURL = musicURL {
            do {
                // Configure audio session for background music
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)

                musicPlayer = try AVAudioPlayer(contentsOf: musicURL)
                musicPlayer?.volume = musicVolume
                musicPlayer?.delegate = self
                musicPlayer?.prepareToPlay()
                musicPlayer?.play()

                #if DEBUG
                print("✅ Successfully playing music: \(trackName) at volume: \(musicVolume)")
                #endif
            } catch {
                #if DEBUG
                print("❌ Could not load music file: \(trackName), error: \(error)")
                #endif
            }
        } else {
            #if DEBUG
            print("❌ Could not find music file: \(trackName) anywhere in bundle")
            print("📦 Bundle path: \(Bundle.main.bundlePath)")
            #endif
        }
    }

    private func playNextTrack() {
        currentMusicTrack = (currentMusicTrack + 1) % musicTracks.count
        playMusicTrack(index: currentMusicTrack)
    }
}


// MARK: - AVAudioPlayerDelegate

extension SoundManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag && isMusicEnabled {
            playNextTrack()
        }
    }
}
