//
//  ImmersiveConversationView.swift
//  guido-1
//
//  Next-generation immersive conversation experience with adaptive canvas
//

import SwiftUI
import CoreLocation

struct ImmersiveConversationView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var realtimeService: OpenAIRealtimeService
    @StateObject private var locationManager = LocationManager()
    
    // UI State
    @State private var showResults = false

    @State private var currentResults: [LiquidGlassOverlay.ResultItem] = []
    @State private var resultsTitle = ""
    @State private var isConnecting = false
    @State private var connectionError: String?
    
    // Canvas State
    @State private var userSpeaking = false
    @State private var guidoSpeaking = false
    @State private var audioLevel: Float = 0.0
    @State private var showSettings = false
    
    // Testing mode
    @State private var testingMode = false
    @State private var currentTestEnvironment: CanvasEnvironment = .unknown
    
    private let openAIAPIKey: String
    
    init(openAIAPIKey: String) {
        self.openAIAPIKey = openAIAPIKey
        self._realtimeService = StateObject(wrappedValue: OpenAIRealtimeService(apiKey: openAIAPIKey))
        print("🌟 Immersive Conversation View initializing...")
    }
    
    var body: some View {
        ZStack {
            // Adaptive Canvas Background - Full immersion
            AdaptiveCanvas(
                userSpeaking: userSpeaking,
                guidoSpeaking: guidoSpeaking,
                conversationState: mapConversationState(realtimeService.conversationState),
                audioLevel: audioLevel,
                testEnvironment: testingMode ? currentTestEnvironment : nil
            )
            .ignoresSafeArea()
            
            // Testing mode overlay (subtle, top-right)
            if testingMode {
                VStack {
                    HStack {
                        Spacer()
                        testingModeControls
                    }
                    Spacer()
                }
            }
            
            // Connection controls in center when not connected (only after auth)
            if appState.authStatus.isAuthenticated && !realtimeService.isConnected {
                centeredLiquidGlassButton
            }
            
            // Floating results panel with inline expansion
            FloatingResultsPanel(
                results: currentResults,
                title: resultsTitle,
                isVisible: showResults,
                onExpand: {
                    // onExpand is now handled internally by the FloatingResultsPanel
                },
                onDismiss: {
                    hideResults()
                }
            )
            
            // Minimal disconnect controls when connected
            if appState.authStatus.isAuthenticated && realtimeService.isConnected {
                VStack {
                    Spacer()
                    disconnectControls
                }
            }

            // Settings bubble (top-right) when authenticated
            if appState.authStatus.isAuthenticated {
                VStack {
                    HStack {
                        Spacer()
                        LiquidGlassCard(intensity: 0.5, cornerRadius: 12, shadowIntensity: 0.15) {
                            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showSettings.toggle() } }) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                    Spacer()
                }
            }

            // Inline settings panel
            if appState.authStatus.isAuthenticated && showSettings {
                VStack {
                    SettingsView()
                        .environmentObject(appState)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            // Inline onboarding components on the same canvas
            if appState.authStatus.isAuthenticated == false {
                OnboardingView()
                    .environmentObject(appState)
                    .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .onReceive(realtimeService.$isConnected) { isConnected in
            if isConnected {
                isConnecting = false
                connectionError = nil
                setupLocationTracking()
            }
        }
        .onReceive(realtimeService.$conversationState) { state in
            updateSpeechStates(for: state)
            
            // Hide results when returning to idle
            if state == .idle && showResults {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if realtimeService.conversationState == .idle {
                        hideResults()
                    }
                }
            }
        }
        .onReceive(realtimeService.$audioLevel) { level in
            audioLevel = level
        }
        .onReceive(realtimeService.$conversation) { conversation in
            processLatestResponse(from: conversation)
        }
        .onReceive(realtimeService.$connectionStatus) { status in
            if status.hasPrefix("Error:") {
                connectionError = String(status.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                isConnecting = false
            }
        }
        .onAppear {
            setupView()
        }
        .onTapGesture(count: 3) {
            // Triple tap anywhere to toggle testing mode
            withAnimation(.easeInOut(duration: 0.3)) {
                testingMode.toggle()
            }
        }
    }
    
    // MARK: - Centered Liquid Glass Button
    
    private var centeredLiquidGlassButton: some View {
        GeometryReader { geometry in
            VStack {
                LiquidGlassCard(intensity: 0.4, cornerRadius: 20, shadowIntensity: 0.15) {
                    Button(action: startConversation) {
                        HStack(spacing: 6) {
                            if isConnecting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(.secondaryLabel)))
                                    .scaleEffect(0.6)
                            }
                            
                            Text(isConnecting ? "connecting..." : "begin")
                                .font(.system(size: 16, weight: .light, design: .rounded))
                                .foregroundColor(Color(.secondaryLabel))
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                    .disabled(isConnecting)
                    .buttonStyle(PlainButtonStyle())
                }
                
                if let error = connectionError {
                    Text(error)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color(.tertiaryLabel))
                        .padding(.top, 8)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
    
    // MARK: - Disconnect Controls
    
    private var disconnectControls: some View {
        LiquidGlassCard(intensity: 0.5, cornerRadius: 16, shadowIntensity: 0.15) {
            Button(action: stopConversation) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .medium))
                    
                    Text("end")
                        .font(.system(size: 14, weight: .light, design: .rounded))
                }
                .foregroundColor(Color(.tertiaryLabel))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.bottom, 40)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Setup and Actions
    
    private func setupView() {
        locationManager.requestLocationPermission()
        
        // Configure audio feedback
        realtimeService.audioFeedbackManager.setEnabled(true)
        realtimeService.audioFeedbackManager.setVolume(0.7)
        realtimeService.audioFeedbackManager.realtimeService = realtimeService
    }
    
    private func setupLocationTracking() {
        realtimeService.setLocationManager(locationManager)
    }
    
    private func startConversation() {
        isConnecting = true
        connectionError = nil
        
        Task {
            do {
                try await realtimeService.connect()
                await MainActor.run {
                    realtimeService.startStreaming()
                    print("🌟 Immersive conversation started")
                }
            } catch {
                await MainActor.run {
                    connectionError = error.localizedDescription
                    isConnecting = false
                }
                print("❌ Failed to start immersive conversation: \(error)")
            }
        }
    }
    
    private func stopConversation() {
        realtimeService.stopStreaming()
        realtimeService.disconnect()
        hideResults()
        print("🌟 Immersive conversation ended")
    }
    

    
    // MARK: - Speech State Management
    
    private func updateSpeechStates(for state: OpenAIRealtimeService.ConversationState) {
        switch state {
        case .listening:
            userSpeaking = true
            guidoSpeaking = false
        case .speaking:
            userSpeaking = false
            guidoSpeaking = true
        case .processing, .thinking:
            userSpeaking = false
            guidoSpeaking = false
        case .idle:
            userSpeaking = false
            guidoSpeaking = false
        }
    }
    
    // MARK: - Results Processing
    
    private func processLatestResponse(from conversation: [RealtimeMessage]) {
        guard let latestMessage = conversation.last,
              latestMessage.role == "assistant",
              !latestMessage.isStreaming else { return }
        
        // Extract structured results using LLM
        Task {
            await extractAndShowResults(from: latestMessage.content)
        }
    }
    
    private func extractAndShowResults(from content: String) async {
        let prompt = createExtractionPrompt(for: content)
        
        do {
            // Access OpenAI service through AppState
            let appState = AppState()
            let response = try await appState.openAIChatService.generateStructuredData(prompt: prompt)
            let results = parseStructuredResponse(response)
            
            await MainActor.run {
                if !results.isEmpty {
                    let title = generateResultsTitle(from: content)
                    showResults(results, title: title)
                }
            }
        } catch {
            print("❌ Failed to extract results: \(error)")
            // Fallback to simple detection
            await MainActor.run {
                let fallbackResults = simpleExtraction(from: content)
                if !fallbackResults.isEmpty {
                    let title = generateResultsTitle(from: content)
                    showResults(fallbackResults, title: title)
                }
            }
        }
    }
    
    private func createExtractionPrompt(for content: String) -> String {
        return """
        Extract structured information from this travel assistant response and return it as JSON. Only extract actual concrete information that appears in the text.

        Response to analyze: "\(content)"

        Return JSON in this exact format (include only categories that have actual data):
        {
          "restaurants": [
            {
              "name": "Restaurant Name",
              "rating": "4.5 stars" or "Highly rated" or null,
              "distance": "500m" or "5 min walk" or null,
              "cuisine": "Italian" or null
            }
          ],
          "places": [
            {
              "name": "Place Name", 
              "type": "Museum" or "Park" or "Beach" etc,
              "distance": "1.2km" or "10 min" or null,
              "description": "Brief description" or null
            }
          ],
          "directions": [
            {
              "destination": "Target location",
              "time": "15 minutes" or null,
              "distance": "2.3km" or null,
              "method": "walking" or "driving" or null
            }
          ],
          "weather": [
            {
              "temperature": "23°C" or "75°F",
              "condition": "Sunny" or "Cloudy" etc,
              "location": "City name" or null
            }
          ],
          "currency": [
            {
              "from": "USD",
              "to": "EUR", 
              "rate": "0.85" or "1.18",
              "amount": "100" or null
            }
          ]
        }

        Rules:
        - Only include categories that have actual data mentioned in the response
        - Return empty object {} if no structured data is found
        - Keep names and descriptions concise
        - Preserve exact distances, times, and temperatures as mentioned
        - Return valid JSON only, no explanations
        """
    }
    
    private func parseStructuredResponse(_ jsonString: String) -> [LiquidGlassOverlay.ResultItem] {
        var results: [LiquidGlassOverlay.ResultItem] = []
        
        // Clean the JSON string
        let cleanedJSON = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            return []
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                // Parse restaurants
                if let restaurants = json["restaurants"] as? [[String: Any]] {
                    for restaurant in restaurants.prefix(3) {
                        if let name = restaurant["name"] as? String {
                            results.append(LiquidGlassOverlay.ResultItem(
                                title: name,
                                subtitle: restaurant["rating"] as? String ?? restaurant["cuisine"] as? String,
                                detail: restaurant["distance"] as? String,
                                iconName: "fork.knife",
                                color: .orange
                            ))
                        }
                    }
                }
                
                // Parse places
                if let places = json["places"] as? [[String: Any]] {
                    for place in places.prefix(3) {
                        if let name = place["name"] as? String {
                            results.append(LiquidGlassOverlay.ResultItem(
                                title: name,
                                subtitle: place["type"] as? String,
                                detail: place["distance"] as? String,
                                iconName: "location.fill",
                                color: .blue
                            ))
                        }
                    }
                }
                
                // Parse directions
                if let directions = json["directions"] as? [[String: Any]] {
                    for direction in directions.prefix(1) {
                        if let destination = direction["destination"] as? String {
                            results.append(LiquidGlassOverlay.ResultItem(
                                title: destination,
                                subtitle: direction["time"] as? String,
                                detail: direction["distance"] as? String,
                                iconName: "arrow.triangle.turn.up.right.diamond",
                                color: .green
                            ))
                        }
                    }
                }
                
                // Parse weather
                if let weather = json["weather"] as? [[String: Any]] {
                    for weatherInfo in weather.prefix(1) {
                        results.append(LiquidGlassOverlay.ResultItem(
                            title: "Weather",
                            subtitle: weatherInfo["temperature"] as? String,
                            detail: weatherInfo["condition"] as? String,
                            iconName: "cloud.sun",
                            color: .cyan
                        ))
                    }
                }
                
                // Parse currency
                if let currency = json["currency"] as? [[String: Any]] {
                    for currencyInfo in currency.prefix(1) {
                        if let from = currencyInfo["from"] as? String,
                           let to = currencyInfo["to"] as? String {
                            results.append(LiquidGlassOverlay.ResultItem(
                                title: "\(from) → \(to)",
                                subtitle: currencyInfo["rate"] as? String,
                                detail: "Exchange rate",
                                iconName: "dollarsign.circle",
                                color: .yellow
                            ))
                        }
                    }
                }
            }
        } catch {
            print("❌ Failed to parse JSON response: \(error)")
        }
        
        return Array(results.prefix(5)) // Limit to 5 total results
    }
    
    private func simpleExtraction(from content: String) -> [LiquidGlassOverlay.ResultItem] {
        var results: [LiquidGlassOverlay.ResultItem] = []
        let lowercaseContent = content.lowercased()
        
        if lowercaseContent.contains("restaurant") || lowercaseContent.contains("café") {
            results.append(LiquidGlassOverlay.ResultItem(
                title: "Restaurant Options",
                subtitle: "Found in response",
                iconName: "fork.knife",
                color: .orange
            ))
        }
        
        if lowercaseContent.contains("weather") || lowercaseContent.contains("°") {
            results.append(LiquidGlassOverlay.ResultItem(
                title: "Weather Info",
                subtitle: "Current conditions",
                iconName: "cloud.sun",
                color: .cyan
            ))
        }
        
        return results
    }
    
    private func generateResultsTitle(from content: String) -> String {
        let lowercaseContent = content.lowercased()
        
        if lowercaseContent.contains("restaurant") {
            return "Restaurant Options"
        } else if lowercaseContent.contains("place") || lowercaseContent.contains("attraction") {
            return "Places to Visit"
        } else if lowercaseContent.contains("direction") || lowercaseContent.contains("route") {
            return "Route Details"
        } else if lowercaseContent.contains("weather") {
            return "Weather Info"
        } else if lowercaseContent.contains("currency") || lowercaseContent.contains("exchange") {
            return "Currency Exchange"
        }
        
        return "Results"
    }
    
    private func showResults(_ results: [LiquidGlassOverlay.ResultItem], title: String) {
        withAnimation(.spring(dampingFraction: 0.8, blendDuration: 0.6)) {
            currentResults = results
            resultsTitle = title
            showResults = true
        }
        
        // Auto-hide after 15 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            if showResults {
                hideResults()
            }
        }
    }
    
    private func hideResults() {
        withAnimation(.easeInOut(duration: 0.4)) {
            showResults = false
    
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            currentResults = []
            resultsTitle = ""
        }
    }
    
    // MARK: - Conversation State Mapping
    
    private func mapConversationState(_ state: OpenAIRealtimeService.ConversationState) -> ConversationState {
        switch state {
        case .idle:
            return .idle
        case .listening:
            return .listening
        case .processing:
            return .processing
        case .speaking:
            return .speaking
        case .thinking:
            return .thinking
        }
    }
    
    // MARK: - Testing Mode Controls
    
    private var testingModeControls: some View {
        VStack(spacing: 8) {
            LiquidGlassCard(intensity: 0.5, cornerRadius: 8, shadowIntensity: 0.1) {
                Text("TEST")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            
            VStack(spacing: 4) {
                ForEach(Array(CanvasEnvironment.allCases.enumerated()), id: \.offset) { index, environment in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.8)) {
                            currentTestEnvironment = environment
                        }
                    }) {
                        LiquidGlassCard(intensity: 0.4, cornerRadius: 6, shadowIntensity: 0.05) {
                            Text(environment.displayName)
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundColor(currentTestEnvironment == environment ? .orange : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.trailing, 16)
        .padding(.top, 60)
    }
}

// MARK: - Preview

struct ImmersiveConversationView_Previews: PreviewProvider {
    static var previews: some View {
        ImmersiveConversationView(openAIAPIKey: "test-key")
    }
}