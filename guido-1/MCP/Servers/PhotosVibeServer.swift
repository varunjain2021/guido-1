import Foundation

public final class PhotosVibeServer {
    private let serverInfo = MCPServerInfo(name: "Guido Photos & Vibe Server", version: "1.0.0")
    private let session: URLSession
    private let isoFormatter: ISO8601DateFormatter
    private let googleApiKey: String?
    private let openAIApiKey: String?
    private let cacheQueue = DispatchQueue(label: "PhotosVibeServer.cache", attributes: .concurrent)
    private var photoCache: [String: CacheEntry] = [:]
    private var vibeCache: [String: CacheEntry] = [:]
    private let photoTTL: TimeInterval = 60 * 15
    private let vibeTTL: TimeInterval = 60 * 20
    
    private struct CacheEntry {
        let timestamp: Date
        let payload: [String: Any]
    }
    
    init(session: URLSession = .shared) {
        self.session = session
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
        self.googleApiKey = PhotosVibeServer.loadConfigValue(for: "Google_API_Key")
        self.openAIApiKey = PhotosVibeServer.loadConfigValue(for: "OpenAI_API_Key")
    }
    
    public func getCapabilities() -> MCPCapabilities {
        MCPCapabilities(tools: MCPToolsCapability(listChanged: true), resources: nil, prompts: nil, sampling: nil)
    }
    
    public func getServerInfo() -> MCPServerInfo { serverInfo }
    
    public func listTools() -> [MCPTool] {
        [
            photosListTool(),
            vibeAnalyzeTool()
        ]
    }
    
    public func callTool(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        switch request.name {
        case "photos_list":
            return await executePhotosList(request)
        case "vibe_analyze":
            return await executeVibeAnalyze(request)
        default:
            return MCPCallToolResponse(
                content: [MCPContent(text: "Tool '\(request.name)' not found")],
                isError: true
            )
        }
    }
    
    // MARK: - Tool Definitions
    
