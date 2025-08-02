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
                    self.threshold = OpenAIRealtimeService.VADConfig.serverThreshold
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
class OpenAIRealtimeService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    
    // MARK: - VAD Configuration
    fileprivate enum VADConfig {
        static let useSemanticVAD = false  // Use server VAD for reliable turn detection
        static let semanticEagerness = "medium"  
        // Simple VAD settings - trust OpenAI defaults with minimal changes
        static let serverThreshold: Double = 0.5  // Default threshold
        static let serverSilenceDuration = 500   // Default silence duration
        static let serverPrefixPadding = 200     // Default prefix padding
        
        // Minimum speech duration threshold (easily adjustable for testing)
        // Original: 0.6s | Testing: 0.3s | Revert to 0.6s if issues arise
        static let minimumSpeechDuration: Double = 0.6
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
    
    // Audio playback
    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerQueue: [Data] = []
    private var isPlayingQueue = false
    private let audioPlayerLock = NSLock()
    

    
    // Tool management
    @Published var toolManager = RealtimeToolManager()
    
    // Event handling
    private var eventSubscriptions = Set<AnyCancellable>()
    
    // Timing tracking
    private var speechStartTime: TimeInterval = 0
    private var speechTimeoutTimer: Timer?
    
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
            // Configure for optimized voice input with enhanced microphone sensitivity
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [
                .defaultToSpeaker, 
                .allowBluetoothA2DP, 
                .allowBluetooth,
                .mixWithOthers
            ])
            
            // Set preferred sample rate and buffer duration for better voice capture
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredIOBufferDuration(0.005) // 5ms for low latency
            
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
        
        inputNode?.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { [weak self] (buffer, time) in
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
            
            let audioData = self.convertAudioBufferToData(buffer)
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
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        
        // Stop audio playback
        audioPlayerLock.lock()
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlayerQueue.removeAll()
        isPlayingQueue = false
        audioPlayerLock.unlock()
        
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
    
    private func convertAudioBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let channelData = buffer.floatChannelData?[0] else {
            return Data()
        }
        
        let frameCount = Int(buffer.frameLength)
        var int16Array = [Int16](repeating: 0, count: frameCount)
        
        for i in 0..<frameCount {
            let sample = channelData[i] * 32767.0
            int16Array[i] = Int16(max(-32767, min(32767, sample)))
        }
        
        return Data(bytes: int16Array, count: frameCount * MemoryLayout<Int16>.size)
    }
    
    // MARK: - Audio Playback
    private func playAudio(data: Data) {
        audioPlayerLock.lock()
        defer { audioPlayerLock.unlock() }
        
        audioPlayerQueue.append(data)
        
        if !isPlayingQueue {
            processAudioQueue()
        }
    }
    
    private func processAudioQueue() {
        guard !audioPlayerQueue.isEmpty else {
            isPlayingQueue = false
            return
        }
        
        isPlayingQueue = true
        let audioData = audioPlayerQueue.removeFirst()
        
        // Convert PCM16 data to playable format
        let wavData = convertPCM16ToWAV(audioData)
        
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            print("🔊 Playing audio chunk (\(audioData.count) bytes)")
        } catch {
            print("❌ Failed to play audio: \(error)")
            processAudioQueue() // Continue with next item
        }
    }
    
    private func convertPCM16ToWAV(_ pcmData: Data) -> Data {
        var wavData = Data()
        
        // WAV header
        let sampleRate: UInt32 = 24000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(pcmData)
        
        return wavData
    }
    
    // MARK: - AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.processAudioQueue()
        }
    }
    
    // MARK: - Streaming Control (for compatibility with UI)
    func startStreaming() {
        // Audio capture is managed automatically by connect/disconnect
        print("🎤 Streaming control - already handled by connection state")
    }
    
    func stopStreaming() {
        // Audio capture is managed automatically by connect/disconnect
        print("🔇 Streaming control - already handled by connection state")
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
    }
    
    // MARK: - Connection Management
    func connect() async throws {
        print("🔌 [CONNECT] Connecting to OpenAI Realtime API...")
        
        // Get ephemeral token
        let ephemeralKey = try await getEphemeralKey()
        print("🔐 [CONNECT] Retrieved ephemeral key")
        
        // Create WebSocket connection
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17") else {
            throw NSError(domain: "OpenAIRealtimeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid WebSocket URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(ephemeralKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "openai-beta")
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
        
        print("✅ [CONNECT] Connected to OpenAI Realtime API")
    }
    
    func disconnect() {
        print("🔌 Disconnecting from OpenAI Realtime API...")
        
        // Stop audio capture
        stopAudioCapture()
        
        // Stop audio streaming immediately
        isAIResponding = false
        NotificationCenter.default.post(name: .realtimeAudioStreamCompleted, object: nil)
        
        // Clear speech tracking state
        speechStartTime = 0

        
        // Close WebSocket connection
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        connectionStatus = "Disconnected"
        
        // Audio cleanup is handled in stopAudioCapture()
        
        print("✅ Disconnected from OpenAI Realtime API")
    }
    
    // MARK: - Private Methods
    private func getEphemeralKey() async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/realtime/sessions") else {
            throw NSError(domain: "OpenAIRealtimeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = [
            "model": "gpt-4o-realtime-preview-2025-06-03",
            "voice": "alloy"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAIRealtimeService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get ephemeral key"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let clientSecret = json?["client_secret"] as? [String: Any],
              let value = clientSecret["value"] as? String else {
            throw NSError(domain: "OpenAIRealtimeService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return value
    }
    
    private func configureSession() async throws {
        let sessionConfig = SessionUpdateEvent(
            eventId: UUID().uuidString,
            session: SessionUpdateEvent.SessionConfig(
                instructions: """
                You are Guido, a helpful and conversational AI travel companion with access to real-time tools and location data. You're designed to have natural, flowing conversations about travel while providing personalized, location-aware assistance.
                
                Guidelines:
                - Keep responses natural and conversational
                - Be warm, helpful, and engaging
                - Use a friendly, casual tone
                - Ask follow-up questions to keep conversations flowing
                - Provide practical travel advice when relevant
                - Be concise but informative
                - Respond quickly and smoothly for natural conversation flow
                - Use your tools proactively to provide personalized recommendations
                - When appropriate, check the user's location, nearby places, weather, and other contextual information
                - Offer specific, actionable suggestions based on real data
                
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
                
                IMPORTANT: Engage in natural conversation flow. The system uses voice activity detection to understand when you should respond. Trust the turn-taking system and respond naturally when prompted.
                """,
                voice: "alloy",
                inputAudioFormat: "pcm16",
                outputAudioFormat: "pcm16",
                inputAudioTranscription: SessionUpdateEvent.SessionConfig.TranscriptionConfig(),
                turnDetection: SessionUpdateEvent.SessionConfig.TurnDetectionConfig(),
                temperature: 0.75,
                maxResponseOutputTokens: "inf",
                toolChoice: "auto",
                tools: RealtimeToolManager.getAllToolDefinitions()
            )
        )
        
        try await sendEvent(sessionConfig)
        let vadType = VADConfig.useSemanticVAD ? "semantic_vad" : "server_vad"
        let eagerness = VADConfig.useSemanticVAD ? VADConfig.semanticEagerness : "N/A"
        print("✅ Session configured with \(vadType) (eagerness: \(eagerness), auto-response: true, interrupts: enabled)")
        print("🔧 VAD Settings: Type=\(vadType), Threshold=\(VADConfig.serverThreshold), SilenceDuration=\(VADConfig.serverSilenceDuration)ms, PrefixPadding=\(VADConfig.serverPrefixPadding)ms")
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
                
            case "response.audio_transcript.delta":
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
                
            case "response.audio_transcript.done":
                // Mark the last streaming AI message as complete
                print("🔍 Looking for streaming AI message to complete. Conversation has \(conversation.count) messages")
                if let lastStreamingIndex = conversation.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                    conversation[lastStreamingIndex].isStreaming = false
                    print("✅ AI transcript completed: '\(conversation[lastStreamingIndex].content)'")
                } else {
                    print("⚠️ No streaming AI message found to mark as complete")
                }
                
            case "response.audio.delta":
                if let audioEvent = try? JSONDecoder().decode(AudioDeltaEvent.self, from: eventData) {
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
                
            case "response.audio.done":
                print("🎵 [AI_AUDIO] Audio response completed - setting isAIResponding=false")
                // Re-enable microphone input after AI finishes speaking
                isAIResponding = false
                
                // Clear any residual audio buffer that might cause transcription issues
                await clearInputAudioBuffer()
                
                print("✅ [AI_AUDIO] AI audio completed - buffer cleared - ready for user input")
                // Notify audio manager that streaming should finish
                NotificationCenter.default.post(name: .realtimeAudioStreamCompleted, object: nil)
                
            case "response.done":
                lastResponseCompleteTime = Date().timeIntervalSince1970
                print("✅ [RESPONSE] Response completed at \(lastResponseCompleteTime) - resetting state")
                isAIResponding = false
                conversationState = .idle  // Reset to idle - let server VAD manage state
                
                // Reset speech tracking for next conversation turn
                speechStartTime = 0
                print("🔄 [RESPONSE] Ready for next speech input")
                
            case "input_audio_buffer.speech_started":
                let currentTime = Date().timeIntervalSince1970
                let timeSinceLastResponse = lastResponseCompleteTime > 0 ? currentTime - lastResponseCompleteTime : 0
                let timeSinceLastClear = lastClearBufferTime > 0 ? currentTime - lastClearBufferTime : 0
                print("🗣️ [VAD] Speech started detected by VAD at \(currentTime)")
                print("🗣️ [VAD] Previous speech start: \(speechStartTime), AI responding: \(isAIResponding), playing: \(isPlayingQueue)")
                print("🗣️ [VAD] Time since last response: \(timeSinceLastResponse)s, since last buffer clear: \(timeSinceLastClear)s")
                
                // Log if speech starts during audio playback (might be user interruption or feedback)
                if isPlayingQueue && timeSinceLastResponse < 2.0 {
                    print("⚠️ [VAD] Speech started during audio playback - could be user interruption or feedback")
                }
                
                speechStartTime = currentTime
                conversationState = .listening
                
                // Server VAD handles speech timeouts automatically
                
                // Let server VAD handle interruptions automatically - no manual intervention needed
                
            case "input_audio_buffer.speech_stopped":
                let currentTime = Date().timeIntervalSince1970
                let speechDuration = speechStartTime > 0 ? currentTime - speechStartTime : 0
                print("🤐 [VAD] Speech stopped at \(currentTime) - duration: \(speechDuration)s")
                print("🤐 [VAD] AI responding: \(isAIResponding), conversation state: \(conversationState)")
                
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
                
            case "response.created":
                print("🤖 AI response created")
                conversationState = .thinking
                
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
                print("🔧 Function call arguments completed")
                await handleFunctionCall(eventData)
                
            case "error":
                if let errorData = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   let error = errorData["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ OpenAI API Error: \(message)")
                    
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
    
    func clearOutputAudioBuffer() async {
        guard isConnected else { return }
        
        struct ClearOutputBufferEvent: Codable {
            let type: String
            let event_id: String
        }
        
        let event = ClearOutputBufferEvent(
            type: "output_audio_buffer.clear",
            event_id: UUID().uuidString
        )
        
        do {
            try await sendEvent(event)
            print("🧹 Cleared output audio buffer")
        } catch {
            print("❌ Failed to clear output audio buffer: \(error)")
        }
    }
    
    func cancelResponse() async {
        guard isConnected else { return }
        
        struct CancelResponseEvent: Codable {
            let type: String
            let event_id: String
        }
        
        let event = CancelResponseEvent(
            type: "response.cancel",
            event_id: UUID().uuidString
        )
        
        do {
            try await sendEvent(event)
            print("❌ Cancelled active response")
        } catch {
            print("❌ Failed to cancel response: \(error)")
        }
    }
    
    private func handleUserInterruption() async {
        print("🛑 [INTERRUPT] Handling user interruption - stopping AI immediately")
        print("🛑 [INTERRUPT] State before: isAIResponding=\(isAIResponding), speechStartTime=\(speechStartTime)")
        
        // Set state immediately to prevent further audio processing
        isAIResponding = false
        
        // Stop audio streaming immediately (not graceful completion)
        NotificationCenter.default.post(name: .realtimeAudioStreamInterrupted, object: nil)
        
        // Cancel current AI response
        await cancelResponse()
        print("🛑 [INTERRUPT] AI response cancelled")
        
        // Clear output audio buffer to stop AI speech immediately
        await clearOutputAudioBuffer()
        print("🛑 [INTERRUPT] Output buffer cleared")
        
        // Clear input buffer to start fresh
        await clearInputAudioBuffer()
        print("🛑 [INTERRUPT] Input buffer cleared")
        
        print("🔄 [INTERRUPT] Interruption handled - ready for user input")
    }
    

    
    // MARK: - Tool Call Handling
    
    private func handleFunctionCall(_ eventData: Data) async {
        do {
            let json = try JSONSerialization.jsonObject(with: eventData) as? [String: Any]
            
            guard let callId = json?["call_id"] as? String,
                  let name = json?["name"] as? String,
                  let argumentsString = json?["arguments"] as? String else {
                print("❌ Invalid function call event format")
                return
            }
            
            print("🔧 Executing function: \(name) with ID: \(callId)")
            
            // Parse arguments
            let argumentsData = Data(argumentsString.utf8)
            let arguments = try JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] ?? [:]
            
            // Execute the tool
            let result = await toolManager.executeTool(name: name, parameters: arguments)
            
            // Send tool response back to OpenAI
            await sendToolResponse(callId: callId, result: result)
            
        } catch {
            print("❌ Failed to handle function call: \(error)")
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