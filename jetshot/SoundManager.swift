//
//  SoundManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import AVFoundation
import AudioToolbox

class SoundManager {

    static let shared = SoundManager()

    private var audioEngine: AVAudioEngine
    private var playerNodes: [AVAudioPlayerNode] = []
    private let audioFormat: AVAudioFormat
    private let maxPolyphony: Int = 8 // Maximum simultaneous sounds

    // Cached pre-generated sound buffers for optimal performance
    private var soundCache: [String: AVAudioPCMBuffer] = [:]

    private init() {
        audioEngine = AVAudioEngine()

        // Create consistent audio format
        audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        // Create multiple player nodes for polyphony
        for _ in 0..<maxPolyphony {
            let node = AVAudioPlayerNode()
            audioEngine.attach(node)
            audioEngine.connect(node, to: audioEngine.mainMixerNode, format: audioFormat)
            playerNodes.append(node)
        }

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }

        // Pre-generate all sounds once for performance
        preGenerateAllSounds()
    }

    private func preGenerateAllSounds() {
        // Generate and cache all sound effects
        soundCache["shoot"] = generateLaserShot(frequency: 1200, sweepTo: 900, duration: 0.08, volume: 0.25)
        soundCache["enemyShoot"] = generateLaserShot(frequency: 700, sweepTo: 500, duration: 0.1, volume: 0.2)
        soundCache["explosion"] = generateNoiseBurst(frequency: 200, duration: 0.15, volume: 0.4)
        soundCache["bossExplosion"] = generateNoiseBurst(frequency: 150, duration: 0.2, volume: 0.45)
        soundCache["hit1"] = generateNoiseBurst(frequency: 800, duration: 0.08, volume: 0.3)
        soundCache["hit2"] = generateTone(frequency: 1500, duration: 0.06, volume: 0.25, envelope: .exponentialDecay)
        soundCache["powerUp1"] = generateTone(frequency: 400, duration: 0.08, volume: 0.3, envelope: .fadeOut)
        soundCache["powerUp2"] = generateTone(frequency: 600, duration: 0.08, volume: 0.3, envelope: .fadeOut)
        soundCache["powerUp3"] = generateTone(frequency: 900, duration: 0.1, volume: 0.35, envelope: .fadeOut)
        soundCache["shieldActivate1"] = generateTone(frequency: 300, duration: 0.15, volume: 0.35, envelope: .fadeIn)
        soundCache["shieldActivate2"] = generateTone(frequency: 500, duration: 0.2, volume: 0.3, envelope: .fadeOut)
        soundCache["shieldDeactivate1"] = generateTone(frequency: 500, duration: 0.15, volume: 0.3, envelope: .fadeOut)
        soundCache["shieldDeactivate2"] = generateTone(frequency: 250, duration: 0.15, volume: 0.25, envelope: .exponentialDecay)
        soundCache["uiClick"] = generateTone(frequency: 1000, duration: 0.05, volume: 0.25, envelope: .exponentialDecay)
        soundCache["pause"] = generateTone(frequency: 800, duration: 0.08, volume: 0.25, envelope: .fadeOut)
        soundCache["resume1"] = generateTone(frequency: 600, duration: 0.08, volume: 0.25, envelope: .fadeOut)
        soundCache["resume2"] = generateTone(frequency: 800, duration: 0.08, volume: 0.25, envelope: .fadeOut)
        soundCache["bossWarning"] = generateTone(frequency: 200, duration: 0.2, volume: 0.35, envelope: .pulse)

        // Game over notes
        soundCache["gameOver1"] = generateTone(frequency: 659, duration: 0.25, volume: 0.3, envelope: .fadeOut)
        soundCache["gameOver2"] = generateTone(frequency: 523, duration: 0.25, volume: 0.3, envelope: .fadeOut)
        soundCache["gameOver3"] = generateTone(frequency: 440, duration: 0.25, volume: 0.3, envelope: .fadeOut)
        soundCache["gameOver4"] = generateTone(frequency: 330, duration: 0.25, volume: 0.3, envelope: .fadeOut)
    }

    // MARK: - Game Sound Effects (optimized to use cached buffers)

    /// Play player shoot sound - crisp laser shot
    func playShoot() {
        playCachedSound("shoot")
    }

    /// Play enemy shoot sound - lower pitched
    func playEnemyShoot() {
        playCachedSound("enemyShoot")
    }

    /// Play explosion sound - short and immediate
    func playExplosion() {
        playCachedSound("explosion")
    }

    /// Play boss explosion - slightly more dramatic but still short
    func playBossExplosion() {
        playCachedSound("bossExplosion")
    }

    /// Play hit sound - sharp impact
    func playHit() {
        playCachedSound("hit1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.playCachedSound("hit2")
        }
    }

    /// Play powerup collection sound
    func playPowerUp() {
        playCachedSound("powerUp1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.playCachedSound("powerUp2")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.playCachedSound("powerUp3")
        }
    }

    /// Play shield activation sound
    func playShieldActivate() {
        playCachedSound("shieldActivate1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.playCachedSound("shieldActivate2")
        }
    }

    /// Play shield deactivation sound
    func playShieldDeactivate() {
        playCachedSound("shieldDeactivate1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.playCachedSound("shieldDeactivate2")
        }
    }

    /// Play button/UI click sound
    func playUIClick() {
        playCachedSound("uiClick")
    }

    /// Play game over sound
    func playGameOver() {
        playCachedSound("gameOver1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.playCachedSound("gameOver2")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.playCachedSound("gameOver3")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.playCachedSound("gameOver4")
        }
    }

    /// Play boss warning sound
    func playBossWarning() {
        playCachedSound("bossWarning")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.playCachedSound("bossWarning")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.playCachedSound("bossWarning")
        }
    }

    /// Play pause sound
    func playPause() {
        playCachedSound("pause")
    }

    /// Play resume sound
    func playResume() {
        playCachedSound("resume1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.playCachedSound("resume2")
        }
    }

    private func playCachedSound(_ key: String) {
        guard let buffer = soundCache[key] else {
            print("Warning: Sound '\(key)' not found in cache")
            return
        }
        scheduleBuffer(buffer)
    }

    // MARK: - Sound Generation Methods (renamed to generate* for pre-caching)

    private enum Envelope {
        case fadeOut
        case fadeIn
        case exponentialDecay
        case pulse
    }

    private func generateLaserShot(frequency startFreq: Float, sweepTo endFreq: Float, duration: TimeInterval, volume: Float) -> AVAudioPCMBuffer? {
        let sampleRate = audioFormat.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return nil }
        let channels = UnsafeBufferPointer(start: channelData, count: Int(audioFormat.channelCount))
        let floats = UnsafeMutableBufferPointer<Float>(start: channels[0], count: Int(frameCount))

        // Generate frequency sweep with sharp attack
        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)

            // Frequency sweep from high to low
            let frequency = startFreq + (endFreq - startFreq) * progress

            let angularFrequency = Float(2.0 * Double.pi * Double(frequency) / sampleRate)
            let sample = sin(angularFrequency * Float(frame))

            // Sharp attack, quick decay envelope
            let envelope = 1.0 - pow(progress, 1.5)
            floats[frame] = sample * volume * envelope
        }

        return buffer
    }

    private func generateNoiseBurst(frequency: Float, duration: TimeInterval, volume: Float) -> AVAudioPCMBuffer? {
        let sampleRate = audioFormat.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return nil }
        let channels = UnsafeBufferPointer(start: channelData, count: Int(audioFormat.channelCount))
        let floats = UnsafeMutableBufferPointer<Float>(start: channels[0], count: Int(frameCount))

        // Generate filtered noise for more realistic explosion
        let angularFrequency = Float(2.0 * Double.pi * Double(frequency) / sampleRate)

        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)

            // Mix sine wave with noise for more complex sound
            let tone = sin(angularFrequency * Float(frame))
            let noise = Float.random(in: -1...1) * 0.5
            let mixed = tone * 0.5 + noise * 0.5

            // Exponential decay envelope
            let envelope = pow(1.0 - progress, 2.0)
            floats[frame] = mixed * volume * envelope
        }

        return buffer
    }

    private func generateTone(frequency: Float, duration: TimeInterval, volume: Float, envelope: Envelope) -> AVAudioPCMBuffer? {
        let sampleRate = audioFormat.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return nil }
        let channels = UnsafeBufferPointer(start: channelData, count: Int(audioFormat.channelCount))
        let floats = UnsafeMutableBufferPointer<Float>(start: channels[0], count: Int(frameCount))

        // Generate sine wave
        let angularFrequency = Float(2.0 * Double.pi * Double(frequency) / sampleRate)
        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)
            let sample = sin(angularFrequency * Float(frame))

            // Apply selected envelope
            let envelopeValue: Float
            switch envelope {
            case .fadeOut:
                envelopeValue = 1.0 - progress
            case .fadeIn:
                envelopeValue = progress
            case .exponentialDecay:
                envelopeValue = pow(1.0 - progress, 2.5)
            case .pulse:
                envelopeValue = sin(progress * .pi)
            }

            floats[frame] = sample * volume * envelopeValue
        }

        return buffer
    }

    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        // Find an available player node or use the first one
        var targetNode = playerNodes[0]

        for node in playerNodes {
            if !node.isPlaying {
                targetNode = node
                break
            }
        }

        targetNode.scheduleBuffer(buffer, completionHandler: nil)

        if !targetNode.isPlaying {
            targetNode.play()
        }
    }

    /// Stop all currently playing sounds
    func stopAllSounds() {
        for node in playerNodes {
            node.stop()
        }
    }
}
