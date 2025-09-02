//
//  OpenAIRealtimeService.swift
//  guido-1
//
//  Created by Varun Jain on 7/27/25.
//

import Foundation
import AVFoundation
import Combine

// MARK: - Realtime Event Types
struct RealtimeEvent: Codable {
    let type: String
    let eventId: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
    }
}

struct SessionUpdateEvent: Codable {
    let type: String = "session.update"
    let eventId: String
    let session: SessionConfig
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case session
    }
    
    struct SessionConfig: Codable {
        let modalities: [String]?
        let instructions: String?
        let voice: String?
        let inputAudioFormat: String?
        let outputAudioFormat: String?
        let inputAudioTranscription: TranscriptionConfig?
        let turnDetection: TurnDetectionConfig?
        let temperature: Double?
        let maxResponseOutputTokens: String?
        let toolChoice: String?
        let tools: [RealtimeToolDefinition]?
        
        // Default initializer for full config
        init(instructions: String, voice: String, inputAudioFormat: String, outputAudioFormat: String, inputAudioTranscription: TranscriptionConfig?, turnDetection: TurnDetectionConfig?, temperature: Double?, maxResponseOutputTokens: String?, toolChoice: String?, tools: [RealtimeToolDefinition]?) {
            self.modalities = ["text", "audio"]
            self.instructions = instructions
            self.voice = voice
            self.inputAudioFormat = inputAudioFormat
            self.outputAudioFormat = outputAudioFormat
            self.inputAudioTranscription = inputAudioTranscription
            self.turnDetection = turnDetection
            self.temperature = temperature
            self.maxResponseOutputTokens = maxResponseOutputTokens
            self.toolChoice = toolChoice
            self.tools = tools
        }
        
        // Refresh initializer for VAD maintenance (minimal update)
        init(inputAudioFormat: String?, outputAudioFormat: String?, inputAudioTranscription: TranscriptionConfig?, turnDetection: TurnDetectionConfig?) {
            self.modalities = nil
            self.instructions = nil
            self.voice = nil
            self.inputAudioFormat = inputAudioFormat
            self.outputAudioFormat = outputAudioFormat
            self.inputAudioTranscription = inputAudioTranscription
            self.turnDetection = turnDetection
            self.temperature = nil
            self.maxResponseOutputTokens = nil
            self.toolChoice = nil
            self.tools = nil
        }
        
        enum CodingKeys: String, CodingKey {
            case modalities, instructions, voice
            case inputAudioFormat = "input_audio_format"
            case outputAudioFormat = "output_audio_format"
            case inputAudioTranscription = "input_audio_transcription"
            case turnDetection = "turn_detection"
            case temperature
            case maxResponseOutputTokens = "max_response_output_tokens"
            case toolChoice = "tool_choice"
            case tools
        }
        
        struct TranscriptionConfig: Codable {
            let model: String
            let language: String?
            
            init() {
                self.model = "whisper-1"
                self.language = "en"
            }
            
            enum CodingKeys: String, CodingKey {
                case model
                case language
            }
        }
        
        struct TurnDetectionConfig: Codable {
            let type: String
            let eagerness: String?
            let threshold: Double?
            let silenceDurationMs: Int?
            let prefixPaddingMs: Int?
            // These are critical for automatic response generation
            let createResponse: Bool = true      // Auto-create responses after speech ends
            let interruptResponse: Bool = true   // Allow graceful interruptions
            
            init() {
                if OpenAIRealtimeService.VADConfig.useSemanticVAD {
                    self.type = "semantic_vad"
                    self.eagerness = OpenAIRealtimeService.VADConfig.semanticEagerness
                    self.threshold = nil
                    self.silenceDurationMs = nil
                    self.prefixPaddingMs = nil
                } else {
                    self.type = "server_vad"
                    self.eagerness = nil
                    // Use optimized threshold for better speech detection  
                    self.threshold = round(OpenAIRealtimeService.VADConfig.serverThreshold * 10) / 10
                    self.silenceDurationMs = OpenAIRealtimeService.VADConfig.serverSilenceDuration
                    self.prefixPaddingMs = OpenAIRealtimeService.VADConfig.serverPrefixPadding
                }
            }
            
            enum CodingKeys: String, CodingKey {
                case type, eagerness, threshold
                case silenceDurationMs = "silence_duration_ms"
                case prefixPaddingMs = "prefix_padding_ms"
                case createResponse = "create_response"
                case interruptResponse = "interrupt_response"
            }
        }
    }
}

struct InputAudioBufferAppendEvent: Codable {
    let type: String = "input_audio_buffer.append"
    let eventId: String
    let audio: String // Base64 encoded audio
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case audio
    }
}

struct ResponseCreateEvent: Codable {
    let type: String = "response.create"
    let eventId: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
    }
}

struct InputAudioBufferCommitEvent: Codable {
    let type: String = "input_audio_buffer.commit"
    let eventId: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
    }
}

// MARK: - Incoming Event Types
struct IncomingEvent: Codable {
    let type: String
    let eventId: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
    }
}

struct AudioTranscriptEvent: Codable {
    let type: String
    let eventId: String
    let responseId: String?
    let itemId: String?
    let outputIndex: Int?
    let contentIndex: Int?
    let delta: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case delta
    }
}

struct AudioTranscriptCompletedEvent: Codable {
    let type: String
    let eventId: String
    let responseId: String?
    let itemId: String?
    let outputIndex: Int?
    let contentIndex: Int?
    let transcript: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case transcript
    }
}

struct AudioDeltaEvent: Codable {
    let type: String
    let eventId: String?
    let delta: String // Base64 encoded audio
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case delta
    }
}

// MARK: - Service Implementation
@MainActor
class OpenAIRealtimeService: NSObject, ObservableObject {
    
    // MARK: - VAD Configuration
    fileprivate enum VADConfig {
        static let useSemanticVAD = true  // Prefer semantic VAD per latest API guidance
        static let semanticEagerness = "medium"  
        // Simple VAD settings - keeping default sensitivity for natural conversation
        static let serverThreshold: Double = 0.6  // Slightly higher for fewer false positives
        static let serverSilenceDuration = 300   // Faster turn close per docs examples
        static let serverPrefixPadding = 300     // Longer padding for better detection
        
        // Minimum speech duration threshold (easily adjustable for testing)
        // Original: 0.6s | Testing: 0.3s | Revert to 0.6s if issues arise
        static let minimumSpeechDuration: Double = 0.5  // Longer minimum to prevent chime detection
    }
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    @Published var conversation: [RealtimeMessage] = []
    @Published var isAIResponding = false
    @Published var conversationState: ConversationState = .idle
    @Published var audioLevel: Float = 0.0
    
    // Debug state tracking
    private var lastClearBufferTime: TimeInterval = 0
    private var lastResponseCompleteTime: TimeInterval = 0
    
    // MARK: - Enhanced Tool Call Interruption State
    private var isToolExecuting = false
    private var currentResponseId: String?
    private var pendingToolCalls: Set<String> = []
    private var lastToolStartTime: TimeInterval = 0
    
    enum ConversationState {
        case idle
        case listening
        case processing 
        case speaking
        case thinking
    }
    
    private let apiKey: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession

    
    // Audio capture and playback - moved from RealtimeAudioManager
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioSession: AVAudioSession
    
    // Audio playback - Streaming solution using AVAudioPlayerNode
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioMixerNode: AVAudioMixerNode?
    // Optional output dynamics to avoid clipping
    private var audioLimiterNode: AVAudioUnitEQ?
    private var streamingAudioBuffer: Data = Data()
    private var isPlayingQueue = false
    private let audioPlayerLock = NSLock()
    // Audio formats for different purposes
    private let pcm24Format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!
    private var engineOutputFormat: AVAudioFormat?
    private var audioConverter: AVAudioConverter?
    // Input resampler: mic format -> 24kHz Int16 mono for OpenAI
    private var inputConverter: AVAudioConverter?
    // Logging toggles
    private let enableVerboseAudioLogging = false
    private let enableAudioQualityLogs = true
    private let enablePlaybackSchedulingLogs = true
    // Background queue for scheduling/playback to avoid main thread contention
    private let playbackQueue = DispatchQueue(label: "OpenAIRealtimeService.playback", qos: .userInitiated)
    // Output gain headroom (dB). Negative values reduce level to prevent clipping
    private let outputHeadroomDb: Float = -3.0
    
