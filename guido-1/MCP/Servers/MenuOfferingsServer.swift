import Foundation

public final class MenuOfferingsServer {
    private weak var openAIChatService: OpenAIChatService?
    private weak var webContentServer: WebContentServer?
    private let serverInfo = MCPServerInfo(name: "Guido Menu & Offerings Server", version: "1.0.0")
    private let cacheQueue = DispatchQueue(label: "MenuOfferingsServer.cache", attributes: .concurrent)
    private var menuCache: [String: CacheEntry] = [:]
    private var catalogCache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 60 * 30
    
    private struct CacheEntry {
        let timestamp: Date
        let payload: [String: Any]
    }
    
    init() {}
    
    func setOpenAIChatService(_ service: OpenAIChatService) {
        self.openAIChatService = service
    }
    
    func setWebContentServer(_ server: WebContentServer) {
        self.webContentServer = server
    }
    
    public func getCapabilities() -> MCPCapabilities {
        MCPCapabilities(tools: MCPToolsCapability(listChanged: true), resources: nil, prompts: nil, sampling: nil)
    }
    
    public func getServerInfo() -> MCPServerInfo { serverInfo }
    
    public func listTools() -> [MCPTool] {
        [
            menuParseTool(),
            catalogClassifyTool()
        ]
    }
    
    public func callTool(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        switch request.name {
        case "menu_parse":
            return await executeMenuParse(request)
        case "catalog_classify":
            return await executeCatalogClassify(request)
        default:
            return MCPCallToolResponse(content: [MCPContent(text: "Tool '\(request.name)' not found")], isError: true)
        }
    }
    
    // MARK: - Tool Definitions
    
