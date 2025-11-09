import Foundation

public final class WebSearchBridgeServer {
    private weak var searchServer: SearchMCPServer?
    private let serverInfo = MCPServerInfo(name: "Guido Discovery Search Bridge", version: "1.0.0")
    private let isoFormatter: ISO8601DateFormatter
    private let cacheQueue = DispatchQueue(label: "WebSearchBridgeServer.cache", attributes: .concurrent)
    private var searchCache: [String: CacheEntry] = [:]
    private var facetCache: [String: CacheEntry] = [:]
    private let searchTTL: TimeInterval = 60 * 30
    private let facetTTL: TimeInterval = 60 * 30
    
    private struct CacheEntry {
        let timestamp: Date
        let payload: [String: Any]
    }
    
    struct BridgeSearchResult {
        let query: String
        let summary: String
        let engine: String
        let results: [[String: Any]]
    }
    
    init(searchServer: SearchMCPServer? = nil) {
        self.searchServer = searchServer
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
    }
    
    func setSearchServer(_ server: SearchMCPServer) {
        self.searchServer = server
    }
    
    public func getCapabilities() -> MCPCapabilities {
        MCPCapabilities(tools: MCPToolsCapability(listChanged: true), resources: nil, prompts: nil, sampling: nil)
    }
    
    public func getServerInfo() -> MCPServerInfo {
        serverInfo
    }
    
    public func listTools() -> [MCPTool] {
        [
            searchWebTool(),
            searchCandidatesTool()
        ]
    }
    
    public func callTool(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        switch request.name {
        case "search_web":
            return await executeSearchWeb(request)
        case "search_candidates_for_facet":
            return await executeFacetCandidates(request)
        default:
            return MCPCallToolResponse(
                content: [MCPContent(text: "Tool '\(request.name)' not found")],
                isError: true
            )
        }
    }
    
    // MARK: - Tool Definitions
    
