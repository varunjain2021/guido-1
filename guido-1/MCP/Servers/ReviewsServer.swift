import Foundation

public final class ReviewsServer {
    private weak var openAIChatService: OpenAIChatService?
    private let serverInfo = MCPServerInfo(name: "Guido Reviews Server", version: "1.0.0")
    private let session: URLSession
    private let isoFormatter: ISO8601DateFormatter
    private let googleApiKey: String?
    private let cacheQueue = DispatchQueue(label: "ReviewsServer.cache", attributes: .concurrent)
    private var reviewsCache: [String: CacheEntry] = [:]
    private let reviewsTTL: TimeInterval = 60 * 15
    
    private struct CacheEntry {
        let timestamp: Date
        let payload: [String: Any]
    }
    
    init(session: URLSession = .shared) {
        self.session = session
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
        self.googleApiKey = ReviewsServer.loadConfigValue(for: "Google_API_Key")
    }
    
    func setOpenAIChatService(_ service: OpenAIChatService) {
        self.openAIChatService = service
    }
    
    public func getCapabilities() -> MCPCapabilities {
        MCPCapabilities(tools: MCPToolsCapability(listChanged: true), resources: nil, prompts: nil, sampling: nil)
    }
    
    public func getServerInfo() -> MCPServerInfo { serverInfo }
    
    public func listTools() -> [MCPTool] {
        [
            reviewsListTool(),
            reviewsAspectsTool()
        ]
    }
    
    public func callTool(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        switch request.name {
        case "reviews_list":
            return await executeReviewsList(request)
        case "reviews_aspects_summarize":
            return await executeReviewsAspects(request)
        default:
            return MCPCallToolResponse(
                content: [MCPContent(text: "Tool '\(request.name)' not found")],
                isError: true
            )
        }
    }
    
    // MARK: - Tool Definitions
    
