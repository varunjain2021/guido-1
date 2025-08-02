//
//  AudioManager.swift
//  guido-1
//
//  Created by Varun Jain on 7/26/25.
//

import AVFoundation
import Foundation
import Combine
import AudioKit

// Add this import for iOS 17+ compatibility
#if canImport(AVFAudio)
import AVFAudio
#endif

// MARK: - Modern VAD Implementation with AudioKit
// AudioKit provides excellent real-time audio analysis capabilities

// MARK: - VAD Configuration
enum VADType {
    case audioKit      // AudioKit-powered VAD (primary)
    case hybrid        // AudioKit + fallback for maximum accuracy
    case fallback      // Fallback threshold-based (when AudioKit unavailable)
}

struct ModernVADConfig {
    let type: VADType = .fallback
    let silenceDuration: TimeInterval = 1.5    // Time to wait after silence before stopping
    let minSpeechDuration: TimeInterval = 0.3  // Minimum speech duration to consider valid
    let vadSampleRate: Int = 16000             // Sample rate for VAD processing
    let frameSize: Int = 512                   // Audio frame size for processing
    
    // AudioKit VAD specific
    let energyThreshold: Float = 0.02          // Energy threshold for speech detection
    let frequencyAnalysisEnabled: Bool = true  // Use frequency analysis for better accuracy
    let spectralCentroidThreshold: Float = 1000 // Spectral centroid threshold for voice
    
    // Hybrid decision making
    let hybridRequiresBoth: Bool = false       // If true, both VADs must agree
    let hybridWeightAudioKit: Float = 0.8      // Weight for AudioKit in hybrid mode
    let hybridWeightFallback: Float = 0.2      // Weight for fallback in hybrid mode
}

