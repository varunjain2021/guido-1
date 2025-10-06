//
//  OpenAIRealtimeService.swift
//  guido-1
//
//  Created by Varun Jain on 7/27/25.
//

import Foundation
import AVFoundation
#if !targetEnvironment(simulator)
import WebRTC
#endif
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
    // Transport selection
    private let useWebRTC: Bool = true

    
    // MARK: - VAD Configuration
    fileprivate enum VADConfig {
        static let useSemanticVAD = true  // Prefer semantic VAD per latest API guidance
        static let semanticEagerness = "low"  
        // Simple VAD settings - keeping default sensitivity for natural conversation
        static let serverThreshold: Double = 0.6  // Slightly higher for fewer false positives
        static let serverSilenceDuration = 300   // Faster turn close per docs examples
        static let serverPrefixPadding = 300     // Longer padding for better detection
        
        // Minimum speech duration threshold (easily adjustable for testing)
        // Original: 0.6s | Testing: 0.3s | Revert to 0.6s if issues arise
        static let minimumSpeechDuration: Double = 0.6  // Slightly longer to avoid premature cut-ins
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
    // WebRTC transport (only when useWebRTC == true)
    #if !targetEnvironment(simulator)
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioSender: RTCRtpSender?
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    #endif

    
    // AVAudioEngine/Player removed in WebRTC-only mode
    private var audioSession: AVAudioSession
    
    // Event handling
    private var eventSubscriptions = Set<AnyCancellable>()
    
    // Timing tracking
    private var speechStartTime: TimeInterval = 0
    private var speechTimeoutTimer: Timer?
    private var commitFallbackWorkItem: DispatchWorkItem?
    private var lastServerSpeechStartTime: TimeInterval = 0
    private var lastServerSpeechStopTime: TimeInterval = 0
    
    // Tool management
    @Published var toolManager = MCPToolCoordinator()
    
    // Audio feedback management
    @Published var audioFeedbackManager = AudioFeedbackManager()
    
    // Outbound event sender (provided by WebRTCManager)
    weak var outboundEventSender: WebRTCEventSender?
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.urlSession = URLSession.shared
        self.audioSession = AVAudioSession.sharedInstance()
        super.init()
        setupAudioSession()
        print("🚀 OpenAI Realtime Service initialized")
    }

    func setEventSender(_ sender: WebRTCEventSender) {
        self.outboundEventSender = sender
    }
    

    
    deinit {
        // Ensure proper cleanup
        speechTimeoutTimer?.invalidate()
        speechTimeoutTimer = nil
        // No WebSocket in WebRTC-only mode
        eventSubscriptions.removeAll()
        print("🗑️ OpenAI Realtime Service deallocated")
    }
    

    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            // Configure for optimized voice input with headphone support
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [
                .allowBluetooth
            ])
            
            // Rely on system-native sample rate and buffer duration for stability
            try audioSession.setActive(true)
            print("✅ Audio session configured for voice chat (native device rate/buffer)")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
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
        
        #if targetEnvironment(simulator)
        // Simulator: WebRTC not available; for your requirement, skip WebSocket fallback
        throw NSError(domain: "OpenAIRealtimeService", code: 99, userInfo: [NSLocalizedDescriptionKey: "WebRTC required (no WebSocket fallback)"])
        #else
        try await connectWebRTC(ephemeralKey: ephemeralKey)
        #endif
        
        // Play connection sound
        audioFeedbackManager.playConnectionSound()
        print("✅ [CONNECT] Connected to OpenAI Realtime API")
    }
    
    func disconnect() {
        print("🔌 Disconnecting from OpenAI Realtime API...")
        // Emit final summary on disconnect in case playback hasn't drained
        // no-op summary in WebRTC mode
        
        if useWebRTC {
            #if !targetEnvironment(simulator)
            dataChannel?.close()
            peerConnection?.close()
            dataChannel = nil
            peerConnection = nil
            localAudioSender = nil
            peerConnectionFactory = nil
            #endif
        } else {
        // Stop audio streaming immediately
        isAIResponding = false
        NotificationCenter.default.post(name: .realtimeAudioStreamCompleted, object: nil)
        }
        
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
        
        // No WebSocket fallback path
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
    
    // MARK: - Private Methods (WebRTC only)

    #if !targetEnvironment(simulator)
    private func connectWebRTC(ephemeralKey: String) async throws {
        // Init factory
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        guard let factory = peerConnectionFactory else { throw NSError(domain: "OpenAIRealtimeService", code: 10, userInfo: [NSLocalizedDescriptionKey: "PC factory init failed"]) }
        // Create peer connection
        let config = RTCConfiguration()
        config.iceServers = []
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        // Audio track with EC/NS/AGC enabled
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: [
            "googEchoCancellation": "true",
            "googNoiseSuppression": "true",
            "googAutoGainControl": "true"
        ], optionalConstraints: nil)
        let audioSource = factory.audioSource(with: audioConstraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        localAudioSender = peerConnection?.add(audioTrack, streamIds: ["stream0"])
        // Data channel for events
        let dcConfig = RTCDataChannelConfiguration()
        dataChannel = peerConnection?.dataChannel(forLabel: "oai-events", configuration: dcConfig)
        dataChannel?.delegate = self
        // Create offer
        let offer = try await peerConnection?.offer(for: constraints)
        try await peerConnection?.setLocalDescription(offer!)
        // Wait for ICE gathering to complete so SDP includes candidates (no trickle)
        try await waitForIceGatheringComplete(timeoutMs: 4000)
        guard let finalLocalSdp = peerConnection?.localDescription?.sdp else {
            throw NSError(domain: "OpenAIRealtimeService", code: 13, userInfo: [NSLocalizedDescriptionKey: "Missing localDescription SDP after ICE gather"]) }
        // Send SDP to OpenAI and set remote description
        let answerSDP = try await sendSDPToOpenAI(sdp: finalLocalSdp, token: ephemeralKey)
        let remoteDescription = RTCSessionDescription(type: .answer, sdp: answerSDP)
        try await peerConnection?.setRemoteDescription(remoteDescription)
        connectionStatus = "Connected"
        isConnected = true
        print("✅ Connected to OpenAI Realtime API via WebRTC")
        // Send session.update over data channel once connected
        try await configureSessionOverDataChannel()
    }

    private func waitForIceGatheringComplete(timeoutMs: Int) async throws {
        let deadline = CFAbsoluteTimeGetCurrent() + Double(timeoutMs) / 1000.0
        while CFAbsoluteTimeGetCurrent() < deadline {
            if peerConnection?.iceGatheringState == .complete { return }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        print("⚠️ [WebRTC] ICE gathering timeout; proceeding with partial candidates")
    }

    private func sendSDPToOpenAI(sdp: String, token: String) async throws -> String {
        func exchange(model: String) async throws -> (String, Int, String) {
            guard let url = URL(string: "https://api.openai.com/v1/realtime?model=\(model)") else {
                throw NSError(domain: "OpenAIRealtimeService", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid Realtime URL"])
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
            request.setValue("application/sdp", forHTTPHeaderField: "Accept")
            request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
            request.httpBody = sdp.data(using: .utf8)
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            return (body, status, model)
        }
        let result = try await exchange(model: "gpt-realtime")
        guard result.1 == 200 else {
            let message = "Failed to exchange SDP for model=\(result.2) status=\(result.1) body=\(result.0)"
            print("🚨 [WebRTC] \(message)")
            throw NSError(
                domain: "OpenAIRealtimeService",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return result.0
    }
    
    private func configureSessionOverDataChannel() async throws {
        // Build same payload as configureSession(), but send over data channel
        let eventId = UUID().uuidString
        let vadType = VADConfig.useSemanticVAD ? "semantic_vad" : "server_vad"
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
        let toolsArray: [[String: Any]] = {
            do {
                let defs = MCPToolCoordinator.getAllToolDefinitions()
                let data = try JSONEncoder().encode(defs)
                return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            } catch { return [] }
        }()
        // For session.update over WebRTC data channel, avoid unknown session.* keys.
        let sessionDict: [String: Any] = [
            "instructions": realtimeSystemInstructions(),
            "tool_choice": "auto",
            "tools": toolsArray
        ]
        let payload: [String: Any] = [
            "type": "session.update",
            "event_id": eventId,
            "session": sessionDict
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return }
        if let dc = dataChannel, dc.readyState == .open {
            let buffer = RTCDataBuffer(data: json, isBinary: false)
            dc.sendData(buffer)
            print("🔧 [WebRTC] Sent session.update over data channel")
        } else {
            print("⚠️ [WebRTC] Data channel not open; session.update not sent")
        }
    }
    
    // Helpers to send events over WebRTC data channel
    private func sendEventOverDataChannel<T: Encodable>(_ event: T) async {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(event),
              let json = String(data: data, encoding: .utf8) else {
            print("❌ [WebRTC] Failed to encode event for data channel send")
            return
        }
        print("📤 [WebRTC] Sending event via sender: \(json.prefix(160))...")
        await MainActor.run { [weak self] in
            self?.outboundEventSender?.sendJSONString(json)
        }
    }
    
    private func requestResponseOverDataChannel() async {
        let body: [String: Any] = ["type": "response.create", "event_id": UUID().uuidString]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return }
        print("📤 [WebRTC] Sending response.create via sender: \(json)")
        await MainActor.run { [weak self] in
            self?.outboundEventSender?.sendJSONString(json)
        }
    }
    #endif
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
    
    // configureSession removed (WebRTC mode)

    // sendRawEvent removed
    
    // startListening removed
    
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
    
    // handleWebSocketMessage removed

    #if !targetEnvironment(simulator)
    // MARK: - WebRTC delegates
    nonisolated private func onDataChannelMessage(_ buffer: RTCDataBuffer) {
        if let text = String(data: buffer.data, encoding: .utf8) {
            Task { @MainActor in
                await self.handleIncomingEvent(text)
            }
        }
    }
    #endif
    
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
                    // Rely on server interrupt_response for barge-in; no client duck/cancel
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
                    let guarded = NavigationStyleGuard.enforce(conversation[lastStreamingIndex].content)
                    conversation[lastStreamingIndex].content = guarded.text
                    print("✅ AI transcript completed (guard applied: \(guarded.violations)): '\(conversation[lastStreamingIndex].content)'")
                } else {
                    print("⚠️ No streaming AI message found to mark as complete")
                }
                
            case "response.audio.delta", "response.output_audio.delta":
                // WebRTC handles audio output; ignore deltas in data channel mode
                _ = ()
                
            case "response.audio.done", "response.output_audio.done":
                print("🎵 [AI_AUDIO] Audio response completed - setting isAIResponding=false")
                // Re-enable microphone input after AI finishes speaking
                isAIResponding = false
                
                // Emit snapshot at response done (playback may still be flushing)
                // no-op summary in WebRTC mode
                
                // No buffer clearing in WebRTC mode
                
                // Rely on natural end of voice output; no completion sound
                
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
                    let guarded = NavigationStyleGuard.enforce(conversation[idx].content)
                    conversation[idx].content = guarded.text
                    print("✅ Output text completed (guard applied: \(guarded.violations))")
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
                print("🗣️ [VAD] Current state: AI responding=\(isAIResponding), tool executing=\(isToolExecuting)")
                print("🗣️ [VAD] Time since: last response=\(String(format: "%.2f", timeSinceLastResponse))s, buffer clear=\(String(format: "%.2f", timeSinceLastClear))s, tool start=\(String(format: "%.2f", timeSinceToolStart))s")
                print("🗣️ [VAD] Pending tool calls: \(pendingToolCalls.count), Response ID: \(currentResponseId ?? "none")")
                
                // ENHANCED INTERRUPTION DETECTION
                // Check if we need to interrupt ongoing AI activity (response, audio playback, or tool execution)
                let shouldInterrupt = isAIResponding || isToolExecuting
                
                if shouldInterrupt {
                    if isToolExecuting {
                        print("🛑 [INTERRUPT] User speaking during tool execution - \(pendingToolCalls.count) tools pending")
                    } else if isAIResponding {
                        print("🛑 [INTERRUPT] User speaking during AI response generation")
                    }
                    // WebRTC handles playback; nothing to stop locally
                } else {
                    print("🗣️ [VAD] Speech started during idle state - normal turn taking")
                }
                
                speechStartTime = currentTime
                conversationState = .listening

                
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
                // no-op metrics; play minimal feedback
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
                // WebRTC path: ignore
                _ = ()
                
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
    
    // handleAudioDelta removed in WebRTC mode
    
    // sendEvent removed in WebRTC mode
    
    // MARK: - Public Methods
    // sendAudioData removed
    
    // requestResponse handled by WebRTC data channel elsewhere

    private func sendManualCommitAndRequest() async { /* removed: rely on server VAD auto-response */ }
    
    func clearInputAudioBuffer() async { /* no-op in WebRTC mode */ }
    
    // Removed: output_audio_buffer.clear is WebRTC-only; not supported over WebSocket
    
    func cancelResponse() async { /* TODO: send over WebRTC data channel if needed */ }
    
    private func handleUserInterruption() async {
        let interruptTime = Date().timeIntervalSince1970
        print("🛑 [INTERRUPT] === USER INTERRUPTION DETECTED ===")
        print("🛑 [INTERRUPT] Time: \(interruptTime)")
        print("🛑 [INTERRUPT] State before: AI responding=\(isAIResponding), tool executing=\(isToolExecuting)")
        print("🛑 [INTERRUPT] Pending tools: \(pendingToolCalls.count) - \(Array(pendingToolCalls))")
        print("🛑 [INTERRUPT] Current response ID: \(currentResponseId ?? "none")")
        
        // 1. IMMEDIATE STATE UPDATES
        isAIResponding = false
        print("🛑 [INTERRUPT] Step 1: Set isAIResponding=false")
        
        // 2. DUCK/STOP AUDIO STREAMING IMMEDIATELY
        // WebRTC handles playback; no local duck/stop
        
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
        
        // 6. RESET CONVERSATION STATE AND PREPARE TO UNDUCK ON NEXT AI AUDIO
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
                // Prefer JSON for machine-readability by the model
                if let json = try? JSONSerialization.data(withJSONObject: data),
                   let text = String(data: json, encoding: .utf8) {
                    outputString = text
                } else {
                    outputString = String(describing: data)
                }
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
        
        await sendEventOverDataChannel(responseEvent)
            print("✅ Tool response sent for call ID: \(callId)")
            print("🎤 Tool result: \(outputString)")
            // After tool response, request a new response to continue the conversation
        await requestResponseOverDataChannel()
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
            
            await sendEventOverDataChannel(event)
                print("✂️ Truncated conversation at last assistant message")
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

// MARK: - WebRTC Event Sink to reuse existing handlers
protocol WebRTCEventSink: AnyObject {
    func handleRealtimeEvent(text: String)
}

extension OpenAIRealtimeService: WebRTCEventSink {
    func handleRealtimeEvent(text: String) {
        Task { @MainActor in
            await self.handleIncomingEvent(text)
        }
    }
}

// MARK: - Public helpers for WebRTCManager integration
extension OpenAIRealtimeService {
    func getToolDefinitionsJSON() -> [[String: Any]] {
        do {
            let defs = MCPToolCoordinator.getAllToolDefinitions()
            let data = try JSONEncoder().encode(defs)
            return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        } catch {
            print("⚠️ Failed to encode tool definitions: \(error)")
            return []
        }
    }
    
    func realtimeSystemInstructions() -> String {
        return """
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
                - When recommending places (e.g., coffee shops, restaurants, attractions), check operating hours against the current local time using get_local_time and account for estimated travel time so the user arrives while the place is open; prefer options that will be open upon arrival
                - Consider current and near-term weather via get_weather when suggesting outdoor activities or travel modes; adapt recommendations (e.g., indoor options during rain, shaded routes in heat)
                - If a target place is closed or closing soon, suggest nearby alternatives with their operating hours and an ETA, and explain the tradeoffs briefly
                - IMPORTANT: You have access to the user's current location through the get_user_location tool. ALWAYS call this first when you need location data. If clarification is needed, present a hypothesis based on the location data (e.g., "I see you're at [address] - shall I give you directions from there?")
                - Confirm the traveler’s mode (walking, driving, transit, etc.) and ask what they can see directly in front of them before giving directions so you can ground orientation; think like a local guide standing beside them
                - When appropriate, check the user's location, nearby places, weather, and other contextual information
                - Offer specific, actionable suggestions based on real data
                - ALWAYS briefly acknowledge before using tools with phrases like "let me check that for you", "let me find that information", or "give me a moment to look that up" - this provides important user feedback during processing
                - After using tools and getting results, naturally transition into sharing the information without additional artificial completion sounds
                
                IMPORTANT: 
                - Engage in natural conversation flow. The system uses voice activity detection to understand when you should respond. Trust the turn-taking system and respond naturally when prompted.
                - DIRECTIONS STYLE (STRICT):
                  • NEVER use compass directions ("north", "south", "east", "west", "northeast", "NW", etc.). Treat these as forbidden and rephrase before speaking.
                  • NEVER use arbitrary measurements like feet, meters, or yards. Keep everything relational to what the user can see and short spans like "about a block" or "just past the next light".
                  • ALWAYS use left/right and clear visual anchors the user can see: named intersections, major storefronts (Starbucks, McDonald's, Wells Fargo), park gates, bridges, subway entrances, transit stops, or natural features.
                  • Keep each step grounded in what the user can see within a block or two; reference multiple nearby anchors (stores, restaurants, banks, transit, parks) whenever possible so the user can confirm they’re on track.
                  • Start with a simple orienting cue if needed (e.g., "Face the river; with the river on your left...") and then give left/right steps.
                  • Break directions into short checkpoints and explicitly ask the user to confirm after each one ("Let me know when you reach the T intersection with the parking garage ahead"). Never give more than the next two steps at a time.
                  • When the user confirms a checkpoint, restate their position using the visible anchors, offer a quick confidence boost ("perfect, you should see the cafe on your right"), and guide them to the next step.
                  • Prefer step-by-step instructions: "Walk one block to 71st Street, then turn right. Keep the Starbucks on your left; the station entrance will be just past it on the corner."
                  • If you catch yourself producing compass words, immediately self-correct and restate using left/right + landmark anchors.
                - CRITICAL AUDIO FEEDBACK PATTERN: When you need to use tools, ALWAYS follow this sequence:
                  1. First, speak an acknowledgment like "let me check that for you" or "let me look that up"
                  2. Then call your tools (ALWAYS call get_user_location first if you need location data)
                  3. Finally, naturally share the results when tools complete
                - NEVER ask users "where are you?" - instead, get their location automatically and present a hypothesis for confirmation if needed (e.g., "I see you're near Riverside Boulevard - is that where you'd like directions from?")
                - INTERRUPTION AWARENESS: When a user interrupts you mid-response, acknowledge what you were doing before switching context.
                """
    }
}

#if !targetEnvironment(simulator)
// MARK: - RTCPeerConnectionDelegate
extension OpenAIRealtimeService: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChange: RTCSignalingState) {
        print("🔄 [WebRTC] Signaling state: \(stateChange)")
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("🎵 [WebRTC] Remote stream added (audio will play via system)")
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("🔇 [WebRTC] Remote stream removed")
    }
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("🤝 [WebRTC] Should negotiate")
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("🧊 [WebRTC] ICE connection state: \(newState)")
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("🧊 [WebRTC] ICE gathering state: \(newState)")
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("🧊 [WebRTC] ICE candidate generated")
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("🧊 [WebRTC] ICE candidates removed")
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("📡 [WebRTC] Data channel opened")
        dataChannel.delegate = self
    }
}

// MARK: - RTCDataChannelDelegate
extension OpenAIRealtimeService: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("📡 [WebRTC] Data channel state: \(dataChannel.readyState)")
    }
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        onDataChannelMessage(buffer)
    }
}
#endif