    private func reviewsListTool() -> MCPTool {
        MCPTool(
            name: "reviews_list",
            description: "Fetch recent Google reviews for a given placeId with lightweight filtering",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "placeId": MCPPropertySchema(type: "string", description: "Google Places placeId (e.g. places/XYZ)"),
                    "maxCount": MCPPropertySchema(type: "string", description: "Maximum number of reviews to return (default 6)"),
                    "minRating": MCPPropertySchema(type: "string", description: "Optional minimum rating filter (1-5)"),
                    "language": MCPPropertySchema(type: "string", description: "Optional language code (e.g. en)")
                ],
                required: ["placeId"]
            )
        )
    }
    
    private func reviewsAspectsTool() -> MCPTool {
        MCPTool(
            name: "reviews_aspects_summarize",
            description: "Summarize reviews by aspect with representative quotes and citations",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "reviews": MCPPropertySchema(type: "string", description: "JSON array of reviews as returned from reviews_list"),
                    "topics": MCPPropertySchema(type: "string", description: "Optional comma-separated list of aspects to focus on"),
                    "maxQuotesPerAspect": MCPPropertySchema(type: "string", description: "Maximum quotes per aspect (default 2)")
                ],
                required: ["reviews"]
            )
        )
    }
    
    // MARK: - Execution
    
    private func executeReviewsList(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let placeId = request.arguments?["placeId"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing required 'placeId' parameter")], isError: true)
        }
        let maxCount = parseInt(request.arguments?["maxCount"], defaultValue: 6, min: 1, max: 10)
        let minRating = parseDouble(request.arguments?["minRating"], defaultValue: nil)
        let language = request.arguments?["language"] as? String
        let cacheKey = cacheKeyForReviews(placeId: placeId, maxCount: maxCount, minRating: minRating, language: language)
        
        if let cached = cachedPayload(forKey: cacheKey, ttl: reviewsTTL) {
            do {
                let json = try encodeJSON(cached)
                return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
            } catch {
                // If encoding cached payload fails, fall through to refetch
            }
        }
        
        do {
            let reviews = try await fetchGoogleReviews(
                placeId: placeId,
                maxCount: maxCount,
                minRating: minRating,
                language: language
            )
            
            let payload: [String: Any] = [
                "placeId": placeId,
                "fetchedAt": isoFormatter.string(from: Date()),
                "reviews": reviews
            ]
            
            storePayload(payload, forKey: cacheKey)
            
            let json = try encodeJSON(payload)
            return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "reviews_list failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func executeReviewsAspects(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let reviewsInput = request.arguments?["reviews"] else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing required 'reviews' parameter")], isError: true)
        }
        
        guard let openAIChatService else {
            return MCPCallToolResponse(
                content: [MCPContent(text: "OpenAIChatService unavailable for summarization")],
                isError: true
            )
        }
        
        let reviewsJSON: String
        if let text = reviewsInput as? String {
            reviewsJSON = text
        } else if let array = reviewsInput as? [Any],
                  let data = try? JSONSerialization.data(withJSONObject: array),
                  let text = String(data: data, encoding: .utf8) {
            reviewsJSON = text
        } else if let dict = reviewsInput as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let text = String(data: data, encoding: .utf8) {
            reviewsJSON = text
        } else {
            return MCPCallToolResponse(
                content: [MCPContent(text: "Unable to parse 'reviews' input; expected JSON string or array")],
                isError: true
            )
        }
        
        let topics = parseListArgument(request.arguments?["topics"])
        let maxQuotes = parseInt(request.arguments?["maxQuotesPerAspect"], defaultValue: 2, min: 1, max: 4)
        
        do {
            let prompt = buildAspectPrompt(reviewsJSON: reviewsJSON, topics: topics, maxQuotes: maxQuotes)
            let response = try await openAIChatService.generateStructuredData(prompt: prompt)
            let sanitized = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sanitized.isEmpty else {
                throw NSError(domain: "ReviewsServer", code: 12, userInfo: [NSLocalizedDescriptionKey: "Empty LLM response"])
            }
            
            // Validate JSON string
            if let data = sanitized.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var payload = jsonObject
                payload["generatedAt"] = isoFormatter.string(from: Date())
                payload["source"] = "openai_structured_v1"
                let output = try encodeJSON(payload)
                return MCPCallToolResponse(content: [MCPContent(text: output)], isError: false)
            } else {
                throw NSError(domain: "ReviewsServer", code: 13, userInfo: [NSLocalizedDescriptionKey: "LLM response is not valid JSON"])
            }
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "reviews_aspects_summarize failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    // MARK: - Google Reviews
    
    private func fetchGoogleReviews(
        placeId: String,
        maxCount: Int,
        minRating: Double?,
        language: String?
    ) async throws -> [[String: Any]] {
        guard let apiKey = googleApiKey, !apiKey.isEmpty else {
            throw NSError(domain: "ReviewsServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Google API key missing from Config.plist"])
        }
        
        var components = URLComponents(string: "https://places.googleapis.com/v1/\(placeId)")!
        let fields = "reviews,reviews.rating,reviews.text,reviews.authorAttribution.displayName,reviews.authorAttribution.uri,reviews.authorAttribution.photoUri,reviews.publishTime,reviews.relativePublishTimeDescription,reviews.languageCode,reviews.originalLanguageCode"
        components.queryItems = [
            URLQueryItem(name: "fields", value: fields)
        ]
        if let language {
            components.queryItems?.append(URLQueryItem(name: "languageCode", value: language))
        }
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fields, forHTTPHeaderField: "X-Goog-FieldMask")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ReviewsServer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ReviewsServer", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Google Places HTTP \(httpResponse.statusCode): \(body)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reviewsRaw = json["reviews"] as? [[String: Any]] else {
            return []
        }
        
        var filtered: [[String: Any]] = []
        for review in reviewsRaw {
            let rating = (review["rating"] as? NSNumber)?.doubleValue
            if let minRating, let rating, rating < minRating {
                continue
            }
            var normalized: [String: Any] = [:]
            normalized["reviewId"] = review["name"] as? String ?? ""
            normalized["rating"] = rating ?? NSNull()
            normalized["text"] = ((review["text"] as? [String: Any])?["text"] as? String) ?? ""
            normalized["publishTime"] = review["publishTime"] as? String ?? ""
            normalized["relativeTime"] = review["relativePublishTimeDescription"] as? String ?? ""
            normalized["languageCode"] = review["languageCode"] as? String ?? ""
            normalized["originalLanguageCode"] = review["originalLanguageCode"] as? String ?? ""
            if let author = review["authorAttribution"] as? [String: Any] {
                normalized["author"] = [
                    "name": author["displayName"] as? String ?? "",
                    "uri": author["uri"] as? String ?? "",
                    "photoUri": author["photoUri"] as? String ?? ""
                ]
            }
            filtered.append(normalized)
            if filtered.count >= maxCount {
                break
            }
        }
        
        return filtered
    }
    
    // MARK: - Prompt Builder
    
    private func buildAspectPrompt(reviewsJSON: String, topics: [String], maxQuotes: Int) -> String {
        let topicsText: String
        if topics.isEmpty {
            topicsText = "Work with whichever aspects emerge from the reviews (service, value, crowd, vibe, cleanliness, remote work, staff, price, accessibility, etc.)"
        } else {
            let topicsList = topics.joined(separator: ", ")
            topicsText = "Focus on these aspects: \(topicsList). You may add closely related aspects if reviewers mention them explicitly."
        }
        
        return """
        You are the Discovery Reviews Analyzer. You will receive Google reviews as JSON.
        Analyze them and produce JSON ONLY (no prose) with this schema:
        {
          "aspects": [
            {
              "aspect": "string",
              "sentiment": "positive|mixed|negative",
              "summary": "2 concise sentences grounded in reviews",
              "confidence": 0.0-1.0,
              "evidence": [
                {
                  "quote": "exact review sentence",
                  "author": "display name if available",
                  "rating": 1-5,
                  "published": "ISO timestamp if available",
                  "reviewId": "original reviewId"
                }
              ]
            }
          ],
          "overallSummary": "One short paragraph summarizing overall tone",
          "reviewCount": number,
          "topicsConsidered": ["list of aspect labels"],
          "dataFreshness": "human-friendly range like 'mostly within last 6 months'"
        }
        
        Rules:
        - Do not invent any content. Use only the supplied reviews.
        - When selecting evidence quotes, prefer the most recent and specific lines. At most \(maxQuotes) quotes per aspect.
        - Use neutral voice and cite contrasting opinions where appropriate.
        - Confidence should reflect volume and agreement of reviews (e.g. 0.9 for consistent patterns across many, 0.3 for sparse or conflicting data).
        
        \(topicsText)
        
        Reviews JSON:
        \(reviewsJSON)
        """
    }
    
    // MARK: - Utilities
    
    private func encodeJSON(_ dictionary: [String: Any]) throws -> String {
        let sanitized = JSONSanitizer.sanitizeDictionary(dictionary)
        let data = try JSONSerialization.data(withJSONObject: sanitized, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ReviewsServer", code: 9, userInfo: [NSLocalizedDescriptionKey: "Unable to encode JSON as UTF-8"])
        }
        return text
    }
    
    private func parseInt(_ value: Any?, defaultValue: Int, min: Int, max: Int) -> Int {
        if let string = value as? String, let int = Int(string) {
            return Swift.max(min, Swift.min(max, int))
        }
        if let number = value as? NSNumber {
            return Swift.max(min, Swift.min(max, number.intValue))
        }
        return defaultValue
    }
    
    private func parseDouble(_ value: Any?, defaultValue: Double?) -> Double? {
        if let string = value as? String, let dbl = Double(string) {
            return dbl
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return defaultValue
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
    
    private static func loadConfigValue(for key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            print("⚠️ [ReviewsServer] Unable to load Config.plist")
            return nil
        }
        let value = dict[key] as? String
        if (value ?? "").isEmpty {
            print("⚠️ [ReviewsServer] Config value for \(key) missing or empty")
        }
        return value
    }
    
    // MARK: - Caching
    
    private func cacheKeyForReviews(placeId: String, maxCount: Int, minRating: Double?, language: String?) -> String {
        let ratingComponent = minRating.map { String(format: "%.1f", $0) } ?? "any"
        let languageComponent = language ?? "default"
        return "\(placeId)|\(maxCount)|\(ratingComponent)|\(languageComponent)"
    }
    
    private func cachedPayload(forKey key: String, ttl: TimeInterval) -> [String: Any]? {
        var entry: CacheEntry?
        cacheQueue.sync {
            entry = reviewsCache[key]
        }
        guard let entry else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            cacheQueue.async(flags: .barrier) {
                self.reviewsCache.removeValue(forKey: key)
            }
            return nil
        }
        return entry.payload
    }
    
    private func storePayload(_ payload: [String: Any], forKey key: String) {
        let entry = CacheEntry(timestamp: Date(), payload: payload)
        cacheQueue.async(flags: .barrier) {
            self.reviewsCache[key] = entry
            if self.reviewsCache.count > 40 {
                self.pruneStaleEntries(ttl: self.reviewsTTL)
            }
        }
    }
    
    private func pruneStaleEntries(ttl: TimeInterval) {
        let now = Date()
        reviewsCache = reviewsCache.filter { now.timeIntervalSince($0.value.timestamp) <= ttl }
    }
}

