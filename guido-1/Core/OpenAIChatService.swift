//
//  OpenAIChatService.swift
//  guido-1
//
//  Created by Varun Jain on 7/27/25.
//

import Foundation

class OpenAIChatService {
    private let apiKey: String
    private let session = URLSession.shared

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func send(message: String, conversation: [ChatMessage]) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Create system prompt for natural conversation
        let systemPrompt = ChatMessage(
            role: "system", 
            content: """
            You are Guido, a helpful and conversational AI assistant. Keep responses natural, concise, and friendly. 
            
            Guidelines:
            - Speak like a real person, not a robot
            - Keep responses under 2-3 sentences when possible
            - Be warm, helpful, and engaging
            - Don't over-explain or be overly verbose
            - Use natural speech patterns and contractions
            - Show personality and be slightly casual
            - Ask follow-up questions to keep the conversation flowing
            """
        )

        var messages = [systemPrompt] + conversation
        messages.append(ChatMessage(role: "user", content: message))

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "max_tokens": 150,
            "temperature": 0.8
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAIChatService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get chat response."])
        }

        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let raw = chatResponse.choices.first?.message.content ?? ""
        let enforced = NavigationStyleGuard.enforce(raw).text
        return enforced
    }
    
    // MARK: - Missing Methods for ListeningView
    
    func transcribeAudio(audioData: Data) async throws -> String {
        // Convert audio data to text using OpenAI Whisper API
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var formData = Data()
        
        // Add model parameter
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        formData.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add audio file
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        formData.append(audioData)
        formData.append("\r\n".data(using: .utf8)!)
        
        // Close boundary
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = formData
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAIChatService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to transcribe audio."])
        }
        
        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return transcriptionResponse.text
    }
    
    func sendMessage(conversation: [ChatMessage]) async throws -> String {
        // Get the last user message from the conversation
        guard let lastMessage = conversation.last, lastMessage.role == "user" else {
            throw NSError(domain: "OpenAIChatService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No user message found in conversation."])
        }
        
        // Use the existing send method with conversation history
        let conversationHistory = Array(conversation.dropLast()) // Remove the last message since it will be added in send()
        return try await send(message: lastMessage.content, conversation: conversationHistory)
    }
    
    func generateProactiveMessage(prompt: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = [
            ["role": "system", "content": prompt],
            ["role": "user", "content": "Generate a proactive suggestion for me."]
        ]

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 120,
            "temperature": 0.9
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAIChatService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to generate proactive message."])
        }

        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }
    
    func generateStructuredData(prompt: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = [
            ["role": "system", "content": "You are a data extraction assistant. Extract structured information from text and return it as valid JSON only. Do not include any explanations or additional text."],
            ["role": "user", "content": prompt]
        ]

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 500,
            "temperature": 0.1  // Low temperature for consistent structured output
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAIChatService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to generate structured data."])
        }

        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }
}

// MARK: - Data Models

struct ChatMessage: Codable, Identifiable {
    let id: UUID
    let role: String
    let content: String
    
    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
    }
    
    // Codable conformance with custom id handling
    enum CodingKeys: String, CodingKey {
        case role, content
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.role = try container.decode(String.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
    }
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: ChatMessage
}

struct TranscriptionResponse: Codable {
    let text: String
}

// MARK: - Location Intelligence Extensions

extension OpenAIChatService {
    
