//
//  SimpleConversationView.swift
//  guido-1
//
//  Created by Varun Jain on 7/30/25.
//

import SwiftUI

struct SimpleConversationView: View {
    @StateObject private var realtimeService: SimpleRealtimeService
    @State private var viewState: SimpleConversationView.SimpleViewState = .disconnected
    @State private var showConnectionAnimation = false
    
    private let openAIAPIKey: String
    
    enum SimpleViewState {
        case disconnected
        case connecting
        case connected
        case error(String)
    }
    
    init(openAIAPIKey: String) {
        self.openAIAPIKey = openAIAPIKey
        self._realtimeService = StateObject(wrappedValue: SimpleRealtimeService(apiKey: openAIAPIKey))
        print("🚀 SimpleConversationView initializing...")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Conversation
            conversationView
            
            // Controls
            controlsView
        }
        .onReceive(realtimeService.$connectionStatus) { status in
            switch status {
            case "Connected":
                viewState = .connected
            case "Disconnected":
                viewState = .disconnected
            case "Connecting":
                viewState = .connecting
            default:
                if status.hasPrefix("Error:") {
                    let errorMessage = String(status.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    viewState = .error(errorMessage)
                }
            }
        }
        .onDisappear {
            if case .connected = viewState {
                stopConversation()
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Simple Realtime Chat")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(radius: 1)
    }
    
    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(realtimeService.conversation) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: realtimeService.conversation) { _ in
                if let lastMessage = realtimeService.conversation.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var controlsView: some View {
        VStack(spacing: 16) {
            // Connection button
            Button(action: {
                if case .connected = viewState {
                    stopConversation()
                } else {
                    startConversation()
                }
            }) {
                HStack {
                    Image(systemName: buttonIcon)
                        .font(.title2)
                    Text(buttonText)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(buttonColor)
                .cornerRadius(25)
                .scaleEffect(showConnectionAnimation ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: showConnectionAnimation)
            }
            .disabled({ if case .connecting = viewState { return true }; return false }())
            
            // Manual response button (for testing)
            if case .connected = viewState {
                Button(action: {
                    realtimeService.requestResponse()
                }) {
                    HStack {
                        Image(systemName: "bubble.left")
                        Text("Request Response")
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(20)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        switch viewState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch viewState {
        case .connected: return "Connected via WebRTC"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .error(let message): return "Error: \(message)"
        }
    }
    
    private var buttonIcon: String {
        switch viewState {
        case .connected: return "phone.down"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .disconnected: return "phone"
        case .error: return "phone"
        }
    }
    
    private var buttonText: String {
        switch viewState {
        case .connected: return "End Chat"
        case .connecting: return "Connecting..."
        case .disconnected: return "Start Simple Chat"
        case .error: return "Retry"
        }
    }
    
    private var buttonColor: Color {
        switch viewState {
        case .connected: return .red
        case .connecting: return .orange
        case .disconnected: return .blue
        case .error: return .blue
        }
    }
    
    // MARK: - Actions
    
    private func startConversation() {
        print("🚀 Starting simple real-time conversation...")
        viewState = .connecting
        showConnectionAnimation = true
        
        Task {
            do {
                try await realtimeService.connect()
                await MainActor.run {
                    showConnectionAnimation = false
                }
            } catch {
                await MainActor.run {
                    viewState = .error(error.localizedDescription)
                    showConnectionAnimation = false
                }
            }
        }
    }
    
    private func stopConversation() {
        print("🛑 Stopping simple real-time conversation...")
        realtimeService.disconnect()
        viewState = .disconnected
        showConnectionAnimation = false
    }
}

// MessageBubble and timeFormatter moved to RealtimeModels.swift

#Preview {
    SimpleConversationView(openAIAPIKey: "test-key")
}