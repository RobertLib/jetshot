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
    private var playerNode: AVAudioPlayerNode
    private let audioFormat: AVAudioFormat

    private init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // Create consistent audio format
        audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    // MARK: - Sound Generation

    /// Play shoot sound - short high-pitched beep
    func playShoot() {
        playTone(frequency: 800, duration: 0.1, volume: 0.3)
    }

    /// Play explosion sound - lower frequency with decay
    func playExplosion() {
        playTone(frequency: 150, duration: 0.3, volume: 0.5)

        // Add second tone for richness
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.playTone(frequency: 100, duration: 0.25, volume: 0.4)
        }
    }

    /// Play hit sound - medium frequency
    func playHit() {
        playTone(frequency: 400, duration: 0.15, volume: 0.4)
    }

    // MARK: - Tone Generator

    private func playTone(frequency: Float, duration: TimeInterval, volume: Float) {
        let sampleRate = audioFormat.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return }
        let channels = UnsafeBufferPointer(start: channelData, count: Int(audioFormat.channelCount))
        let floats = UnsafeMutableBufferPointer<Float>(start: channels[0], count: Int(frameCount))

        // Generate sine wave
        let angularFrequency = Float(2.0 * Double.pi * Double(frequency) / sampleRate)
        for frame in 0..<Int(frameCount) {
            let sample = sin(angularFrequency * Float(frame))

            // Apply envelope (fade out) for smoother sound
            let envelope = 1.0 - (Float(frame) / Float(frameCount))
            floats[frame] = sample * volume * envelope
        }

        // Schedule and play buffer
        playerNode.scheduleBuffer(buffer, completionHandler: nil)

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    /// Play system sound (alternative for simple feedback)
    func playSystemSound() {
        AudioServicesPlaySystemSound(1057) // Simple click sound
    }

    /// Stop all currently playing sounds
    func stopAllSounds() {
        playerNode.stop()
    }
}