    private func photosListTool() -> MCPTool {
        MCPTool(
            name: "photos_list",
            description: "Fetch Google Place photos (metadata + signed URLs) for downstream vibe analysis",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "placeId": MCPPropertySchema(type: "string", description: "Google Places placeId (e.g. places/XYZ)"),
                    "maxCount": MCPPropertySchema(type: "string", description: "Maximum photos to return (default 6, max 10)"),
                    "maxWidth": MCPPropertySchema(type: "string", description: "Max width in pixels for signed URLs (default 800)")
                ],
                required: ["placeId"]
            )
        )
    }
    
    private func vibeAnalyzeTool() -> MCPTool {
        MCPTool(
            name: "vibe_analyze",
            description: "Analyze image URLs to extract vibe facets (ambiance, seating, crowd, accessibility, cleanliness, retail categories)",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "photoUrls": MCPPropertySchema(type: "string", description: "Comma-separated list of image URLs (prefer output of photos_list)"),
                    "facets": MCPPropertySchema(type: "string", description: "Optional comma-separated facets to focus on"),
                    "placeName": MCPPropertySchema(type: "string", description: "Optional place name context for the analysis")
                ],
                required: ["photoUrls"]
            )
        )
    }
    
    // MARK: - Execution
    
    private func executePhotosList(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let placeId = request.arguments?["placeId"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing required 'placeId' parameter")], isError: true)
        }
        let maxCount = parseInt(request.arguments?["maxCount"], defaultValue: 6, min: 1, max: 10)
        let maxWidth = parseInt(request.arguments?["maxWidth"], defaultValue: 800, min: 200, max: 1600)
        let cacheKey = "\(placeId)|\(maxCount)|\(maxWidth)"
        
        if let cached = cachedPhotoPayload(key: cacheKey) {
            do {
                let json = try encodeJSON(cached)
                return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
            } catch {
                // fall through to refetch
            }
        }
        
        do {
            let photos = try await fetchPhotos(placeId: placeId, maxCount: maxCount, maxWidth: maxWidth)
            print("📸 [PhotosVibeServer] photos_list for \(placeId): fetched \(photos.count) photos (max \(maxCount))")
            let payload: [String: Any] = [
                "placeId": placeId,
                "fetchedAt": isoFormatter.string(from: Date()),
                "photos": photos
            ]
            storePhotoPayload(payload, key: cacheKey)
            let json = try encodeJSON(payload)
            return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
        } catch {
            print("❌ [PhotosVibeServer] photos_list error for \(placeId): \(error.localizedDescription)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "photos_list failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func executeVibeAnalyze(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let rawUrls = request.arguments?["photoUrls"] else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing required 'photoUrls' parameter")], isError: true)
        }
        
        guard let openAIApiKey, !openAIApiKey.isEmpty else {
            return MCPCallToolResponse(
                content: [MCPContent(text: "OpenAI API key missing; cannot perform vibe analysis")],
                isError: true
            )
        }
        
        let photoUrls = parseListArgument(rawUrls)
        guard !photoUrls.isEmpty else {
            return MCPCallToolResponse(
                content: [MCPContent(text: "photoUrls parameter must include at least one URL")],
                isError: true
            )
        }
        
        let facets = parseListArgument(request.arguments?["facets"])
        let placeName = request.arguments?["placeName"] as? String ?? ""
        let vibeCacheKey = vibeCacheKeyFor(photoUrls: photoUrls, facets: facets, placeName: placeName)
        
        if let cached = cachedVibePayload(key: vibeCacheKey) {
            do {
                var payload = cached
                payload["fromCache"] = true
                let json = try encodeJSON(payload)
                return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
            } catch {
                // ignore and recompute
            }
        }
        
        do {
            let analysis = try await analyzeImagesWithOpenAI(
                apiKey: openAIApiKey,
                photoUrls: photoUrls,
                facets: facets,
                placeName: placeName
            )
            
            var payload = analysis
            payload["analyzedAt"] = isoFormatter.string(from: Date())
            payload["imageCount"] = photoUrls.count
            payload["source"] = "openai_gpt4o_vision"
            
            storeVibePayload(payload, key: vibeCacheKey)
            
            let json = try encodeJSON(payload)
            return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "vibe_analyze failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    // MARK: - Google Photos
    
    private func fetchPhotos(placeId: String, maxCount: Int, maxWidth: Int) async throws -> [[String: Any]] {
        guard let apiKey = googleApiKey, !apiKey.isEmpty else {
            throw NSError(domain: "PhotosVibeServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Google API key missing from Config.plist"])
        }
        
        var components = URLComponents(string: "https://places.googleapis.com/v1/\(placeId)")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "photos,displayName,googleMapsUri")
        ]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("photos,displayName,googleMapsUri", forHTTPHeaderField: "X-Goog-FieldMask")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "PhotosVibeServer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "PhotosVibeServer", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Google Places HTTP \(httpResponse.statusCode): \(body)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let photosRaw = json["photos"] as? [[String: Any]] else {
            return []
        }
        
        var output: [[String: Any]] = []
        for photo in photosRaw.prefix(maxCount) {
            guard let name = photo["name"] as? String else { continue }
            var entry: [String: Any] = [:]
            entry["photoId"] = name
            entry["widthPx"] = photo["widthPx"] ?? NSNull()
            entry["heightPx"] = photo["heightPx"] ?? NSNull()
            if let author = photo["authorAttributions"] as? [[String: Any]], let first = author.first {
                entry["author"] = [
                    "name": first["displayName"] as? String ?? "",
                    "uri": first["uri"] as? String ?? ""
                ]
            }
            entry["htmlAttributions"] = photo["htmlAttributions"] ?? []
            entry["createTime"] = photo["createTime"] as? String ?? ""
            entry["mediaUrl"] = buildPhotoMediaURL(photoName: name, apiKey: apiKey, maxWidth: maxWidth)?.absoluteString ?? ""
            output.append(entry)
        }
        
        return output
    }
    
    private func buildPhotoMediaURL(photoName: String, apiKey: String, maxWidth: Int) -> URL? {
        var components = URLComponents(string: "https://places.googleapis.com/v1/\(photoName)/media")
        components?.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: "\(maxWidth)"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        return components?.url
    }
    
    // MARK: - OpenAI Vision
    
    private func analyzeImagesWithOpenAI(apiKey: String, photoUrls: [String], facets: [String], placeName: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NSError(domain: "PhotosVibeServer", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15.0
        
        let systemContent: [[String: Any]] = [
            ["type": "text", "text": """
            You are VibeScope, an expert at understanding venue ambiance, seating, crowd density, cleanliness, accessibility, and retail merchandising from images.
            Output JSON only. Do not include prose outside of the JSON. Be honest about uncertainty.
            """]
        ]
        
        var userContent: [[String: Any]] = []
        let focusFacets = facets.isEmpty ? "ambiance, seating, lighting, crowd density, cleanliness, accessibility cues, signage, merchandise or menu boards, work-friendly signals (outlets, laptops)" : facets.joined(separator: ", ")
        let introText = placeName.isEmpty
            ? "Analyze these images. Focus on \(focusFacets). Reference images by index (Image 1, Image 2, ...)."
            : "Analyze these images from \(placeName). Focus on \(focusFacets). Reference images by index (Image 1, Image 2, ...)."
        userContent.append(["type": "text", "text": introText])
        
        for (index, url) in photoUrls.enumerated() {
            userContent.append([
                "type": "image_url",
                "image_url": [
                    "url": url,
                    "detail": "low"
                ]
            ])
            userContent.append([
                "type": "text",
                "text": "Image \(index + 1): \(url)"
            ])
        }
        
        let responseFormat: [String: Any] = [
            "type": "json_schema",
            "json_schema": [
                "name": "VibeInsights",
                "schema": [
                    "type": "object",
                    "properties": [
                        "facets": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "facet": ["type": "string"],
                                    "summary": ["type": "string"],
                                    "confidence": ["type": "number"],
                                    "evidenceImages": [
                                        "type": "array",
                                        "items": ["type": "string"]
                                    ],
                                    "notes": [
                                        "type": "array",
                                        "items": ["type": "string"]
                                    ]
                                ],
                                "required": ["facet", "summary", "confidence"]
                            ]
                        ],
                        "overallMood": ["type": "string"],
                        "workFriendliness": ["type": "string"],
                        "accessibilitySummary": ["type": "string"],
                        "notableDetails": [
                            "type": "array",
                            "items": ["type": "string"]
                        ]
                    ],
                    "required": ["facets", "overallMood"]
                ]
            ]
        ]
        
        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "temperature": 0.2,
            "response_format": responseFormat,
            "messages": [
                [
                    "role": "system",
                    "content": systemContent
                ],
                [
                    "role": "user",
                    "content": userContent
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "PhotosVibeServer", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI HTTP response"])
        }
        guard httpResponse.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "PhotosVibeServer", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI HTTP \(httpResponse.statusCode): \(bodyText)"])
        }
        
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw NSError(domain: "PhotosVibeServer", code: 12, userInfo: [NSLocalizedDescriptionKey: "Unexpected OpenAI response format"])
        }
        
        var candidateStrings: [String] = []
        if let contentArray = message["content"] as? [[String: Any]] {
            for content in contentArray {
                if let text = content["text"] as? String {
                    candidateStrings.append(text)
                } else if let text = (content["output_text"] as? String) {
                    candidateStrings.append(text)
                }
            }
        } else if let text = message["content"] as? String {
            candidateStrings.append(text)
        }
        
        for text in candidateStrings {
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        }
        
        throw NSError(domain: "PhotosVibeServer", code: 13, userInfo: [NSLocalizedDescriptionKey: "OpenAI did not return structured JSON"])
    }
    
    // MARK: - Utilities
    
    private func parseInt(_ value: Any?, defaultValue: Int, min: Int, max: Int) -> Int {
        if let string = value as? String, let int = Int(string) {
            return Swift.max(min, Swift.min(max, int))
        }
        if let number = value as? NSNumber {
            return Swift.max(min, Swift.min(max, number.intValue))
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
    
    private func encodeJSON(_ dictionary: [String: Any]) throws -> String {
        let sanitized = JSONSanitizer.sanitizeDictionary(dictionary)
        let data = try JSONSerialization.data(withJSONObject: sanitized, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PhotosVibeServer", code: 9, userInfo: [NSLocalizedDescriptionKey: "Unable to encode JSON as UTF-8"])
        }
        return text
    }
    
    private static func loadConfigValue(for key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            print("⚠️ [PhotosVibeServer] Unable to load Config.plist")
            return nil
        }
        let value = dict[key] as? String
        if (value ?? "").isEmpty {
            print("⚠️ [PhotosVibeServer] Config value for \(key) missing or empty")
        }
        return value
    }
    
    // MARK: - Caching Helpers
    
    private func cachedPhotoPayload(key: String) -> [String: Any]? {
        var entry: CacheEntry?
        cacheQueue.sync {
            entry = photoCache[key]
        }
        guard let entry else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > photoTTL {
            cacheQueue.async(flags: .barrier) {
                self.photoCache.removeValue(forKey: key)
            }
            return nil
        }
        return entry.payload
    }
    
    private func storePhotoPayload(_ payload: [String: Any], key: String) {
        let entry = CacheEntry(timestamp: Date(), payload: payload)
        cacheQueue.async(flags: .barrier) {
            self.photoCache[key] = entry
            self.photoCache = self.pruneCacheDictionary(self.photoCache, ttl: self.photoTTL, limit: 40)
        }
    }
    
    private func cachedVibePayload(key: String) -> [String: Any]? {
        var entry: CacheEntry?
        cacheQueue.sync {
            entry = vibeCache[key]
        }
        guard let entry else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > vibeTTL {
            cacheQueue.async(flags: .barrier) {
                self.vibeCache.removeValue(forKey: key)
            }
            return nil
        }
        return entry.payload
    }
    
    private func storeVibePayload(_ payload: [String: Any], key: String) {
        let entry = CacheEntry(timestamp: Date(), payload: payload)
        cacheQueue.async(flags: .barrier) {
            self.vibeCache[key] = entry
            self.vibeCache = self.pruneCacheDictionary(self.vibeCache, ttl: self.vibeTTL, limit: 40)
        }
    }
    
    private func pruneCacheDictionary(_ cache: [String: CacheEntry], ttl: TimeInterval, limit: Int) -> [String: CacheEntry] {
        let now = Date()
        var filtered = cache.filter { now.timeIntervalSince($0.value.timestamp) <= ttl }
        if filtered.count > limit {
            let sortedKeys = filtered.sorted { $0.value.timestamp > $1.value.timestamp }.map { $0.key }
            let keysToKeep = Set(sortedKeys.prefix(limit))
            filtered = filtered.filter { keysToKeep.contains($0.key) }
        }
        return filtered
    }
    
    private func vibeCacheKeyFor(photoUrls: [String], facets: [String], placeName: String) -> String {
        let normalized = photoUrls.sorted().joined(separator: "|")
        let facetsKey = facets.sorted().joined(separator: "|")
        return "\(normalized)|\(facetsKey)|\(placeName)"
    }
}

