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

    // Preloaded sound effects
    private var shootSound: SKAction?
    private var explosionSound: SKAction?
    private var powerUpSound: SKAction?
    private var coinSound: SKAction?
    private var hitSound: SKAction?
    private var gameOverSound: SKAction?
    private var levelCompleteSound: SKAction?

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
        // Preload all sounds for better performance
        shootSound = SKAction.playSoundFileNamed("retro-laser.mp3", waitForCompletion: false)
        explosionSound = SKAction.playSoundFileNamed("retro-explode.mp3", waitForCompletion: false)
        powerUpSound = SKAction.playSoundFileNamed("retro-powerup.mp3", waitForCompletion: false)
        coinSound = SKAction.playSoundFileNamed("retro-coin.mp3", waitForCompletion: false)
        hitSound = SKAction.playSoundFileNamed("retro-hurt.mp3", waitForCompletion: false)
        gameOverSound = SKAction.playSoundFileNamed("game-over-arcade.mp3", waitForCompletion: false)
        levelCompleteSound = SKAction.playSoundFileNamed("level-completed.mp3", waitForCompletion: false)
    }

    // MARK: - Sound Effects

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
}
