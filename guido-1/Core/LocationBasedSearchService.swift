import Foundation
import CoreLocation

@MainActor
class LocationBasedSearchService: ObservableObject {
    private let apiKey: String
    private let locationManager: LocationManager
    
    @Published var isSearching = false
    @Published var lastSearchResults: LocationSearchResult?
    
    // Cache for recent searches to avoid redundant API calls
    private var searchCache: [String: LocationSearchResult] = [:]
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    init(apiKey: String, locationManager: LocationManager) {
        self.apiKey = apiKey
        self.locationManager = locationManager
    }
    
    // MARK: - Public Search Methods
    
    func findNearbyRestaurants(query: String = "", cuisine: String = "") async -> LocationSearchResult {
        let searchQuery = buildRestaurantQuery(query: query, cuisine: cuisine)
        return await performLocationSearch(searchQuery: searchQuery, type: .restaurants)
    }
    
    func findNearbyTransport(type: TransportType = .all) async -> LocationSearchResult {
        let searchQuery = buildTransportQuery(type: type)
        return await performLocationSearch(searchQuery: searchQuery, type: .transport)
    }
    
    func findNearbyLandmarks(query: String = "") async -> LocationSearchResult {
        let searchQuery = buildLandmarksQuery(query: query)
        return await performLocationSearch(searchQuery: searchQuery, type: .landmarks)
    }
    
    func findNearbyServices(serviceType: String, query: String = "") async -> LocationSearchResult {
        let searchQuery = buildServicesQuery(serviceType: serviceType, query: query)
        return await performLocationSearch(searchQuery: searchQuery, type: .services)
    }
    
    // MARK: - Core Search Implementation
    
    private func performLocationSearch(searchQuery: String, type: SearchType) async -> LocationSearchResult {
        // Build a cache key that includes an approximate geohash (~200m precision)
        let lat = locationManager.currentLocation?.coordinate.latitude ?? 0
        let lon = locationManager.currentLocation?.coordinate.longitude ?? 0
        let quantize: (Double) -> Double = { value in
            let step = 0.002 // ~200m
            return (value / step).rounded() * step
        }
        let latQ = quantize(lat)
        let lonQ = quantize(lon)
        let cacheKey = "\(searchQuery)_\(type.rawValue)_\(latQ)_\(lonQ)"
        if let cachedResult = getCachedResult(for: cacheKey) {
            print("📋 Using cached results for: \(searchQuery)")
            return cachedResult
        }
        
        isSearching = true
        
        do {
            // Get current location context
            let locationContext = await getCurrentLocationContext()
            
            // Build the complete search query with location context
            let fullQuery = buildFullSearchQuery(searchQuery: searchQuery, locationContext: locationContext)
            
            // Use OpenAI Responses API with web search
            let result = try await performWebSearch(query: fullQuery, type: type)
            
            // Cache the result
            cacheResult(result, for: cacheKey)
            
            lastSearchResults = result
            isSearching = false
            
            return result
            
        } catch {
            print("❌ Location search error: \(error)")
            isSearching = false
            
            return LocationSearchResult(
                query: searchQuery,
                type: type,
                results: [],
                locationContext: await getCurrentLocationContext(),
                summary: nil,
                error: error.localizedDescription
            )
        }
    }
    