    /// Synthesizes location results from multiple data sources into natural, conversational responses
    func synthesizeLocationResults(
        userQuery: String,
        googlePlaces: [Any]?,
        webSearchData: String?,
        locationContext: String,
        conversationContext: String? = nil
    ) async throws -> String {
        
        let systemPrompt = ChatMessage(
            role: "system",
            content: """
            You are Guido's location intelligence system. Synthesize location data from multiple sources into natural, helpful responses.
            
            CRITICAL ACCURACY REQUIREMENTS:
            - ONLY mention specific addresses/businesses that are explicitly provided in the data
            - NEVER invent, approximate, or hallucinate addresses, names, or details
            - Use EXACT names and addresses from the provided data
            - If uncertain about details, be general ("I found a location nearby") rather than specific
            
            Guidelines:
            - Prioritize accuracy and user safety above all else
            - Be conversational and contextual
            - Highlight key details (open/closed, distance, ratings) naturally from the data
            - Suggest the best options based on actual provided information
            - If data conflicts or seems unreliable, explain uncertainty honestly
            - Be concise but informative
            - Use natural speech patterns, not template formatting
            - Consider the user's likely intent and provide proactive suggestions
            """
        )
        
        var dataDescription = "Location Context: \(locationContext)\n"
        
        if let googlePlaces = googlePlaces, !googlePlaces.isEmpty {
            dataDescription += "\nGoogle Places Results (\(googlePlaces.count) found):\n"
            for (index, place) in googlePlaces.enumerated() {
                if let placeDict = place as? [String: Any] {
                    let name = placeDict["name"] as? String ?? "Unknown"
                    let address = placeDict["address"] as? String ?? "Address unavailable"
                    let distance = placeDict["distance_meters"] as? Int ?? 0
                    let isOpen = placeDict["is_open"] as? Bool
                    let rating = placeDict["rating"] as? Double
                    
                    dataDescription += "\(index + 1). \(name) at \(address) (\(distance)m away)"
                    if let open = isOpen {
                        dataDescription += open ? " - OPEN" : " - CLOSED"
                    }
                    if let rating = rating, rating > 0 {
                        dataDescription += " - Rating: \(rating)"
                    }
                    dataDescription += "\n"
                }
            }
        }
        
        if let webData = webSearchData, !webData.isEmpty {
            dataDescription += "\nWeb Search Context: \(webData)\n"
        }
        
        let userPrompt = ChatMessage(
            role: "user",
            content: """
            User asked: "\(userQuery)"
            
            \(dataDescription)
            
            \(conversationContext.map { "Conversation context: \($0)" } ?? "")
            
            Provide a natural, helpful response with your best recommendations. Focus on being genuinely helpful rather than just listing information.
            """
        )
        
        let response = try await send(message: userPrompt.content, conversation: [systemPrompt])
        
        // Validate that LLM response doesn't contain hallucinated addresses
        if let googlePlaces = googlePlaces, !googlePlaces.isEmpty {
            let validatedResponse = validateLocationResponse(response: response, googlePlacesData: googlePlaces)
            return validatedResponse
        }
        
        return response
    }
    
    /// Intelligently detects if results need user clarification
    func detectAmbiguityAndAskClarification(
        userQuery: String,
        googlePlaces: [Any]?,
        webSearchData: String?,
        locationContext: String
    ) async throws -> String? {
        
        let systemPrompt = ChatMessage(
            role: "system",
            content: """
            You are Guido's ambiguity detection system. Analyze search results to determine if they might not match the user's intent.
            
            Detect these scenarios that require clarification:
            1. Brand name confusion (e.g., "Uniqlo" vs "Uniclo", "Starbucks" vs "Star Bucks")
            2. Similar but different businesses (e.g., "Target that sells X brand" vs "X brand store")
            3. Generic terms that could mean multiple things
            4. Results that seem unrelated to the query
            5. No exact matches found, only similar alternatives
            
            If clarification is needed, respond with "CLARIFY:" followed by a natural question.
            If results seem appropriate, respond with "PROCEED"
            
            Be intelligent - minor variations are OK, but significant mismatches need clarification.
            """
        )
        
        var analysisContext = "User Query: '\(userQuery)'\nLocation: \(locationContext)\n"
        
        if let googlePlaces = googlePlaces, !googlePlaces.isEmpty {
            analysisContext += "\nGoogle Places Results:\n"
            for (index, place) in googlePlaces.enumerated() {
                if let placeDict = place as? [String: Any] {
                    let name = placeDict["name"] as? String ?? "Unknown"
                    let address = placeDict["address"] as? String ?? "Address unavailable"
                    analysisContext += "\(index + 1). \(name) at \(address)\n"
                }
            }
        }
        
        if let webData = webSearchData, !webData.isEmpty {
            analysisContext += "\nWeb Search Context: \(webData)\n"
        }
        
        let userPrompt = ChatMessage(
            role: "user",
            content: """
            \(analysisContext)
            
            Do these results match what the user is looking for, or should we ask for clarification?
            """
        )
        
        let response = try await send(message: userPrompt.content, conversation: [systemPrompt])
        
        if response.hasPrefix("CLARIFY:") {
            return String(response.dropFirst(8).trimmingCharacters(in: .whitespaces))
        }
        
        return nil // Proceed with normal results
    }
    
