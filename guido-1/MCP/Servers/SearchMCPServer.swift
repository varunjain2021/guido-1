import Foundation

public class SearchMCPServer {
    private weak var openAIChatService: OpenAIChatService?
    private weak var locationSearchService: LocationBasedSearchService?
    private let serverInfo = MCPServerInfo(name: "Guido Search Server", version: "1.0.0")
    
    init() {}
    
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
        guard let searchService = locationSearchService else {
            return MCPCallToolResponse(content: [MCPContent(text: "Search service unavailable")], isError: true)
        }
        guard let query = request.arguments?["query"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing query")], isError: true)
        }
        let location = request.arguments?["location"] as? String
        let searchQuery = location != nil && !(location!.isEmpty) ? "\(query) in \(location!)" : query
        let result = await searchService.findNearbyServices(serviceType: "general search", query: searchQuery)
        if let error = result.error {
            return MCPCallToolResponse(content: [MCPContent(text: "Web search error: \(error)")], isError: true)
        }
        let text = result.summary ?? "No results"
        return MCPCallToolResponse(content: [MCPContent(text: text)], isError: false)
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

