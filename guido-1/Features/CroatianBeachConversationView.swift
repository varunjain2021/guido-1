import SwiftUI

/// Result item for dynamic results pane
struct ResultItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let detail: String?
    let iconName: String
    let color: Color
    
    init(title: String, subtitle: String? = nil, detail: String? = nil, iconName: String = "location.fill", color: Color = CroatianBeachColors.crystalWater) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.iconName = iconName
        self.color = color
    }
}

/// Clean, Croatian beach-themed conversation interface
struct CroatianBeachConversationView: View {
    @StateObject private var realtimeService: OpenAIRealtimeService
    @StateObject private var locationManager = LocationManager()
    
    @State private var currentResults: [ResultItem] = []
    @State private var showResultsPane: Bool = false
    @State private var resultsTitle: String = ""
    @State private var showExpandedResults: Bool = false
    @State private var isConnecting: Bool = false
    
    private let openAIAPIKey: String
    
    init(openAIAPIKey: String) {
        self.openAIAPIKey = openAIAPIKey
        self._realtimeService = StateObject(wrappedValue: OpenAIRealtimeService(apiKey: openAIAPIKey))
        print("🌊 Croatian Beach Conversation initializing...")
    }
    
    var body: some View {
        ZStack {
            // Enhanced background for mic-focused interface
            backgroundGradient
                .ignoresSafeArea()
            
            // Centered mic interface
            centeredMicInterface
        }
        .navigationBarHidden(true)
        .onReceive(realtimeService.$isConnected) { isConnected in
            if isConnected {
                startLocationTracking()
            }
        }
        .onReceive(realtimeService.$conversationState) { state in
            if state == .idle || state == .listening {
                hideResults()
            }
        }
        .onReceive(realtimeService.$conversation) { conversation in
            processLatestResponse(from: conversation)
        }
        .onAppear {
            locationManager.requestLocationPermission()
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        RadialGradient(
            colors: [
                CroatianBeachColors.beachSand,
                CroatianBeachColors.seafoamMist.opacity(0.8),
                CroatianBeachColors.seaFoam.opacity(0.3)
            ],
            center: .center,
            startRadius: 100,
            endRadius: 400
        )
    }
    
    // MARK: - Centered Mic Interface
    
    private var centeredMicInterface: some View {
        ZStack {
            VStack(spacing: 0) {
                // Fixed top spacer - mic stays in same position
                Spacer()
                    .frame(minHeight: 150)
                
                // Mic and status section - always in center
                VStack(spacing: CroatianBeachSpacing.medium) {
                    // Enhanced voice hub - stays in fixed position
                    EnhancedCroatianVoiceHub(
                        isListening: realtimeService.conversationState == .listening,
                        isActive: realtimeService.isConnected,
                        toolStatus: stableToolStatus,
                        action: toggleConversation
                    )
                    
                    // Connection and status feedback
                    connectionAndStatusFeedback
                }
                .frame(maxWidth: .infinity)
                
                // Fixed bottom spacer
                Spacer()
                    .frame(minHeight: 150)
                
                // Connection indicator at bottom
                connectionStatusIndicator
                    .padding(.bottom, CroatianBeachSpacing.large)
            }
            
            // Results pane overlays at bottom - doesn't affect mic position
            VStack {
                Spacer()
                dynamicResultsPane
                    .animation(.easeInOut(duration: 0.5), value: showResultsPane)
                Spacer()
                    .frame(height: 80) // Space for connection indicator
            }
            
            // Expanded results overlay
            if showExpandedResults {
                expandedResultsOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Connection and Status Feedback
    
    private var connectionAndStatusFeedback: some View {
        VStack(spacing: CroatianBeachSpacing.small) {
            if isConnecting {
                HStack(spacing: CroatianBeachSpacing.small) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: CroatianBeachColors.crystalWater))
                        .scaleEffect(0.8)
                    
                    Text("Connecting...")
                        .font(CroatianBeachTypography.voiceState)
                        .foregroundColor(CroatianBeachColors.crystalWater)
                }
                .transition(.opacity)
            } else if realtimeService.isConnected && realtimeService.conversationState == .idle {
                Text("Ready to listen")
                    .font(CroatianBeachTypography.voiceState)
                    .foregroundColor(CroatianBeachColors.seaFoam)
                    .transition(.opacity)
            } else if shouldShowStatusText {
                Text(voiceStateText)
                    .font(CroatianBeachTypography.voiceState)
                    .foregroundColor(CroatianBeachColors.emeraldShade.opacity(0.8))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isConnecting)
        .animation(.easeInOut(duration: 0.3), value: realtimeService.isConnected)
        .animation(.easeInOut(duration: 0.3), value: voiceStateText)
    }
    
    // MARK: - Dynamic Results Pane
    
    private var dynamicResultsPane: some View {
        Group {
            if showResultsPane && !currentResults.isEmpty {
                VStack(spacing: CroatianBeachSpacing.medium) {
                    // Results title with expand button
                    HStack {
                        if !resultsTitle.isEmpty {
                            Text(resultsTitle)
                                .font(CroatianBeachTypography.body)
                                .fontWeight(.medium)
                                .foregroundColor(CroatianBeachColors.deepEmerald)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showExpandedResults = true
                            }
                        }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(CroatianBeachColors.crystalWater)
                        }
                    }
                    
                    // Vertical stack of results (compact preview)
                    VStack(spacing: CroatianBeachSpacing.small) {
                        ForEach(Array(currentResults.prefix(2).enumerated()), id: \.offset) { index, result in
                            compactResultCard(result)
                        }
                        
                        if currentResults.count > 2 {
                            Text("+ \(currentResults.count - 2) more")
                                .font(CroatianBeachTypography.caption)
                                .foregroundColor(CroatianBeachColors.seaFoam)
                                .padding(.top, CroatianBeachSpacing.small)
                        }
                    }
                }
                .padding(CroatianBeachSpacing.large)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(CroatianBeachColors.seafoamMist.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            CroatianBeachColors.crystalWater.opacity(0.4),
                                            CroatianBeachColors.seaFoam.opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: CroatianBeachColors.seaFoam.opacity(0.2), radius: 12, x: 0, y: 6)
                )
                .padding(.horizontal, CroatianBeachSpacing.large)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                ))
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showExpandedResults = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func resultCard(_ result: ResultItem) -> some View {
        VStack(alignment: .leading, spacing: CroatianBeachSpacing.small) {
            // Icon and title
            HStack(spacing: CroatianBeachSpacing.small) {
                Image(systemName: result.iconName)
                    .foregroundColor(result.color)
                    .font(.system(size: 16, weight: .medium))
                
                Text(result.title)
                    .font(CroatianBeachTypography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(CroatianBeachColors.deepEmerald)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            
            // Subtitle
            if let subtitle = result.subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(CroatianBeachColors.emeraldShade)
                    .lineLimit(2)
            }
            
            // Detail
            if let detail = result.detail {
                Text(detail)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(CroatianBeachColors.seaFoam)
                    .lineLimit(1)
            }
        }
        .padding(CroatianBeachSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CroatianBeachColors.beachSand.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(result.color.opacity(0.2), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func compactResultCard(_ result: ResultItem) -> some View {
        HStack(spacing: CroatianBeachSpacing.medium) {
            // Icon
            Image(systemName: result.iconName)
                .foregroundColor(result.color)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(CroatianBeachTypography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(CroatianBeachColors.deepEmerald)
                    .lineLimit(1)
                
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(CroatianBeachColors.emeraldShade)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let detail = result.detail {
                Text(detail)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(CroatianBeachColors.seaFoam)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, CroatianBeachSpacing.small)
        .padding(.horizontal, CroatianBeachSpacing.medium)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CroatianBeachColors.beachSand.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(result.color.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Expanded Results Overlay
    
    private var expandedResultsOverlay: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showExpandedResults = false
                    }
                }
            
            // Expanded results content
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: CroatianBeachSpacing.large) {
                    // Header
                    HStack {
                        Text(resultsTitle)
                            .font(CroatianBeachTypography.title)
                            .fontWeight(.semibold)
                            .foregroundColor(CroatianBeachColors.deepEmerald)
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showExpandedResults = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(CroatianBeachColors.emeraldShade)
                        }
                    }
                    
                    // All results in scrollable view
                    ScrollView {
                        VStack(spacing: CroatianBeachSpacing.medium) {
                            ForEach(currentResults) { result in
                                expandedResultCard(result)
                            }
                        }
                        .padding(.vertical, CroatianBeachSpacing.medium)
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                }
                .padding(CroatianBeachSpacing.xlarge)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(CroatianBeachColors.beachSand)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            CroatianBeachColors.crystalWater.opacity(0.4),
                                            CroatianBeachColors.seaFoam.opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: CroatianBeachColors.seaFoam.opacity(0.3), radius: 20, x: 0, y: 10)
                )
                .frame(maxWidth: UIScreen.main.bounds.width * 0.9)
                
                Spacer()
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)),
            removal: .opacity
        ))
    }
    
    private func expandedResultCard(_ result: ResultItem) -> some View {
        VStack(alignment: .leading, spacing: CroatianBeachSpacing.medium) {
            // Header with icon and title
            HStack(spacing: CroatianBeachSpacing.medium) {
                Image(systemName: result.iconName)
                    .foregroundColor(result.color)
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(CroatianBeachTypography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(CroatianBeachColors.deepEmerald)
                    
                    if let subtitle = result.subtitle {
                        Text(subtitle)
                            .font(CroatianBeachTypography.caption)
                            .foregroundColor(CroatianBeachColors.emeraldShade)
                    }
                }
                
                Spacer()
                
                if let detail = result.detail {
                    Text(detail)
                        .font(CroatianBeachTypography.caption)
                        .foregroundColor(CroatianBeachColors.seaFoam)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(CroatianBeachSpacing.large)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(CroatianBeachColors.seafoamMist.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(result.color.opacity(0.3), lineWidth: 1.5)
                )
        )
    }
    
    // MARK: - Connection Status
    
    private var connectionStatusIndicator: some View {
        HStack(spacing: CroatianBeachSpacing.small) {
            Circle()
                .fill(realtimeService.isConnected ? CroatianBeachColors.seaFoam : CroatianBeachColors.emeraldShade.opacity(0.5))
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.3), value: realtimeService.isConnected)
            
            Text(realtimeService.isConnected ? "Connected" : "Tap to connect")
                .font(CroatianBeachTypography.caption)
                .foregroundColor(CroatianBeachColors.emeraldShade.opacity(0.7))
        }
    }
    
    // MARK: - Computed Properties
    
    private var voiceStateText: String {
        if !realtimeService.isConnected {
            return "Tap to connect"
        }
        
        switch realtimeService.conversationState {
        case .idle:
            return "Ready to listen"
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .speaking:
            return "Responding..."
        case .thinking:
            return "Thinking..."
        }
    }
    
    private var shouldShowStatusText: Bool {
        // Only show status text when there's meaningful activity
        return !realtimeService.isConnected || 
               realtimeService.conversationState == .listening ||
               realtimeService.conversationState == .processing ||
               realtimeService.conversationState == .thinking ||
               realtimeService.conversationState == .speaking
    }
    
    private var stableToolStatus: ToolStatus {
        // Prevent flickering by only changing status when tool calls are confirmed
        switch realtimeService.conversationState {
        case .listening:
            return .listening
        case .processing, .thinking:
            // Only show tool-specific status if we have confirmed tool usage
            if let toolName = realtimeService.toolManager.lastToolUsed,
               realtimeService.conversationState == .processing {
                switch toolName {
                case let tool where tool.contains("find") || tool.contains("search"):
                    return .searching
                case let tool where tool.contains("location") || tool.contains("directions"):
                    return .lookingAround
                default:
                    return .thinking
                }
            } else {
                return .thinking
            }
        case .speaking:
            return .thinking // Keep stable during response
        default:
            return .idle
        }
    }
    
    // MARK: - Actions
    
    private func toggleConversation() {
        if realtimeService.isConnected {
            stopConversation()
        } else {
            startConversation()
        }
    }
    
    private func startConversation() {
        isConnecting = true
        
        Task {
            do {
                try await realtimeService.connect()
                await MainActor.run {
                    realtimeService.setLocationManager(locationManager)
                    realtimeService.startStreaming()
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                }
                print("❌ Failed to connect: \(error)")
            }
        }
    }
    
    private func stopConversation() {
        realtimeService.stopStreaming()
        realtimeService.disconnect()
    }
    
    private func resetConversation() {
        // Clear conversation data but keep it in logs
        realtimeService.clearConversation()
        print("🗑️ Conversation cleared from UI (retained in logs)")
    }
    
    private func startLocationTracking() {
        locationManager.requestLocationPermission()
    }
    
    // MARK: - Results Processing
    
    private func processLatestResponse(from conversation: [RealtimeMessage]) {
        guard let latestMessage = conversation.last,
              latestMessage.role == "assistant",
              !latestMessage.isStreaming else { return }
        
        // Parse response for structured data
        let results = extractResults(from: latestMessage.content)
        
        if !results.isEmpty {
            showResults(results, title: generateResultsTitle(from: latestMessage.content))
        } else {
            // Hide results for simple responses
            hideResults()
        }
    }
    
    private func extractResults(from content: String) -> [ResultItem] {
        // Use LLM to intelligently extract structured data
        Task {
            await extractResultsWithLLM(from: content)
        }
        
        // Return empty for now - LLM extraction will update state asynchronously
        return []
    }
    
    private func extractResultsWithLLM(from content: String) async {
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
            print("❌ Failed to extract results with LLM: \(error)")
            // Fallback to simple detection if LLM fails
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
    
    // MARK: - JSON Parsing
    
    private func parseStructuredResponse(_ jsonString: String) -> [ResultItem] {
        var results: [ResultItem] = []
        
        // Clean the JSON string (remove any markdown formatting)
        let cleanedJSON = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            print("❌ Failed to convert response to data")
            return []
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                // Parse restaurants
                if let restaurants = json["restaurants"] as? [[String: Any]] {
                    for restaurant in restaurants.prefix(2) {
                        if let name = restaurant["name"] as? String {
                            results.append(ResultItem(
                                title: name,
                                subtitle: restaurant["rating"] as? String ?? restaurant["cuisine"] as? String,
                                detail: restaurant["distance"] as? String,
                                iconName: "fork.knife",
                                color: CroatianBeachColors.seaFoam
                            ))
                        }
                    }
                }
                
                // Parse places
                if let places = json["places"] as? [[String: Any]] {
                    for place in places.prefix(2) {
                        if let name = place["name"] as? String {
                            results.append(ResultItem(
                                title: name,
                                subtitle: place["type"] as? String,
                                detail: place["distance"] as? String,
                                iconName: "location.fill",
                                color: CroatianBeachColors.crystalWater
                            ))
                        }
                    }
                }
                
                // Parse directions
                if let directions = json["directions"] as? [[String: Any]] {
                    for direction in directions.prefix(1) {
                        if let destination = direction["destination"] as? String {
                            results.append(ResultItem(
                                title: destination,
                                subtitle: direction["time"] as? String,
                                detail: direction["distance"] as? String,
                                iconName: "arrow.triangle.turn.up.right.diamond",
                                color: CroatianBeachColors.emeraldShade
                            ))
                        }
                    }
                }
                
                // Parse weather
                if let weather = json["weather"] as? [[String: Any]] {
                    for weatherInfo in weather.prefix(1) {
                        results.append(ResultItem(
                            title: "Weather",
                            subtitle: weatherInfo["temperature"] as? String,
                            detail: weatherInfo["condition"] as? String,
                            iconName: "cloud.sun",
                            color: CroatianBeachColors.seaFoam
                        ))
                    }
                }
                
                // Parse currency
                if let currency = json["currency"] as? [[String: Any]] {
                    for currencyInfo in currency.prefix(1) {
                        if let from = currencyInfo["from"] as? String,
                           let to = currencyInfo["to"] as? String {
                            results.append(ResultItem(
                                title: "\(from) → \(to)",
                                subtitle: currencyInfo["rate"] as? String,
                                detail: "Exchange rate",
                                iconName: "dollarsign.circle",
                                color: CroatianBeachColors.deepWater
                            ))
                        }
                    }
                }
            }
        } catch {
            print("❌ Failed to parse JSON response: \(error)")
        }
        
        return Array(results.prefix(4)) // Limit to 4 total results
    }
    
    // MARK: - Fallback Simple Extraction
    
    private func simpleExtraction(from content: String) -> [ResultItem] {
        var results: [ResultItem] = []
        let lowercaseContent = content.lowercased()
        
        // Simple keyword-based detection for fallback
        if lowercaseContent.contains("restaurant") || lowercaseContent.contains("café") {
            results.append(ResultItem(
                title: "Restaurant Options",
                subtitle: "Found in response",
                detail: nil,
                iconName: "fork.knife",
                color: CroatianBeachColors.seaFoam
            ))
        }
        
        if lowercaseContent.contains("museum") || lowercaseContent.contains("park") || lowercaseContent.contains("attraction") {
            results.append(ResultItem(
                title: "Places to Visit",
                subtitle: "Found in response",
                detail: nil,
                iconName: "location.fill",
                color: CroatianBeachColors.crystalWater
            ))
        }
        
        if lowercaseContent.contains("weather") || lowercaseContent.contains("°") {
            results.append(ResultItem(
                title: "Weather Info",
                subtitle: "Current conditions",
                detail: nil,
                iconName: "cloud.sun",
                color: CroatianBeachColors.seaFoam
            ))
        }
        
        if lowercaseContent.contains("direction") || lowercaseContent.contains("route") {
            results.append(ResultItem(
                title: "Directions",
                subtitle: "Route information",
                detail: nil,
                iconName: "arrow.triangle.turn.up.right.diamond",
                color: CroatianBeachColors.emeraldShade
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
    
    private func showResults(_ results: [ResultItem], title: String) {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentResults = results
            resultsTitle = title
            showResultsPane = true
        }
        
        // Auto-hide after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            hideResults()
        }
    }
    
    private func hideResults() {
        withAnimation(.easeInOut(duration: 0.4)) {
            showResultsPane = false
            showExpandedResults = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            currentResults = []
            resultsTitle = ""
        }
    }
}