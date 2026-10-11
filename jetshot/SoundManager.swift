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
    //
    // Readable so `jetshotTests` can tell a call that carried on with the playing
    // track from one that tore it down and rebuilt it — the difference between the
    // music running on across a screen change and jumping back to 0:00.
    private(set) var musicPlayer: AVAudioPlayer?

    /// The track `musicPlayer` holds, which is not always `currentMusicResource`.
    ///
    /// While the music is switched off, `setMusicForLevel` moves the selection on
    /// without touching the paused player, so the two drift apart. Switching it back on
    /// used to resume that player as it was, playing the previous level's track for the
    /// rest of the level.
    private(set) var musicPlayerResource: String?

    /// A track on its way out under a fade (see `endSpecificMusic`), held so it is not
    /// released mid-fade.
    private var fadingMusicPlayer: AVAudioPlayer?

    /// The last level track selected, which a one-off track hands back to when it ends.
    private var rotationResource: String?

    /// Exposed so `jetshotTests` can assert every track is actually in the bundle.
    /// A renamed or unbundled track is otherwise silent at runtime, which is exactly
    /// how five sound effects once shipped referencing files that were never added.
    nonisolated static let musicExtension = "m4a"
    nonisolated static let musicTracks = [
        "music-1", "music-2", "music-3", "music-4", "music-5", "music-6", "music-7"
    ]
    /// One-off track played under the story films, outside the level rotation.
    nonisolated static let storyMusicTrack = "music-story"

    /// Resource name of the track that *should* be playing.
    ///
    /// Tracked by name rather than by index into `musicTracks`, because the story
    /// track is not in that array at all. With an index, an unexpected stop during
    /// the story crawl (see `audioPlayerDidFinishPlaying`) restarted whatever level
    /// track the index happened to point at instead of the story music.
    private(set) var currentMusicResource: String?

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
        configureAudioSession()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// Puts the session in `.ambient`, once, before anything plays.
    ///
    /// `.ambient`, not `.playback`: game audio is non-primary, so it has to honour the
    /// ring/silent switch. `.playback` ignores it, which made the game play music out
    /// loud on a phone the player had deliberately silenced. `.ambient` also mixes with
    /// other apps by default, so an explicit .mixWithOthers option is not needed.
    ///
    /// This used to be set only on the way into a music track, so with the music
    /// switched off the session stayed at the system default, `.soloAmbient` — which
    /// does not mix, and the first sound effect stopped whatever the player had on (their
    /// own music, a podcast). SpriteKit's effects go through this same shared session,
    /// so it is set here, as the manager comes up; `AppDelegate` brings it up at launch.
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        } catch {
            #if DEBUG
            print("❌ Could not set the audio session category: \(error)")
            #endif
        }
    }

    /// Picks the music back up when the player returns to the game.
    ///
    /// Only a player that already exists is touched: with none, nothing has asked for
    /// music yet, and starting the rotation here at launch would race the first scene's
    /// own choice of track. Nothing pauses the music on purpose except the music switch,
    /// which `resumeMusic()` honours — the pause menu leaves it playing.
    @objc private func handleAppDidBecomeActive() {
        guard musicPlayer != nil else { return }
        resumeMusic()
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
            // `.shouldResume` used to be required, and it is often absent, which left
            // the music silent until the next screen change. It is a hint for apps whose
            // audio would take over from someone else's; this music is ambient and mixes
            // with everything, so there is no one to defer to. Resume now if the game is
            // in front — otherwise `handleAppDidBecomeActive()` does it on the way back.
            guard options.contains(.shouldResume)
                    || UIApplication.shared.applicationState == .active else { return }
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
        guard resolveEffect(fileName) != nil else { return nil }
        return SKAction.playSoundFileNamed(fileName, waitForCompletion: false)
    }

    /// The bundled file behind an effect, recorded in `requestedEffectResources` (and
    /// `missingEffectResources` when it is not there) whichever way the effect plays.
    private func resolveEffect(_ fileName: String) -> URL? {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        requestedEffectResources.append(fileName)

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            missingEffectResources.append(fileName)
            #if DEBUG
            print("❌ Missing sound resource in bundle: \(fileName)")
            assertionFailure("Sound file '\(fileName)' is referenced but not present in the app bundle")
            #endif
            return nil
        }
        return url
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

        detachedPlayers = [:]
        for fileName in Self.detachedEffects {
            guard let url = resolveEffect(fileName),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            detachedPlayers[fileName] = player
        }
    }

    // MARK: - Rate limiting

    /// When each effect last started, keyed by its action.
    private var lastStarted: [ObjectIdentifier: CFTimeInterval] = [:]

    /// Whether an effect may start now, recording it if so.
    ///
    /// `playSoundFileNamed` neither stops nor ducks a sound already playing, so a cue
    /// fired faster than it decays piles up into a roar. That was tolerable at the old
    /// 3.3 shots a second; with a dense stream of fire, dozens of hits a second on a
    /// boss whose hit cue alone runs three seconds, and shards and grazes ticking in
    /// between, the mix turned to mush. Each high-frequency cue now has a floor on how
    /// often it may restart. Real time, not the gameplay clock: this is about what the
    /// speaker can carry.
    private func admit(_ sound: SKAction, minInterval: CFTimeInterval) -> Bool {
        let key = ObjectIdentifier(sound)
        let now = CACurrentMediaTime()
        if let last = lastStarted[key], now - last < minInterval { return false }
        lastStarted[key] = now
        return true
    }

    // MARK: - Existing Sound Effects

    func playShootSound(on node: SKNode) {
        guard isSoundEnabled, let sound = shootSound else { return }
        guard admit(sound, minInterval: 0.1) else { return }
        node.run(sound)
    }

    func playExplosionSound(on node: SKNode) {
        guard isSoundEnabled, let sound = explosionSound else { return }
        guard admit(sound, minInterval: 0.06) else { return }
        node.run(sound)
    }

    func playPowerUpSound(on node: SKNode) {
        guard isSoundEnabled, let sound = powerUpSound else { return }
        node.run(sound)
    }

    func playCoinSound(on node: SKNode) {
        guard isSoundEnabled, let sound = coinSound else { return }
        guard admit(sound, minInterval: 0.07) else { return }
        node.run(sound)
    }

    func playHitSound(on node: SKNode) {
        guard isSoundEnabled, let sound = hitSound else { return }
        guard admit(sound, minInterval: 0.1) else { return }
        node.run(sound)
    }

    // MARK: - Effects that outlive their scene

    /// Cues fired by a scene in the act of leaving: the game-over and level-complete
    /// jingles, and the click of a button that presents the next screen on the spot.
    ///
    /// Every other effect is an SKAction run on a node, and an action only starts when
    /// its node's actions are next evaluated. These were queued on the outgoing scene a
    /// moment before `presentScene(_:transition:)`, which pauses that scene for the fade
    /// (`SKTransition.pausesOutgoingScene`) and then tears it down — so the action never
    /// got to run and the cue never played. They go through players of their own here,
    /// which belong to no scene.
    private static let detachedEffects = ["game-over.mp3", "level-complete.mp3", "button-click.mp3"]

    /// One player per `detachedEffects` cue, by file name. Readable for `jetshotTests`.
    private(set) var detachedPlayers: [String: AVAudioPlayer] = [:]

    private func playDetached(_ fileName: String) {
        guard isSoundEnabled, let player = detachedPlayers[fileName] else { return }
        // Full volume, as `playSoundFileNamed` plays every other effect.
        player.currentTime = 0
        player.play()
    }

    func playGameOverSound() {
        playDetached("game-over.mp3")
    }

    func playLevelCompleteSound() {
        playDetached("level-complete.mp3")
    }

    /// The button click, for a tap that presents the next scene straight away — with no
    /// press animation to give `playButtonClickSound(on:)` a frame to start in.
    func playSceneExitClickSound() {
        playDetached("button-click.mp3")
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
        guard admit(sound, minInterval: 0.12) else { return }
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
        guard admit(sound, minInterval: 0.16) else { return }
        node.run(sound)
    }

    // MARK: - Weapon Sound Effects

    func playEnemyShootSound(on node: SKNode) {
        guard isSoundEnabled, let sound = enemyShootSound else { return }
        guard admit(sound, minInterval: 0.08) else { return }
        node.run(sound)
    }

    func playMissileSound(on node: SKNode) {
        guard isSoundEnabled, let sound = missileSound else { return }
        guard admit(sound, minInterval: 0.3) else { return }
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
        guard admit(sound, minInterval: 0.12) else { return }
        node.run(sound)
    }

    func playObstacleHitSound(on node: SKNode) {
        guard isSoundEnabled, let sound = obstacleHitSound else { return }
        guard admit(sound, minInterval: 0.12) else { return }
        node.run(sound)
    }

    // MARK: - Special Enemy Sound Effects

    func playAbsorbSound(on node: SKNode) {
        guard isSoundEnabled, let sound = absorbSound else { return }
        guard admit(sound, minInterval: 0.2) else { return }
        node.run(sound)
    }

    func playReflectSound(on node: SKNode) {
        guard isSoundEnabled, let sound = reflectSound else { return }
        guard admit(sound, minInterval: 0.15) else { return }
        node.run(sound)
    }

    func playShieldBlockSound(on node: SKNode) {
        guard isSoundEnabled, let sound = shieldBlockSound else { return }
        guard admit(sound, minInterval: 0.12) else { return }
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

    /// Makes sure the selected track is playing, carrying on from where it is.
    ///
    /// Every screen calls this as it arrives. It used to rebuild the player whatever was
    /// already playing, so the music jumped back to 0:00 on nearly every screen change
    /// (menu, level select, victory screen) — `setMusicForLevel` had a guard against
    /// exactly that, and this did not.
    func startBackgroundMusic() {
        guard isMusicEnabled else { return }
        ensurePlaying(currentMusicResource ?? Self.musicTracks[0])
    }

    /// Selects and starts the track belonging to a level.
    func setMusicForLevel(_ level: Int) {
        // `level` is 1-based, but a caller passing 0 or a negative value would make
        // the remainder negative and trap on the subscript.
        let index = (max(1, level) - 1) % Self.musicTracks.count
        let resource = Self.musicTracks[index]

        currentMusicResource = resource
        rotationResource = resource
        guard isMusicEnabled else { return }
        // Already playing the right thing: left alone rather than restarted from the
        // top, so consecutive levels that share a track play continuously.
        ensurePlaying(resource)
    }

    /// Plays a one-off track that is not part of the level rotation (the story films).
    ///
    /// Always from the top, unlike the rotation: the story music is cut to its film.
    func playSpecificMusic(named resource: String) {
        currentMusicResource = resource
        guard isMusicEnabled else { return }
        play(resource: resource)
    }

    /// Ends a one-off track and hands the music back to the level rotation.
    ///
    /// The story films used to end with `stopBackgroundMusic()` and
    /// `startBackgroundMusic()`, but the selection was still the story track, so that
    /// only restarted it: after the opening it played a second from the top before the
    /// level's own track cut in, and after the ending it carried on under the victory
    /// screen and the menu. The selection now goes back to the last level track, and
    /// the story track fades out under the film's own fade rather than being cut. The
    /// next screen starts the rotation track as it arrives, as every screen does.
    func endSpecificMusic(fadeDuration: TimeInterval) {
        guard let ending = currentMusicResource, !Self.musicTracks.contains(ending) else { return }
        currentMusicResource = rotationResource

        guard let player = musicPlayer, musicPlayerResource == ending else { return }
        musicPlayer = nil
        musicPlayerResource = nil
        fadeOut(player, over: fadeDuration)
    }

    func stopBackgroundMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
        musicPlayerResource = nil
        stopFadingMusic()
    }

    func pauseMusic() {
        musicPlayer?.pause()
        // Or a track still fading out plays on for a moment after the switch is off.
        stopFadingMusic()
    }

    /// Resumes the music — the selected track, not necessarily the one that was paused.
    /// See `musicPlayerResource`.
    func resumeMusic() {
        startBackgroundMusic()
    }

    /// Plays `resource`: on in the player that already holds it (resumed if paused),
    /// or in a new one when the player holds another track or there is none.
    private func ensurePlaying(_ resource: String) {
        if let player = musicPlayer, musicPlayerResource == resource {
            if !player.isPlaying { player.play() }
            return
        }
        play(resource: resource)
    }

    /// How long a track coming in under one that is fading out takes to reach full
    /// volume.
    private static let crossfadeIn: TimeInterval = 1.0

    private func fadeOut(_ player: AVAudioPlayer, over duration: TimeInterval) {
        stopFadingMusic()
        fadingMusicPlayer = player
        player.setVolume(0, fadeDuration: duration)
        // Compared by identity rather than by capturing the player, so a later fade
        // that has replaced this one is left alone.
        let fading = ObjectIdentifier(player)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, let player = self.fadingMusicPlayer,
                  ObjectIdentifier(player) == fading else { return }
            self.stopFadingMusic()
        }
    }

    private func stopFadingMusic() {
        fadingMusicPlayer?.stop()
        fadingMusicPlayer = nil
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
            // The category is set once, in `configureAudioSession()`.
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
            // Coming in under a track that is fading out (the end of a story film):
            // rise under it rather than land at full volume on top of it.
            if fadingMusicPlayer != nil {
                player.volume = 0
                player.play()
                player.setVolume(musicVolume, fadeDuration: Self.crossfadeIn)
            } else {
                player.play()
            }
            musicPlayer = player
            musicPlayerResource = resource
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
        //
        // Only for the current player: one already let go of (a fading one) ending says
        // nothing about the track that should be playing now.
        guard flag, player === musicPlayer, isMusicEnabled,
              let resource = currentMusicResource else { return }
        play(resource: resource)
    }
}