    // Audio output quality instrumentation
    private struct AudioOutputStats {
        var chunkCount: Int = 0
        var dropCount: Int = 0
        var totalBytes: Int = 0
        var lastAppendAt: TimeInterval = 0
        var interarrivalMsMax: Double = 0
        var interarrivalMsSum: Double = 0
        var queueDepthMax: Int = 0
        var convertMsSum: Double = 0
        var peakMax: Double = 0
        var rmsSum: Double = 0
        var firstDeltaAt: TimeInterval = 0
        var firstPlayAt: TimeInterval = 0
    }
    private var audioOutStats = AudioOutputStats()
    private func resetAudioOutStats() {
        audioOutStats = AudioOutputStats()
    }
    private func printAudioQualitySummary(tag: String, isFinal: Bool) {
        guard enableAudioQualityLogs else { return }
        let n = max(1, audioOutStats.chunkCount)
        let meanIat = (audioOutStats.chunkCount > 1) ? (audioOutStats.interarrivalMsSum / Double(audioOutStats.chunkCount - 1)) : 0
        let meanConvert = audioOutStats.convertMsSum / Double(n)
        let meanRms = audioOutStats.rmsSum / Double(n)
        let startLagMs = (audioOutStats.firstPlayAt > 0 && audioOutStats.firstDeltaAt > 0) ? (audioOutStats.firstPlayAt - audioOutStats.firstDeltaAt) * 1000.0 : 0
        let prefix = isFinal ? "📈 [AUDIO-QUALITY]" : "📈 [AUDIO-QUALITY SNAPSHOT]"
        print("\(prefix) tag=\(tag) chunks=\(audioOutStats.chunkCount), drops=\(audioOutStats.dropCount), bytes=\(audioOutStats.totalBytes), queueDepthMax=\(audioOutStats.queueDepthMax)")
        print("\(prefix) tag=\(tag) iat_ms(mean/max)=\(String(format: "%.1f/%.1f", meanIat, audioOutStats.interarrivalMsMax)) convert_ms(mean)=\(String(format: "%.2f", meanConvert)) start_lag_ms=\(String(format: "%.1f", startLagMs))")
        print("\(prefix) tag=\(tag) peak_max=\(String(format: "%.3f", audioOutStats.peakMax)) rms_mean=\(String(format: "%.3f", meanRms))")
        if isFinal { resetAudioOutStats() }
    }
    

    
    // Tool management
    @Published var toolManager = MCPToolCoordinator()
    
    // Audio feedback management
    @Published var audioFeedbackManager = AudioFeedbackManager()
    
    // Event handling
    private var eventSubscriptions = Set<AnyCancellable>()
    
