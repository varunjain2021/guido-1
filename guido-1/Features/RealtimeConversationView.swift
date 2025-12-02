//
//  RealtimeConversationView.swift
//  guido-1
//
//  Created by Varun Jain on 7/27/25.
//

import SwiftUI

struct RealtimeConversationView: View {
    enum ViewState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
        
        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    
    @EnvironmentObject private var appState: AppState
    @State private var viewState: ViewState = .disconnected
    @State private var showConnectionAnimation = false
    @State private var audioLevelAnimation = false
    
    @StateObject private var realtimeService: OpenAIRealtimeService
    @StateObject private var locationManager = LocationManager.shared
    @State private var sessionLogger: SessionLogger
    @State private var activeUserId: String?
    
    private let openAIAPIKey: String
    private let supabaseURL: String
    private let supabaseAnonKey: String
    
    init(openAIAPIKey: String, supabaseURL: String, supabaseAnonKey: String, currentUserId: String?) {
        self.openAIAPIKey = openAIAPIKey
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        let initialSink = RealtimeConversationView.makeSink(baseURL: supabaseURL, anonKey: supabaseAnonKey)
        let logger = SessionLogger(sink: initialSink, userId: currentUserId)
        self._sessionLogger = State(initialValue: logger)
        self._activeUserId = State(initialValue: currentUserId)
        self._realtimeService = StateObject(wrappedValue: OpenAIRealtimeService(apiKey: openAIAPIKey, sessionLogger: logger))
        print("🚀 RealtimeConversationView initializing...")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with connection status
            headerView
            
            // Main content area
            switch viewState {
            case .disconnected:
                disconnectedView
            case .connecting:
                connectingView
            case .connected:
                VStack(spacing: 0) {
                    // Live conversation view
                    conversationView
                    // Connected controls
                    connectedView
                }
            case .error(let message):
                errorView(message: message)
            }
            
            // Control panel
            controlPanel
        }
        .navigationTitle("Real-time Chat")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onReceive(realtimeService.$isConnected) { isConnected in
            if isConnected {
                viewState = .connected
            } else if viewState == .connecting {
                viewState = .disconnected
            }
        }
        .onReceive(realtimeService.$connectionStatus) { status in
            if status.hasPrefix("Error:") {
                let errorMessage = String(status.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                viewState = .error(errorMessage)
            }
        }
        .onReceive(realtimeService.$audioLevel) { level in
            withAnimation(.easeInOut(duration: 0.1)) {
                audioLevelAnimation = level > 0.02
            }
        }
        .onReceive(locationManager.$currentLocation.compactMap { $0 }) { location in
            guard viewState == .connected else { return }
            sessionLogger.logLocation(SessionLocationSnapshot(location: location, source: "device.location"))
        }
        .onChange(of: appState.authStatus.user?.id) { newUserId in
            activeUserId = newUserId
            sessionLogger.updateUser(id: newUserId)
        }
        .onAppear {
            locationManager.requestLocationPermission()
            realtimeService.setSessionLogger(sessionLogger)
            sessionLogger.appendLifecycle(.foregrounded, detail: "RealtimeConversationView appeared")
        }
        .onDisappear {
            // Cleanup when user navigates away
            if viewState == .connected {
                stopConversation()
            }
            sessionLogger.appendLifecycle(.backgrounded, detail: "RealtimeConversationView disappeared")
            sessionLogger.flush()
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                // Connection indicator
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 12, height: 12)
                    .scaleEffect(showConnectionAnimation ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), 
                              value: showConnectionAnimation)
                