    private func performWebSearch(query: String, type: SearchType) async throws -> LocationSearchResult {
        // Use OpenAI Responses API with web search tool via HTTP
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "input": query,
            "tools": [
                ["type": "web_search"]
            ],
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "LocationSearchError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "LocationSearchError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMessage)"])
        }
        
        // Parse the response
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LocationSearchError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
        }
        
        // Process the response and extract location results
        return try await processSearchResponse(jsonResponse, originalQuery: query, type: type)
    }
    
    private func processSearchResponse(_ response: [String: Any], originalQuery: String, type: SearchType) async throws -> LocationSearchResult {
        var places: [WebSearchPlace] = []
        var responseText = ""
        
        // Extract output from the Responses API response
        guard let output = response["output"] as? [[String: Any]] else {
            throw NSError(domain: "LocationSearchError", code: 3, userInfo: [NSLocalizedDescriptionKey: "No output in response"])
        }
        
        // Process each output item
        for outputItem in output {
            if let messageType = outputItem["type"] as? String, messageType == "message",
               let content = outputItem["content"] as? [[String: Any]] {
                
                for contentItem in content {
                    if let text = contentItem["text"] as? String {
                        responseText += text
                    }
                    
                    // Extract annotations for citations
                    if let annotations = contentItem["annotations"] as? [[String: Any]] {
                        for annotation in annotations {
                            if let title = annotation["title"] as? String,
                               let url = annotation["url"] as? String {
                                // Parse citation data into NearbyPlace objects
                                if let place = parseLocationFromCitation(title: title, url: url, type: type) {
                                    places.append(place)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // If no structured data found, parse from response text
        if places.isEmpty {
            places = parseLocationsFromText(responseText, type: type)
        }
        
        return LocationSearchResult(
            query: originalQuery,
            type: type,
            results: places,
            locationContext: await getCurrentLocationContext(),
            summary: responseText,
            error: nil
        )
    }
    
    // MARK: - Query Builders
    
    private func buildRestaurantQuery(query: String, cuisine: String) -> String {
        var searchTerms = ["restaurants", "dining", "food"]
        
        if !query.isEmpty {
            searchTerms.append(query)
        }
        
        if !cuisine.isEmpty {
            searchTerms.append(cuisine)
        }
        
        return searchTerms.joined(separator: " ")
    }
    
    private func buildTransportQuery(type: TransportType) -> String {
        switch type {
        case .all:
            return "public transportation subway bus train stations nearby"
        case .subway:
            return "subway metro stations nearby"
        case .bus:
            return "bus stops stations nearby"
        case .train:
            return "train stations nearby"
        case .taxi:
            return "taxi services ride sharing uber lyft nearby"
        case .parking:
            return "parking garages lots nearby"
        }
    }
    
    private func buildLandmarksQuery(query: String) -> String {
        var searchTerms = ["landmarks", "attractions", "points of interest", "tourist sites"]
        
        if !query.isEmpty {
            searchTerms.append(query)
        }
        
        return searchTerms.joined(separator: " ")
    }
    
    private func buildServicesQuery(serviceType: String, query: String) -> String {
        var searchTerms = [serviceType, "services"]
        
        if !query.isEmpty {
            searchTerms.append(query)
        }
        
        return searchTerms.joined(separator: " ")
    }
    
    private func buildFullSearchQuery(searchQuery: String, locationContext: WebSearchLocationContext) -> String {
        let locationString = formatLocationContext(locationContext)
        
        return """
        Find \(searchQuery) near \(locationString). 
        
        Please provide:
        1. Specific business names and addresses
        2. Brief descriptions or specialties
        3. Operating hours if available
        4. Contact information if available
        5. Distance or walking time from current location
        
        Focus on currently open and highly-rated options. Include both popular chains and local businesses.
        """
    }
    
    // MARK: - Location Context
    
    private func getCurrentLocationContext() async -> WebSearchLocationContext {
        guard let location = locationManager.currentLocation else {
            return WebSearchLocationContext(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                address: "Unknown Location",
                city: "Unknown",
                state: "Unknown",
                country: "Unknown"
            )
        }
        
        let address = locationManager.getCurrentLocationDescription()
        let components = address.components(separatedBy: ", ")
        
        return WebSearchLocationContext(
            coordinate: location.coordinate,
            address: address,
            city: components.count > 1 ? components[1] : "Unknown",
            state: components.count > 2 ? components[2] : "Unknown",
            country: components.last ?? "Unknown"
        )
    }
    
    private func formatLocationContext(_ context: WebSearchLocationContext) -> String {
        return "\(context.address), \(context.city), \(context.state)"
    }
    
    // MARK: - Response Parsing
    
    private func parseLocationFromCitation(title: String, url: String, type: SearchType) -> WebSearchPlace? {
        // Extract business information from citation title and URL
        guard let url = URL(string: url) else { return nil }
        
        return WebSearchPlace(
            name: title,
            address: "Address available via link",
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), // Would need geocoding
            category: type.displayName,
            rating: nil,
            distance: nil,
            url: url,
            description: "Details available via web search"
        )
    }
    
    private func parseLocationsFromText(_ text: String, type: SearchType) -> [WebSearchPlace] {
        // Basic text parsing - could be enhanced with more sophisticated NLP
        var places: [WebSearchPlace] = []
        
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            // Look for patterns like "1. Restaurant Name - Address"
            if line.contains("-") && (line.contains("1.") || line.contains("2.") || line.contains("3.")) {
                let components = line.components(separatedBy: " - ")
                if components.count >= 2 {
                    let nameComponent = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = nameComponent.replacingOccurrences(of: #"\d+\.\s*"#, with: "", options: .regularExpression)
                    let address = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    
                                    let place = WebSearchPlace(
                    name: name,
                    address: address,
                    coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    category: type.displayName,
                    rating: nil,
                    distance: nil,
                    description: line
                )
                    places.append(place)
                }
            }
        }
        
        return places
    }
    
    // MARK: - Caching
    
    private func getCachedResult(for key: String) -> LocationSearchResult? {
        guard let cached = searchCache[key],
              Date().timeIntervalSince(cached.timestamp) < cacheTimeout else {
            searchCache.removeValue(forKey: key)
            return nil
        }
        return cached
    }
    
    private func cacheResult(_ result: LocationSearchResult, for key: String) {
        var cachedResult = result
        cachedResult.timestamp = Date()
        searchCache[key] = cachedResult
        
        // Clean old cache entries
        let cutoff = Date().addingTimeInterval(-cacheTimeout)
        searchCache = searchCache.filter { $0.value.timestamp > cutoff }
    }
}

// MARK: - Supporting Types

struct WebSearchLocationContext {
    let coordinate: CLLocationCoordinate2D
    let address: String
    let city: String
    let state: String
    let country: String
}

struct LocationSearchResult {
    let query: String
    let type: SearchType
    let results: [WebSearchPlace]
    let locationContext: WebSearchLocationContext
    let summary: String?
    let error: String?
    var timestamp: Date = Date()
}

struct WebSearchPlace {
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let category: String
    let rating: Double?
    let distance: Double? // in meters
    let url: URL?
    let description: String?
    let phoneNumber: String?
    let isOpen: Bool?
    
    init(name: String, address: String, coordinate: CLLocationCoordinate2D, category: String, rating: Double? = nil, distance: Double? = nil, url: URL? = nil, description: String? = nil, phoneNumber: String? = nil, isOpen: Bool? = nil) {
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.category = category
        self.rating = rating
        self.distance = distance
        self.url = url
        self.description = description
        self.phoneNumber = phoneNumber
        self.isOpen = isOpen
    }
}

enum SearchType: String, CaseIterable {
    case restaurants = "restaurants"
    case transport = "transport"
    case landmarks = "landmarks"
    case services = "services"
    
    var displayName: String {
        switch self {
        case .restaurants: return "Restaurants"
        case .transport: return "Transportation"
        case .landmarks: return "Landmarks"
        case .services: return "Services"
        }
    }
}

enum TransportType: String, CaseIterable {
    case all = "all"
    case subway = "subway"
    case bus = "bus"
    case train = "train"
    case taxi = "taxi"
    case parking = "parking"
    
    var displayName: String {
        switch self {
        case .all: return "All Transportation"
        case .subway: return "Subway/Metro"
        case .bus: return "Bus"
        case .train: return "Train"
        case .taxi: return "Taxi/Rideshare"
        case .parking: return "Parking"
        }
    }
} 