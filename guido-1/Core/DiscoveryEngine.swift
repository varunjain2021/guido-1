import Foundation

struct DiscoveryPlaceContext {
    let placeId: String
    let placeName: String
    let website: String?
}

struct DiscoveryCitation: Identifiable {
    let id = UUID()
    let title: String
    let url: URL?
    let source: String
    let timestamp: Date?
}

struct DiscoveryResult {
    let facet: String
    let answer: String
    let rationaleShort: String?
    let confidence: Double?
    let citations: [DiscoveryCitation]
    let followUps: [String]
    let rawJSON: String
}

final class DiscoveryEngine {
    private let toolCoordinator: MCPToolCoordinator
    private let openAI: OpenAIChatService
    private let isoFormatter = ISO8601DateFormatter()
    
    init(toolCoordinator: MCPToolCoordinator, openAI: OpenAIChatService) {
        self.toolCoordinator = toolCoordinator
        self.openAI = openAI
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    
    struct RouterDecision {
        let facet: String
        let needsSearch: Bool
        let confidence: Double
        let reason: String
    }
    
    private struct FacetData {
        let facet: String
        let payload: [String: Any]
        let citations: [DiscoveryCitation]
        let followUps: [String]
    }
    
    func answer(question: String, context: DiscoveryPlaceContext) async throws -> DiscoveryResult {
        let decision = try await determineFacet(for: question, context: context)
        let facetData = try await collectData(for: decision.facet, question: question, context: context, decision: decision)
        let orchestrated = try await orchestrateResponse(
            question: question,
            context: context,
            decision: decision,
            facetData: facetData.payload
        )
        let citations = orchestrated.citations.isEmpty ? facetData.citations : orchestrated.citations
        let finalCitations = mergeCitations(primary: orchestrated.citations, secondary: facetData.citations)
        
        return DiscoveryResult(
            facet: decision.facet,
            answer: orchestrated.answer,
            rationaleShort: orchestrated.rationaleShort,
            confidence: orchestrated.confidence ?? decision.confidence,
            citations: finalCitations,
            followUps: orchestrated.followUps.isEmpty ? facetData.followUps : orchestrated.followUps,
            rawJSON: orchestrated.rawJSON
        )
    }
    
    // MARK: - Facet Routing
    
    private func determineFacet(for question: String, context: DiscoveryPlaceContext) async throws -> RouterDecision {
        // Provide strong routing guidance to avoid excessive generic web search.
        let hasPlaceId = !context.placeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let availableFacets = ["reviews","vibe","menu","offerings","policy","search"]
        let availableFacetsStr = availableFacets.joined(separator: ", ")
        let prompt = """
        You are the Discovery Router. Choose the SINGLE best facet to answer the user's question.
        
        Facets (choose one):
        - reviews: Sentiment, praise, complaints from reviews.
        - vibe: Atmosphere, seating, crowd, laptop-friendliness, accessibility from photos.
        - menu: Food & drink specifics, dietary options, pricing (restaurant/cafe/bar).
        - offerings: Retail catalog, product categories, price level, services (retail).
        - policy: Returns/exchange/cancellation/dress code policies.
        - search: General info lookup ONLY when no structured facet applies or no place context exists.
        
        Strong preferences:
        - If a placeId is provided, prefer a structured facet (reviews/vibe/menu/offerings/policy) over "search".
        - Use "search" only if the question clearly asks to search the web broadly or no structured facet fits.
        - If the question mentions look/feel, seating, outlets, accessibility → prefer "vibe".
        - If it asks what people are saying, service quality, common complaints → prefer "reviews".
        - If it asks about menu, dietary options, prices → prefer "menu".
        - If it asks what they sell, product types, brands, styles → prefer "offerings".
        - If it asks about returns, cancellations, dress code, age limits → prefer "policy".
        
        Context:
        - availableFacets: [\(availableFacetsStr)]
        - hasPlaceId: \(hasPlaceId ? "true" : "false")
        - placeName: \(context.placeName.isEmpty ? "unknown" : context.placeName)
        - placeId: \(context.placeId)
        - question: \(question)
        
        Return JSON ONLY:
        {
          "facet": "reviews|vibe|menu|offerings|policy|search",
          "needsSearch": true/false,
          "confidence": 0.0-1.0,
          "reason": "concise justification referencing question keywords"
        }
        """
        
        let response = try await openAI.generateStructuredData(prompt: prompt)
        guard
            let data = response.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let facet = json["facet"] as? String,
            let confidence = (json["confidence"] as? NSNumber)?.doubleValue,
            let reason = json["reason"] as? String
        else {
            throw NSError(domain: "DiscoveryEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to parse facet decision JSON"])
        }
        
        let needsSearch = (json["needsSearch"] as? Bool) ?? false
        let decision = RouterDecision(facet: facet.lowercased(), needsSearch: needsSearch, confidence: confidence, reason: reason)
        print("🧭 [DiscoveryRouter] facet='\(decision.facet)', needsSearch=\(decision.needsSearch), conf=\(String(format: "%.2f", decision.confidence)), reason='\(decision.reason)'")
        return decision
    }
    
