//
//  SimpleRealtimeService.swift
//  guido-1
//
//  Created by Varun Jain on 7/30/25.
//

import Foundation
#if !targetEnvironment(simulator)
import WebRTC
#endif
import AVFoundation

@MainActor
class SimpleRealtimeService: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    @Published var conversation: [RealtimeMessage] = []
    
    private let apiKey: String
    #if !targetEnvironment(simulator)
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCRtpSender?
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    #endif
    
    // Audio setup
    private let audioSession = AVAudioSession.sharedInstance()
    
    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        #if !targetEnvironment(simulator)
        setupWebRTC()
        #endif
        setupAudioSession()
        print("🚀 Simple Realtime Service initialized")
    }
    
    #if !targetEnvironment(simulator)
    private func setupWebRTC() {
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
    }
    #endif
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
            print("✅ Audio session configured for WebRTC with headphone support")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    func connect() async throws {
        print("🔌 Starting simple realtime connection...")
        
        #if targetEnvironment(simulator)
        // Simulator mode - just set connected state
        await MainActor.run {
            isConnected = true
            connectionStatus = "Connected (Simulator Mode)"
        }
        print("📱 Running in simulator - WebRTC features disabled")
        return
        #else
        // Get ephemeral token
        let token = try await getEphemeralToken()
        
        // Create peer connection
        let config = RTCConfiguration()
        config.iceServers = []
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let factory = peerConnectionFactory else {
            throw NSError(domain: "SimpleRealtimeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Peer connection factory not initialized"])
        }
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        
        // Add audio track
        try await addAudioTrack()
        
        // Create data channel
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannel = peerConnection?.dataChannel(forLabel: "oai-events", configuration: dataChannelConfig)
        dataChannel?.delegate = self
        
        // Create offer
        let offer = try await peerConnection?.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        try await peerConnection?.setLocalDescription(offer!)
        
        // Send SDP to OpenAI
        let answer = try await sendSDPToOpenAI(sdp: offer!.sdp, token: token)
        let remoteDescription = RTCSessionDescription(type: .answer, sdp: answer)
        try await peerConnection?.setRemoteDescription(remoteDescription)
        
        connectionStatus = "Connected"
        isConnected = true
        print("✅ Connected to OpenAI Realtime API via WebRTC")
        #endif
    }
    
    #if !targetEnvironment(simulator)
    private func addAudioTrack() async throws {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["googEchoCancellation": "true", "googNoiseSuppression": "true"],
            optionalConstraints: nil
        )
        
        guard let factory = peerConnectionFactory else {
            throw NSError(domain: "SimpleRealtimeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create peer connection factory"])
        }
        
        let audioSource = factory.audioSource(with: constraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        
        localAudioTrack = peerConnection?.add(audioTrack, streamIds: ["stream0"])
    }
    #endif
    
    private func getEphemeralToken() async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/realtime/sessions") else {
            throw NSError(domain: "SimpleRealtimeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "model": "gpt-4o-realtime-preview-2024-12-17",
            "voice": "coral"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "SimpleRealtimeService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get token"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientSecret = json["client_secret"] as? [String: Any],
              let token = clientSecret["value"] as? String else {
            throw NSError(domain: "SimpleRealtimeService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid token response"])
        }
        
        return token
    }
    
    private func sendSDPToOpenAI(sdp: String, token: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17") else {
            throw NSError(domain: "SimpleRealtimeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = sdp.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "SimpleRealtimeService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to exchange SDP"])
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func disconnect() {
        #if !targetEnvironment(simulator)
        dataChannel?.close()
        peerConnection?.close()
        
        dataChannel = nil
        peerConnection = nil
        localAudioTrack = nil
        #endif
        
        connectionStatus = "Disconnected"
        isConnected = false
        
        print("✅ Disconnected from OpenAI Realtime API")
    }
    
    private func sendEvent(_ event: [String: Any]) {
        #if targetEnvironment(simulator)
        print("📱 Simulator mode: Would send event \(event["type"] ?? "unknown")")
        return
        #else
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let _ = String(data: data, encoding: .utf8) else {
            print("❌ Failed to serialize event")
            return
        }
        
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        dataChannel?.sendData(buffer)
        print("📤 Sent event: \(event["type"] ?? "unknown")")
        #endif
    }
    
    func requestResponse() {
        sendEvent([
            "type": "response.create",
            "event_id": UUID().uuidString
        ])
    }
}

#if !targetEnvironment(simulator)
// MARK: - RTCPeerConnectionDelegate
extension SimpleRealtimeService: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChange: RTCSignalingState) {
        print("🔄 Signaling state: \(stateChange)")
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("🎵 Remote audio stream added")
        // Audio will automatically play through speakers
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("🔇 Remote audio stream removed")
    }
    
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("🤝 Should negotiate")
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("🧊 ICE connection state: \(newState)")
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("🧊 ICE gathering state: \(newState)")
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("🧊 ICE candidate generated")
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("🧊 ICE candidates removed")
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("📡 Data channel opened")
    }
}

// MARK: - RTCDataChannelDelegate  
extension SimpleRealtimeService: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("📡 Data channel state: \(dataChannel.readyState)")
        if dataChannel.readyState == .open {
            Task { @MainActor in
                // Request initial response
                requestResponse()
            }
        }
    }
    
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = buffer.data
        guard let _ = String(data: data, encoding: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["type"] as? String else {
            print("❌ Failed to parse event")
            return
        }
        
        print("📥 Received event: \(eventType)")
        
        Task { @MainActor in
            // Handle transcript events
            if eventType == "conversation.item.input_audio_transcription.completed",
               let transcript = json["transcript"] as? String {
                let message = RealtimeMessage(role: "user", content: transcript, timestamp: Date())
                conversation.append(message)
                print("👤 User said: \(transcript)")
            }
            
            if eventType == "response.audio_transcript.done",
               let transcript = json["transcript"] as? String {
                let message = RealtimeMessage(role: "assistant", content: transcript, timestamp: Date())
                conversation.append(message)
                print("🤖 AI said: \(transcript)")
            }
        }
    }
}
#endif

// RealtimeMessage moved to RealtimeModels.swift