                Text(connectionStatusText)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if viewState == .connected {
                    // Audio level indicator
                    Circle()
                        .fill(audioLevelColor)
                        .frame(width: 16, height: 16)
                        .scaleEffect(audioLevelAnimation ? 1.3 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: audioLevelAnimation)
                }
            }
            
            // Status description
            Text(statusDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - State Views
    private var disconnectedView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("Real-time Conversation")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Have a natural conversation with Guido using OpenAI's real-time voice API")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            VStack(spacing: 16) {
                FeatureRow(icon: "mic.fill", 
                          title: "Automatic Voice Detection", 
                          description: "No need to press buttons - just speak naturally")
                
                FeatureRow(icon: "bolt.fill", 
                          title: "Real-time Responses", 
                          description: "Instant AI responses with natural conversation flow")
                
                FeatureRow(icon: "ear.fill", 
                          title: "Natural Speech", 
                          description: "High-quality voice synthesis for lifelike conversations")
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var connectingView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                
                Text("Connecting...")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Establishing secure connection to OpenAI's real-time API")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
    }
    
    private var connectedView: some View {
        VStack(spacing: 20) {
            // Audio visualization and tool status only - conversation moved to top
            audioVisualizationView
            
            // Tool status indicator  
            if let lastTool = realtimeService.toolManager.lastToolUsed {
                toolStatusView(toolName: lastTool)
            }
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                VStack(spacing: 8) {
                    Text("Connection Error")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Audio Visualization
    private var audioVisualizationView: some View {
        VStack(spacing: 16) {
            // Conversation state indicator
            HStack(spacing: 12) {
                Image(systemName: conversationStateIcon)
                    .foregroundColor(conversationStateColor)
                    .font(.title2)
                
                Text(conversationStateText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(conversationStateColor)
                
                if realtimeService.conversationState == .idle && !realtimeService.conversation.isEmpty {
                    Image(systemName: "mic.circle.fill")
                        .foregroundColor(.blue)
                        .opacity(0.7)
                        .scaleEffect(1.2)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: realtimeService.conversationState)
                }
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(20)
            
            // Audio level bars
            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(audioBarColor(for: index))
                        .frame(width: 6, height: audioBarHeight(for: index))
                        .animation(.easeInOut(duration: 0.1), value: realtimeService.audioLevel)
                }
            }
            .frame(height: 40)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Tool Status View
    private func toolStatusView(toolName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toolIconName(for: toolName))
                .foregroundColor(.blue)
                .font(.caption)
            
            Text("Using \(toolDisplayName(for: toolName))")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if locationManager.isLocationAuthorized {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                    
                    if locationManager.isMoving {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.orange)
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    private func toolIconName(for toolName: String) -> String {
        switch toolName {
        case "get_user_location": return "location.circle"
        case "find_nearby_places": return "mappin.and.ellipse"
        case "get_directions": return "arrow.turn.up.right"
        case "get_weather": return "cloud.sun"
        case "check_calendar": return "calendar"
        case "get_local_time": return "clock"
        case "find_transportation": return "car"
        case "find_local_events": return "star"
        case "recommend_restaurants": return "fork.knife"
        case "currency_converter": return "dollarsign.circle"
        case "translate_text": return "globe"
        case "get_safety_info": return "shield"
        case "check_travel_requirements": return "doc.text"
        case "get_emergency_info": return "cross.circle"
        default: return "wrench"
        }
    }
    
    private func toolDisplayName(for toolName: String) -> String {
        return toolName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "get ", with: "")
            .replacingOccurrences(of: "find ", with: "")
            .replacingOccurrences(of: "check ", with: "")
            .capitalized
    }
    
    // MARK: - Control Panel
    private var controlPanel: some View {
        VStack(spacing: 16) {
            switch viewState {
            case .disconnected:
                Button(action: startConversation) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                        Text("Start Real-time Chat")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                
            case .connecting:
                Button(action: {}) {
                    HStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.gray)
                    .cornerRadius(12)
                }
                .disabled(true)
                
            case .connected:
                Button(action: stopConversation) {
                    HStack(spacing: 12) {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                        Text("End Conversation")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red)
                    .cornerRadius(12)
                }
                
                // MCP Testing Controls
                mcpTestingControls
                
            case .error:
                Button(action: startConversation) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                        Text("Retry Connection")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Conversation View
    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(realtimeService.conversation) { message in
                        HStack(alignment: .top, spacing: 12) {
                            // Avatar/Icon
                            Image(systemName: message.role == "user" ? "person.circle.fill" : "brain.head.profile")
                                .font(.title2)
                                .foregroundColor(message.role == "user" ? .blue : .green)
                                .frame(width: 30)
                            
                            // Message content
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(message.role == "user" ? "You" : "Guido")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text(message.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text(message.content)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                if message.isStreaming {
                                    HStack(spacing: 4) {
                                        ForEach(0..<3) { i in
                                            Circle()
                                                .fill(Color.secondary)
                                                .frame(width: 6, height: 6)
                                                .opacity(0.6)
                                                .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: message.isStreaming)
                                        }
                                        Text("typing...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id(message.id)
                    }
                    
                    // Conversation state indicator
                    HStack {
                        Image(systemName: conversationStateIcon)
                            .font(.caption)
                            .foregroundColor(conversationStateColor)
                        
                        Text(conversationStateText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.vertical)
            }
            .onChange(of: realtimeService.conversation.count) { _ in
                if let lastMessage = realtimeService.conversation.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxHeight: 300)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var conversationStateIcon: String {
        switch realtimeService.conversationState {
        case .idle:
            return "moon.zzz"
        case .listening:
            return "waveform"
        case .processing:
            return "brain"
        case .thinking:
            return "lightbulb"
        case .speaking:
            return "speaker.wave.2"
        }
    }
    
    private var conversationStateColor: Color {
        switch realtimeService.conversationState {
        case .idle:
            return .gray
        case .listening:
            return .blue
        case .processing:
            return .orange
        case .thinking:
            return .purple
        case .speaking:
            return .green
        }
    }
    
    private var conversationStateText: String {
        switch realtimeService.conversationState {
        case .idle:
            return realtimeService.conversation.isEmpty ? "Ready to chat - just start speaking!" : "Speak anytime to continue..."
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing speech..."
        case .thinking:
            return "Thinking..."
        case .speaking:
            return "Speaking..."
        }
    }
    
    // MARK: - Computed Properties
    private var connectionStatusColor: Color {
        switch viewState {
        case .disconnected:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .error:
            return .red
        }
    }
    
    private var connectionStatusText: String {
        switch viewState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .error:
            return "Error"
        }
    }
    
    private var statusDescription: String {
        switch viewState {
        case .disconnected:
            return "Tap to start a real-time conversation with Guido"
        case .connecting:
            return "Establishing secure connection..."
        case .connected:
            return "Voice detection active • Speak naturally"
        case .error(let message):
            return "Connection failed: \(message)"
        }
    }
    
    private var audioLevelColor: Color {
        if realtimeService.audioLevel > 0.05 {
            return .green
        } else if realtimeService.audioLevel > 0.02 {
            return .orange
        } else {
            return .gray
        }
    }
    
    private func audioBarColor(for index: Int) -> Color {
        let threshold = Float(index + 1) * 0.1
        return realtimeService.audioLevel > threshold ? .blue : .gray.opacity(0.3)
    }
    
    private func audioBarHeight(for index: Int) -> CGFloat {
        let threshold = Float(index + 1) * 0.1
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 32
        
        if realtimeService.audioLevel > threshold {
            return min(maxHeight, baseHeight + CGFloat(realtimeService.audioLevel * 60))
        } else {
            return baseHeight
        }
    }
    
    // MARK: - Actions
    private static func makeSink(baseURL: String, anonKey: String) -> SessionLogSink {
        guard !baseURL.isEmpty, !anonKey.isEmpty else {
            return ConsoleSessionLogSink()
        }
        return SupabaseSessionLogSink(baseURL: baseURL, anonKey: anonKey)
    }
    
    private func resetSessionLogger(reason: String) {
        let sink = RealtimeConversationView.makeSink(baseURL: supabaseURL, anonKey: supabaseAnonKey)
        let logger = SessionLogger(sink: sink, userId: activeUserId)
        sessionLogger = logger
        realtimeService.setSessionLogger(logger)
        logger.updateMetadata { metadata in
            metadata.connectionType = NetworkStatusMonitor.shared.connectionType()
            var extras = metadata.additionalInfo ?? [:]
            extras["experience"] = "realtime"
            extras["preferredLanguage"] = realtimeService.preferredLanguageCode
            extras["theme"] = String(describing: appState.selectedTheme)
            if let email = appState.authStatus.user?.email {
                extras["userEmail"] = email
            }
            metadata.additionalInfo = extras
        }
        logger.appendLifecycle(.foregrounded, detail: reason)
    }
    
    private func startConversation() {
        print("🚀 Starting real-time conversation...")
        viewState = .connecting
        showConnectionAnimation = true
        resetSessionLogger(reason: "User started conversation")
        
        Task {
            do {
                try await realtimeService.connect()
                await MainActor.run {
                    realtimeService.setLocationManager(locationManager)
                    realtimeService.startStreaming()
                    showConnectionAnimation = false
                }
            } catch {
                await MainActor.run {
                    viewState = .error(error.localizedDescription)
                    showConnectionAnimation = false
                }
                print("❌ Failed to connect: \(error)")
            }
        }
    }
    
    private func stopConversation() {
        print("🛑 Stopping real-time conversation...")
        sessionLogger.appendLifecycle(.ended, detail: "User ended conversation")
        sessionLogger.endSession()
        sessionLogger.flush()
        realtimeService.stopStreaming()
        realtimeService.disconnect()
        viewState = .disconnected
        showConnectionAnimation = false
    }
    
    // MARK: - MCP Testing Controls
    private var mcpTestingControls: some View {
        VStack(spacing: 12) {
            Text("🧪 MCP Testing")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button("🧪 Enable MCP Mode") {
                    Task { @MainActor in
                        FeatureFlags.shared.migrationState = .hybrid
                        FeatureFlags.shared.enableMCPForCategory(.location)
                        FeatureFlags.shared.debugLoggingEnabled = true
                        FeatureFlags.shared.isPerformanceMonitoringEnabled = true
                        
                        print("✅ TESTING: Enabled MCP for location tools")
                        print("🔍 TESTING: Debug logging enabled")
                        print("📊 TESTING: Performance monitoring enabled")
                        print("🎯 TESTING: Migration state: \(FeatureFlags.shared.migrationState.displayName)")
                    }
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(6)
                
                Button("🔄 Back to Legacy") {
                    Task { @MainActor in
                        FeatureFlags.shared.migrationState = .legacy
                        FeatureFlags.shared.debugLoggingEnabled = true
                        
                        print("🔙 TESTING: Reverted to Legacy mode")
                        print("🎯 TESTING: Migration state: \(FeatureFlags.shared.migrationState.displayName)")
                    }
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(6)
                
                Button("🚨 Emergency Rollback") {
                    Task { @MainActor in
                        FeatureFlags.shared.emergencyRollbackToLegacy(reason: "User requested emergency rollback")
                        print("🚨 EMERGENCY ROLLBACK ACTIVATED")
                    }
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Supporting Views
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct RealtimeMessageBubble: View {
    let message: RealtimeMessage
    
    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
            }
            
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if message.role == "assistant" {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.purple)
                            .font(.caption)
                    }
                    
                    Text(message.role == "user" ? "You" : "Guido")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    if message.role == "user" {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
                
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.role == "user" ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.role == "user" ? .white : .primary)
                    .cornerRadius(18)
                    .overlay(
                        // Streaming indicator
                        Group {
                            if message.isStreaming {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                }
                                .padding(.trailing, 8)
                            }
                        }
                    )
                
                Text(SharedDateFormatter.timeFormatter.string(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.role == "assistant" {
                Spacer()
            }
        }
    }
}

// timeFormatter moved to RealtimeModels.swift 