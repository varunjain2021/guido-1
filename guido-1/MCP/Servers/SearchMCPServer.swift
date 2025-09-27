import Foundation

public class SearchMCPServer {
    private weak var openAIChatService: OpenAIChatService?
    private weak var locationSearchService: LocationBasedSearchService?
    private let serverInfo = MCPServerInfo(name: "Guido Search Server", version: "1.0.0")
    private var perplexityApiKey: String?
    
    init() {
        // Load Perplexity key from Config.plist
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let key = dict["Perplexity_API_Key"] as? String, !key.isEmpty {
            perplexityApiKey = key
            print("🔑 [SearchMCPServer] Perplexity API key loaded")
        } else {
            print("⚠️ [SearchMCPServer] Perplexity API key missing; web_search will fallback")
        }
    }
    
    func setOpenAIChatService(_ service: OpenAIChatService) {
        self.openAIChatService = service
    }
    
    func setLocationSearchService(_ service: LocationBasedSearchService) {
        self.locationSearchService = service
    }
    
    public func getCapabilities() -> MCPCapabilities {
        return MCPCapabilities(tools: MCPToolsCapability(listChanged: true), resources: nil, prompts: nil, sampling: nil)
    }
    
    public func getServerInfo() -> MCPServerInfo { serverInfo }
    
    public func listTools() -> [MCPTool] {
        return [
            webSearchTool(),
            aiResponseTool()
        ]
    }
    
    public func callTool(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        print("🔎 [SearchMCPServer] Executing tool: \(request.name)")
        switch request.name {
        case "web_search":
            return await executeWebSearch(request)
        case "ai_response":
            return await executeAIResponse(request)
        default:
            return MCPCallToolResponse(content: [MCPContent(text: "Tool '\(request.name)' not found")], isError: true)
        }
    }
    
    private func webSearchTool() -> MCPTool {
        return MCPTool(
            name: "web_search",
            description: "Search the internet for real-time information",
            inputSchema: MCPToolInputSchema(properties: [
                "query": MCPPropertySchema(type: "string", description: "Search query"),
                "location": MCPPropertySchema(type: "string", description: "Location context (optional)")
            ], required: ["query"]) 
        )
    }
    
    private func aiResponseTool() -> MCPTool {
        return MCPTool(
            name: "ai_response",
            description: "Get intelligent responses and analysis",
            inputSchema: MCPToolInputSchema(properties: [
                "prompt": MCPPropertySchema(type: "string", description: "Prompt"),
                "context": MCPPropertySchema(type: "string", description: "Context (optional)")
            ], required: ["prompt"]) 
        )
    }
    
    private func executeWebSearch(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let query = request.arguments?["query"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing query")], isError: true)
        }
        let location = request.arguments?["location"] as? String
        let composedQuery = (location != nil && !(location!.isEmpty)) ? "\(query) in \(location!)" : query
        
        if let key = perplexityApiKey, !key.isEmpty {
            do {
                let text = try await callPerplexity(query: composedQuery, apiKey: key)
                return MCPCallToolResponse(content: [MCPContent(text: text)], isError: false)
            } catch {
                print("⚠️ [SearchMCPServer] Perplexity call failed: \(error). Falling back")
                // fall through to legacy search fallback
            }
        }
        
        // Fallback to legacy LocationBasedSearchService if available
        if let searchService = locationSearchService {
            let result = await searchService.findNearbyServices(serviceType: "general search", query: composedQuery)
            if let error = result.error {
                return MCPCallToolResponse(content: [MCPContent(text: "Web search error: \(error)")], isError: true)
            }
            let text = result.summary ?? "No results"
            return MCPCallToolResponse(content: [MCPContent(text: text)], isError: false)
        } else {
            return MCPCallToolResponse(content: [MCPContent(text: "Search service unavailable and Perplexity not configured")], isError: true)
        }
    }
    
    private func executeAIResponse(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let openAI = openAIChatService else {
            return MCPCallToolResponse(content: [MCPContent(text: "AI service unavailable")], isError: true)
        }
        guard let prompt = request.arguments?["prompt"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing prompt")], isError: true)
        }
        let context = (request.arguments?["context"] as? String) ?? ""
        let composed = context.isEmpty ? prompt : "\(prompt)\n\nContext: \(context)"
        do {
            let response = try await openAI.send(message: composed, conversation: [])
            return MCPCallToolResponse(content: [MCPContent(text: response)], isError: false)
        } catch {
            return MCPCallToolResponse(content: [MCPContent(text: "AI error: \(error.localizedDescription)")], isError: true)
        }
    }
}

// MARK: - Perplexity Integration
extension SearchMCPServer {
    private func callPerplexity(query: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.perplexity.ai/chat/completions") else {
            throw NSError(domain: "SearchMCPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Perplexity URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "sonar-pro",
            "messages": [["role": "user", "content": query]],
            "temperature": 0.2
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SearchMCPServer", code: status, userInfo: [NSLocalizedDescriptionKey: "Perplexity HTTP \(status): \(raw)"])
        }
        
        // Parse minimally: choices[0].message.content; append citations if present
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var output = ""
            if let choices = root["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                output = content
            }
            if let citations = root["citations"] as? [String], !citations.isEmpty {
                let sources = citations.prefix(8).map { "- \($0)" }.joined(separator: "\n")
                output += "\n\nSources:\n\(sources)"
            }
            return output.isEmpty ? (String(data: data, encoding: .utf8) ?? "") : output
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