    /// Validates that LLM response only contains addresses from the actual data
    private func validateLocationResponse(response: String, googlePlacesData: [Any]) -> String {
        // Extract valid addresses from Google Places data
        var validAddresses: [String] = []
        var validNames: [String] = []
        
        for place in googlePlacesData {
            if let placeDict = place as? [String: Any] {
                if let address = placeDict["address"] as? String {
                    validAddresses.append(address)
                }
                if let name = placeDict["name"] as? String {
                    validNames.append(name)
                }
            }
        }
        
        // Check for common hallucination patterns in addresses
        let suspiciousPatterns = [
            "165 Amsterdam Ave",
            "165 Amsterdam Avenue", 
            "123 Main St",
            "456 Broadway"
        ]
        
        for pattern in suspiciousPatterns {
            if response.contains(pattern) && !validAddresses.contains(where: { $0.contains(pattern) }) {
                print("⚠️ [OpenAIChatService] Detected potential hallucinated address: \(pattern)")
                // Return a safer, more general response
                return "I found several locations nearby. Let me give you the verified information: \(validNames.joined(separator: ", ")). Would you like specific details about any of these?"
            }
        }
        
        return response
    }
    
    /// Determines optimal search strategy based on user intent and context
    func determineSearchStrategy(
        query: String,
        locationContext: String,
        timeContext: String? = nil,
        userHistory: String? = nil
    ) async throws -> SearchStrategy {
        
        let systemPrompt = ChatMessage(
            role: "system",
            content: """
            You are Guido's search strategy optimizer. Determine the best approach for finding places based on user intent and context.
            
            Respond with a JSON object containing:
            - searchRadius: recommended radius in meters (200-8000)
            - searchSources: array of preferred sources ["google_places", "web_search", "both"]
            - searchPriority: "proximity", "quality", "availability", or "comprehensive"
            - expandSearch: boolean if should progressively expand radius
            - contextualHints: array of search refinements to try
            """
        )
        
        let userPrompt = ChatMessage(
            role: "user",
            content: """
            User query: "\(query)"
            Location context: \(locationContext)
            \(timeContext.map { "Time context: \($0)" } ?? "")
            \(userHistory.map { "Recent searches: \($0)" } ?? "")
            
            What's the optimal search strategy?
            """
        )
        
        let response = try await send(message: userPrompt.content, conversation: [systemPrompt])
        
        // Parse JSON response into SearchStrategy
        guard let jsonData = response.data(using: .utf8),
              let strategy = try? JSONDecoder().decode(SearchStrategy.self, from: jsonData) else {
            // Fallback to default strategy if parsing fails
            return SearchStrategy.default(for: query)
        }
        
        return strategy
    }
    
    /// Provides intelligent route-aware recommendations
    func synthesizeRouteRecommendations(
        userQuery: String,
        destination: String,
        routePlaces: [Any]?,
        webInsights: String?,
        travelMode: String? = nil,
        currentLocation: String
    ) async throws -> String {
        
        let systemPrompt = ChatMessage(
            role: "system",
            content: """
            You are Guido's route intelligence system. Help users find places along their route with smart spatial reasoning.
            
            Guidelines:
            - Understand travel direction and suggest places that make sense for the journey
            - Consider travel mode (walking, driving, transit) for recommendations
            - Prioritize places that are genuinely "on the way" vs. detours
            - Be honest if nothing good is available along the route
            - Suggest alternatives if the direct route doesn't have what they need
            - Use natural language to explain the spatial relationships
            """
        )
        
        let userPrompt = ChatMessage(
            role: "user",
            content: """
            User wants: "\(userQuery)"
            Traveling from: \(currentLocation)
            Traveling to: \(destination)
            \(travelMode.map { "Travel mode: \($0)" } ?? "")
            
            Route-specific places found: \(routePlaces?.description ?? "None")
            Additional insights: \(webInsights ?? "None")
            
            Provide intelligent route recommendations with natural spatial reasoning.
            """
        )
        
        return try await send(message: userPrompt.content, conversation: [systemPrompt])
    }
    
    /// Handles edge cases and conflicting data intelligently
    func handleLocationUncertainty(
        userQuery: String,
        conflictingData: [String],
        locationContext: String,
        suggestedAlternatives: [String]? = nil
    ) async throws -> String {
        
        let systemPrompt = ChatMessage(
            role: "system",
            content: """
            You are Guido's uncertainty handler. When location data is conflicting or unreliable, provide honest, helpful guidance.
            
            Guidelines:
            - Be transparent about data limitations
            - Suggest verification methods (calling ahead, checking websites)
            - Provide alternative approaches
            - Maintain user confidence while being honest about uncertainty
            - Turn limitations into helpful guidance
            """
        )
        
        let userPrompt = ChatMessage(
            role: "user",
            content: """
            User query: "\(userQuery)"
            Location context: \(locationContext)
            Conflicting information: \(conflictingData.joined(separator: "; "))
            \(suggestedAlternatives.map { "Alternatives available: \($0.joined(separator: ", "))" } ?? "")
            
            How should we handle this uncertainty helpfully?
            """
        )
        
        return try await send(message: userPrompt.content, conversation: [systemPrompt])
    }
    