    private func searchWebTool() -> MCPTool {
        MCPTool(
            name: "search_web",
            description: "Run a lightweight web search (Google/Perplexity bridge) and return structured results",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "query": MCPPropertySchema(type: "string", description: "Primary search query"),
                    "siteFilters": MCPPropertySchema(type: "string", description: "Optional comma-separated domain filters (e.g. example.com,example.org)"),
                    "maxResults": MCPPropertySchema(type: "string", description: "Maximum number of structured results (default 5)"),
                    "origin": MCPPropertySchema(type: "string", description: "Optional calling context for logging")
                ],
                required: ["query"]
            )
        )
    }
    
    private func searchCandidatesTool() -> MCPTool {
        MCPTool(
            name: "search_candidates_for_facet",
            description: "Find candidate URLs for a discovery facet (e.g. menu, reviews, photos) using targeted web search",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "placeName": MCPPropertySchema(type: "string", description: "Canonical name of the place or entity"),
                    "facet": MCPPropertySchema(type: "string", description: "Facet to target (menu, offerings, reviews, photos, policy, vibe)"),
                    "patterns": MCPPropertySchema(type: "string", description: "Optional comma-separated override search phrases"),
                    "siteFilters": MCPPropertySchema(type: "string", description: "Optional comma-separated domain filters"),
                    "maxResults": MCPPropertySchema(type: "string", description: "Maximum results to return across all patterns (default 8)")
                ],
                required: ["placeName", "facet"]
            )
        )
    }
    
    // MARK: - Execution
    
    private func executeSearchWeb(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let query = request.arguments?["query"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing required 'query' parameter")], isError: true)
        }
        
        let siteFilters = parseListArgument(request.arguments?["siteFilters"])
        let maxResults = parseInt(request.arguments?["maxResults"], defaultValue: 5, minimum: 1, maximum: 12)
        let origin = request.arguments?["origin"] as? String ?? "discovery_bridge"
        let cacheKey = cacheKeyForSearch(query: query, siteFilters: siteFilters, maxResults: maxResults)
        
        if let cached = cachedSearchPayload(key: cacheKey) {
            do {
                var payload = cached
                payload["origin"] = origin
                let json = try encodeJSON(payload)
                return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
            } catch {
                // continue to live call
            }
        }
        
        do {
            let searchResult = try await bridgeSearch(
                query: composeQuery(query: query, siteFilters: siteFilters),
                siteFilters: siteFilters,
                maxResults: maxResults
            )
            
            let timestamp = isoFormatter.string(from: Date())
            let cachedPayload: [String: Any] = [
                "query": searchResult.query,
                "summary": searchResult.summary,
                "results": searchResult.results,
                "source": [
                    "engine": searchResult.engine,
                    "timestamp": timestamp
                ]
            ]
            
            storeSearchPayload(cachedPayload, key: cacheKey)
            
            var responsePayload = cachedPayload
            responsePayload["origin"] = origin
            
            let json = try encodeJSON(responsePayload)
            return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "search_web failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func executeFacetCandidates(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let placeName = request.arguments?["placeName"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing required 'placeName' parameter")], isError: true)
        }
        guard let facet = request.arguments?["facet"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing required 'facet' parameter")], isError: true)
        }
        
        let customPatterns = parseListArgument(request.arguments?["patterns"])
        let siteFilters = parseListArgument(request.arguments?["siteFilters"])
        let maxResults = parseInt(request.arguments?["maxResults"], defaultValue: 8, minimum: 1, maximum: 20)
        let patterns = customPatterns.isEmpty ? defaultPatterns(for: facet) : customPatterns
        guard !patterns.isEmpty else {
            return MCPCallToolResponse(
                content: [MCPContent(text: "No patterns available for facet '\(facet)'")],
                isError: true
            )
        }
        
        var aggregated: [[String: Any]] = []
        var usedURLs = Set<String>()
        var queriesRun: [String] = []
        var errors: [String] = []
        let cacheKey = cacheKeyForFacet(placeName: placeName, facet: facet, patterns: patterns, siteFilters: siteFilters, maxResults: maxResults)
        
        if let cached = cachedFacetPayload(key: cacheKey) {
            do {
                let json = try encodeJSON(cached)
                let isError = (cached["results"] as? [[String: Any]])?.isEmpty == true && !(cached["errors"] as? [String] ?? []).isEmpty
                return MCPCallToolResponse(content: [MCPContent(text: json)], isError: isError)
            } catch {
                // fall through
            }
        }
        
        do {
            for pattern in patterns {
                let candidateQuery = composeFacetQuery(placeName: placeName, pattern: pattern, facet: facet)
                queriesRun.append(candidateQuery)
                
                do {
                    let result = try await bridgeSearch(
                        query: composeQuery(query: candidateQuery, siteFilters: siteFilters),
                        siteFilters: siteFilters,
                        maxResults: maxResults
                    )
                    
                    for entry in result.results {
                        guard let url = entry["url"] as? String else { continue }
                        if usedURLs.insert(url).inserted && aggregated.count < maxResults {
                            var enriched = entry
                            enriched["pattern"] = pattern
                            enriched["originQuery"] = result.query
                            aggregated.append(enriched)
                        }
                    }
                } catch {
                    errors.append("\(pattern): \(error.localizedDescription)")
                }
                
                if aggregated.count >= maxResults {
                    break
                }
            }
        }
        
        let payload: [String: Any] = [
            "facet": facet,
            "placeName": placeName,
            "patterns": patterns,
            "queries": queriesRun,
            "results": aggregated,
            "errors": errors,
            "source": [
                "engine": "perplexity_bridge",
                "timestamp": isoFormatter.string(from: Date())
            ]
        ]
        
        do {
            storeFacetPayload(payload, key: cacheKey)
            let json = try encodeJSON(payload)
            let isError = aggregated.isEmpty && !errors.isEmpty
            return MCPCallToolResponse(content: [MCPContent(text: json)], isError: isError)
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to encode facet candidates: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    // MARK: - Helpers
    
    private func bridgeSearch(query: String, siteFilters: [String], maxResults: Int) async throws -> BridgeSearchResult {
        guard let searchServer else {
            throw NSError(domain: "WebSearchBridgeServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Underlying search server unavailable"])
        }
        
        let request = MCPCallToolRequest(
            name: "web_search",
            arguments: ["query": query]
        )
        
        let response = await searchServer.callTool(request)
        if response.isError == true {
            let message = response.content.first?.text ?? "Unknown search error"
            throw NSError(domain: "WebSearchBridgeServer", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
        
        let rawText = response.content.compactMap { $0.text }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            throw NSError(domain: "WebSearchBridgeServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Empty search response"])
        }
        
        let parsed = parseSearchResponse(rawText, requestedQuery: query, maxResults: maxResults)
        return parsed
    }
    
    private func parseSearchResponse(_ text: String, requestedQuery: String, maxResults: Int) -> BridgeSearchResult {
        var summaryLines: [String] = []
        var results: [[String: Any]] = []
        var collectingSources = false
        var sourceEngine = "perplexity"
        var rank = 1
        
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("sources:") {
                collectingSources = true
                continue
            }
            
            if collectingSources {
                guard !trimmed.isEmpty else { continue }
                if let url = extractURL(from: trimmed) {
                    var title = extractTitle(from: trimmed)
                    if title.isEmpty {
                        title = url
                    }
                    results.append([
                        "title": title,
                        "url": url,
                        "rank": rank,
                        "snippet": "",
                        "sourceEngine": sourceEngine
                    ])
                    rank += 1
                    if results.count >= maxResults {
                        break
                    }
                }
            } else {
                if !trimmed.isEmpty {
                    summaryLines.append(trimmed)
                }
            }
        }
        
        if results.isEmpty {
            // Attempt to heuristically extract URLs from summary when no explicit sources
            let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = urlDetector?.matches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) ?? []
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                let url = String(text[range])
                if results.count >= maxResults {
                    break
                }
                results.append([
                    "title": url,
                    "url": url,
                    "rank": rank,
                    "snippet": "",
                    "sourceEngine": sourceEngine
                ])
                rank += 1
            }
        }
        
        let summary = summaryLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return BridgeSearchResult(query: requestedQuery, summary: summary, engine: sourceEngine, results: results)
    }
    
    private func extractURL(from line: String) -> String? {
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(location: 0, length: (line as NSString).length)
            let matches = detector.matches(in: line, options: [], range: range)
            return matches.first.flatMap { match in
                guard let range = Range(match.range, in: line) else { return nil }
                return String(line[range])
            }
        }
        return nil
    }
    
    private func extractTitle(from line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2, parts[0] == "-" {
            return String(parts[1])
        }
        return line.replacingOccurrences(of: "- ", with: "").trimmingCharacters(in: .whitespaces)
    }
    
    private func composeQuery(query: String, siteFilters: [String]) -> String {
        guard !siteFilters.isEmpty else { return query }
        let filters = siteFilters.map { "site:\($0)" }.joined(separator: " ")
        return "\(query) \(filters)"
    }
    
    private func composeFacetQuery(placeName: String, pattern: String, facet: String) -> String {
        if pattern.localizedCaseInsensitiveContains(placeName) {
            return pattern
        }
        return "\(placeName) \(pattern) \(facet)"
    }
    
    private func parseListArgument(_ value: Any?) -> [String] {
        if let array = value as? [String] {
            return array.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let string = value as? String {
            return string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }
    
    private func parseInt(_ value: Any?, defaultValue: Int, minimum: Int, maximum: Int) -> Int {
        if let string = value as? String, let intValue = Int(string) {
            return min(max(intValue, minimum), maximum)
        }
        if let number = value as? NSNumber {
            return min(max(number.intValue, minimum), maximum)
        }
        return defaultValue
    }

    private func cacheKeyForSearch(query: String, siteFilters: [String], maxResults: Int) -> String {
        let filters = siteFilters.sorted().joined(separator: "|")
        return "search|\(query)|\(filters)|\(maxResults)"
    }
    
    private func cacheKeyForFacet(placeName: String, facet: String, patterns: [String], siteFilters: [String], maxResults: Int) -> String {
        let patternKey = patterns.joined(separator: "|")
        let filters = siteFilters.sorted().joined(separator: "|")
        return "facet|\(placeName)|\(facet)|\(patternKey)|\(filters)|\(maxResults)"
    }
    
    private func cachedSearchPayload(key: String) -> [String: Any]? {
        var entry: CacheEntry?
        cacheQueue.sync {
            entry = searchCache[key]
        }
        guard let entry else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > searchTTL {
            cacheQueue.async(flags: .barrier) {
                self.searchCache.removeValue(forKey: key)
            }
            return nil
        }
        return entry.payload
    }
    
    private func storeSearchPayload(_ payload: [String: Any], key: String) {
        let entry = CacheEntry(timestamp: Date(), payload: payload)
        cacheQueue.async(flags: .barrier) {
            self.searchCache[key] = entry
            self.searchCache = self.pruneCache(self.searchCache, ttl: self.searchTTL, limit: 50)
        }
    }
    
    private func cachedFacetPayload(key: String) -> [String: Any]? {
        var entry: CacheEntry?
        cacheQueue.sync {
            entry = facetCache[key]
        }
        guard let entry else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > facetTTL {
            cacheQueue.async(flags: .barrier) {
                self.facetCache.removeValue(forKey: key)
            }
            return nil
        }
        return entry.payload
    }
    
    private func storeFacetPayload(_ payload: [String: Any], key: String) {
        let entry = CacheEntry(timestamp: Date(), payload: payload)
        cacheQueue.async(flags: .barrier) {
            self.facetCache[key] = entry
            self.facetCache = self.pruneCache(self.facetCache, ttl: self.facetTTL, limit: 80)
        }
    }
    
    private func pruneCache(_ cache: [String: CacheEntry], ttl: TimeInterval, limit: Int) -> [String: CacheEntry] {
        let now = Date()
        var filtered = cache.filter { now.timeIntervalSince($0.value.timestamp) <= ttl }
        if filtered.count > limit {
            let sortedKeys = filtered.sorted { $0.value.timestamp > $1.value.timestamp }.map { $0.key }
            let keysToKeep = Set(sortedKeys.prefix(limit))
            filtered = filtered.filter { keysToKeep.contains($0.key) }
        }
        return filtered
    }

    private func encodeJSON(_ dictionary: [String: Any]) throws -> String {
        let sanitized = JSONSanitizer.sanitizeDictionary(dictionary)
        let data = try JSONSerialization.data(withJSONObject: sanitized, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "WebSearchBridgeServer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to encode JSON as UTF-8"])
        }
        return text
    }
    
    private func defaultPatterns(for facet: String) -> [String] {
        switch facet.lowercased() {
        case "menu", "food", "drink":
            return ["menu", "food menu", "drink menu", "menu pdf", "order online"]
        case "offerings", "catalog", "retail":
            return ["product catalog", "shop", "collection", "what they sell", "brands carried"]
        case "reviews":
            return ["reviews", "customer reviews", "google reviews", "yelp reviews"]
        case "photos", "vibe":
            return ["photo gallery", "instagram photos", "inside photos", "interior pictures"]
        case "policy", "policies":
            return ["return policy", "cancellation policy", "dress code", "age policy"]
        default:
            return ["overview", "details", facet]
        }
    }
}

