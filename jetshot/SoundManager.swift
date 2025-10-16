//
//  SoundManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 30.11.2025.
//

import SpriteKit
import AVFoundation

class SoundManager: NSObject {

    static let shared = SoundManager()

    // Audio engine for sound effects with reverb and other effects
    private let audioEngine = AVAudioEngine()
    private let reverbNode = AVAudioUnitReverb()
    private let pitchNode = AVAudioUnitTimePitch()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 3)
    private let distortionNode = AVAudioUnitDistortion()
    private var soundPlayers: [AVAudioPlayerNode] = []

    // Background music
    private var musicPlayer: AVAudioPlayer?
    private var currentMusicTrack: Int = 0
    private let musicTracks = ["music-1.mp3", "music-2.mp3", "music-3.mp3", "music-4.mp3", "music-5.mp3", "music-6.mp3", "music-7.mp3"]

    var isMusicEnabled: Bool = true {
        didSet {
            if isMusicEnabled {
                resumeMusic()
            } else {
                pauseMusic()
            }
        }
    }

    var musicVolume: Float = 0.5 {
        didSet {
            musicPlayer?.volume = musicVolume
        }
    }

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
    var isSoundEnabled: Bool = true


    private override init() {
        super.init()
        setupAudioEngine()
        preloadSounds()
        setupMusicPlayerDelegate()
    }

    private func setupAudioEngine() {
        // Attach all effect nodes to audio engine
        audioEngine.attach(pitchNode)
        audioEngine.attach(eqNode)
        audioEngine.attach(distortionNode)
        audioEngine.attach(reverbNode)

        // EXTREME pitch shift - lower by 10 semitones (full octave minus 2 semitones)
        pitchNode.pitch = -1000 // -1000 cents = -10 semitones - extremely deep
        pitchNode.rate = 0.85 // Also slow down slightly for heavier feel

        // EXTREME EQ - radical frequency shaping for sci-fi/synthetic sound
        // Band 0: Sub-bass boost (extreme rumble)
        eqNode.bands[0].frequency = 80
        eqNode.bands[0].gain = 12.0 // Maximum boost
        eqNode.bands[0].bandwidth = 2.0
        eqNode.bands[0].bypass = false
        eqNode.bands[0].filterType = .parametric

        // Band 1: Mid frequencies (severe cut for hollow, robotic character)
        eqNode.bands[1].frequency = 1500
        eqNode.bands[1].gain = -12.0 // Maximum cut
        eqNode.bands[1].bandwidth = 2.0
        eqNode.bands[1].bypass = false
        eqNode.bands[1].filterType = .parametric

        // Band 2: High frequencies (extreme cut for dark, heavy sound)
        eqNode.bands[2].frequency = 4000
        eqNode.bands[2].gain = -18.0 // Extreme cut
        eqNode.bands[2].bandwidth = 1.5
        eqNode.bands[2].bypass = false
        eqNode.bands[2].filterType = .lowShelf

        // EXTREME distortion - heavy digital/mechanical distortion
        distortionNode.loadFactoryPreset(.multiDistortedCubed) // Heavy cubic distortion
        distortionNode.wetDryMix = 70 // 70% distortion mix - heavily distorted

        // Heavy reverb for deep space atmosphere
        reverbNode.loadFactoryPreset(.cathedral) // Bigger space
        reverbNode.wetDryMix = 45 // 45% reverb mix - very spacey

        // Connect effects chain: pitch -> EQ -> distortion -> reverb -> main mixer
        audioEngine.connect(pitchNode, to: eqNode, format: nil)
        audioEngine.connect(eqNode, to: distortionNode, format: nil)
        audioEngine.connect(distortionNode, to: reverbNode, format: nil)
        audioEngine.connect(reverbNode, to: audioEngine.mainMixerNode, format: nil)

        // Start audio engine
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func setupMusicPlayerDelegate() {
        // This will be called after music player is created
    }

    // Helper function to create sound action - volume is baked into the individual sound files
    private func createSoundAction(fileName: String, volume: Float = 0.5) -> SKAction {
        return SKAction.playSoundFileNamed(fileName, waitForCompletion: false)
    }

    // Play sound with reverb using AVAudioEngine
    private func playSoundWithReverb(fileName: String, volume: Float = 0.5) {
        guard isSoundEnabled else { return }

        guard let url = Bundle.main.url(forResource: fileName.replacingOccurrences(of: ".mp3", with: ""), withExtension: "mp3") else {
            print("Sound file not found: \(fileName)")
            return
        }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            let playerNode = AVAudioPlayerNode()

            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: pitchNode, format: audioFile.processingFormat)

            playerNode.volume = volume
            playerNode.scheduleFile(audioFile, at: nil) {
                // Clean up player node after playback
                DispatchQueue.main.async { [weak self] in
                    self?.audioEngine.detach(playerNode)
                }
            }
            playerNode.play()

        } catch {
            print("Failed to play sound with reverb: \(error)")
        }
    }

    private func preloadSounds() {
        // Preload existing sounds with normalized volume (0.5 = 50% volume)
        shootSound = createSoundAction(fileName: "shoot-sound.mp3", volume: 0.2)
        explosionSound = createSoundAction(fileName: "explosion.mp3", volume: 0.5)
        powerUpSound = createSoundAction(fileName: "power-up.mp3", volume: 0.5)
        coinSound = createSoundAction(fileName: "coin.mp3", volume: 0.4)
        hitSound = createSoundAction(fileName: "hit.mp3", volume: 0.5)
        gameOverSound = createSoundAction(fileName: "game-over.mp3", volume: 0.6)
        levelCompleteSound = createSoundAction(fileName: "level-complete.mp3", volume: 0.6)
        buttonClickSound = createSoundAction(fileName: "button-click.mp3", volume: 0.3)
        buttonHoverSound = createSoundAction(fileName: "button-hover.mp3", volume: 0.2)
        menuSelectSound = createSoundAction(fileName: "menu-select.mp3", volume: 0.4)
        pauseSound = createSoundAction(fileName: "pause.mp3", volume: 0.4)
        resumeSound = createSoundAction(fileName: "resume.mp3", volume: 0.4)
        shieldActivateSound = createSoundAction(fileName: "shield-activate.mp3", volume: 0.5)
        shieldDeactivateSound = createSoundAction(fileName: "shield-deactivate.mp3", volume: 0.4)
        shieldHitSound = createSoundAction(fileName: "shield-hit.mp3", volume: 0.5)
        extraLifeSound = createSoundAction(fileName: "extra-life.mp3", volume: 0.6)
        bossAppearSound = createSoundAction(fileName: "boss-appear.mp3", volume: 0.7)
        bossAppearSound = createSoundAction(fileName: "boss-appear.mp3", volume: 0.7)
        bossDefeatSound = createSoundAction(fileName: "boss-defeat.mp3", volume: 0.7)
        bossHitSound = createSoundAction(fileName: "boss-hit.mp3", volume: 0.5)
        enemyShootSound = createSoundAction(fileName: "enemy-shoot.mp3", volume: 0.3)
        missileSound = createSoundAction(fileName: "missile.mp3", volume: 0.5)
        lightningSound = createSoundAction(fileName: "lightning.mp3", volume: 0.6)
        warningSound = createSoundAction(fileName: "warning.mp3", volume: 0.5)
        countdownSound = createSoundAction(fileName: "countdown.mp3", volume: 0.5)
        levelStartSound = createSoundAction(fileName: "level-start.mp3", volume: 0.6)
        playerSpawnSound = createSoundAction(fileName: "player-spawn.mp3", volume: 0.5)
        playerExitSound = createSoundAction(fileName: "player-exit.mp3", volume: 0.4)
        asteroidHitSound = createSoundAction(fileName: "asteroid-hit.mp3", volume: 0.2)
        obstacleHitSound = createSoundAction(fileName: "obstacle-hit.mp3", volume: 0.4)
        magnetActivateSound = createSoundAction(fileName: "magnet-activate.mp3", volume: 0.5)
        slowMotionActivateSound = createSoundAction(fileName: "slow-motion.mp3", volume: 0.5)
        rapidFireActivateSound = createSoundAction(fileName: "rapid-fire.mp3", volume: 0.5)
        multiShotActivateSound = createSoundAction(fileName: "multi-shot.mp3", volume: 0.5)
        barrierActivateSound = createSoundAction(fileName: "barrier-activate.mp3", volume: 0.5)
        scoreMultiplierSound = createSoundAction(fileName: "score-multiplier.mp3", volume: 0.5)
        invulnerabilitySound = createSoundAction(fileName: "invulnerability.mp3", volume: 0.5)
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

    // MARK: - Background Music

    func startBackgroundMusic() {
        print("🎵 startBackgroundMusic called - isMusicEnabled: \(isMusicEnabled)")
        guard isMusicEnabled else {
            print("⚠️ Music is disabled")
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

        print("🎵 Attempting to load music: \(trackName)")

        // Try multiple methods to find the music file
        var musicURL: URL?

        // Method 1: Try subdirectory "Music"
        musicURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3", subdirectory: "Music")
        if musicURL != nil {
            print("✅ Found music in Music subdirectory")
        } else {
            print("⚠️ Not found in Music subdirectory, trying root...")
            // Method 2: Try root directory
            musicURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3")
            if musicURL != nil {
                print("✅ Found music in root directory")
            } else {
                print("⚠️ Not found in root, trying jetshot/Music...")
                // Method 3: Try jetshot/Music path
                musicURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3", subdirectory: "jetshot/Music")
                if musicURL != nil {
                    print("✅ Found music in jetshot/Music")
                }
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

                print("✅ Successfully playing music: \(trackName) at volume: \(musicVolume)")
            } catch {
                print("❌ Could not load music file: \(trackName), error: \(error)")
            }
        } else {
            print("❌ Could not find music file: \(trackName) anywhere in bundle")
            print("📦 Bundle path: \(Bundle.main.bundlePath)")
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