    /// Synthesizes intelligent directions with spatial reasoning and contextual guidance
    func synthesizeIntelligentDirections(
        destination: String,
        destinationData: [String: Any]?,
        routeData: [String: Any]?,
        transportationMode: String,
        currentLocation: String
    ) async throws -> String {
        
        let systemPrompt = ChatMessage(
            role: "system",
            content: """
            You are Guido's intelligent directions system. Provide natural, helpful navigation guidance with spatial reasoning.
            
            CRITICAL ACCURACY REQUIREMENTS:
            - ONLY reference specific addresses, business names, and landmarks from the provided data
            - NEVER invent or hallucinate street names, business names, or addresses
            - Use EXACT information from the route and destination data provided
            - If route details are unclear, provide general directional guidance
            
            Guidelines:
            - Confirm the traveler’s mode (walking, driving, etc.) and what they see directly ahead before describing the route
            - Think like a local guide walking beside the user: speak in a warm, calm tone and surface useful local context ("there’s a cozy cafe on the corner if you need a break")
            - Deliver directions step-by-step instead of dumping the entire route at once
            - Include helpful landmarks and spatial references when available in the data
            - Mention destination details from the provided data (hours, ratings, etc.)
            - Adapt language based on transportation mode (walking vs driving vs transit)
            - Provide practical tips when supported by the data
            - Be encouraging and confident about the route
            - Include estimated time and important travel considerations from the data
            - Make the directions feel personal and helpful, not robotic

            DIRECTIONS STYLE (STRICT):
            - NEVER use compass directions ("north", "south", "east", "west", "northeast", "NW", etc.). If you start to, immediately rephrase.
            - NEVER use arbitrary measurements like feet, meters, or yards. Keep everything relational to the user's view and short spans like "about a block" or "just past the next light".
            - ALWAYS use left/right instructions anchored to visible cues: intersections, named storefronts (Starbucks, McDonald's, Wells Fargo), park entrances, subway entrances, bridges, notable buildings, transit stops, or natural features near the user.
            - Keep each step grounded in what the user can see within a block or two; call out multiple nearby anchors (stores, restaurants, banks, transit, parks) when available so the user can verify they are on track.
            - If orientation is needed, give a quick visual cue (e.g., "Face the river; with the river on your left...") then proceed with left/right steps.
            - Break directions into short checkpoints and explicitly ask the user to confirm after each one ("Let me know when you reach the T intersection with the parking garage ahead"). Never give more than the next two steps at a time.
            - When the user confirms a checkpoint, restate their position using the visible anchors, offer a quick confidence boost ("perfect, you should see the cafe on your right"), and guide them to the next step.
            - Use clear step-by-step phrasing: "Walk one block to 71st Street and turn right. Keep the Starbucks on your left; the station entrance is just past it on the corner."
            """
        )
        
        var directionContext = "From: \(currentLocation)\nTo: \(destination)\nTravel mode: \(transportationMode)\n"
        
        if let destData = destinationData {
            directionContext += "\nDestination details: \(destData)\n"
        }
        
        if let routeInfo = routeData {
            directionContext += "\nRoute information: \(routeInfo)\n"
        }
        
        let userPrompt = ChatMessage(
            role: "user",
            content: """
            \(directionContext)
            
            Provide intelligent, conversational directions that help the user navigate confidently. Make it feel like helpful guidance from a knowledgeable friend who knows the area well.
            """
        )
        
        return try await send(message: userPrompt.content, conversation: [systemPrompt])
    }
}

// MARK: - Supporting Types

struct SearchStrategy: Codable {
    let searchRadius: Int
    let searchSources: [String]
    let searchPriority: String
    let expandSearch: Bool
    let contextualHints: [String]
    
    static func `default`(for query: String) -> SearchStrategy {
        return SearchStrategy(
            searchRadius: 1500,
            searchSources: ["both"],
            searchPriority: "comprehensive",
            expandSearch: true,
            contextualHints: [query]
        )
    }
} 