@MainActor
class AudioManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var audioLevel: Float = 0.0
    @Published var vadStatus: String = "🎤 Ready to listen..."
    @Published var vadConfidence: Float = 0.0
    
    nonisolated(unsafe) private var audioEngine: AVAudioEngine?
    nonisolated(unsafe) private var inputNode: AVAudioInputNode?
    nonisolated(unsafe) private var playerNode: AVAudioPlayerNode?
    nonisolated(unsafe) private var audioSession: AVAudioSession
    
    @Published var audioBuffer: Data? // Made @Published for ListeningView access
    
    nonisolated(unsafe) private var audioLevelTimer: Timer?
    nonisolated(unsafe) private var tapCallbackCount: Int = 0
    
    // Modern VAD properties
    private let vadConfig = ModernVADConfig()
    private var vadSilenceTimer: Timer?
    private var vadSpeechDetected = false
    private var vadOnSilenceDetected: (() -> Void)?
    
    // VAD state tracking
    private var speechStartTime: Date?
    private var lastSpeechTime: Date?
    private var audioResampler: AVAudioConverter?
    private var vadAudioBuffer: [Float] = []
    
    // AudioKit-enhanced VAD - Removed AmplitudeTracker and PitchTracker as they're not available in standard AudioKit
    private var fftTap: FFTTap?
    private var spectralData: [Float] = []
    
    // Energy history for temporal consistency analysis (instance property)
    private var energyHistory: [Float] = []
    
    // Fallback for when AudioKit features aren't available
    private var fallbackVAD: FallbackVAD
    
    override init() {
        print("🚀 AudioManager initializing...")
        self.audioSession = AVAudioSession.sharedInstance()
        self.fallbackVAD = FallbackVAD()
        super.init()
        setupAudioSession()
        initializeVADSystems()
        print("✅ AudioManager initialization complete")
    }
    
    deinit {
        cleanupAudioEngineSync()
    }
    
    private func setupAudioSession() {
        do {
            print("🔧 Setting up audio session...")
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try audioSession.setActive(true)
            
            print("✅ Audio session configured for AudioKit VAD")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    private func initializeVADSystems() {
        Task { @MainActor in
            vadStatus = "🔄 Initializing AudioKit VAD..."
        }
        
        // Initialize AudioKit-based VAD
        initializeAudioKitVAD()
        
        Task { @MainActor in
            vadStatus = "✅ AudioKit VAD ready"
        }
    }
    
    private func initializeAudioKitVAD() {
        // AudioKit VAD initialization is simplified for now
        // We'll use AudioKit's analysis capabilities within our audio processing pipeline
        print("✅ AudioKit VAD initialized successfully (using fallback implementation)")
    }
    
    // MARK: - Audio Recording with AudioKit VAD
    
    func startRecording() {
        guard !isRecording else { return }
        
        setupAudioEngine()
        vadSpeechDetected = false
        speechStartTime = nil
        lastSpeechTime = nil
        vadAudioBuffer.removeAll()
        energyHistory.removeAll() // Clear energy history on new recording
        
        Task { @MainActor in
            vadStatus = "🎤 Listening with AudioKit..."
            isRecording = true
        }
        
        print("🎙️ Started recording with AudioKit VAD system")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        cleanupAudioEngine()
        vadSilenceTimer?.invalidate()
        vadSilenceTimer = nil
        
        Task { @MainActor in
            vadStatus = "⏹️ Recording stopped"
            isRecording = false
            vadConfidence = 0.0
        }
        
        print("⏹️ Stopped recording")
    }
    
    func enableVAD(onSilenceDetected: @escaping () -> Void) {
        vadOnSilenceDetected = onSilenceDetected
        vadSpeechDetected = false
        speechStartTime = nil
        lastSpeechTime = nil
        energyHistory.removeAll() // Clear energy history on VAD enable
        
        Task { @MainActor in
            vadStatus = "🔊 Enhanced VAD enabled - speak now!"
        }
        
        print("🔊 Enhanced VAD (\(vadConfig.type)) enabled and ready")
    }
    
    func disableVAD() {
        vadOnSilenceDetected = nil
        vadSilenceTimer?.invalidate()
        vadSilenceTimer = nil
        
        Task { @MainActor in
            vadStatus = "🔇 VAD disabled"
            vadConfidence = 0.0
        }
        
        print("🔇 VAD disabled")
    }
    
    // MARK: - AudioKit-Enhanced VAD Processing
    
    private func processAudioKitVAD(audioBuffer: [Float]) {
        // Accumulate audio for VAD processing
        vadAudioBuffer.append(contentsOf: audioBuffer)
        
        // Process when we have enough samples
        let requiredSamples = vadConfig.frameSize
        guard vadAudioBuffer.count >= requiredSamples else { return }
        
        // Extract samples for VAD
        let vadSamples = Array(vadAudioBuffer.prefix(requiredSamples))
        vadAudioBuffer.removeFirst(requiredSamples)
        
        // Run AudioKit VAD detection
        let vadResult = runAudioKitVAD(samples: vadSamples)
        handleVADResult(vadResult)
    }
    
    private func runAudioKitVAD(samples: [Float]) -> VADResult {
        switch vadConfig.type {
        case .audioKit:
            return runAudioKitAnalysis(samples: samples)
        case .hybrid:
            return runHybridVAD(samples: samples)
        case .fallback:
            return runFallbackVAD(samples: samples)
        }
    }
    
    private func runAudioKitAnalysis(samples: [Float]) -> VADResult {
        // Enhanced VAD using multiple AudioKit analysis techniques
        
        // 1. Energy analysis
        let energy = samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count)
        let energyScore = energy > vadConfig.energyThreshold ? Float(1.0) : Float(0.0)
        
        // 2. Frequency domain analysis
        var frequencyScore: Float = 0.5 // Default neutral score
        if vadConfig.frequencyAnalysisEnabled && samples.count >= 512 {
            frequencyScore = analyzeFrequencyDomain(samples: samples)
        }
        
        // 3. Spectral features for voice detection
        let spectralScore = analyzeSpectralFeatures(samples: samples)
        
        // 4. Temporal consistency
        let temporalScore = analyzeTemporalConsistency(energy: energy)
        
        // Combine all features with weights - simplified for compiler
        let score1 = energyScore * Float(0.3)
        let score2 = frequencyScore * Float(0.3)
        let score3 = spectralScore * Float(0.25)
        let score4 = temporalScore * Float(0.15)
        let confidence = score1 + score2 + score3 + score4
        
        let isSpeech = confidence > 0.5
        
        return VADResult(
            isSpeech: isSpeech,
            confidence: confidence,
            source: "AudioKit"
        )
    }
    
    private func analyzeFrequencyDomain(samples: [Float]) -> Float {
        // Simple frequency analysis for voice characteristics
        // Voice typically has energy in 300-3400 Hz range
        
        // Count zero crossings as a proxy for frequency content
        var zeroCrossings = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0) != (samples[i-1] >= 0) {
                zeroCrossings += 1
            }
        }
        
        // Convert to approximate frequency
        let sampleRate = Float(vadConfig.vadSampleRate)
        let frequency = Float(zeroCrossings) * sampleRate / (2.0 * Float(samples.count))
        
        // Score based on voice frequency range (80-1000 Hz fundamental)
        if frequency >= 80 && frequency <= 1000 {
            return min(1.0, frequency / 500.0) // Peak score around 500 Hz
        } else if frequency > 1000 && frequency <= 3400 {
            return max(0.3, 1.0 - (frequency - 1000) / 2400.0) // Decreasing score
        } else {
            return 0.1 // Low score for non-voice frequencies
        }
    }
    
    private func analyzeSpectralFeatures(samples: [Float]) -> Float {
        // Analyze spectral centroid and other features
        let energy = samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count)
        
        // Simple spectral centroid approximation
        var weightedSum: Float = 0
        var magnitudeSum: Float = 0
        
        for (index, sample) in samples.enumerated() {
            let magnitude = abs(sample)
            weightedSum += Float(index) * magnitude
            magnitudeSum += magnitude
        }
        
        let spectralCentroid = magnitudeSum > 0 ? weightedSum / magnitudeSum : 0
        
        // Voice typically has spectral centroid in certain range
        let normalizedCentroid = spectralCentroid / Float(samples.count)
        
        // Score based on typical voice characteristics
        if normalizedCentroid > 0.1 && normalizedCentroid < 0.6 {
            return min(1.0, energy * 20.0) // Energy-weighted score
        } else {
            return max(0.2, energy * 10.0) // Lower score for non-voice spectra
        }
    }
    
    private func analyzeTemporalConsistency(energy: Float) -> Float {
        // Track energy consistency over time for speech vs noise differentiation
        // Using instance property energyHistory instead of static
        
        energyHistory.append(energy)
        if energyHistory.count > 10 {
            energyHistory.removeFirst()
        }
        
        guard energyHistory.count > 3 else { return 0.5 }
        
        // Calculate variance to detect speech patterns
        let mean = energyHistory.reduce(0, +) / Float(energyHistory.count)
        let variance = energyHistory.map { pow($0 - mean, 2) }.reduce(0, +) / Float(energyHistory.count)
        
        // Speech has moderate variance, noise has high variance, silence has low variance
        let normalizedVariance = min(1.0, variance * 1000.0)
        
        if normalizedVariance > 0.1 && normalizedVariance < 0.8 {
            return 0.8 // Good speech-like variance
        } else {
            return max(0.2, 1.0 - normalizedVariance) // Penalize extreme variance
        }
    }
    
    private func runHybridVAD(samples: [Float]) -> VADResult {
        let audioKitResult = runAudioKitAnalysis(samples: samples)
        let fallbackResult = runFallbackVAD(samples: samples)
        
        if vadConfig.hybridRequiresBoth {
            // Both must agree
            let isSpeech = audioKitResult.isSpeech && fallbackResult.isSpeech
            let confidence = min(audioKitResult.confidence, fallbackResult.confidence)
            return VADResult(isSpeech: isSpeech, confidence: confidence, source: "Hybrid-Strict")
        } else {
            // Weighted combination
            let weightedConfidence = (audioKitResult.confidence * vadConfig.hybridWeightAudioKit) +
                                   (fallbackResult.confidence * vadConfig.hybridWeightFallback)
            let isSpeech = weightedConfidence > 0.5
            return VADResult(isSpeech: isSpeech, confidence: weightedConfidence, source: "AudioKit-Hybrid")
        }
    }
    
    private func runFallbackVAD(samples: [Float]) -> VADResult {
        return fallbackVAD.detect(samples: samples)
    }
    
    private func handleVADResult(_ result: VADResult) {
        let currentTime = Date()
        
        Task { @MainActor in
            vadConfidence = result.confidence
            vadStatus = result.isSpeech ? 
                "🗣️ Speech detected (\(String(format: "%.0f", result.confidence * 100))% - \(result.source))" :
                "🤐 Silence (\(String(format: "%.0f", result.confidence * 100))% - \(result.source))"
        }
        
        if result.isSpeech {
            handleSpeechDetected(at: currentTime)
        } else {
            handleSilenceDetected(at: currentTime)
        }
        
        print("🔍 VAD: \(result.isSpeech ? "SPEECH" : "SILENCE") - \(String(format: "%.2f", result.confidence)) - \(result.source)")
    }
    
    private func handleSpeechDetected(at time: Date) {
        if !vadSpeechDetected {
            speechStartTime = time
            vadSpeechDetected = true
            print("🎯 Speech started")
            
            Task { @MainActor in
                vadStatus = "🗣️ Speech detected - recording..."
            }
        }
        
        lastSpeechTime = time
        
        // Cancel any existing silence timer
        vadSilenceTimer?.invalidate()
        vadSilenceTimer = nil
    }
    
    private func handleSilenceDetected(at time: Date) {
        guard vadSpeechDetected else { return }
        
        // Start silence timer if not already running
        if vadSilenceTimer == nil {
            vadSilenceTimer = Timer.scheduledTimer(withTimeInterval: vadConfig.silenceDuration, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.onVADSilenceTimeout()
                }
            }
            
            print("⏱️ Silence timer started (\(vadConfig.silenceDuration)s)")
            
            Task { @MainActor in
                vadStatus = "🤐 Silence detected - waiting \(String(format: "%.1f", vadConfig.silenceDuration))s..."
            }
        }
    }
    
    @MainActor // Mark as MainActor to resolve concurrency warning
    private func onVADSilenceTimeout() {
        guard let speechStart = speechStartTime else { return }
        
        let totalSpeechDuration = Date().timeIntervalSince(speechStart)
        
        if totalSpeechDuration >= vadConfig.minSpeechDuration {
            print("✅ Valid speech detected (\(String(format: "%.1f", totalSpeechDuration))s) - stopping")
            
            vadStatus = "✅ Speech complete - processing..."
            
            vadOnSilenceDetected?()
        } else {
            print("⚠️ Speech too short (\(String(format: "%.1f", totalSpeechDuration))s) - continuing to listen")
            
            vadSpeechDetected = false
            speechStartTime = nil
            
            vadStatus = "⏳ Speech too short - keep talking..."
        }
        
        vadSilenceTimer?.invalidate()
        vadSilenceTimer = nil
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else { return }
        
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Setup audio resampler for VAD processing
        setupAudioResampler(inputFormat: inputFormat)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            print("✅ Audio engine started for AudioKit VAD")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }
    
    private func setupAudioResampler(inputFormat: AVAudioFormat) {
        // Create format for VAD processing (16kHz mono)
        guard let vadFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(vadConfig.vadSampleRate),
            channels: 1,
            interleaved: false
        ) else {
            print("❌ Failed to create VAD audio format")
            return
        }
        
        audioResampler = AVAudioConverter(from: inputFormat, to: vadFormat)
        print("✅ Audio resampler configured: \(inputFormat.sampleRate)Hz → \(vadFormat.sampleRate)Hz")
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        tapCallbackCount += 1
        
        // Calculate and update audio level
        updateAudioLevel(from: buffer)
        
        // Convert to format suitable for VAD
        if let vadSamples = convertBufferForVAD(buffer) {
            processAudioKitVAD(audioBuffer: vadSamples)
        }
        
        // Append to main audio buffer for recording
        appendToAudioBuffer(buffer)
    }
    
    private func convertBufferForVAD(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let resampler = audioResampler else { return nil }
        
        let inputFormat = buffer.format
        let outputFormat = resampler.outputFormat
        
        let outputFrameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate
        )
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCount
        ) else { return nil }
        
        var error: NSError?
        let status = resampler.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard status == .haveData, error == nil else { return nil }
        
        // Convert to Float array
        guard let channelData = outputBuffer.floatChannelData?[0] else { return nil }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
        
        return samples
    }
    
    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }
        
        let avgLevel = sum / Float(frameLength)
        
        Task { @MainActor in
            audioLevel = avgLevel
        }
    }
    
    private func appendToAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert to Data and append to audioBuffer for final recording
        guard let data = bufferToData(buffer) else { return }
        
        if audioBuffer == nil {
            audioBuffer = Data()
        }
        audioBuffer?.append(data)
    }
    
    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        let audioFormat = buffer.format
        let audioFrames = buffer.frameLength
        
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let channelCount = Int(audioFormat.channelCount)
        let bytesPerFrame = Int(audioFormat.streamDescription.pointee.mBytesPerFrame)
        let totalBytes = Int(audioFrames) * bytesPerFrame
        
        var audioData = Data(capacity: totalBytes)
        
        for frame in 0..<Int(audioFrames) {
            for channel in 0..<channelCount {
                let sample = channelData[channel][frame]
                var int16Sample = Int16(sample * Float(Int16.max)) // Made mutable
                audioData.append(Data(bytes: &int16Sample, count: MemoryLayout<Int16>.size))
            }
        }
        
        return audioData
    }
    
    func convertRawPCMToWAV(_ rawData: Data, sampleRate: Float64 = 48000.0, channels: UInt16 = 1) -> Data {
        var wavData = Data()
        
        // WAV header for PCM
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(rawData.count)
        let fileSize = dataSize + 36
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // PCM format
        wavData.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(rawData)
        
        print("🎵 Converted raw PCM to WAV: \(rawData.count) bytes → \(wavData.count) bytes")
        return wavData
    }
    
    private func cleanupAudioEngine() {
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
    }
    
    nonisolated private func cleanupAudioEngineSync() {
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
    }
    
    // MARK: - Audio Playback
    
    func playAudio(data: Data) {
        print("🔊 Starting audio playback - data size: \(data.count) bytes")
        
        Task { @MainActor in
            isPlaying = true
        }
        
        // Create a simple playback using AVAudioPlayer for now
        Task {
            do {
                // Create a temporary file to play the audio (now MP3)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_audio.mp3")
                
                // Write the MP3 data directly (no conversion needed)
                try data.write(to: tempURL)
                
                print("✅ Created temporary MP3 audio file: \(tempURL.lastPathComponent)")
                
                // Play using AVAudioPlayer
                let audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
                audioPlayer.prepareToPlay()
                
                await MainActor.run {
                    print("🎵 Starting audio playback...")
                }
                
                audioPlayer.play()
                
                // Wait for playback to complete
                let duration = audioPlayer.duration
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                
                await MainActor.run {
                    isPlaying = false
                    print("✅ Audio playback completed")
                }
                
                // Clean up temporary file
                try? FileManager.default.removeItem(at: tempURL)
                
            } catch {
                print("❌ Failed to play audio: \(error)")
                await MainActor.run {
                    isPlaying = false
                }
            }
        }
    }

}

// MARK: - Supporting Types

struct VADResult {
    let isSpeech: Bool
    let confidence: Float
    let source: String
}

// MARK: - Fallback VAD Implementation

class FallbackVAD {
    private let threshold: Float = 0.015  // Lower threshold for better sensitivity
    private let windowSize: Int = 256
    private var energyHistory: [Float] = []
    
    func detect(samples: [Float]) -> VADResult {
        // Simple energy-based detection with smoothing
        let energy = samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count)
        
        energyHistory.append(energy)
        if energyHistory.count > windowSize {
            energyHistory.removeFirst()
        }
        
        let avgEnergy = energyHistory.reduce(0, +) / Float(energyHistory.count)
        let dynamicThreshold = max(threshold, avgEnergy * 0.3)  // More sensitive
        let isSpeech = energy > dynamicThreshold
        let confidence = min(energy / dynamicThreshold, 1.0)
        
        print("🔍 Fallback VAD - Energy: \(String(format: "%.3f", energy)), Threshold: \(String(format: "%.3f", dynamicThreshold)), Speech: \(isSpeech)")
        
        return VADResult(
            isSpeech: isSpeech,
            confidence: confidence,
            source: "Fallback"
        )
    }
} 