    // MARK: - Data Collection
    
    private func collectData(for facet: String, question: String, context: DiscoveryPlaceContext, decision: RouterDecision) async throws -> FacetData {
        switch facet {
        case "reviews":
            return try await collectReviews(question: question, context: context, decision: decision)
        case "vibe":
            return try await collectVibe(question: question, context: context, decision: decision)
        case "menu":
            return try await collectMenu(context: context, decision: decision)
        case "offerings":
            return try await collectOfferings(context: context, decision: decision)
        case "policy":
            return try await collectPolicy(context: context, decision: decision)
        case "search":
            return try await collectSearch(question: question, context: context)
        default:
            throw NSError(domain: "DiscoveryEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported facet: \(facet)"])
        }
    }
    
    private func collectReviews(question: String, context: DiscoveryPlaceContext, decision: RouterDecision) async throws -> FacetData {
        let listResult = await toolCoordinator.executeTool(
            name: "reviews_list",
            parameters: [
                "placeId": context.placeId,
                "maxCount": "8"
            ]
        )
        guard listResult.success, let listData = parseResultDictionary(listResult.data) else {
            throw NSError(domain: "DiscoveryEngine", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch reviews"])
        }
        let reviews = listData["reviews"] ?? []
        let summarizeResult = await toolCoordinator.executeTool(
            name: "reviews_aspects_summarize",
            parameters: [
                "reviews": reviews,
                "topics": ""
            ]
        )
        guard summarizeResult.success, let summaryData = parseResultDictionary(summarizeResult.data) else {
            throw NSError(domain: "DiscoveryEngine", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to summarize reviews"])
        }
        
        var payload: [String: Any] = [
            "reviews": listData,
            "summary": summaryData
        ]
        if decision.needsSearch {
            print("🧭 [Discovery] Augmenting reviews with external search…")
            let searchParams: [String: Any] = [
                "query": "\(context.placeName) reviews",
                "siteFilters": "yelp.com,tripadvisor.com",
                "maxResults": "5",
                "origin": "discovery_reviews_augment"
            ]
            let searchResult = await toolCoordinator.executeTool(name: "search_web", parameters: searchParams)
            if searchResult.success, let searchData = parseResultDictionary(searchResult.data) {
                payload["externalReviewLinks"] = searchData["results"] ?? []
            }
        }
        let citations = extractCitations(from: summaryData["aspects"], defaultSource: "places")
        return FacetData(facet: "reviews", payload: payload, citations: citations, followUps: ["Want a sense of the vibe?", "Need the menu highlights?"])
    }
    
    private func collectVibe(question: String, context: DiscoveryPlaceContext, decision: RouterDecision) async throws -> FacetData {
        // 1) Try Google Places photos first
        let photosResult = await toolCoordinator.executeTool(
            name: "photos_list",
            parameters: [
                "placeId": context.placeId,
                "maxCount": "5",
                "maxWidth": "1024"
            ]
        )
        var photosData: [String: Any] = [:]
        var placesPhotos: [[String: Any]] = []
        if photosResult.success, let data = parseResultDictionary(photosResult.data) {
            photosData = data
            placesPhotos = (data["photos"] as? [[String: Any]]) ?? []
        }
        
        // 2) Optionally augment with external image URLs discovered from candidate pages
        var externalImageURLs: [String] = []
        if decision.needsSearch {
            print("🧭 [Discovery] Augmenting vibe with gallery candidates…")
            let candidatesResult = await toolCoordinator.executeTool(
                name: "search_candidates_for_facet",
                parameters: [
                    "placeName": context.placeName,
                    "facet": "photos",
                    "maxResults": "3"
                ]
            )
            if candidatesResult.success, let candidatesData = parseResultDictionary(candidatesResult.data),
               let links = candidatesData["results"] as? [[String: Any]] {
                for link in links.prefix(3) {
                    if let pageURL = link["url"] as? String {
                        let imagesResp = await toolCoordinator.executeTool(
                            name: "web_images_discover",
                            parameters: [
                                "url": pageURL,
                                "maxImages": "4"
                            ]
                        )
                        if imagesResp.success, let imgData = parseResultDictionary(imagesResp.data),
                           let imgs = imgData["images"] as? [String] {
                            externalImageURLs.append(contentsOf: imgs)
                        }
                    }
                }
            }
        }
        
        // 3) Build final URL list: Places + external (unique, capped)
        let placesURLs = placesPhotos.compactMap { ($0["mediaUrl"] as? String) ?? ($0["mediaURL"] as? String) }
        var combined = Array(Set(placesURLs + externalImageURLs))
        if combined.count > 8 { combined = Array(combined.prefix(8)) }
        guard !combined.isEmpty else {
            throw NSError(domain: "DiscoveryEngine", code: 12, userInfo: [NSLocalizedDescriptionKey: "No photos available for vibe analysis"])
        }
        
        let vibeResult = await toolCoordinator.executeTool(
            name: "vibe_analyze",
            parameters: [
                "photoUrls": combined.joined(separator: ","),
                "facets": "",
                "placeName": context.placeName
            ]
        )
        guard vibeResult.success, let vibeData = parseResultDictionary(vibeResult.data) else {
            throw NSError(domain: "DiscoveryEngine", code: 13, userInfo: [NSLocalizedDescriptionKey: "Failed to analyze vibe"])
        }
        
        var payload: [String: Any] = [
            "photos": photosData,
            "analysis": vibeData,
            "externalImages": externalImageURLs
        ]
        payload["question"] = question
        let citations = extractImageCitations(from: placesPhotos)
        return FacetData(facet: "vibe", payload: payload, citations: citations, followUps: ["Want to see what people say about it?", "Need menu details?"])
    }
    
    private func collectMenu(context: DiscoveryPlaceContext, decision: RouterDecision) async throws -> FacetData {
        guard let menuURL = try await resolveMenuURL(placeName: context.placeName, fallbackURL: context.website, facet: "menu") else {
            throw NSError(domain: "DiscoveryEngine", code: 14, userInfo: [NSLocalizedDescriptionKey: "Menu link not found"])
        }
        
        let readableResult = await toolCoordinator.executeTool(
            name: "web_readable_extract",
            parameters: [
                "url": menuURL.absoluteString
            ]
        )
        guard readableResult.success, let readableData = parseResultDictionary(readableResult.data),
              let content = readableData["content"] as? String, !content.isEmpty else {
            throw NSError(domain: "DiscoveryEngine", code: 15, userInfo: [NSLocalizedDescriptionKey: "Failed to extract menu text"])
        }
        
        let menuResult = await toolCoordinator.executeTool(
            name: "menu_parse",
            parameters: [
                "htmlText": content,
                "placeName": context.placeName
            ]
        )
        guard menuResult.success, let menuData = parseResultDictionary(menuResult.data) else {
            throw NSError(domain: "DiscoveryEngine", code: 16, userInfo: [NSLocalizedDescriptionKey: "Failed to parse menu"])
        }
        let payload: [String: Any] = [
            "sourceUrl": menuURL.absoluteString,
            "readable": readableData,
            "menu": menuData
        ]
        let citations = [DiscoveryCitation(title: "Menu", url: menuURL, source: "site", timestamp: nil)]
        return FacetData(facet: "menu", payload: payload, citations: citations, followUps: ["Need vibe or seating info?", "Want to hear what regulars say?"])
    }
    
    private func collectOfferings(context: DiscoveryPlaceContext, decision: RouterDecision) async throws -> FacetData {
        guard let catalogURL = try await resolveMenuURL(placeName: context.placeName, fallbackURL: context.website, facet: "offerings") else {
            throw NSError(domain: "DiscoveryEngine", code: 17, userInfo: [NSLocalizedDescriptionKey: "Offerings link not found"])
        }
        
        let readableResult = await toolCoordinator.executeTool(
            name: "web_readable_extract",
            parameters: [
                "url": catalogURL.absoluteString
            ]
        )
        guard readableResult.success, let readableData = parseResultDictionary(readableResult.data),
              let content = readableData["content"] as? String, !content.isEmpty else {
            throw NSError(domain: "DiscoveryEngine", code: 18, userInfo: [NSLocalizedDescriptionKey: "Failed to extract catalog text"])
        }
        
        let catalogResult = await toolCoordinator.executeTool(
            name: "catalog_classify",
            parameters: [
                "htmlText": content,
                "placeName": context.placeName
            ]
        )
        guard catalogResult.success, let catalogData = parseResultDictionary(catalogResult.data) else {
            throw NSError(domain: "DiscoveryEngine", code: 19, userInfo: [NSLocalizedDescriptionKey: "Failed to classify catalog"])
        }
        
        let payload: [String: Any] = [
            "sourceUrl": catalogURL.absoluteString,
            "readable": readableData,
            "catalog": catalogData
        ]
        let citations = [DiscoveryCitation(title: "Offerings", url: catalogURL, source: "site", timestamp: nil)]
        return FacetData(facet: "offerings", payload: payload, citations: citations, followUps: ["Interested in reviews?", "Need return policies?"])
    }
    
    private func collectPolicy(context: DiscoveryPlaceContext, decision: RouterDecision) async throws -> FacetData {
        guard let policyURL = try await resolveMenuURL(placeName: context.placeName, fallbackURL: context.website, facet: "policy") else {
            throw NSError(domain: "DiscoveryEngine", code: 21, userInfo: [NSLocalizedDescriptionKey: "Policy link not found"])
        }
        
        let readableResult = await toolCoordinator.executeTool(
            name: "web_readable_extract",
            parameters: [
                "url": policyURL.absoluteString
            ]
        )
        guard readableResult.success, let readableData = parseResultDictionary(readableResult.data) else {
            throw NSError(domain: "DiscoveryEngine", code: 22, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch policy text"])
        }
        let payload: [String: Any] = [
            "sourceUrl": policyURL.absoluteString,
            "readable": readableData
        ]
        let citations = [DiscoveryCitation(title: "Policy", url: policyURL, source: "site", timestamp: nil)]
        return FacetData(facet: "policy", payload: payload, citations: citations, followUps: ["Want to check reviews?", "Need product availability?"])
    }
    
    private func collectSearch(question: String, context: DiscoveryPlaceContext) async throws -> FacetData {
        let searchResult = await toolCoordinator.executeTool(
            name: "search_web",
            parameters: [
                "query": "\(context.placeName) \(question)"
            ]
        )
        guard searchResult.success, let searchData = parseResultDictionary(searchResult.data) else {
            throw NSError(domain: "DiscoveryEngine", code: 23, userInfo: [NSLocalizedDescriptionKey: "Web search failed"])
        }
        let citations = extractSearchCitations(from: searchData["results"])
        return FacetData(facet: "search", payload: searchData, citations: citations, followUps: ["Want reviews?", "Need the vibe?"])
    }
    
    private func resolveMenuURL(placeName: String, fallbackURL: String?, facet: String) async throws -> URL? {
        let searchResult = await toolCoordinator.executeTool(
            name: "search_candidates_for_facet",
            parameters: [
                "placeName": placeName,
                "facet": facet,
                "maxResults": "6"
            ]
        )
        if searchResult.success, let data = parseResultDictionary(searchResult.data),
           let links = data["results"] as? [[String: Any]] {
            for link in links {
                if let href = link["url"] as? String, let url = URL(string: href) {
                    return url
                }
            }
        }
        if let fallbackURL, let url = URL(string: fallbackURL) {
            return url
        }
        return nil
    }
    
    // MARK: - Orchestrator
    
    private struct OrchestratorResponse {
        let answer: String
        let rationaleShort: String?
        let confidence: Double?
        let citations: [DiscoveryCitation]
        let followUps: [String]
        let rawJSON: String
    }
    
    private func orchestrateResponse(
        question: String,
        context: DiscoveryPlaceContext,
        decision: RouterDecision,
        facetData: [String: Any]
    ) async throws -> OrchestratorResponse {
        let orchestratorPrompt = DiscoveryPromptProvider.loadPrompt()
        let payload: [String: Any] = [
            "question": question,
            "facet": decision.facet,
            "decision": [
                "needsSearch": decision.needsSearch,
                "confidence": decision.confidence,
                "reason": decision.reason
            ],
            "place": [
                "name": context.placeName,
                "id": context.placeId,
                "website": context.website ?? ""
            ],
            "data": facetData
        ]
        let payloadJSON = try encodeJSON(payload)
        let prompt = """
\(orchestratorPrompt)

DATA:
\(payloadJSON)
"""
        let response = try await openAI.generateStructuredData(prompt: prompt)
        guard let data = response.data(using: .utf8) else {
            throw NSError(domain: "DiscoveryEngine", code: 30, userInfo: [NSLocalizedDescriptionKey: "Empty orchestrator response"])
        }
        let rawJSON = String(data: data, encoding: .utf8) ?? response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answer = json["answer"] as? String else {
            throw NSError(domain: "DiscoveryEngine", code: 31, userInfo: [NSLocalizedDescriptionKey: "Invalid orchestrator JSON"])
        }
        let rationale = json["rationale_short"] as? String
        let confidence = (json["confidence"] as? NSNumber)?.doubleValue
        let followUps = json["follow_ups"] as? [String] ?? []
        let citations = extractCitations(from: json["citations"], defaultSource: "web")
        return OrchestratorResponse(
            answer: answer,
            rationaleShort: rationale,
            confidence: confidence,
            citations: citations,
            followUps: followUps,
            rawJSON: rawJSON
        )
    }
    
    // MARK: - Helpers
    
    private func parseResultDictionary(_ data: Any) -> [String: Any]? {
        if let dict = data as? [String: Any] {
            return dict
        }
        if let text = data as? String,
           let textData = text.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: textData) as? [String: Any] {
            return dict
        }
        return nil
    }
    
    private func encodeJSON(_ dictionary: [String: Any]) throws -> String {
        let sanitized = JSONSanitizer.sanitizeDictionary(dictionary)
        let data = try JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "DiscoveryEngine", code: 40, userInfo: [NSLocalizedDescriptionKey: "Unable to encode JSON as UTF-8"])
        }
        return text
    }
    
    private func extractCitations(from value: Any?, defaultSource: String) -> [DiscoveryCitation] {
        guard let array = value as? [[String: Any]] else { return [] }
        var citations: [DiscoveryCitation] = []
        for item in array {
            let title = item["title"] as? String ?? ""
            let urlString = item["url"] as? String
            let source = (item["source"] as? String) ?? defaultSource
            let timestamp = (item["timestamp"] as? String).flatMap { isoFormatter.date(from: $0) }
            let url = urlString.flatMap { URL(string: $0) }
            citations.append(DiscoveryCitation(title: title, url: url, source: source, timestamp: timestamp))
        }
        return citations
    }
    
    private func extractImageCitations(from photos: [[String: Any]]) -> [DiscoveryCitation] {
        photos.compactMap { photo in
            guard let urlString = photo["mediaUrl"] as? String ?? photo["mediaURL"] as? String,
                  let url = URL(string: urlString) else { return nil }
            let title = photo["photoId"] as? String ?? "Photo"
            return DiscoveryCitation(title: title, url: url, source: "places", timestamp: nil)
        }
    }
    
    private func extractSearchCitations(from value: Any?) -> [DiscoveryCitation] {
        guard let results = value as? [[String: Any]] else { return [] }
        return results.compactMap { result in
            guard let urlString = result["url"] as? String, let url = URL(string: urlString) else { return nil }
            let title = result["title"] as? String ?? url.host ?? url.absoluteString
            let source = result["sourceEngine"] as? String ?? "web"
            let timestamp = (result["timestamp"] as? String).flatMap { isoFormatter.date(from: $0) }
            return DiscoveryCitation(title: title, url: url, source: source, timestamp: timestamp)
        }
    }
    
    private func mergeCitations(primary: [DiscoveryCitation], secondary: [DiscoveryCitation]) -> [DiscoveryCitation] {
        var combined = primary
        let existingURLs = Set(primary.compactMap { $0.url })
        for citation in secondary {
            if let url = citation.url, existingURLs.contains(url) {
                continue
            }
            combined.append(citation)
        }
        return combined
    }
}