    private func menuParseTool() -> MCPTool {
        MCPTool(
            name: "menu_parse",
            description: "Summarize a food/beverage menu, highlighting sections, dietary tags, price level, signatures, and availability.",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "htmlText": MCPPropertySchema(type: "string", description: "Optional HTML or readable text of the menu"),
                    "url": MCPPropertySchema(type: "string", description: "Optional URL to fetch using WebContentServer"),
                    "placeName": MCPPropertySchema(type: "string", description: "Optional place name for context")
                ],
                required: []
            )
        )
    }
    
    private func catalogClassifyTool() -> MCPTool {
        MCPTool(
            name: "catalog_classify",
            description: "Summarize a retail catalog/offerings page, capturing categories, styles, price level, policies, and notable items.",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "htmlText": MCPPropertySchema(type: "string", description: "Optional HTML or readable text of the catalog"),
                    "url": MCPPropertySchema(type: "string", description: "Optional URL to fetch using WebContentServer"),
                    "placeName": MCPPropertySchema(type: "string", description: "Optional place name for context")
                ],
                required: []
            )
        )
    }
    
    // MARK: - Execution
    
    private func executeMenuParse(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        await summarizeOfferings(
            request: request,
            purpose: .menu
        )
    }
    
    private func executeCatalogClassify(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        await summarizeOfferings(
            request: request,
            purpose: .catalog
        )
    }
    
    private enum Purpose {
        case menu
        case catalog
        
        var label: String {
            switch self {
            case .menu: return "menu"
            case .catalog: return "catalog"
            }
        }
    }
    
    private func summarizeOfferings(request: MCPCallToolRequest, purpose: Purpose) async -> MCPCallToolResponse {
        let placeName = (request.arguments?["placeName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let htmlText = request.arguments?["htmlText"] as? String
        let urlString = request.arguments?["url"] as? String
        
        do {
            let rawText: String
            if let htmlText, !htmlText.isEmpty {
                rawText = htmlText
            } else if let urlString, let url = URL(string: urlString) {
                guard let server = webContentServer else {
                    throw NSError(domain: "MenuOfferingsServer", code: 20, userInfo: [NSLocalizedDescriptionKey: "WebContentServer not configured"])
                }
                let response = await server.callTool(
                    MCPCallToolRequest(name: "web_readable_extract", arguments: ["url": url.absoluteString])
                )
                guard response.isError != true,
                      let text = response.content.first?.text,
                      let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = json["content"] as? String else {
                    throw NSError(domain: "MenuOfferingsServer", code: 21, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch readable content from \(url.absoluteString)"])
                }
                rawText = content
            } else {
                throw NSError(domain: "MenuOfferingsServer", code: 22, userInfo: [NSLocalizedDescriptionKey: "Provide htmlText or url for \(purpose.label)_parse"])
            }
            
            let cacheKey = cacheKeyFor(text: rawText, purpose: purpose, placeName: placeName, urlString: urlString)
            if let cached = cachedPayload(for: cacheKey, purpose: purpose) {
                let payload = cached
                let result = try encodeJSON(payload)
                return MCPCallToolResponse(content: [MCPContent(text: result)], isError: false)
            }
            
            guard let openAIChatService else {
                throw NSError(domain: "MenuOfferingsServer", code: 23, userInfo: [NSLocalizedDescriptionKey: "OpenAIChatService unavailable"])
            }
            
            let prompt = buildPrompt(text: rawText, placeName: placeName, purpose: purpose)
            let response = try await openAIChatService.generateStructuredData(prompt: prompt)
            guard let data = response.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "MenuOfferingsServer", code: 24, userInfo: [NSLocalizedDescriptionKey: "OpenAI response was not valid JSON"])
            }
            
            var payload = jsonObject
            payload["generatedAt"] = ISO8601DateFormatter().string(from: Date())
            payload["source"] = [
                "type": purpose.label,
                "placeName": placeName,
                "url": urlString ?? ""
            ]
            storePayload(payload, for: cacheKey, purpose: purpose)
            let result = try encodeJSON(payload)
            return MCPCallToolResponse(content: [MCPContent(text: result)], isError: false)
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "\(purpose.label)_parse failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func buildPrompt(text: String, placeName: String, purpose: Purpose) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = trimmed.count > 8000 ? String(trimmed.prefix(8000)) : trimmed
        switch purpose {
        case .menu:
            return """
            You are MenuScope, an expert at extracting structured menu information for AI discovery. Analyze the provided menu text and return JSON ONLY with this schema:
            {
              "priceLevel": "cheap|moderate|expensive|premium|unknown",
              "sections": [
                {
                  "title": "string",
                  "items": [
                    {
                      "name": "string",
                      "description": "string",
                      "price": "string",
                      "dietaryTags": ["vegan","vegetarian","gluten-free","dairy-free","nut-free","plant-based","halal","kosher","keto","other"]
                    }
                  ]
                }
              ],
              "dietaryHighlights": ["string"],
              "beverageHighlights": ["string"],
              "signatures": ["string"],
              "serviceNotes": ["string"],
              "availability": {
                "breakfast": true,
                "lunch": true,
                "dinner": true,
                "weekendBrunch": true
              },
              "lastUpdatedHint": "string"
            }
            Rules:
            - Do NOT invent items. Only use what appears in the text.
            - Group items into logical sections (e.g., Breakfast, Sandwiches, Coffee).
            - Summaries should be concise (1-2 sentences).
            - If dietary tags are implied (e.g., “vegan bowl”), include them.
            - priceLevel is your best estimate based on typical item prices.
            \(placeName.isEmpty ? "" : "Context: The venue is \(placeName).")
            Menu Text:
            \(clipped)
            """
        case .catalog:
            return """
            You are RetailScope, an expert at summarizing retail offerings. Analyze the provided text and return JSON ONLY with this schema:
            {
              "styles": ["streetwear","formal","outdoor","athleisure","minimalist","classic","casual","luxury","other"],
              "categories": [
                {
                  "label": "string",
                  "examples": ["string"]
                }
              ],
              "priceLevel": "budget|moderate|premium|luxury|unknown",
              "sizeRange": "string",
              "policies": {
                "returns": "string",
                "exchange": "string",
                "shipping": "string",
                "special": ["string"]
              },
              "notableBrands": ["string"],
              "sustainabilityNotes": ["string"],
              "serviceNotes": ["string"]
            }
            Rules:
            - Stick strictly to what's in the text. If unknown, use sensible defaults like "unknown" or empty arrays.
            - Summaries should be short and factual.
            - serviceNotes can capture tailoring, appointments, personal shoppers, etc.
            \(placeName.isEmpty ? "" : "Context: The venue is \(placeName).")
            Catalog Text:
            \(clipped)
            """
        }
    }
    
    // MARK: - Helpers
    
    private func encodeJSON(_ dictionary: [String: Any]) throws -> String {
        let sanitized = JSONSanitizer.sanitizeDictionary(dictionary)
        let data = try JSONSerialization.data(withJSONObject: sanitized, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "MenuOfferingsServer", code: 31, userInfo: [NSLocalizedDescriptionKey: "Unable to encode JSON as UTF-8"])
        }
        return text
    }
    
    // MARK: - Caching
    
    private func cacheKeyFor(text: String, purpose: Purpose, placeName: String, urlString: String?) -> String {
        let snippet = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = snippet.prefix(512)
        let hashBase = "\(purpose.label)|\(placeName)|\(urlString ?? "inline")|\(prefix)"
        return String(hashBase.hashValue)
    }
    
    private func cachedPayload(for key: String, purpose: Purpose) -> [String: Any]? {
        var entry: CacheEntry?
        cacheQueue.sync {
            switch purpose {
            case .menu:
                entry = menuCache[key]
            case .catalog:
                entry = catalogCache[key]
            }
        }
        guard let entry else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > cacheTTL {
            cacheQueue.async(flags: .barrier) {
                switch purpose {
                case .menu:
                    self.menuCache.removeValue(forKey: key)
                case .catalog:
                    self.catalogCache.removeValue(forKey: key)
                }
            }
            return nil
        }
        return entry.payload
    }
    
    private func storePayload(_ payload: [String: Any], for key: String, purpose: Purpose) {
        let entry = CacheEntry(timestamp: Date(), payload: payload)
        cacheQueue.async(flags: .barrier) {
            switch purpose {
            case .menu:
                self.menuCache[key] = entry
                self.menuCache = self.pruneCache(self.menuCache, limit: 40)
            case .catalog:
                self.catalogCache[key] = entry
                self.catalogCache = self.pruneCache(self.catalogCache, limit: 40)
            }
        }
    }
    
    private func pruneCache(_ cache: [String: CacheEntry], limit: Int) -> [String: CacheEntry] {
        let now = Date()
        var filtered = cache.filter { now.timeIntervalSince($0.value.timestamp) <= cacheTTL }
        if filtered.count > limit {
            let sortedKeys = filtered.sorted { $0.value.timestamp > $1.value.timestamp }.map { $0.key }
            let keysToKeep = Set(sortedKeys.prefix(limit))
            filtered = filtered.filter { keysToKeep.contains($0.key) }
        }
        return filtered
    }
}