    // Timing tracking
    private var speechStartTime: TimeInterval = 0
    private var speechTimeoutTimer: Timer?
    private var commitFallbackWorkItem: DispatchWorkItem?
    private var lastServerSpeechStartTime: TimeInterval = 0
    private var lastServerSpeechStopTime: TimeInterval = 0
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.urlSession = URLSession.shared
        self.audioSession = AVAudioSession.sharedInstance()
        super.init()
        setupAudioSession()
        print("🚀 OpenAI Realtime Service initialized")
    }
    

    
    deinit {
        // Ensure proper cleanup
        speechTimeoutTimer?.invalidate()
        speechTimeoutTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        eventSubscriptions.removeAll()
        print("🗑️ OpenAI Realtime Service deallocated")
    }
    

    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            // Configure for optimized voice input with headphone support
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [
                .allowBluetoothA2DP, 
                .allowBluetooth,
                .mixWithOthers
            ])
            
            // Set preferred sample rate and buffer duration for better voice capture
            try audioSession.setPreferredSampleRate(24000)
            try audioSession.setPreferredIOBufferDuration(0.020) // 20ms for smoother streaming playback
            
            try audioSession.setActive(true)
            print("✅ Audio session configured for optimized voice input with enhanced sensitivity")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Audio Capture
    private func startAudioCapture() {
        print("🎤 [AUDIO] Starting audio capture engine...")
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("❌ [AUDIO] Failed to create audio engine")
            return
        }
        
        inputNode = audioEngine.inputNode
        let inputFormat = inputNode?.outputFormat(forBus: 0)
        print("🎤 [AUDIO] Input format: \(inputFormat?.description ?? "unknown")")
        // Build input converter to match server-required format (24kHz Int16 mono)
        if let inFmt = inputFormat {
            inputConverter = AVAudioConverter(from: inFmt, to: pcm24Format)
            if let conv = inputConverter {
                print("🔄 [AUDIO] Mic input converter created: \(conv.inputFormat.sampleRate)Hz/\(conv.inputFormat.channelCount)ch -> \(conv.outputFormat.sampleRate)Hz/\(conv.outputFormat.channelCount)ch")
            } else {
                print("⚠️ [AUDIO] Failed to create mic input converter; relying on raw conversion")
            }
        }
        
        // Set up streaming audio nodes BEFORE starting the engine
        setupStreamingAudio()
        
        inputNode?.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // Calculate audio level for visualization (always)
            let audioLevel = self.calculateAudioLevel(from: buffer)
            Task { @MainActor in
                self.audioLevel = audioLevel
            }
            
            // Log audio state periodically
            if Int.random(in: 1...200) == 1 {
                print("🎤 [AUDIO] Audio state - isAIResponding: \(isAIResponding), isPlayingQueue: \(isPlayingQueue), level: \(audioLevel)")
            }
            
            // Block audio input while AI playback queue is active to avoid echo being transcribed
            guard !isPlayingQueue else { return }
            // Allow user to interrupt when AI is responding but not yet playing audio
            guard !isAIResponding else { return }
            
            let audioData = self.convertMicBufferToServerPCMData(buffer)
            if audioData.count > 0 {
                Task {
                    await self.sendAudioData(audioData)
                }
            }
        }
        
        do {
            try audioEngine.start()
            print("🎤 Audio capture started")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }
    
    private func stopAudioCapture() {
        // Stop audio playback first
        stopAudioPlayback()
        
        // Remove tap from input node
        inputNode?.removeTap(onBus: 0)
        
        // Stop audio engine safely
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        
        // Clear references
        audioEngine = nil
        inputNode = nil
        
        print("🔇 Audio capture and playback stopped")
    }
    
    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else {
            return 0.0
        }
        
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0.0
        
        for i in 0..<frameCount {
            sum += abs(channelData[i])
        }
        
        return sum / Float(frameCount)
    }
    
    private func convertMicBufferToServerPCMData(_ buffer: AVAudioPCMBuffer) -> Data {
        // Prefer AVAudioConverter for sample rate/channel/format conversion
        if let converter = inputConverter {
            let inFmt = buffer.format
            let outFmt = converter.outputFormat // 24kHz Int16 mono
            // Estimate destination frame capacity
            let ratio = outFmt.sampleRate / inFmt.sampleRate
            let dstCapacity = max(1, Int(Double(buffer.frameLength) * ratio) + 32)
            guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount(dstCapacity)) else {
                print("❌ [AUDIO] Failed to create dst buffer for input conversion")
            return Data()
        }
            var error: NSError?
            let status = converter.convert(to: dstBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if status == .error || error != nil {
                print("❌ [AUDIO] Mic convert error: \(error?.localizedDescription ?? "unknown")")
                return Data()
            }
            // Extract Int16 mono samples
            guard let i16 = dstBuffer.int16ChannelData?[0] else { return Data() }
            let frames = Int(dstBuffer.frameLength)
            let byteCount = frames * MemoryLayout<Int16>.size
            let data = Data(bytes: i16, count: byteCount)
            if enableVerboseAudioLogging {
                print("🎚️ [AUDIO] Mic chunk converted: src=\(buffer.frameLength) -> dst=\(dstBuffer.frameLength) @ \(outFmt.sampleRate)Hz")
            }
            return data
        }
        // Fallback: only if input is already mono Float32 at 24kHz
        if buffer.format.sampleRate == 24000,
           buffer.format.commonFormat == .pcmFormatFloat32,
           buffer.format.channelCount == 1,
           let channelData = buffer.floatChannelData?[0] {
        let frameCount = Int(buffer.frameLength)
        var int16Array = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let sample = channelData[i] * 32767.0
            int16Array[i] = Int16(max(-32767, min(32767, sample)))
        }
        return Data(bytes: int16Array, count: frameCount * MemoryLayout<Int16>.size)
        }
        // As a last resort, drop chunk to avoid corrupting server VAD with wrong sample rate
        if enableVerboseAudioLogging {
            print("⚠️ [AUDIO] Dropping mic chunk due to unsupported format (no converter)")
        }
        return Data()
    }
    
    // MARK: - Audio Playback - Streaming Solution
        private func playAudio(data: Data) {
        audioPlayerLock.lock()
        defer { audioPlayerLock.unlock() }
        
        // Final interruption check - don't queue audio if user interrupted
        if conversationState == .listening {
            print("🛑 [AUDIO] Refusing to queue audio - user interrupted")
            return
        }

        // Mark playback queue as active when we start receiving audio
        if !isPlayingQueue {
            isPlayingQueue = true
            print("🎵 [AUDIO] Playback queue started - blocking user input")
        }

        // Append and schedule on background queue to avoid main-thread contention
        playbackQueue.async { [weak self] in
            guard let self = self else { return }
            // Append new audio data to the streaming buffer
            self.streamingAudioBuffer.append(data)

            // Quality: track interarrival and queue depth
            if self.enableAudioQualityLogs {
                let now = CFAbsoluteTimeGetCurrent()
                if self.audioOutStats.firstDeltaAt == 0 { self.audioOutStats.firstDeltaAt = now }
                if self.audioOutStats.lastAppendAt > 0 {
                    let iatMs = (now - self.audioOutStats.lastAppendAt) * 1000.0
                    self.audioOutStats.interarrivalMsSum += iatMs
                    if iatMs > self.audioOutStats.interarrivalMsMax { self.audioOutStats.interarrivalMsMax = iatMs }
                }
                self.audioOutStats.lastAppendAt = now
                self.audioOutStats.totalBytes += data.count
                let queueDepth = self.streamingAudioBuffer.count / 960 // ~20ms@24k/16-bit
                if queueDepth > self.audioOutStats.queueDepthMax { self.audioOutStats.queueDepthMax = queueDepth }
            }

            // Process buffered audio (setup already done in startAudioCapture)
            self.processStreamingAudio()
        }
    }
    
    private func setupStreamingAudio() {
        // Create audio nodes for streaming playback
        audioPlayerNode = AVAudioPlayerNode()
        audioMixerNode = AVAudioMixerNode()
        // Simple EQ used here as a dynamics stage to add headroom (low output gain)
        let limiter = AVAudioUnitEQ(numberOfBands: 1)
        limiter.globalGain = outputHeadroomDb // reduce overall level to avoid clipping
        audioLimiterNode = limiter
        
        guard let playerNode = audioPlayerNode,
              let mixerNode = audioMixerNode,
              let audioEngine = audioEngine,
              let limiterNode = audioLimiterNode else {
            print("❌ Failed to create audio nodes for streaming")
            return
        }
        
        // Use OpenAI's native format for input (24kHz, Int16, Mono)
        let openAIFormat = pcm24Format
        
        // Use system's preferred format for output (usually 48kHz, Float32, Stereo)
        let systemFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        engineOutputFormat = systemFormat
        
        print("🆔 OpenAI format: \(openAIFormat.sampleRate)Hz, \(openAIFormat.channelCount) channels, \(openAIFormat.commonFormat.rawValue)")
        print("🔊 System format: \(systemFormat.sampleRate)Hz, \(systemFormat.channelCount) channels, \(systemFormat.commonFormat.rawValue)")
        
        // Attach nodes to the audio engine
        audioEngine.attach(playerNode)
        audioEngine.attach(limiterNode)
        audioEngine.attach(mixerNode)
        
        // Let the engine choose a compatible processing format between nodes
        audioEngine.connect(playerNode, to: limiterNode, format: nil)
        audioEngine.connect(limiterNode, to: mixerNode, format: nil)
        audioEngine.connect(mixerNode, to: audioEngine.outputNode, format: nil)
        
        // Build a converter from OpenAI (24k Int16 mono) -> player's processing format
        let playerFormat = playerNode.outputFormat(forBus: 0)
        audioConverter = AVAudioConverter(from: openAIFormat, to: playerFormat)
        if let conv = audioConverter {
            print("🔄 Audio converter created: \(conv.inputFormat.sampleRate)Hz -> \(conv.outputFormat.sampleRate)Hz")
        } else {
            print("⚠️ Failed to create audio converter; audio may sound incorrect")
        }
        
        print("✅ Streaming audio setup complete with automatic format conversion and headroom \(outputHeadroomDb) dB")
    }
    
    private func processStreamingAudio() {
        guard let playerNode = audioPlayerNode else { return }
        
        // Scheduling state
        struct SchedulingState { static var queuedChunks: Int = 0; static var queuedMs: Double = 0; static var queuedMsMax: Double = 0; static var underflows: Int = 0; static var scheduleLatencyMsSum: Double = 0; static var scheduleLatencyMsMax: Double = 0; static var scheduleCount: Int = 0 }
        let srcChunkBytes = 480 * 2 // ~20ms @24kHz Int16 mono
        let prebufferTargetMs: Double = 350 // aim for a larger prebuffer to reduce starvation
        var scheduledSomething = false

        // While we have data and our queued duration is below target, schedule more
        while streamingAudioBuffer.count >= srcChunkBytes && SchedulingState.queuedMs < prebufferTargetMs {
            let audioDataSize = srcChunkBytes
            let slice = streamingAudioBuffer.prefix(audioDataSize)
            guard let converter = audioConverter else {
                print("❌ No audio converter; dropping chunk")
                streamingAudioBuffer.removeFirst(audioDataSize)
                if enableAudioQualityLogs { audioOutStats.dropCount += 1 }
                continue
            }
            let srcFormat = converter.inputFormat
            guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(audioDataSize / 2)) else {
                print("❌ Failed to create source PCM buffer")
                break
            }
            srcBuffer.frameLength = AVAudioFrameCount(audioDataSize / 2)
            slice.withUnsafeBytes { rawPtr in
                if let src = rawPtr.bindMemory(to: Int16.self).baseAddress,
                   let dstI16 = srcBuffer.int16ChannelData?[0] {
                    dstI16.assign(from: src, count: Int(srcBuffer.frameLength))
                }
            }
            // Prepare destination buffer
            let dstFormat = converter.outputFormat
            let ratio = dstFormat.sampleRate / srcFormat.sampleRate
            let dstCapacity = max(1, Int(Double(srcBuffer.frameLength) * ratio) + 16)
            guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: AVAudioFrameCount(dstCapacity)) else { break }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return srcBuffer
            }
            let t0c = CFAbsoluteTimeGetCurrent()
            let status = converter.convert(to: dstBuffer, error: &error, withInputFrom: inputBlock)
            let t1c = CFAbsoluteTimeGetCurrent()
            if status == .error || error != nil {
                if enableVerboseAudioLogging { print("❌ Audio convert error: \(error?.localizedDescription ?? "unknown")") }
                if enableAudioQualityLogs { audioOutStats.dropCount += 1 }
                // Drop this chunk and continue
                streamingAudioBuffer.removeFirst(audioDataSize)
                continue
            }
            // Update quality stats
            if enableAudioQualityLogs {
                audioOutStats.convertMsSum += (t1c - t0c) * 1000.0
                let fmt = dstBuffer.format
                var peak: Double = 0
                var rms: Double = 0
                if fmt.commonFormat == .pcmFormatFloat32, let ch0 = dstBuffer.floatChannelData?[0] {
                    let n = Int(dstBuffer.frameLength)
                    var sumsq: Double = 0
                    for i in 0..<n { let v = Double(ch0[i]); let av = abs(v); if av > peak { peak = av }; sumsq += v * v }
                    rms = n > 0 ? sqrt(sumsq / Double(n)) : 0
                } else if fmt.commonFormat == .pcmFormatInt16, let ch0 = dstBuffer.int16ChannelData?[0] {
                    let n = Int(dstBuffer.frameLength)
                    var sumsq: Double = 0
                    for i in 0..<n { let v = Double(ch0[i]) / 32768.0; let av = abs(v); if av > peak { peak = av }; sumsq += v * v }
                    rms = n > 0 ? sqrt(sumsq / Double(n)) : 0
                }
                if peak > audioOutStats.peakMax { audioOutStats.peakMax = peak }
                audioOutStats.rmsSum += rms
                audioOutStats.chunkCount += 1
            }

            // Schedule buffer and update queue metrics
            let bufferMs = (Double(dstBuffer.frameLength) / dstBuffer.format.sampleRate) * 1000.0
            let t0s = CFAbsoluteTimeGetCurrent()
            playerNode.scheduleBuffer(dstBuffer) { [weak self] in
                // Decrement queued on background to avoid main thread stalls
                self?.playbackQueue.async {
                    SchedulingState.queuedChunks = max(0, SchedulingState.queuedChunks - 1)
                    SchedulingState.queuedMs = max(0, SchedulingState.queuedMs - bufferMs)
                    // Detect underflow: if no more queued and no data to schedule
                    if let self = self, self.streamingAudioBuffer.count < srcChunkBytes && self.audioPlayerNode?.isPlaying == true {
                        SchedulingState.underflows += 1
                        if self.enablePlaybackSchedulingLogs {
                            print("⚠️ [AUDIO] Potential playback underflow (no queued buffers)")
                        }
                    }
                    // Try to schedule more
                    self?.processStreamingAudio()
                }
            }
            let t1s = CFAbsoluteTimeGetCurrent()
            let schedLatencyMs = (t1s - t0s) * 1000.0
            SchedulingState.scheduleLatencyMsSum += schedLatencyMs
            if schedLatencyMs > SchedulingState.scheduleLatencyMsMax { SchedulingState.scheduleLatencyMsMax = schedLatencyMs }
            SchedulingState.scheduleCount += 1
            SchedulingState.queuedChunks += 1
            SchedulingState.queuedMs += bufferMs
            if SchedulingState.queuedMs > SchedulingState.queuedMsMax { SchedulingState.queuedMsMax = SchedulingState.queuedMs }
            scheduledSomething = true
            // Consume source bytes
            streamingAudioBuffer.removeFirst(audioDataSize)
        }

        if scheduledSomething && enablePlaybackSchedulingLogs {
            print("🎛️ [AUDIO] Queued chunks=\(SchedulingState.queuedChunks) (~\(Int(SchedulingState.queuedMs)) ms), scheduled in avg \(String(format: "%.2f", SchedulingState.scheduleLatencyMsSum / Double(max(1, SchedulingState.scheduleCount)))) ms")
        }

        // Start playing if not already
        if scheduledSomething && !playerNode.isPlaying {
            playerNode.play()
            isPlayingQueue = true
            if enableVerboseAudioLogging { print("🎵 Started streaming audio playback") }
            if enableAudioQualityLogs && audioOutStats.firstPlayAt == 0 { audioOutStats.firstPlayAt = CFAbsoluteTimeGetCurrent() }
        }
        
        // If no data and not playing, playback is done
        if streamingAudioBuffer.isEmpty && !playerNode.isPlaying {
            isPlayingQueue = false
            print("✅ Streaming audio playback completed")
            if enableAudioQualityLogs {
                printAudioQualitySummary(tag: "drain", isFinal: true)
            }
        }
    }
    
    private func stopAudioPlayback() {
        audioPlayerLock.lock()
        defer { audioPlayerLock.unlock() }
        
        audioPlayerNode?.stop()
        streamingAudioBuffer.removeAll()
        isPlayingQueue = false
        print("🛑 Stopped streaming audio playback")
    }
    
    // MARK: - Audio Delegate Methods Removed
    // No longer needed with AVAudioPlayerNode streaming
    
    // MARK: - Streaming Control (for compatibility with UI)
    func startStreaming() {
        // Audio capture is managed automatically by connect/disconnect
        print("🎤 Streaming control - already handled by connection state")
    }
    
    func stopStreaming() {
        // Audio capture is managed automatically by connect/disconnect
        print("🔇 Streaming control - already handled by connection state")
    }
    
    /// Clear conversation history
    func clearConversation() {
        conversation.removeAll()
    }
    
    func setLocationManager(_ manager: LocationManager) {
        toolManager.setLocationManager(manager)
        
        // Initialize location search service
        let locationSearchService = LocationBasedSearchService(
            apiKey: self.apiKey,
            locationManager: manager
        )
        toolManager.setLocationSearchService(locationSearchService)
        
        // Initialize OpenAI Chat service
        let openAIChatService = OpenAIChatService(apiKey: self.apiKey)
        toolManager.setOpenAIChatService(openAIChatService)
        
        // Initialize Google Places/Routes service if key available in Config.plist
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let configDict = NSDictionary(contentsOfFile: configPath),
           let googleKey = configDict["Google_API_Key"] as? String, !googleKey.isEmpty {
            let googleService = GooglePlacesRoutesService(apiKey: googleKey, locationManager: manager)
            toolManager.setGooglePlacesRoutesService(googleService)
            
            // Travel services
            let weatherKey = (configDict["OpenWeather_API_Key"] as? String) ?? ""
            let weatherService = WeatherService(apiKey: weatherKey)
            let currencyService = CurrencyService()
            let translationService = TranslationService(openAIChatService: openAIChatService)
            let travelReqService = TravelRequirementsService()
            toolManager.setTravelServices(weather: weatherService, currency: currencyService, translation: translationService, travelRequirements: travelReqService)
        } else {
            print("⚠️ Google API Key missing; Google Places/Routes not enabled")
        }
    }
    
    // MARK: - Connection Management
    func connect() async throws {
        print("🔌 [CONNECT] Connecting to OpenAI Realtime API...")
        
        // Get ephemeral token
        let ephemeralKey = try await getEphemeralKey()
        print("🔐 [CONNECT] Retrieved ephemeral key")
        
        // Create WebSocket connection (GA model, no beta header)
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime") else {
            throw NSError(domain: "OpenAIRealtimeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid WebSocket URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(ephemeralKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        print("🔗 [CONNECT] WebSocket task created and resumed")
        
        // Start listening for messages
        startListening()
        print("👂 [CONNECT] Started listening for messages")
        
        // Wait a moment for connection to establish
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Configure session once connected
        try await configureSession()
        
        connectionStatus = "Connected"
        isConnected = true
        
        // Start audio capture
        startAudioCapture()
        
        // Play connection sound
        audioFeedbackManager.playConnectionSound()
        
        print("✅ [CONNECT] Connected to OpenAI Realtime API")
    }
    
    func disconnect() {
        print("🔌 Disconnecting from OpenAI Realtime API...")
        // Emit final summary on disconnect in case playback hasn't drained
        printAudioQualitySummary(tag: "disconnect", isFinal: true)
        
        // Stop audio capture first to prevent engine issues
        stopAudioCapture()
        
        // Stop audio streaming immediately
        isAIResponding = false
        NotificationCenter.default.post(name: .realtimeAudioStreamCompleted, object: nil)
        
        // Clear speech tracking state
        speechStartTime = 0
        
        // CLEANUP TOOL EXECUTION STATE
        if isToolExecuting || !pendingToolCalls.isEmpty {
            print("🔌 [DISCONNECT] Cleaning up tool execution state")
            print("🔌 [DISCONNECT] Was executing: \(isToolExecuting), Pending calls: \(pendingToolCalls.count)")
        }
        isToolExecuting = false
        pendingToolCalls.removeAll()
        currentResponseId = nil
        lastToolStartTime = 0
        print("🔌 [DISCONNECT] Tool execution state reset")
        
        // Close WebSocket connection
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        connectionStatus = "Disconnected"
        
        // Stop audio feedback after main audio systems are stopped
        audioFeedbackManager.stopThinkingSound()
        
        // Play disconnection sound with a small delay to avoid conflicts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.audioFeedbackManager.playDisconnectionSound()
        }
        
        print("✅ Disconnected from OpenAI Realtime API")
    }
    
    // MARK: - Private Methods
    private func getEphemeralKey() async throws -> String {
        // Latest docs: POST /v1/realtime/client_secrets returns { value, session }
        guard let url = URL(string: "https://api.openai.com/v1/realtime/client_secrets") else {
            throw NSError(domain: "OpenAIRealtimeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Provide minimal session seed per docs if desired; keep server defaults otherwise
        let requestBody: [String: Any] = [
            "session": [
                "type": "realtime",
            "model": "gpt-realtime",
                "instructions": "You are Guido, a helpful travel companion."
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAIRealtimeService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get ephemeral key"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // New schema: top-level { value: string, session: {...} }
        if let value = json?["value"] as? String {
            return value
        }
        // Back-compat fallback
        if let clientSecret = json?["client_secret"] as? [String: Any], let value = clientSecret["value"] as? String {
        return value
        }
        else {
            throw NSError(domain: "OpenAIRealtimeService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
    }
    
    private func configureSession() async throws {
        // Build GA session.update payload per latest Realtime API
        let eventId = UUID().uuidString
        let vadType = VADConfig.useSemanticVAD ? "semantic_vad" : "server_vad"
        let toolsArray: [[String: Any]] = {
            do {
                let defs = MCPToolCoordinator.getAllToolDefinitions()
                let data = try JSONEncoder().encode(defs)
                return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            } catch {
                print("⚠️ Failed to encode tool definitions: \(error)")
                return []
            }
        }()
        var turnDetection: [String: Any] = [
            "type": vadType,
            "create_response": true,
            "interrupt_response": true
        ]
        if !VADConfig.useSemanticVAD {
            turnDetection["threshold"] = VADConfig.serverThreshold
            turnDetection["prefix_padding_ms"] = VADConfig.serverPrefixPadding
            turnDetection["silence_duration_ms"] = VADConfig.serverSilenceDuration
        } else {
            turnDetection["eagerness"] = VADConfig.semanticEagerness
        }
        var sessionDict: [String: Any] = [
            "type": "realtime",
            "model": "gpt-realtime",
            "output_modalities": ["audio"],
            "audio": [
                "input": [
                    "format": ["type": "audio/pcm", "rate": 24000],
                    "transcription": ["model": "gpt-4o-transcribe", "language": "en"],
                    "turn_detection": turnDetection
                ],
                "output": [
                    "format": ["type": "audio/pcm", "rate": 24000],
                    "voice": "marin"
                ]
            ],
            "instructions": """
                You are Guido, a helpful, upbeat and conversational AI travel companion with access to real-time tools and location data. You're designed to have natural, flowing conversations about travel while providing personalized, location-aware assistance.
                
                Guidelines:
                - Keep responses natural and conversational
                - Be warm, helpful, and engaging
                - Use a friendly, casual tone
                - Ask follow-up questions to keep conversations flowing
                - Provide practical travel advice when relevant
                - Be concise but informative
                - Respond quickly and smoothly for natural conversation flow
                - Use your tools proactively to provide personalized recommendations
                - IMPORTANT: You have access to the user's current location through the get_user_location tool. ALWAYS call this first when you need location data. If clarification is needed, present a hypothesis based on the location data (e.g., "I see you're at [address] - shall I give you directions from there?")
                - When appropriate, check the user's location, nearby places, weather, and other contextual information
                - Offer specific, actionable suggestions based on real data
                - ALWAYS briefly acknowledge before using tools with phrases like "let me check that for you", "let me find that information", or "give me a moment to look that up" - this provides important user feedback during processing
                - After using tools and getting results, naturally transition into sharing the information without additional artificial completion sounds
                
                Available Tools:
                - Location tracking and movement detection
                - Nearby places search (restaurants, attractions, hotels, transportation)
                - Turn-by-turn directions and navigation
                - Real-time weather and forecasts
                - Calendar integration for trip planning
                - Local time and timezone information
                - Transportation options (rideshare, public transit, car rental)
                - Local events and activities
                - Restaurant recommendations with filters
                - Currency conversion and exchange rates
                - Language translation for travel
                - Safety information and travel advisories
                - Travel document requirements (visas, passports)
                - Emergency contacts and services
                - Real-time web search for current information about destinations, businesses, and local conditions
                - Advanced AI reasoning and analysis for complex travel planning and personalized recommendations
                
                Use these tools naturally in conversation to provide the most helpful and personalized travel experience.
                
                IMPORTANT: 
                - Engage in natural conversation flow. The system uses voice activity detection to understand when you should respond. Trust the turn-taking system and respond naturally when prompted.
                - CRITICAL AUDIO FEEDBACK PATTERN: When you need to use tools, ALWAYS follow this sequence:
                  1. First, speak an acknowledgment like "let me check that for you" or "let me look that up"
                  2. Then call your tools (ALWAYS call get_user_location first if you need location data)
                  3. Finally, naturally share the results when tools complete
                - NEVER ask users "where are you?" - instead, get their location automatically and present a hypothesis for confirmation if needed (e.g., "I see you're near Riverside Boulevard - is that where you'd like directions from?")
                - INTERRUPTION AWARENESS: When a user interrupts you mid-response, acknowledge what you were doing before switching context. For example: "Oh, I was just about to tell you about those dessert places, but let me help you find lunch options instead" or "I see you want something different - let me switch from dessert to lunch recommendations"
                - This verbal feedback replaces artificial beeps and provides natural user experience
                """,
            "tool_choice": "auto",
            "tools": toolsArray
        ]
        // GA session.update does not accept temperature/max_output_tokens at session level
        let payload: [String: Any] = [
            "type": "session.update",
            "event_id": eventId,
            "session": sessionDict
        ]
        try await sendRawEvent(payload)
        let eagerness = VADConfig.useSemanticVAD ? VADConfig.semanticEagerness : "N/A"
        print("✅ Session configured with \(vadType) (eagerness: \(eagerness), auto-response: true, interrupts: enabled)")
        print("🔧 VAD Settings: Type=\(vadType), Threshold=\(VADConfig.serverThreshold), SilenceDuration=\(VADConfig.serverSilenceDuration)ms, PrefixPadding=\(VADConfig.serverPrefixPadding)ms")
    }

    private func sendRawEvent(_ payload: [String: Any]) async throws {
        guard let webSocketTask = webSocketTask else {
            throw NSError(domain: "OpenAIRealtimeService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        if let str = String(data: data, encoding: .utf8), str.contains("\"type\":\"session.update\"") {
            print("🔍 [DEBUG] Sending session.update JSON: \(str)")
        }
        try await webSocketTask.send(.string(String(data: data, encoding: .utf8)!))
    }
    
    private func startListening() {
        guard let webSocketTask = webSocketTask else { return }
        
        webSocketTask.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    await self?.handleWebSocketMessage(message)
                    self?.startListening() // Continue listening
                case .failure(let error):
                    print("❌ WebSocket error: \(error)")
                    await self?.handleConnectionError(error)
                }
            }
        }
    }
    
    private func handleConnectionError(_ error: Error) async {
        let errorMessage: String
        
        if let nsError = error as NSError? {
            switch nsError.code {
            case 57: // Socket is not connected
                errorMessage = "Connection failed - check internet connection"
            case 60: // SSL error
                errorMessage = "SSL connection failed"
            case 401: // Unauthorized
                errorMessage = "Invalid API key"
            default:
                errorMessage = "Connection error: \(nsError.localizedDescription)"
            }
        } else {
            errorMessage = error.localizedDescription
        }
        
        await MainActor.run {
            connectionStatus = "Error: \(errorMessage)"
            isConnected = false
        }
        
        disconnect()
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            await handleIncomingEvent(text)
        case .data(let data):
            print("📦 Received binary data: \(data.count) bytes")
        @unknown default:
            print("❓ Unknown message type")
        }
    }
    
    private func handleIncomingEvent(_ eventText: String) async {
        guard let eventData = eventText.data(using: .utf8) else { return }
        
        do {
            let event = try JSONDecoder().decode(IncomingEvent.self, from: eventData)
            print("📥 Received event: \(event.type)")
            
            switch event.type {
            case "session.created":
                print("✅ Session created successfully")
                
            case "session.updated":
                print("✅ Session updated successfully")
                
            case "conversation.item.input_audio_transcription.delta":
                // Handle incremental user transcription
                if let jsonDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   let delta = jsonDict["delta"] as? String {
                    print("📝 User transcription delta: '\(delta)'")
                } else {
                    print("⚠️ Failed to decode transcription delta event")
                }
                
            case "conversation.item.input_audio_transcription.completed":
                if let jsonDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   let transcript = jsonDict["transcript"] as? String {
                    
                    print("🎤 [TRANSCRIPT] User transcription received: '\(transcript)' (length: \(transcript.count))")
                    
                    // More detailed analysis of the transcript
                    let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lowercaseTranscript = transcript.lowercased()
                    
                    print("🎤 [TRANSCRIPT] Trimmed: '\(trimmedTranscript)' (length: \(trimmedTranscript.count))")
                    
                    // Enhanced filtering for system prompts and transcription artifacts
                    let systemPhrases = [
                        "transcribe clear human speech", "ignore background noise", "system sounds",
                        "audio feedback", "focus on natural conversational flow", "complete thoughts",
                        "whisper-1", "transcription", "clear human speech from the user"
                    ]
                    
                    let isSystemPrompt = systemPhrases.contains { phrase in
                        lowercaseTranscript.contains(phrase)
                    }
                    
                                    // Check for empty or whitespace-only transcripts
                if trimmedTranscript.isEmpty {
                    print("🚫 [TRANSCRIPT] Empty transcript - likely audio buffer issue")
                    return
                }
                
                // Skip if this looks like a duplicate transcription (happens in subsequent turns)
                if let lastMessage = conversation.last,
                   lastMessage.role == "user",
                   lastMessage.content == trimmedTranscript,
                   Date().timeIntervalSince(lastMessage.timestamp) < 2.0 {
                    print("🚫 [TRANSCRIPT] Skipping duplicate transcription: '\(trimmedTranscript)'")
                    return
                }
                    
                    // Filter system prompts or extremely long transcripts (likely errors)
                    if isSystemPrompt || transcript.count > 200 {
                        print("🚫 [TRANSCRIPT] Filtered system prompt or overly long transcript")
                        return
                    }
                    
                    // Add user message to conversation
                    let message = RealtimeMessage(role: "user", content: transcript, timestamp: Date())
                    conversation.append(message)
                    print("👤 [TRANSCRIPT] User said: '\(transcript)' - added to conversation (total: \(conversation.count))")
                } else {
                    print("⚠️ [TRANSCRIPT] Failed to decode transcription completed event")
                    if let jsonString = String(data: eventData, encoding: .utf8) {
                        print("📄 [TRANSCRIPT] Raw JSON: \(jsonString)")
                    }
                }
                
            case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
                if let transcriptEvent = try? JSONDecoder().decode(AudioTranscriptEvent.self, from: eventData) {
                    print("📝 AI transcript delta: '\(transcriptEvent.delta)'")
                    // Find the last streaming assistant message (not just the last message)
                    if let lastStreamingAssistantIndex = conversation.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                        conversation[lastStreamingAssistantIndex].content += transcriptEvent.delta
                        print("📝 Updated streaming AI message. Total length: \(conversation[lastStreamingAssistantIndex].content.count)")
                    } else {
                        let message = RealtimeMessage(role: "assistant", content: transcriptEvent.delta, timestamp: Date(), isStreaming: true)
                        conversation.append(message)
                        print("🗨️ Added new AI message to conversation. Total messages: \(conversation.count)")
                    }
                } else {
                    print("❌ Failed to decode AudioTranscriptEvent")
                    if let jsonString = String(data: eventData, encoding: .utf8) {
                        print("📄 Raw JSON: \(jsonString)")
                    }
                }
                
            case "response.audio_transcript.done", "response.output_audio_transcript.done":
                // Mark the last streaming AI message as complete
                print("🔍 Looking for streaming AI message to complete. Conversation has \(conversation.count) messages")
                if let lastStreamingIndex = conversation.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                    conversation[lastStreamingIndex].isStreaming = false
                    print("✅ AI transcript completed: '\(conversation[lastStreamingIndex].content)'")
                } else {
                    print("⚠️ No streaming AI message found to mark as complete")
                }
                
            case "response.audio.delta", "response.output_audio.delta":
                if let audioEvent = try? JSONDecoder().decode(AudioDeltaEvent.self, from: eventData) {
                    // Check if we're in an interrupted state - ignore audio if so
                    if conversationState == .listening {
                        print("🛑 [AI_AUDIO] Ignoring audio delta - user has interrupted")
                        return
                    }
                    
                    // Enable feedback prevention IMMEDIATELY on first audio chunk
                    if !isAIResponding {
                        print("🎤 [AI_AUDIO] First AI audio delta - setting isAIResponding=true")
                        isAIResponding = true
                        conversationState = .speaking
                        print("🎤 [AI_AUDIO] AI generating audio - blocking new input during generation")
                    }
                    await handleAudioDelta(audioEvent.delta)
                } else {
                    print("❌ [AI_AUDIO] Failed to decode audio delta event")
                }
                
            case "response.audio.done", "response.output_audio.done":
                print("🎵 [AI_AUDIO] Audio response completed - setting isAIResponding=false")
                // Re-enable microphone input after AI finishes speaking
                isAIResponding = false
                
                // Emit snapshot at response done (playback may still be flushing)
                printAudioQualitySummary(tag: "response_done", isFinal: false)
                
                // Reset playback queue to allow user input
                await MainActor.run {
                    isPlayingQueue = false
                }
                
                // Clear any residual audio buffer that might cause transcription issues
                await clearInputAudioBuffer()
                
                // Wait for audio playback to actually complete before playing completion sound
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.audioFeedbackManager.playCompletionSound()
                }
                
                print("✅ [AI_AUDIO] AI audio completed - buffer cleared - ready for user input")
                // Notify audio manager that streaming should finish
                NotificationCenter.default.post(name: .realtimeAudioStreamCompleted, object: nil)
            
            case "response.output_text.delta":
                if let root = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   let delta = root["delta"] as? String {
                    if let idx = conversation.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                        conversation[idx].content += delta
                    } else {
                        conversation.append(RealtimeMessage(role: "assistant", content: delta, timestamp: Date(), isStreaming: true))
                    }
                }
            case "response.output_text.done":
                if let idx = conversation.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                    conversation[idx].isStreaming = false
                }
                
            case "response.done":
                lastResponseCompleteTime = Date().timeIntervalSince1970
                
                // Extract response completion details
                var completionInfo = "unknown"
                if let root = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   let responseObj = root["response"] as? [String: Any] {
                    if let responseId = responseObj["id"] as? String {
                        completionInfo = "ID: \(responseId)"
                        if currentResponseId == responseId {
                            currentResponseId = nil
                            print("🔄 [RESPONSE] Cleared current response ID: \(responseId)")
                        }
                    }
                    if let status = responseObj["status"] as? String {
                        completionInfo += ", status: \(status)"
                        if status == "failed" {
                            let err = responseObj["error"] as? [String: Any]
                            let msg = err?["message"] as? String ?? "(no message)"
                            print("🚨 [RESPONSE] Failure reason: \(msg)")
                            if let raw = String(data: eventData, encoding: .utf8) {
                                print("📄 [RESPONSE] Raw response.done JSON: \(raw)")
                            }
                        }
                    }
                } else if let raw = String(data: eventData, encoding: .utf8) {
                    print("📄 [RESPONSE] Raw response.done JSON (unparsed): \(raw)")
                }
                
                print("✅ [RESPONSE] Response completed at \(lastResponseCompleteTime) (\(completionInfo))")
                print("✅ [RESPONSE] Final state: tool executing=\(isToolExecuting), pending tools=\(pendingToolCalls.count)")
                
                isAIResponding = false
                conversationState = .idle  // Reset to idle - let server VAD manage state
                
                // Reset speech tracking for next conversation turn
                speechStartTime = 0
                print("🔄 [RESPONSE] Ready for next speech input")
                
            case "response.cancelled":
                let cancelTime = Date().timeIntervalSince1970
                var cancelInfo = "unknown"
                if let root = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   let responseObj = root["response"] as? [String: Any],
                   let responseId = responseObj["id"] as? String {
                        cancelInfo = "ID: \(responseId)"
                        if currentResponseId == responseId {
                            currentResponseId = nil
                            print("🔄 [CANCEL] Cleared cancelled response ID: \(responseId)")
                    }
                }
                
                print("❌ [CANCEL] Response cancelled at \(cancelTime) (\(cancelInfo))")
                print("❌ [CANCEL] State at cancellation: tool executing=\(isToolExecuting), pending tools=\(pendingToolCalls.count)")
                
                isAIResponding = false
                conversationState = .listening  // Back to listening after cancellation
                
            case "input_audio_buffer.speech_started":
                let currentTime = Date().timeIntervalSince1970
                let timeSinceLastResponse = lastResponseCompleteTime > 0 ? currentTime - lastResponseCompleteTime : 0
                let timeSinceLastClear = lastClearBufferTime > 0 ? currentTime - lastClearBufferTime : 0
                let timeSinceToolStart = lastToolStartTime > 0 ? currentTime - lastToolStartTime : 0
                
                print("🗣️ [VAD] Speech started detected by VAD at \(currentTime)")
                print("🗣️ [VAD] Current state: AI responding=\(isAIResponding), playing=\(isPlayingQueue), tool executing=\(isToolExecuting)")
                print("🗣️ [VAD] Time since: last response=\(String(format: "%.2f", timeSinceLastResponse))s, buffer clear=\(String(format: "%.2f", timeSinceLastClear))s, tool start=\(String(format: "%.2f", timeSinceToolStart))s")
                print("🗣️ [VAD] Pending tool calls: \(pendingToolCalls.count), Response ID: \(currentResponseId ?? "none")")
                
                // ENHANCED INTERRUPTION DETECTION
                // Check if we need to interrupt ongoing AI activity (response, audio playback, or tool execution)
                let shouldInterrupt = isAIResponding || isPlayingQueue || isToolExecuting
                
                if shouldInterrupt {
                    if isToolExecuting {
                        print("🛑 [INTERRUPT] User speaking during tool execution - \(pendingToolCalls.count) tools pending")
                    } else if isAIResponding {
                        print("🛑 [INTERRUPT] User speaking during AI response generation")
                    } else if isPlayingQueue {
                        print("🛑 [INTERRUPT] User speaking during audio playback")
                    }
                    
                    await handleUserInterruption()
                } else {
                    print("🗣️ [VAD] Speech started during idle state - normal turn taking")
                }
                
                speechStartTime = currentTime
                conversationState = .listening

                // Start a safety fallback: if server doesn't emit speech_stopped soon, manually commit
                lastServerSpeechStartTime = currentTime
                commitFallbackWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    // If we haven't seen speech_stopped or response start, force commit + response
                    let now = Date().timeIntervalSince1970
                    let sinceStop = self.lastServerSpeechStopTime > 0 ? now - self.lastServerSpeechStopTime : nil
                    if self.currentResponseId == nil && (sinceStop == nil || sinceStop! > 0.5) {
                        print("⚠️ [VAD] Fallback commit fired (no speech_stopped) - forcing commit + response.create")
                        Task { await self.sendManualCommitAndRequest() }
                    }
                }
                commitFallbackWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
                
            case "input_audio_buffer.speech_stopped":
                let currentTime = Date().timeIntervalSince1970
                let speechDuration = speechStartTime > 0 ? currentTime - speechStartTime : 0
                print("🤐 [VAD] Speech stopped at \(currentTime) - duration: \(speechDuration)s")
                print("🤐 [VAD] AI responding: \(isAIResponding), conversation state: \(conversationState)")
                lastServerSpeechStopTime = currentTime
                commitFallbackWorkItem?.cancel()
                
                // Let server VAD handle all speech detection - trust OpenAI's optimized algorithms
                

                
                // Ignore very short utterances that Whisper often mis-transcribes
                if speechDuration < VADConfig.minimumSpeechDuration {
                    print("⚠️ [VAD] Speech too short (\(String(format: "%.2f", speechDuration))s) – ignored (threshold: \(VADConfig.minimumSpeechDuration)s)")
                    conversationState = .listening
                    return
                }
                // Accept all other speech durations - server VAD will determine validity
                print("✅ [VAD] Speech stopped (duration: \(String(format: "%.2f", speechDuration))s) - server VAD processing")
                
                conversationState = .processing
                
                // Trust server VAD for all turn detection and response generation
                print("🔄 [VAD] Server VAD will handle turn detection automatically")
                
            case "input_audio_buffer.committed":
                print("✅ [BUFFER] Audio buffer committed successfully")
                
            case "conversation.item.created":
                print("💬 Conversation item created")
            case "conversation.item.added":
                print("💬 Conversation item added")
            case "conversation.item.done":
                print("💬 Conversation item done")
                
            case "response.created":
                // Extract nested response.id per latest schema
                if let root = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   let responseObj = root["response"] as? [String: Any],
                   let responseId = responseObj["id"] as? String {
                    currentResponseId = responseId
                    print("🤖 [RESPONSE] AI response created with ID: \(responseId)")
                } else {
                    print("🤖 [RESPONSE] AI response created (no ID extracted)")
                }
                
                conversationState = .thinking
                // Play thinking sound when AI starts processing
                audioFeedbackManager.playThinkingSound()
                commitFallbackWorkItem?.cancel()
                
            case "response.output_item.added":
                print("📝 Response output item added")
                
            case "response.content_part.added":
                print("📄 Response content part added")
                
            case "response.content_part.done":
                print("✅ Response content part completed")
                
            case "response.output_item.done":
                print("✅ Response output item completed")
                
            case "rate_limits.updated":
                print("📊 Rate limits updated")
                
            case "response.function_call_arguments.delta":
                print("🔧 Function call arguments delta received")
                
            case "response.function_call_arguments.done":
                // Extract call ID for tool execution tracking
                let currentTime = Date().timeIntervalSince1970
                
                if let json = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   let callId = json["call_id"] as? String,
                   let toolName = json["name"] as? String {
                    
                    pendingToolCalls.insert(callId)
                    isToolExecuting = true
                    lastToolStartTime = currentTime
                    
                    print("🔧 [TOOL] Function call arguments completed - starting execution")
                    print("🔧 [TOOL] Tool: \(toolName), Call ID: \(callId)")
                    print("🔧 [TOOL] Now tracking \(pendingToolCalls.count) pending tool call(s): \(Array(pendingToolCalls))")
                    print("🔧 [TOOL] Tool execution state: isToolExecuting=\(isToolExecuting)")
                } else {
                    print("🔧 [TOOL] Function call arguments completed (could not extract call ID)")
                }
                
                // Execute the function call
                await handleFunctionCall(eventData)
                
            case "error":
                if let errorData = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   let error = errorData["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ OpenAI API Error: \(message)")
                    if let raw = String(data: eventData, encoding: .utf8) {
                        print("📄 [ERROR] Raw error JSON: \(raw)")
                    }
                    
                    // Handle specific error types
                    if message.contains("buffer too small") {
                        print("🔧 [ERROR] Buffer too small error - this indicates audio buffer was cleared while VAD was active")
                        print("🔧 [ERROR] Current state - isAIResponding: \(isAIResponding), speechStartTime: \(speechStartTime)")
                        // Reset audio state but don't disconnect
                        speechStartTime = 0
                
                    } else if message.contains("already has an active response") {
                        print("🔧 [ERROR] Duplicate response error - ignoring (likely race condition)")
                        // Just ignore this error and continue
                    } else {
                        print("🚨 [ERROR] Other API error: \(message)")
                        // For other errors, update status but try to maintain connection
                        await MainActor.run {
                            connectionStatus = "Error: \(message)"
                        }
                    }
                } else {
                    print("❌ Unknown API error received")
                    if let raw = String(data: eventData, encoding: .utf8) {
                        print("📄 [ERROR] Raw event JSON (unknown error): \(raw)")
                    }
                }
                
            case "input_audio_buffer.cleared":
                print("🧹 [BUFFER] Input audio buffer cleared by server")
                
            default:
                print("📋 [UNKNOWN] Unhandled event type: \(event.type)")
                if let jsonString = String(data: eventData, encoding: .utf8) {
                    print("📄 [UNKNOWN] Raw event JSON: \(jsonString)")
                }
            }
            
        } catch {
            print("❌ Failed to decode event: \(error)")
        }
    }
    
    private func handleAudioDelta(_ base64Audio: String) async {
        // Double-check interruption state before processing audio
        if conversationState == .listening {
            print("🛑 [AI_AUDIO] Skipping audio delta - user interrupted")
            return
        }
        
        guard let audioData = Data(base64Encoded: base64Audio) else {
            print("❌ Failed to decode base64 audio")
            return
        }
        
        // Directly play audio data
        await MainActor.run {
            playAudio(data: audioData)
        }
    }
    
    private func sendEvent<T: Codable>(_ event: T) async throws {
        guard let webSocketTask = webSocketTask else {
            throw NSError(domain: "OpenAIRealtimeService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        
        // Configure JSON encoder to avoid floating point precision issues
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        
        let eventData = try encoder.encode(event)
        guard let eventString = String(data: eventData, encoding: .utf8) else {
            throw NSError(domain: "OpenAIRealtimeService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to encode event"])
        }
        
        // Debug: Print session.update events to see threshold formatting
        if eventString.contains("session.update") {
            print("🔍 [DEBUG] Sending session.update JSON: \(eventString)")
        }
        
        try await webSocketTask.send(.string(eventString))
    }
    
    // MARK: - Public Methods
    func sendAudioData(_ audioData: Data) async {
        guard isConnected else { 
            print("🚫 [AUDIO] Not connected - skipping audio data")
            return 
        }
        
        // Let OpenAI's server VAD handle everything - no manual blocking
        
        let base64Audio = audioData.base64EncodedString()
        let event = InputAudioBufferAppendEvent(
            eventId: UUID().uuidString,
            audio: base64Audio
        )
        
        // Log occasionally to confirm audio is being sent
        if Int.random(in: 1...100) == 1 {
            print("🎵 [AUDIO] Sending audio chunk: \(audioData.count) bytes, base64 length: \(base64Audio.count)")
        }
        
        do {
            try await sendEvent(event)
        } catch {
            print("❌ [AUDIO] Failed to send audio data: \(error)")
        }
    }
    
    func requestResponse() async {
        guard isConnected else { 
            print("🚫 [REQUEST] Not connected - cannot request response")
            return 
        }
        
        // Prevent duplicate response requests
        guard !isAIResponding else {
            print("🚫 [REQUEST] Response already in progress - skipping duplicate request")
            return
        }
        
        let eventId = UUID().uuidString
        let event = ResponseCreateEvent(eventId: eventId)
        
        do {
            try await sendEvent(event)
            print("🎬 [REQUEST] Requested new response with ID: \(eventId)")
            isAIResponding = true
            conversationState = .thinking
        } catch {
            print("❌ [REQUEST] Failed to request response: \(error)")
        }
    }

    private func sendManualCommitAndRequest() async {
        // Manually commit buffer and request a response when server VAD stalls
        struct Commit: Codable { let type: String = "input_audio_buffer.commit"; let event_id: String }
        let commit = Commit(event_id: UUID().uuidString)
        do {
            try await sendEvent(commit)
            print("🧷 [FALLBACK] input_audio_buffer.commit sent")
        } catch {
            print("❌ [FALLBACK] Failed to commit buffer: \(error)")
        }
        await requestResponse()
    }
    
    func clearInputAudioBuffer() async {
        guard isConnected else { 
            print("🚫 [BUFFER] Not connected - cannot clear input buffer")
            return 
        }
        
        struct ClearInputBufferEvent: Codable {
            let type: String
            let event_id: String
        }
        
        let eventId = UUID().uuidString
        let event = ClearInputBufferEvent(
            type: "input_audio_buffer.clear",
            event_id: eventId
        )
        
        do {
            try await sendEvent(event)
            lastClearBufferTime = Date().timeIntervalSince1970
            print("🧹 [BUFFER] Cleared input audio buffer with ID: \(eventId) at \(lastClearBufferTime)")
        } catch {
            print("❌ [BUFFER] Failed to clear input audio buffer: \(error)")
        }
    }
    
    // Removed: output_audio_buffer.clear is WebRTC-only; not supported over WebSocket
    
    func cancelResponse() async {
        guard isConnected else { return }
        
        struct CancelResponseEvent: Codable {
            let type: String
            let event_id: String
            let response_id: String?
        }
        
        let event = CancelResponseEvent(
            type: "response.cancel",
            event_id: UUID().uuidString,
            response_id: currentResponseId
        )
        
        do {
            try await sendEvent(event)
            print("❌ Cancelled active response")
        } catch {
            print("❌ Failed to cancel response: \(error)")
        }
    }
    
    private func handleUserInterruption() async {
        let interruptTime = Date().timeIntervalSince1970
        print("🛑 [INTERRUPT] === USER INTERRUPTION DETECTED ===")
        print("🛑 [INTERRUPT] Time: \(interruptTime)")
        print("🛑 [INTERRUPT] State before: AI responding=\(isAIResponding), playing=\(isPlayingQueue), tool executing=\(isToolExecuting)")
        print("🛑 [INTERRUPT] Pending tools: \(pendingToolCalls.count) - \(Array(pendingToolCalls))")
        print("🛑 [INTERRUPT] Current response ID: \(currentResponseId ?? "none")")
        
        // 1. IMMEDIATE STATE UPDATES
        isAIResponding = false
        print("🛑 [INTERRUPT] Step 1: Set isAIResponding=false")
        
        // 2. STOP AUDIO STREAMING IMMEDIATELY
        // Stop client-side audio playback first for immediate feedback
        stopAudioPlayback()
        print("🛑 [INTERRUPT] Step 2: Stopped client-side audio playback immediately")
        
        // Notify other components
        NotificationCenter.default.post(name: .realtimeAudioStreamInterrupted, object: nil)
        print("🛑 [INTERRUPT] Step 2: Posted audio stream interruption notification")
        
        // 3. CANCEL ACTIVE AI RESPONSE
        if let responseId = currentResponseId {
            print("🛑 [INTERRUPT] Step 3: Cancelling response ID: \(responseId)")
            await cancelResponse()
            currentResponseId = nil
            print("🛑 [INTERRUPT] Step 3: AI response cancelled and ID cleared")
        } else {
            print("🛑 [INTERRUPT] Step 3: No active response to cancel")
        }
        
        // 4. CLEAR AUDIO BUFFERS
        // WebSocket path: no output buffer clear; rely on cancel + local stop
        print("🛑 [INTERRUPT] Step 4: Output buffer clear skipped (WebSocket)")
        
        await clearInputAudioBuffer()
        print("🛑 [INTERRUPT] Step 4: Input buffer cleared")
        
        // 5. HANDLE TOOL EXECUTION STATE
        if isToolExecuting {
            let toolInterruptTime = lastToolStartTime > 0 ? interruptTime - lastToolStartTime : 0
            print("🛑 [INTERRUPT] Step 5: Tool execution in progress (\(String(format: "%.2f", toolInterruptTime))s since start)")
            print("🛑 [INTERRUPT] Step 5: Allowing tools to complete naturally to prevent data corruption")
            print("🛑 [INTERRUPT] Step 5: Tool results will be available for next user interaction")
            // NOTE: We don't cancel tool execution as it could cause data corruption
            // Tools will complete and update their tracking state naturally
        } else {
            print("🛑 [INTERRUPT] Step 5: No active tool execution to handle")
        }
        
        // 6. RESET CONVERSATION STATE
        conversationState = .listening
        print("🛑 [INTERRUPT] Step 6: Set conversation state to listening")
        
        print("🔄 [INTERRUPT] === INTERRUPTION COMPLETE - READY FOR NEW INPUT ===")
    }
    

    
    // MARK: - Tool Call Handling
    
    private func handleFunctionCall(_ eventData: Data) async {
        do {
            let json = try JSONSerialization.jsonObject(with: eventData) as? [String: Any]
            
            guard let callId = json?["call_id"] as? String,
                  let name = json?["name"] as? String,
                  let argumentsString = json?["arguments"] as? String else {
                print("❌ [TOOL] Invalid function call event format")
                return
            }
            
            let executionStartTime = Date().timeIntervalSince1970
            print("🔧 [TOOL] Starting execution: \(name) with ID: \(callId)")
            print("🔧 [TOOL] Execution started at: \(executionStartTime)")
            
            // Parse arguments
            let argumentsData = Data(argumentsString.utf8)
            let arguments = try JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] ?? [:]
            print("🔧 [TOOL] Raw arguments string: \(argumentsString)")
            print("🔧 [TOOL] Parsed arguments: \(arguments)")
            
            // Validate arguments are JSON-serializable to prevent crashes
            do {
                _ = try JSONSerialization.data(withJSONObject: arguments)
                print("🔧 [TOOL] Arguments validation: ✅ JSON-serializable")
            } catch {
                print("⚠️ [TOOL] Arguments validation: ❌ Not JSON-serializable - \(error)")
                print("🔧 [TOOL] This may cause issues downstream in MCP serialization")
            }
            
            // Execute the tool
            let result = await toolManager.executeTool(name: name, parameters: arguments)
            
            let executionEndTime = Date().timeIntervalSince1970
            let executionDuration = executionEndTime - executionStartTime
            print("🔧 [TOOL] Completed execution: \(name) in \(String(format: "%.2f", executionDuration))s")
            print("🔧 [TOOL] Result success: \(result.success)")
            
            // Mark tool as completed and update tracking state
            pendingToolCalls.remove(callId)
            print("🔧 [TOOL] Removed call ID \(callId) from tracking")
            print("🔧 [TOOL] Remaining pending tools: \(pendingToolCalls.count) - \(Array(pendingToolCalls))")
            
            if pendingToolCalls.isEmpty {
                isToolExecuting = false
                print("🔧 [TOOL] All tool calls completed - isToolExecuting=\(isToolExecuting)")
            } else {
                print("🔧 [TOOL] Still waiting for \(pendingToolCalls.count) tool(s) to complete")
            }
            
            // Send tool response back to OpenAI
            await sendToolResponse(callId: callId, result: result)
            
        } catch {
            print("❌ [TOOL] Failed to handle function call: \(error)")
            // Clean up tracking state on error
            if let json = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
               let callId = json["call_id"] as? String {
                pendingToolCalls.remove(callId)
                print("🔧 [TOOL] Cleaned up failed call ID: \(callId)")
            }
            
            if pendingToolCalls.isEmpty {
                isToolExecuting = false
                print("🔧 [TOOL] Reset tool execution state after error")
            }
        }
    }
    
    private func sendToolResponse(callId: String, result: ToolResult) async {
        let outputString: String
        
        if result.success {
            if let data = result.data as? String {
                outputString = data
            } else if let data = result.data as? [String: Any] {
                outputString = formatToolResponseData(data)
            } else {
                outputString = String(describing: result.data)
            }
        } else {
            outputString = "Error: \(result.data)"
        }
        
        let responseEvent = ToolResponseEvent(
            eventId: UUID().uuidString,
            item: ToolResponseItem(
                callId: callId,
                output: outputString
            )
        )
        
        do {
            try await sendEvent(responseEvent)
            print("✅ Tool response sent for call ID: \(callId)")
            print("🎤 Tool result: \(outputString)")
            
            // After tool response, request a new response to continue the conversation
            await requestResponse()
            
        } catch {
            print("❌ Failed to send tool response: \(error)")
        }
    }
    
    private func formatToolResponseData(_ data: [String: Any]) -> String {
        // Format structured data for the AI to interpret
        var formatted: [String] = []
        
        for (key, value) in data {
            let formattedKey = key.replacingOccurrences(of: "_", with: " ").capitalized
            formatted.append("\(formattedKey): \(value)")
        }
        
        return formatted.joined(separator: ", ")
    }
    
    func truncateConversation() async {
        guard isConnected else { return }
        
        // Find the last assistant item to truncate
        if let lastAssistantMessage = conversation.last(where: { $0.role == "assistant" }) {
            struct TruncateEvent: Codable {
                let type: String
                let event_id: String
                let item_id: String
            }
            
            let event = TruncateEvent(
                type: "conversation.item.truncate",
                event_id: UUID().uuidString,
                item_id: lastAssistantMessage.id.uuidString
            )
            
            do {
                try await sendEvent(event)
                print("✂️ Truncated conversation at last assistant message")
            } catch {
                print("❌ Failed to truncate conversation: \(error)")
            }
        }
    }
    
    // Note: getQueuedAudioData() is no longer needed since we play audio directly
    
    // MARK: - Clean Simple Implementation - Trust Server VAD
    
    // MARK: - Clean Server VAD Implementation
    // Trust OpenAI's server VAD for all timing, turn detection, and speech management
}

// RealtimeMessage moved to RealtimeModels.swift

// MARK: - Notification Names
extension Notification.Name {
    static let realtimeAudioReceived = Notification.Name("realtimeAudioReceived")
    static let realtimeAudioStreamCompleted = Notification.Name("realtimeAudioStreamCompleted")
    static let realtimeAudioStreamInterrupted = Notification.Name("realtimeAudioStreamInterrupted")
} 