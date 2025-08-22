//
//  AudioFeedbackManager.swift
//  guido-1
//
//  Created by AI Assistant on [Current Date]
//

import Foundation
import AVFoundation
import Combine

/// Manages audio feedback for user experience - connection tones, thinking sounds, and completion notifications
@MainActor
class AudioFeedbackManager: ObservableObject {
    
    // MARK: - Audio Players
    private var connectionPlayer: AVAudioPlayer?
    private var thinkingPlayer: AVAudioPlayer?
    private var completionPlayer: AVAudioPlayer?
    
    // MARK: - Settings
    @Published var isEnabled: Bool = true
    @Published var volume: Float = 0.7
    
    // MARK: - State (minimal - most feedback handled by AI)
    
    // MARK: - External State Checking
    weak var realtimeService: OpenAIRealtimeService?
    
    // MARK: - Croatian Beach Theme Audio Frequencies
    private struct AudioTones {
        static let connectionFreqs: [Float] = [523.25, 659.25, 783.99]  // C-E-G major chord
        // Thinking and completion tones removed - AI handles these through voice
    }
    
    init() {
        setupAudioSession()
        generateSystemTones()
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use playback category for better compatibility with system audio
            try audioSession.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            try audioSession.setActive(true)
            print("✅ Audio feedback session configured")
        } catch {
            print("❌ Failed to setup audio feedback session: \(error)")
        }
    }
    
    // MARK: - System Tone Generation
    private func generateSystemTones() {
        // Generate connection tone only - AI handles thinking/completion through voice
        connectionPlayer = createHarmonicTone(frequencies: AudioTones.connectionFreqs, duration: 0.4, type: .rising)
        
        // Disabled - AI provides its own audio feedback
        thinkingPlayer = nil
        completionPlayer = nil
        
        print("✅ Connection tone generated (thinking/completion handled by AI)")
    }
    
    // MARK: - Modern Audio Generation
    
    enum ToneType {
        case rising     // Frequencies play in sequence, rising
        case gentle     // Soft harmonic blend
        case chord      // All frequencies together as a chord
    }
    
    private func createHarmonicTone(frequencies: [Float], duration: Double, type: ToneType) -> AVAudioPlayer? {
        let sampleRate: Float = 44100.0
        let samples = Int(sampleRate * Float(duration))
        
        // Create proper WAV header
        var audioData = Data()
        
        // WAV header (44 bytes)
        let dataSize = UInt32(samples * 2) // 16-bit samples
        let fileSize = dataSize + 36
        
        // RIFF header
        audioData.append("RIFF".data(using: .ascii)!)
        audioData.append(Data(bytes: [UInt8(fileSize & 0xFF), UInt8((fileSize >> 8) & 0xFF), UInt8((fileSize >> 16) & 0xFF), UInt8((fileSize >> 24) & 0xFF)]))
        audioData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        audioData.append("fmt ".data(using: .ascii)!)
        audioData.append(Data(bytes: [16, 0, 0, 0])) // chunk size
        audioData.append(Data(bytes: [1, 0])) // PCM format
        audioData.append(Data(bytes: [1, 0])) // mono
        
        // Sample rate (44100)
        let sr = UInt32(sampleRate)
        audioData.append(Data(bytes: [UInt8(sr & 0xFF), UInt8((sr >> 8) & 0xFF), UInt8((sr >> 16) & 0xFF), UInt8((sr >> 24) & 0xFF)]))
        
        // Byte rate
        let byteRate = UInt32(sampleRate * 2)
        audioData.append(Data(bytes: [UInt8(byteRate & 0xFF), UInt8((byteRate >> 8) & 0xFF), UInt8((byteRate >> 16) & 0xFF), UInt8((byteRate >> 24) & 0xFF)]))
        
        audioData.append(Data(bytes: [2, 0])) // block align
        audioData.append(Data(bytes: [16, 0])) // bits per sample
        
        // data chunk
        audioData.append("data".data(using: .ascii)!)
        audioData.append(Data(bytes: [UInt8(dataSize & 0xFF), UInt8((dataSize >> 8) & 0xFF), UInt8((dataSize >> 16) & 0xFF), UInt8((dataSize >> 24) & 0xFF)]))
        
        // Generate modern harmonic audio samples
        for i in 0..<samples {
            let time = Float(i) / sampleRate
            let progress = time / Float(duration)
            
            // Enhanced envelope with smooth curves
            var envelope: Float = 1.0
            let fadeInTime: Float = 0.1  // Longer, smoother fade
            let fadeOutTime: Float = 0.2
            
            if progress < fadeInTime {
                // Smooth exponential fade in
                envelope = pow(progress / fadeInTime, 0.5)
            } else if progress > (1.0 - fadeOutTime) {
                // Smooth exponential fade out
                let fadeProgress = (progress - (1.0 - fadeOutTime)) / fadeOutTime
                envelope = pow(1.0 - fadeProgress, 0.5)
            }
            
            var sample: Float = 0.0
            
            switch type {
            case .rising:
                // Play frequencies in sequence with smooth transitions
                let segmentDuration = Float(duration) / Float(frequencies.count)
                let segmentIndex = min(Int(time / segmentDuration), frequencies.count - 1)
                let segmentProgress = (time - Float(segmentIndex) * segmentDuration) / segmentDuration
                
                let frequency = frequencies[segmentIndex]
                // Add subtle harmonics for richness
                sample = sin(2.0 * Float.pi * frequency * time) * 0.6
                sample += sin(2.0 * Float.pi * frequency * 2.0 * time) * 0.2 // Second harmonic
                sample += sin(2.0 * Float.pi * frequency * 3.0 * time) * 0.1 // Third harmonic
                
                // Smooth transition between segments
                if segmentProgress < 0.1 && segmentIndex > 0 {
                    let prevFreq = frequencies[segmentIndex - 1]
                    let prevSample = sin(2.0 * Float.pi * prevFreq * time) * 0.6
                    sample = sample * segmentProgress / 0.1 + prevSample * (1.0 - segmentProgress / 0.1)
                }
                
            case .gentle:
                // Blend two frequencies with gentle modulation
                for (index, frequency) in frequencies.enumerated() {
                    let weight = index == 0 ? 0.7 : 0.3
                    let modulation = 1.0 + 0.1 * sin(2.0 * Float.pi * 2.0 * time) // Gentle tremolo
                    sample += sin(2.0 * Float.pi * frequency * time) * Float(weight) * modulation
                }
                sample *= 0.5 // Normalize
                
            case .chord:
                // Play all frequencies as a harmonic chord
                for frequency in frequencies {
                    sample += sin(2.0 * Float.pi * frequency * time)
                }
                sample /= Float(frequencies.count) // Normalize by frequency count
                sample *= 0.4 // Reduce overall amplitude for chord
            }
            
            // Apply envelope and convert to 16-bit
            sample *= envelope * 0.3 // Overall volume control
            let intSample = Int16(max(-32767, min(32767, sample * 32767.0)))
            
            // Convert to little-endian bytes
            audioData.append(UInt8(intSample & 0xFF))
            audioData.append(UInt8((intSample >> 8) & 0xFF))
        }
        
        do {
            let player = try AVAudioPlayer(data: audioData)
            player.volume = volume
            player.prepareToPlay()
            return player
        } catch {
            print("❌ Failed to create tone player: \(error)")
            return nil
        }
    }
    
    // MARK: - Public Interface
    
    /// Play connection established sound
    func playConnectionSound() {
        guard isEnabled, let player = connectionPlayer else { return }
        print("🔊 Playing connection sound")
        
        // Ensure audio session is active
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Could not activate audio session for connection sound")
        }
        
        player.volume = volume
        if player.play() {
            print("✅ Connection sound played successfully")
        } else {
            print("⚠️ Failed to play connection sound")
        }
    }
    
    /// Play thinking/processing sound - DISABLED (AI handles its own audio feedback)
    func playThinkingSound() {
        // Disabled - AI will handle thinking acknowledgment through voice
        print("🔇 Thinking sound disabled - AI handles audio feedback")
    }
    
    /// Stop thinking sounds and state - DISABLED
    func stopThinkingSound() {
        print("🔇 Stop thinking sound disabled - AI handles audio feedback")
    }
    
    /// Play completion sound when AI finishes speaking - DISABLED (AI handles its own audio feedback)
    func playCompletionSound() {
        // Disabled - AI will handle completion acknowledgment through voice
        print("🔇 Completion sound disabled - AI handles audio feedback")
    }
    
    /// Play disconnection sound
    func playDisconnectionSound() {
        guard isEnabled else { return }
        print("🔊 Playing disconnection sound")
        
        // Create a simple descending tone for disconnection
        if let disconnectPlayer = createHarmonicTone(frequencies: [400.0, 300.0], duration: 0.5, type: .rising) {
            disconnectPlayer.volume = volume * 0.6
            if disconnectPlayer.play() {
                print("✅ Disconnection sound played successfully")
            } else {
                print("⚠️ Failed to play disconnection sound")
            }
        }
    }
    

    

    
    // MARK: - Volume Control
    func setVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
        connectionPlayer?.volume = volume
        thinkingPlayer?.volume = volume * 0.8
        completionPlayer?.volume = volume
    }
    
    // MARK: - Enable/Disable
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            stopThinkingSound()
        }
    }
    

}

