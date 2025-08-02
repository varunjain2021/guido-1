//
//  ListeningView.swift
//  guido-1
//
//  Created by Varun Jain on 7/26/25.
//

import SwiftUI

struct ListeningView: View {
    
    enum ViewState {
        case idle
        case recording
        case processing
        case speaking
    }
    
    @State private var state: ViewState = .idle
    @State private var conversation: [ChatMessage] = []
    @State private var micAnimation = false
    
    @StateObject private var audioManager = AudioManager()
    private let openAIChatService: OpenAIChatService
    private let elevenLabsService: ElevenLabsService
    private let initialMessage: String?
    
    init(openAIAPIKey: String, elevenLabsAPIKey: String, initialMessage: String? = nil) {
        print("🚀 ListeningView initializing...")
        self.openAIChatService = OpenAIChatService(apiKey: openAIAPIKey)
        self.elevenLabsService = ElevenLabsService(apiKey: elevenLabsAPIKey)
        self.initialMessage = initialMessage
        print("✅ ListeningView initialized")
    }
    
    var body: some View {
        VStack(spacing: 30) {
            // Header with modern VAD status
            VStack(spacing: 16) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(vadStatusColor)
                    .scaleEffect(state == .recording ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: state)
                
                Text("Guido AI Assistant")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            
            // Modern VAD Status Display
            VStack(spacing: 12) {
                // VAD Status Message
                Text(audioManager.vadStatus)
                    .font(.headline)
                    .foregroundColor(vadStatusTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // VAD Confidence Meter (when active)
                if audioManager.vadConfidence > 0 {
                    VStack(spacing: 8) {
                        Text("VAD Confidence")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("0%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            ProgressView(value: audioManager.vadConfidence, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: vadConfidenceColor))
                                .scaleEffect(y: 2)
                            
                            Text("100%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("\(Int(audioManager.vadConfidence * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(vadConfidenceColor)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Audio Level Visualization
                WaveformView(audioLevel: audioManager.audioLevel)
                    .frame(height: 60)
                    .padding(.horizontal)
            }
            
            // Action Button
            Button(action: handleMainAction) {
                HStack(spacing: 12) {
                    Image(systemName: buttonIcon)
                        .font(.title2)
                    Text(buttonText)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 15)
                .background(buttonColor)
                .clipShape(Capsule())
                .scaleEffect(micAnimation ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: micAnimation)
            }
            .disabled(state == .processing || state == .speaking)
            
            // Conversation History
            if !conversation.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conversation) { message in
                            ChatMessageBubble(message: message)
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            setupInitialMessage()
        }
    }
    
    // MARK: - Computed Properties for Modern VAD
    
    private var vadStatusColor: Color {
        if audioManager.vadConfidence > 0.7 {
            return .green
        } else if audioManager.vadConfidence > 0.3 {
            return .orange
        } else if state == .recording {
            return .red
        } else {
            return .blue
        }
    }
    
    private var vadStatusTextColor: Color {
        if audioManager.vadStatus.contains("🗣️") {
            return .green
        } else if audioManager.vadStatus.contains("🤐") {
            return .orange
        } else if audioManager.vadStatus.contains("⚠️") || audioManager.vadStatus.contains("❌") {
            return .red
        } else {
            return .primary
        }
    }
    
    private var vadConfidenceColor: Color {
        if audioManager.vadConfidence > 0.7 {
            return .green
        } else if audioManager.vadConfidence > 0.3 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var buttonIcon: String {
        switch state {
        case .idle:
            return "mic.fill"
        case .recording:
            return "stop.fill"
        case .processing:
            return "gearshape.fill"
        case .speaking:
            return "speaker.wave.2.fill"
        }
    }
    
    private var buttonText: String {
        switch state {
        case .idle:
            return "Start Listening"
        case .recording:
            return "Stop Recording"
        case .processing:
            return "Processing..."
        case .speaking:
            return "Speaking..."
        }
    }
    
    private var buttonColor: Color {
        switch state {
        case .idle:
            return .blue
        case .recording:
            return .red
        case .processing:
            return .orange
        case .speaking:
            return .green
        }
    }
    
    // MARK: - Actions
    
    private func handleMainAction() {
        switch state {
        case .idle:
            startListening()
        case .recording:
            stopListening()
        case .processing, .speaking:
            break // Disabled states
        }
    }
    
    private func startListening() {
        print("🎙️ Starting to listen...")
        state = .recording
        
        // Enable modern VAD with silence detection
        audioManager.enableVAD { [self] in
            print("🔇 VAD detected silence - automatically stopping")
            Task { @MainActor in
                stopListening()
            }
        }
        
        // Start recording with the modern system
        audioManager.startRecording()
        
        // Add pulse animation while recording
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            micAnimation = true
        }
    }
    
    private func stopListening() {
        print("🛑 Stopping listening...")
        
        // Stop recording and disable VAD
        audioManager.stopRecording()
        audioManager.disableVAD()
        
        // Stop animations
        micAnimation = false
        
        // Process the recorded audio
        if let audioData = audioManager.audioBuffer, !audioData.isEmpty {
            processRecordedAudio(audioData)
        } else {
            print("⚠️ No audio data recorded")
            state = .idle
        }
    }
    
    private func processRecordedAudio(_ audioData: Data) {
        state = .processing
        
        Task {
            do {
                // Convert raw PCM to WAV format for OpenAI Whisper
                print("🗣️ Converting speech to text...")
                let wavAudioData = audioManager.convertRawPCMToWAV(audioData)
                let userMessage = try await openAIChatService.transcribeAudio(audioData: wavAudioData)
                
                await MainActor.run {
                    // Add user message to conversation
                    conversation.append(ChatMessage(role: "user", content: userMessage))
                }
                
                // Get AI response
                print("🤖 Getting AI response...")
                let aiResponse = try await openAIChatService.sendMessage(conversation: conversation)
                
                await MainActor.run {
                    // Add AI response to conversation
                    conversation.append(ChatMessage(role: "assistant", content: aiResponse))
                    state = .speaking
                }
                
                // Convert AI response to speech
                print("🔊 Converting AI response to speech...")
                let audioData = try await elevenLabsService.textToSpeech(text: aiResponse)
                
                // Play the audio response
                await MainActor.run {
                    audioManager.playAudio(data: audioData)
                }
                
                // Wait for playback to complete, then return to idle
                // Note: This is simplified - in a real app you'd want to track playback completion
                try await Task.sleep(nanoseconds: UInt64(audioData.count / 44100 * 1_000_000_000)) // Rough estimate
                
                await MainActor.run {
                    state = .idle
                }
                
            } catch {
                print("❌ Error processing audio: \(error)")
                await MainActor.run {
                    state = .idle
                    // Could show error message to user here
                }
            }
        }
    }
    
    private func setupInitialMessage() {
        if let initialMessage = initialMessage {
            conversation.append(ChatMessage(role: "assistant", content: initialMessage))
        }
    }
}

// MARK: - Supporting Views

struct WaveformView: View {
    let audioLevel: Float
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(audioLevel > Float(index) * 0.05 ? .blue : .gray.opacity(0.3))
                    .frame(width: 4)
                    .frame(height: CGFloat(10 + (audioLevel * 40)))
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)
            }
        }
    }
}

struct ChatMessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == "user" ? "You" : "Guido")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(message.role == "user" ? .blue : .gray.opacity(0.2))
                    .foregroundColor(message.role == "user" ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            
            if message.role == "assistant" {
                Spacer()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ListeningView(
        openAIAPIKey: "preview-key",
        elevenLabsAPIKey: "preview-key",
        initialMessage: "Hello! I'm Guido, your AI assistant. How can I help you today?"
    )
} 