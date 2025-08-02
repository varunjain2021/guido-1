import SwiftUI
import CoreLocation

struct ProactiveGuideView: View {
    @StateObject private var audioManager = AudioManager()
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var isGeneratingMessage = true
    @State private var proactiveMessage = ""
    @State private var hasSpoken = false
    @State private var errorMessage: String?
    @State private var isAutoPlaying = true
    @State private var showConversationView = false
    
    let locationDescription: String
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Guido's Proactive Suggestions")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Based on your location in \(locationDescription)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Main Content
                if isGeneratingMessage {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.2)
                        
                        Text("Guido is thinking of great things for you to do...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                } else if isAutoPlaying {
                    VStack(spacing: 20) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        Text("Guido is talking...")
                            .font(.headline)
                        
                        Text(proactiveMessage)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        
                        Text("Oops! Something went wrong")
                            .font(.headline)
                        
                        Text(error)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Try Again") {
                            generateProactiveMessage()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 20) {
                        // Guido's message
                        ScrollView {
                            Text(proactiveMessage)
                                .font(.body)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }
                        
                        // Action buttons
                        VStack(spacing: 15) {
                            Button {
                                // Transition to voice conversation
                                showConversationView = true
                            } label: {
                                HStack {
                                    Image(systemName: "mic.fill")
                                    Text("Continue Conversation")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            
                            if !hasSpoken {
                                Button {
                                    speakMessage()
                                } label: {
                                    HStack {
                                        Image(systemName: "speaker.wave.2.fill")
                                        Text("Hear Again")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                            }
                            
                            Button("Maybe Later") {
                                dismiss()
                            }
                            .font(.body)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            generateProactiveMessage()
        }
        .onDisappear {
            // AudioManager cleanup is handled automatically in deinit
        }
        .sheet(isPresented: $showConversationView) {
            NavigationView {
                RealtimeConversationView(openAIAPIKey: appState.openAIAPIKey)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                showConversationView = false
                            }
                        }
                    }
            }
        }
    }
    
    private func generateProactiveMessage() {
        isGeneratingMessage = true
        errorMessage = nil
        
        Task {
            do {
                let prompt = appState.locationManager.getProactivePrompt()
                let message = try await appState.openAIChatService.generateProactiveMessage(prompt: prompt)
                
                await MainActor.run {
                    proactiveMessage = message
                    isGeneratingMessage = false
                }
                
                print("🎯 Generated proactive message: \(message)")
                
                // Automatically play the message
                await speakMessageAuto()
                
            } catch {
                await MainActor.run {
                    errorMessage = "I'm having trouble connecting right now. Please try again."
                    isGeneratingMessage = false
                }
                print("❌ Error generating proactive message: \(error)")
            }
        }
    }
    
    private func speakMessageAuto() async {
        do {
            let ttsData = try await appState.elevenLabsService.textToSpeech(text: proactiveMessage)
            
            await MainActor.run {
                audioManager.playAudio(data: ttsData)
                print("🎵 Proactive message playback completed")
                self.isAutoPlaying = false
                self.hasSpoken = true
            }
            
        } catch {
            print("❌ Error playing proactive message: \(error)")
            await MainActor.run {
                isAutoPlaying = false
                errorMessage = "I'm having trouble speaking right now. Please try again."
            }
        }
    }
    
    private func speakMessage() {
        isAutoPlaying = true
        
        Task {
            await speakMessageAuto()
        }
    }
}

#Preview {
    ProactiveGuideView(locationDescription: "Upper West Side, New York")
        .environmentObject(AppState())
} 