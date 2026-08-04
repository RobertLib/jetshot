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
    //
    // Tracks are 128 kbps AAC (.m4a). They were 256 kbps MP3, which put 33 MB of
    // looping background music into a 51 MB app — over half the download for audio
    // no one listens to critically through a phone speaker.
    private var musicPlayer: AVAudioPlayer?

    /// Exposed so `jetshotTests` can assert every track is actually in the bundle.
    /// A renamed or unbundled track is otherwise silent at runtime, which is exactly
    /// how five sound effects once shipped referencing files that were never added.
    nonisolated static let musicExtension = "m4a"
    nonisolated static let musicTracks = [
        "music-1", "music-2", "music-3", "music-4", "music-5", "music-6", "music-7"
    ]
    /// One-off track played over the story crawl, outside the level rotation.
    nonisolated static let storyMusicTrack = "music-story"

    /// Resource name of the track that *should* be playing.
    ///
    /// Tracked by name rather than by index into `musicTracks`, because the story
    /// track is not in that array at all. With an index, an unexpected stop during
    /// the story crawl (see `audioPlayerDidFinishPlaying`) restarted whatever level
    /// track the index happened to point at instead of the story music.
    private var currentMusicResource: String?

    var isMusicEnabled: Bool {
        get {
            // Check if value was ever set, if not return true (enabled by default)
            guard UserDefaults.standard.object(forKey: "isMusicEnabled") != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: "isMusicEnabled")
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

    var musicVolume: Float = GameConfiguration.defaultMusicVolume {
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
            // Check if value was ever set, if not return true (enabled by default)
            guard UserDefaults.standard.object(forKey: "isSoundEnabled") != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: "isSoundEnabled")
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
        // Preload off the init call stack so startup isn't blocked, but stay on the
        // main queue: every stored action is read from the main thread by the
        // play* methods, and filling ~50 non-atomic properties from a background
        // queue was an unsynchronised write/read race.
        DispatchQueue.main.async { [weak self] in
            self?.preloadSounds()
        }
        // Handle audio session interruptions (alarms, phone calls, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            musicPlayer?.pause()
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            guard options.contains(.shouldResume) else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                #if DEBUG
                print("❌ Could not reactivate audio session after interruption: \(error)")
                #endif
            }
            resumeMusic()
        @unknown default:
            break
        }
    }

    // Helper function to create sound action
    // Note: SKAction.playSoundFileNamed doesn't support volume control - volume must be adjusted in the audio files themselves
    //
    // The resource is verified up front: playSoundFileNamed on a missing file does
    // not throw, it just logs "SKAction: Error loading sound resource" once and
    // then plays silence forever. That failure mode already shipped once (five
    // .wav effects were referenced but never added to the bundle), so a missing
    // file now returns nil and trips an assertion in debug builds instead.
    private func createSoundAction(fileName: String) -> SKAction? {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        requestedEffectResources.append(fileName)

        guard Bundle.main.url(forResource: name, withExtension: ext) != nil else {
            missingEffectResources.append(fileName)
            #if DEBUG
            print("❌ Missing sound resource in bundle: \(fileName)")
            assertionFailure("Sound file '\(fileName)' is referenced but not present in the app bundle")
            #endif
            return nil
        }

        return SKAction.playSoundFileNamed(fileName, waitForCompletion: false)
    }

    /// Every effect file `preloadSounds()` asked for, in the order it asked.
    ///
    /// Recorded as it runs rather than declared up front, because the only other place
    /// this list existed was a hand-copied duplicate of all 42 names inside
    /// `AudioResourceTests`. That copy was correct only while someone remembered to
    /// edit both — a newly added cue would have been silently untested, which is the
    /// exact failure mode (a referenced file that is not bundled plays silence) the
    /// test exists to catch. Reading it back off the manager cannot drift.
    private(set) var requestedEffectResources: [String] = []

    /// The subset of `requestedEffectResources` that could not be resolved in the
    /// bundle, and will therefore play silence.
    private(set) var missingEffectResources: [String] = []

    /// Not private so `jetshotTests` can drive it synchronously: `init` schedules it on
    /// the main queue, and a test that raced that dispatch would inspect empty lists.
    /// Idempotent — every property it touches is unconditionally reassigned.
    func preloadSounds() {
        requestedEffectResources.removeAll()
        missingEffectResources.removeAll()

        // Preload sound effects
        shootSound = createSoundAction(fileName: "shoot-sound.mp3")
        explosionSound = createSoundAction(fileName: "explosion.mp3")
        powerUpSound = createSoundAction(fileName: "power-up.mp3")
        coinSound = createSoundAction(fileName: "coin.mp3")
        hitSound = createSoundAction(fileName: "hit.mp3")
        gameOverSound = createSoundAction(fileName: "game-over.mp3")
        levelCompleteSound = createSoundAction(fileName: "level-complete.mp3")
        buttonClickSound = createSoundAction(fileName: "button-click.mp3")
        // No hover effect: nothing on a touch screen can hover, so the button-hover
        // cue had no caller and its file has been dropped from the bundle.
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
        // These five effects originally pointed at absorb.wav / reflect.wav /
        // shield_block.wav / laser_charge.wav / laser_fire.wav, which were never
        // added to the project — so vortex absorption, mirror reflection, shield
        // blocks and the boss laser were all silent. Remapped onto the closest
        // existing effects; swap in dedicated files here if they get recorded.
        absorbSound = createSoundAction(fileName: "ghost-phase.mp3")
        reflectSound = createSoundAction(fileName: "shield-hit.mp3")
        shieldBlockSound = createSoundAction(fileName: "shield-hit.mp3")
        laserChargeSound = createSoundAction(fileName: "mine-arm.mp3")
        laserFireSound = createSoundAction(fileName: "lightning.mp3")
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

    /// Starts (or restarts) whichever track is currently selected.
    func startBackgroundMusic() {
        guard isMusicEnabled else { return }
        play(resource: currentMusicResource ?? Self.musicTracks[0])
    }

    /// Selects and starts the track belonging to a level.
    func setMusicForLevel(_ level: Int) {
        // `level` is 1-based, but a caller passing 0 or a negative value would make
        // the remainder negative and trap on the subscript.
        let index = (max(1, level) - 1) % Self.musicTracks.count
        let resource = Self.musicTracks[index]

        // Already playing the right thing: leave it alone rather than restarting it
        // from the top, so consecutive levels that share a track play continuously.
        if currentMusicResource == resource, musicPlayer?.isPlaying == true {
            return
        }

        currentMusicResource = resource
        guard isMusicEnabled else { return }
        play(resource: resource)
    }

    /// Plays a one-off track that is not part of the level rotation (the story crawl).
    func playSpecificMusic(named resource: String) {
        currentMusicResource = resource
        guard isMusicEnabled else { return }
        play(resource: resource)
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

    /// Single loader for every music track.
    ///
    /// This used to be two near-identical methods, each trying three bundle
    /// locations in turn: `subdirectory: "Music"`, then the bundle root, then
    /// `subdirectory: "jetshot/Music"`. The build flattens the `Music` folder into
    /// the bundle root, so the first lookup *always* failed (logging a warning on
    /// every single track load) and the third was unreachable. One lookup at the
    /// place the files actually are is the whole job.
    private func play(resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: Self.musicExtension) else {
            #if DEBUG
            print("❌ Missing music resource in bundle: \(resource).\(Self.musicExtension)")
            assertionFailure("Music file '\(resource).\(Self.musicExtension)' is referenced but not present in the app bundle")
            #endif
            return
        }

        do {
            // `.ambient`, not `.playback`: game audio is non-primary, so it has to
            // honour the ring/silent switch. `.playback` ignores it, which made the
            // game play music out loud on a phone the player had deliberately
            // silenced. `.ambient` also mixes with other apps by default, so an
            // explicit .mixWithOthers option is not needed.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            // Stop the outgoing player explicitly rather than relying on it being
            // torn down when the property is reassigned.
            musicPlayer?.stop()

            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = musicVolume
            player.delegate = self
            // Loop. Without this the player ran to the end of the file and
            // audioPlayerDidFinishPlaying() advanced to the next track, which made
            // setMusicForLevel()'s whole point — one specific track per level —
            // evaporate the moment that track ended.
            player.numberOfLoops = -1
            player.prepareToPlay()
            player.play()
            musicPlayer = player
        } catch {
            #if DEBUG
            print("❌ Could not play music file \(resource).\(Self.musicExtension): \(error)")
            #endif
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}


// MARK: - AVAudioPlayerDelegate

extension SoundManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Players loop indefinitely (numberOfLoops = -1), so reaching here at all
        // means playback stopped for some reason other than the track ending.
        // Restart the current track rather than advancing: which track plays is a
        // property of the level, decided by setMusicForLevel(_:).
        guard flag, isMusicEnabled, let resource = currentMusicResource else { return }
        play(resource: resource)
    }
}
