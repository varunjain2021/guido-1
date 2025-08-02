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
        return chatResponse.choices.first?.message.content ?? ""
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