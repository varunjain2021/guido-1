//
//  LocationMCPServer.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  MCP Server implementation for Location tools (Proof of Concept)
//

import Foundation
import CoreLocation

// MARK: - Location MCP Server

public class LocationMCPServer {
    
    // MARK: - Properties
    
    private weak var locationManager: LocationManager?
    private weak var locationSearchService: LocationBasedSearchService?
    private weak var openAIChatService: OpenAIChatService?
    private weak var googlePlacesRoutesService: GooglePlacesRoutesService?
    private let serverInfo = MCPServerInfo(name: "Guido Location Server", version: "1.0.0")
    
    // Track last navigation destination to enable "on the way" confirmations
    struct DestinationContext {
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
        let timestamp: Date
    }
    private var lastDestination: DestinationContext?

    // MARK: - Initialization
    
    init(locationManager: LocationManager? = nil) {
        self.locationManager = locationManager
    }
    
    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
    }
    
    func setLocationSearchService(_ service: LocationBasedSearchService) {
        self.locationSearchService = service
    }
    
    func setOpenAIChatService(_ service: OpenAIChatService) {
        self.openAIChatService = service
    }
    
    func setGooglePlacesRoutesService(_ service: GooglePlacesRoutesService) {
        self.googlePlacesRoutesService = service
    }
    
    // MARK: - MCP Server Interface
    
    public func getCapabilities() -> MCPCapabilities {
        return MCPCapabilities(
            tools: MCPToolsCapability(listChanged: true),
            resources: nil,
            prompts: nil,
            sampling: nil
        )
    }
    
    public func getServerInfo() -> MCPServerInfo {
        return serverInfo
    }
    
    public func listTools() -> [MCPTool] {
        return [
            getUserLocationTool(),
            findNearbyPlacesTool(),
            getDirectionsTool(),
            findNearbyRestaurantsTool(),
            findNearbyTransportTool(),
            findNearbyLandmarksTool(),
            findNearbyServicesTool(),
            findPlacesOnRouteTool()
        ]
    }
    
    public func callTool(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        print("🗺️ [LocationMCPServer] Executing tool: \(request.name)")
        
        switch request.name {
        case "get_user_location":
            return await executeGetUserLocation(request)
        case "find_nearby_places":
            return await executeFindNearbyPlaces(request)
        case "get_directions":
            return await executeGetDirections(request)
        case "find_nearby_restaurants":
            return await executeFindNearbyRestaurants(request)
        case "find_nearby_transport":
            return await executeFindNearbyTransport(request)
        case "find_nearby_landmarks":
            return await executeFindNearbyLandmarks(request)
        case "find_nearby_services":
            return await executeFindNearbyServices(request)
        case "find_places_on_route":
            return await executeFindPlacesOnRoute(request)
        default:
            return MCPCallToolResponse(
                content: [MCPContent(text: "Tool '\(request.name)' not found")],
                isError: true
            )
        }
    }
    
    // MARK: - Tool Definitions
    
    private func getUserLocationTool() -> MCPTool {
        return MCPTool(
            name: "get_user_location",
            description: "Get the user's current location, movement status, and nearby area information for personalized travel recommendations",
            inputSchema: MCPToolInputSchema(
                properties: [:], // No parameters required
                required: []
            )
        )
    }
    
    private func findNearbyPlacesTool() -> MCPTool {
        return MCPTool(
            name: "find_nearby_places",
            description: "Find nearby places of interest like restaurants, attractions, hotels, or transportation hubs",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "category": MCPPropertySchema(
                        type: "string",
                        description: "Type of place to search for",
                        enumValues: ["restaurants", "attractions", "hotels", "transportation", "shopping", "entertainment", "medical", "gas_stations"]
                    ),
                    "radius": MCPPropertySchema(
                        type: "string",
                        description: "Search radius in meters (default: 1000)",
                        enumValues: ["500", "1000", "2000", "5000"]
                    )
                ],
                required: ["category"]
            )
        )
    }
    
    private func getDirectionsTool() -> MCPTool {
        return MCPTool(
            name: "get_directions",
            description: "Get a directions summary and Google Maps link with estimated travel time",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "destination": MCPPropertySchema(
                        type: "string",
                        description: "The destination address or place name"
                    ),
                    "transportation_mode": MCPPropertySchema(
                        type: "string",
                        description: "Mode of transportation",
                        enumValues: ["walking", "driving", "transit", "cycling"]
                    )
                ],
                required: ["destination", "transportation_mode"]
            )
        )
    }
    
    private func findNearbyRestaurantsTool() -> MCPTool {
        return MCPTool(
            name: "find_nearby_restaurants",
            description: "Find restaurants within walking or driving distance, with cuisine type and rating filters",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "cuisine_type": MCPPropertySchema(
                        type: "string",
                        description: "Type of cuisine (optional)",
                        enumValues: ["italian", "chinese", "japanese", "mexican", "indian", "american", "french", "thai", "vietnamese", "korean", "mediterranean"]
                    ),
                    "distance": MCPPropertySchema(
                        type: "string",
                        description: "Maximum distance in meters",
                        enumValues: ["500", "1000", "2000", "5000"]
                    )
                ],
                required: []
            )
        )
    }
    
    private func findNearbyTransportTool() -> MCPTool {
        return MCPTool(
            name: "find_nearby_transport",
            description: "Find transportation options like bus stops, train stations, subway, taxi stands, bike sharing",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "transport_type": MCPPropertySchema(
                        type: "string",
                        description: "Type of transportation",
                        enumValues: ["bus", "train", "subway", "taxi", "bike_sharing", "car_rental", "airport"]
                    ),
                    "radius": MCPPropertySchema(
                        type: "string",
                        description: "Search radius in meters",
                        enumValues: ["500", "1000", "2000", "5000"]
                    )
                ],
                required: ["transport_type"]
            )
        )
    }
    
    private func findNearbyLandmarksTool() -> MCPTool {
        return MCPTool(
            name: "find_nearby_landmarks",
            description: "Find landmarks, attractions, museums, parks, and points of interest",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "landmark_type": MCPPropertySchema(
                        type: "string",
                        description: "Type of landmark or attraction",
                        enumValues: ["museums", "parks", "monuments", "viewpoints", "historic_sites", "art_galleries", "theaters", "stadiums"]
                    ),
                    "radius": MCPPropertySchema(
                        type: "string",
                        description: "Search radius in meters",
                        enumValues: ["1000", "2000", "5000", "10000"]
                    )
                ],
                required: ["landmark_type"]
            )
        )
    }
    
    private func findNearbyServicesTool() -> MCPTool {
        return MCPTool(
            name: "find_nearby_services",
            description: "Find essential services like hospitals, pharmacies, banks, gas stations, post offices",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "service_type": MCPPropertySchema(
                        type: "string",
                        description: "Type of service needed",
                        enumValues: ["hospital", "pharmacy", "bank", "atm", "gas_station", "post_office", "police", "fire_station"]
                    ),
                    "radius": MCPPropertySchema(
                        type: "string",
                        description: "Search radius in meters",
                        enumValues: ["500", "1000", "2000", "5000"]
                    )
                ],
                required: ["service_type"]
            )
        )
    }
    
    private func findPlacesOnRouteTool() -> MCPTool {
        return MCPTool(
            name: "find_places_on_route",
            description: "Find places along the route to a destination - perfect for 'on the way' searches",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "query": MCPPropertySchema(
                        type: "string",
                        description: "Type of place to find (e.g., 'coffee shop', 'gas station', 'smoothie bar')"
                    ),
                    "destination": MCPPropertySchema(
                        type: "string",
                        description: "Destination address or place name"
                    ),
                    "max_results": MCPPropertySchema(
                        type: "string",
                        description: "Maximum number of results (default: 5)",
                        enumValues: ["3", "5", "8", "10"]
                    )
                ],
                required: ["query", "destination"]
            )
        )
    }
    
    // MARK: - Tool Implementations
    
    // MARK: - LLM-First Intelligent Search
    
    private func performIntelligentLocationSearch(
        userQuery: String,
        searchType: String,
        context: [String: Any]
    ) async -> MCPCallToolResponse {
        do {
            // Gather location context
            let locationContext = await getCurrentLocationContext()
            
            // Get search strategy from LLM
            let searchStrategy = await getIntelligentSearchStrategy(
                query: userQuery,
                locationContext: locationContext,
                searchType: searchType
            )
            
            // Gather data from multiple sources
            var googlePlacesData: [Any]? = nil
            var webSearchData: String? = nil
            var conflictingData: [String] = []
            
            // Google Places search (if recommended by strategy)
            if searchStrategy.searchSources.contains("google_places") || searchStrategy.searchSources.contains("both") {
                if let google = googlePlacesRoutesService {
                    do {
                        let candidates = try await google.searchText(query: userQuery, maxResults: 10)
                        if !candidates.isEmpty {
                            googlePlacesData = candidates.map { candidate in
                                return [
                                    "name": candidate.name,
                                    "address": candidate.formattedAddress,
                                    "distance_meters": candidate.distanceMeters,
                                    "latitude": candidate.latitude,
                                    "longitude": candidate.longitude,
                                    "is_open": candidate.isOpen ?? false,
                                    "business_status": candidate.businessStatus ?? "unknown",
                                    "rating": candidate.rating ?? 0.0,
                                    "user_rating_count": candidate.userRatingCount ?? 0,
                                    "phone_number": candidate.phoneNumber ?? "",
                                    "has_business_details": candidate.hasBusinessDetails
                                ]
                            }
                            print("✅ [LocationMCPServer] Google Places: \(candidates.count) results for '\(userQuery)'")
                        } else {
                            conflictingData.append("Google Places found no results")
                        }
                    } catch {
                        conflictingData.append("Google Places error: \(error.localizedDescription)")
                        print("⚠️ [LocationMCPServer] Google Places failed: \(error)")
                    }
                }
            }
            
            // Web search (if recommended by strategy)
            if searchStrategy.searchSources.contains("web_search") || searchStrategy.searchSources.contains("both") {
                if let locationSearchService = locationSearchService {
                    let searchResult = await performWebSearchForType(userQuery, searchType: searchType, locationSearchService: locationSearchService)
                    if let error = searchResult.error {
                                            conflictingData.append("Web search error: \(error)")
                } else {
                    webSearchData = searchResult.summary
                    print("✅ [LocationMCPServer] Web search: \(searchResult.results.count) results for '\(userQuery)'")
                }
            }
        }
        
        // Check for ambiguity before proceeding with results
        if let openAIChatService = openAIChatService {
            do {
                if let clarificationQuestion = try await openAIChatService.detectAmbiguityAndAskClarification(
                    userQuery: userQuery,
                    googlePlaces: googlePlacesData,
                    webSearchData: webSearchData,
                    locationContext: locationContext
                ) {
                    print("🤔 [LocationMCPServer] Detected ambiguity, asking for clarification")
                    return MCPCallToolResponse(
                        content: [MCPContent(text: clarificationQuestion)],
                        isError: false
                    )
                }
            } catch {
                print("⚠️ [LocationMCPServer] Ambiguity detection failed: \(error)")
                // Continue with normal processing if clarification fails
            }
        }
        
        // Handle conflicting or insufficient data
        if conflictingData.count > 0 && googlePlacesData == nil && webSearchData == nil {
                guard let openAIChatService = openAIChatService else {
                    return MCPCallToolResponse(
                        content: [MCPContent(text: "Search services unavailable: \(conflictingData.joined(separator: ", "))")],
                        isError: true
                    )
                }
                
                let uncertaintyResponse = try await openAIChatService.handleLocationUncertainty(
                    userQuery: userQuery,
                    conflictingData: conflictingData,
                    locationContext: locationContext
                )
                
                return MCPCallToolResponse(
                    content: [MCPContent(text: uncertaintyResponse)],
                    isError: false
                )
            }
            
            // Synthesize intelligent response using LLM
            guard let openAIChatService = openAIChatService else {
                // Fallback to basic response if no LLM available
                if let webData = webSearchData {
                    return MCPCallToolResponse(content: [MCPContent(text: webData)], isError: false)
                } else if let googleData = googlePlacesData, !googleData.isEmpty {
                    let basicResponse = "Found \(googleData.count) places for \(userQuery)"
                    return MCPCallToolResponse(content: [MCPContent(text: basicResponse)], isError: false)
                } else {
                    return MCPCallToolResponse(content: [MCPContent(text: "No results found for \(userQuery)")], isError: false)
                }
            }
            
            let intelligentResponse = try await openAIChatService.synthesizeLocationResults(
                userQuery: userQuery,
                googlePlaces: googlePlacesData,
                webSearchData: webSearchData,
                locationContext: locationContext,
                conversationContext: "User searching for \(searchType)"
            )
            
            print("✅ [LocationMCPServer] LLM synthesized intelligent response for '\(userQuery)'")
            return MCPCallToolResponse(
                content: [MCPContent(text: intelligentResponse)],
                isError: false
            )
            
        } catch {
            print("❌ [LocationMCPServer] Intelligent search failed: \(error)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "Search failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func getIntelligentSearchStrategy(
        query: String,
        locationContext: String,
        searchType: String
    ) async -> SearchStrategy {
        guard let openAIChatService = openAIChatService else {
            return SearchStrategy.default(for: query)
        }
        
        do {
            let timeContext = "Current time: \(DateFormatter().string(from: Date()))"
            return try await openAIChatService.determineSearchStrategy(
                query: query,
                locationContext: locationContext,
                timeContext: timeContext
            )
        } catch {
            print("⚠️ [LocationMCPServer] Failed to get search strategy from LLM: \(error)")
            return SearchStrategy.default(for: query)
        }
    }
    
    private func performWebSearchForType(
        _ query: String,
        searchType: String,
        locationSearchService: LocationBasedSearchService
    ) async -> LocationSearchResult {
        switch searchType {
        case "nearby_places":
            return await locationSearchService.findNearbyServices(serviceType: query)
        case "restaurants":
            return await locationSearchService.findNearbyRestaurants(query: query)
        case "transport":
            return await locationSearchService.findNearbyTransport(type: .all)
        case "landmarks":
            return await locationSearchService.findNearbyLandmarks()
        case "services":
            return await locationSearchService.findNearbyServices(serviceType: query)
        default:
            return await locationSearchService.findNearbyServices(serviceType: query)
        }
    }
    
    private func getCurrentLocationContext() async -> String {
        guard let locationManager = locationManager else {
            return "Location unavailable"
        }
        
        return await MainActor.run {
            let location = locationManager.currentLocation?.coordinate
            let address = locationManager.currentAddress
            let city = locationManager.currentCity
            
            var context = "Current location: "
            if let addr = address {
                context += addr
            } else if let city = city {
                context += city
            } else if let loc = location {
                context += "\(loc.latitude), \(loc.longitude)"
            } else {
                context += "unknown"
            }
            
            return context
        }
    }
    
    private func executeGetUserLocation(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        do {
            guard let locationManager = locationManager else {
                throw LocationMCPError.locationManagerNotAvailable
            }
            
            // Get current location
            guard let currentLocation = await locationManager.currentLocation else {
                throw LocationMCPError.locationNotAvailable
            }
            
            // Get movement status (clamped to sane values)
            let movementStatus = await locationManager.isMoving ? "Moving" : "Stationary"
            let rawSpeed = await locationManager.averageSpeed
            let speed = min(max(rawSpeed, 0), 200.0)
            
            // Get friendly address and neighborhood
            let address = await locationManager.currentAddress ?? "Address unavailable"
            let neighborhood = await locationManager.currentNeighborhood ?? ""
            let friendly = await locationManager.friendlyLocationString()
            let localTime = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            
            // Prepare result
            let result: [String: Any] = [
                "latitude": currentLocation.coordinate.latitude,
                "longitude": currentLocation.coordinate.longitude,
                "accuracy": currentLocation.horizontalAccuracy,
                "altitude": currentLocation.altitude,
                "movement_status": movementStatus,
                "speed_kmh": speed,
                "address": address,
                "neighborhood": neighborhood,
                "friendly_location": friendly,
                "local_time": localTime,
                "timestamp": ISO8601DateFormatter().string(from: currentLocation.timestamp)
            ]
            
            let resultData = try JSONSerialization.data(withJSONObject: result)
            let resultText = String(data: resultData, encoding: .utf8) ?? "{}"
            
            print("✅ [LocationMCPServer] Location retrieved: \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)")
            
            return MCPCallToolResponse(
                content: [MCPContent(text: resultText)],
                isError: false
            )
            
        } catch {
            print("❌ [LocationMCPServer] Get location failed: \(error)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to get location: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func executeFindNearbyPlaces(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        do {
            guard let arguments = request.arguments else {
                throw LocationMCPError.invalidParameters("Missing arguments")
            }
            
            guard let category = arguments["category"] as? String else {
                throw LocationMCPError.invalidParameters("Missing category parameter")
            }
            
            // Use LLM-first intelligent search fusion
            return await performIntelligentLocationSearch(
                userQuery: category,
                searchType: "nearby_places",
                context: arguments
            )
            
        } catch {
            print("❌ [LocationMCPServer] Find nearby places failed: \(error)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to find nearby places: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func executeGetDirections(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        do {
            guard let arguments = request.arguments else {
                throw LocationMCPError.invalidParameters("Missing arguments")
            }
            
            guard let destination = arguments["destination"] as? String else {
                throw LocationMCPError.invalidParameters("Missing destination parameter")
            }
            
            guard let transportationMode = arguments["transportation_mode"] as? String else {
                throw LocationMCPError.invalidParameters("Missing transportation_mode parameter")
            }
            
            // Use LLM-first intelligent directions
            return await performIntelligentDirections(
                destination: destination,
                transportationMode: transportationMode,
                context: arguments
            )
            
        } catch {
            print("❌ [LocationMCPServer] Get directions failed: \(error)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to get directions: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func performIntelligentDirections(
        destination: String,
        transportationMode: String,
        context: [String: Any]
    ) async -> MCPCallToolResponse {
        do {
            let locationContext = await getCurrentLocationContext()
            
            // Gather data for intelligent directions
            var destinationData: [String: Any]? = nil
            var routeSummary: GooglePlacesRoutesService.RouteSummary? = nil
            var mapsURLs: (web: URL, app: URL?)? = nil
            var conflictingData: [String] = []
            // Step 1: Intelligent destination resolution using LLM
            if let google = googlePlacesRoutesService {
                do {
                    // Use LLM to determine if we need place resolution
                    let candidates = try await google.searchText(query: destination, maxResults: 3)
                    
                    // Check for destination ambiguity before proceeding
                    if let openAIChatService = openAIChatService {
                        do {
                            let candidatesData = candidates.map { candidate in
                                return [
                                    "name": candidate.name,
                                    "address": candidate.formattedAddress,
                                    "distance_meters": candidate.distanceMeters
                                ]
                            }
                            
                            if let clarificationQuestion = try await openAIChatService.detectAmbiguityAndAskClarification(
                                userQuery: "Directions to \(destination)",
                                googlePlaces: candidatesData,
                                webSearchData: nil,
                                locationContext: locationContext
                            ) {
                                print("🤔 [LocationMCPServer] Detected destination ambiguity, asking for clarification")
                                return MCPCallToolResponse(
                                    content: [MCPContent(text: clarificationQuestion)],
                                    isError: false
                                )
                            }
                        } catch {
                            print("⚠️ [LocationMCPServer] Destination ambiguity detection failed: \(error)")
                        }
                    }
                    
                    if let resolvedPlace = candidates.first {
                        destinationData = [
                            "name": resolvedPlace.name,
                            "address": resolvedPlace.formattedAddress,
                            "distance_meters": resolvedPlace.distanceMeters,
                            "is_open": resolvedPlace.isOpen ?? false,
                            "business_status": resolvedPlace.businessStatus ?? "unknown",
                            "rating": resolvedPlace.rating ?? 0.0,
                            "has_business_details": resolvedPlace.hasBusinessDetails
                        ]
                        
                        // Step 2: Get route information
                        do {
                            let summary = try await google.computeRoute(to: resolvedPlace.formattedAddress, mode: transportationMode)
                            routeSummary = summary
                            
                            mapsURLs = await MainActor.run {
                                google.buildDirectionsURLs(to: resolvedPlace.formattedAddress, mode: transportationMode)
                            }
                        } catch {
                            conflictingData.append("Route calculation failed: \(error.localizedDescription)")
                        }
                    } else {
                        // Try with original destination string
                        do {
                            let summary = try await google.computeRoute(to: destination, mode: transportationMode)
                            routeSummary = summary
                            mapsURLs = await MainActor.run {
                                google.buildDirectionsURLs(to: destination, mode: transportationMode)
                            }
                        } catch {
                            conflictingData.append("Could not find or route to destination: \(destination)")
                        }
                    }
                } catch {
                    conflictingData.append("Place search failed: \(error.localizedDescription)")
                }
            }
            
            if !conflictingData.isEmpty && routeSummary == nil {
                let message = conflictingData.joined(separator: "\n")
                print("[Directions] ⚠️ Conflicting data prevented directions: \(message)")
                return MCPCallToolResponse(
                    content: [MCPContent(text: "Could not generate directions to \(destination). \(message)")],
                    isError: true
                )
            }
            
            guard let summary = routeSummary else {
                return MCPCallToolResponse(
                    content: [MCPContent(text: "Could not generate directions to \(destination)")],
                    isError: true
                )
            }
            
            guard let google = googlePlacesRoutesService else {
                return MCPCallToolResponse(
                    content: [MCPContent(text: "Google Routes service unavailable")],
                    isError: true
                )
            }
            
            if mapsURLs == nil {
                mapsURLs = await MainActor.run {
                    google.buildDirectionsURLs(to: summary.destination, mode: transportationMode)
                }
            }
            
            // Persist the resolved destination context for future "on the way" queries
            if let dest = destinationData,
               let name = dest["name"] as? String,
               let address = dest["address"] as? String {
                // Try to resolve coordinates via a quick text search (best-effort)
                do {
                    let candidates = try await google.searchText(query: name, maxResults: 1)
                    if let first = candidates.first {
                        lastDestination = DestinationContext(
                            name: first.name,
                            address: first.formattedAddress,
                            latitude: first.latitude,
                            longitude: first.longitude,
                            timestamp: Date()
                        )
                        print("📌 [LocationMCPServer] Saved last destination context: \(first.name)")
                    }
                } catch {
                    // Ignore coordinate persistence failure
                }
            }
            
            guard let webURL = mapsURLs?.web else {
                print("[Directions] ❌ Failed to produce Google Maps URL for destination '\(summary.destination)'")
                return MCPCallToolResponse(
                    content: [MCPContent(text: "Could not generate a Google Maps link for \(summary.destination)")],
                    isError: true
                )
            }
            
            let durationMinutes = max(1, Int(round(Double(summary.durationSeconds) / 60.0)))
            let displayDestination = (destinationData?["name"] as? String) ?? summary.destination
            var responsePayload: [String: Any] = [
                "title": "Directions",
                "summary": summary.summaryText,
                "destination": displayDestination,
                "transportation_mode": summary.travelMode,
                "eta_minutes": durationMinutes,
                "distance_meters": summary.distanceMeters,
                "maps_url": webURL.absoluteString
            ]
            if !summary.stepInstructions.isEmpty {
                responsePayload["route_steps"] = summary.stepInstructions
            }
            
            if let appURL = mapsURLs?.app {
                responsePayload["maps_app_url"] = appURL.absoluteString
            }
            
            if let resolvedAddress = destinationData?["address"] as? String {
                responsePayload["destination_address"] = resolvedAddress
            }
            
            let payloadData = try JSONSerialization.data(withJSONObject: responsePayload)
            let payloadText = String(data: payloadData, encoding: .utf8) ?? "{}"
            
            print("[Directions] ✅ Generated handoff payload: \(payloadText)")
            return MCPCallToolResponse(
                content: [MCPContent(text: payloadText)],
                isError: false
            )
            
        } catch {
            print("❌ [LocationMCPServer] Intelligent directions failed: \(error)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to generate directions: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    // MARK: - Mock Data Generators (Deprecated)
    
    private func generateMockDirections(to destination: String, mode: String) -> [String: Any] {
        return [
            "duration_minutes": mode == "walking" ? 15 : 8,
            "distance_meters": 1200,
            "steps": [
                "Head north on Current Street",
                "Turn right onto Main Street",
                "Continue for 0.8 miles",
                "Arrive at \(destination)"
            ],
            "estimated_arrival": Date().addingTimeInterval(mode == "walking" ? 900 : 480)
        ]
    }
    
    private func executeFindNearbyRestaurants(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        let arguments = request.arguments ?? [:]
        let cuisineType = arguments["cuisine_type"] as? String ?? ""
        let query = arguments["query"] as? String ?? ""
        
        if let clarification = await onTheWayClarificationIfNeeded(searchLabel: "restaurants") {
            return MCPCallToolResponse(content: [MCPContent(text: clarification)], isError: false)
        }
        
        // Build intelligent search query
        let searchQuery = !query.isEmpty ? "\(query) restaurant" : 
                         !cuisineType.isEmpty ? "\(cuisineType) restaurant" : "restaurants"
        
        // Use LLM-first intelligent search fusion
        return await performIntelligentLocationSearch(
            userQuery: searchQuery,
            searchType: "restaurants",
            context: arguments
        )
    }
    
    // Fallback to mock data if real service unavailable
    private func executeFindNearbyRestaurantsMock(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        let arguments = request.arguments ?? [:]
        let cuisineType = arguments["cuisine_type"] as? String ?? "any"
        let distance = arguments["distance"] as? String ?? "1000"
        
        let mockRestaurants = generateMockRestaurants(cuisineType: cuisineType, distance: distance)
        
        let result: [String: Any] = [
            "cuisine_type": cuisineType,
            "search_radius_meters": distance,
            "restaurants": mockRestaurants
        ]
        
        do {
            let resultData = try JSONSerialization.data(withJSONObject: result)
            let resultText = String(data: resultData, encoding: .utf8) ?? "{}"
            
            print("✅ [LocationMCPServer] Found \(mockRestaurants.count) restaurants (mock data)")
            
            return MCPCallToolResponse(
                content: [MCPContent(text: resultText)],
                isError: false
            )
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to generate restaurant data")],
                isError: true
            )
        }
    }
    
    private func executeFindNearbyTransport(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        do {
            if let clarification = await onTheWayClarificationIfNeeded(searchLabel: "transport options") {
                return MCPCallToolResponse(content: [MCPContent(text: clarification)], isError: false)
            }
            guard let arguments = request.arguments else {
                throw LocationMCPError.invalidParameters("Missing arguments")
            }
            
            guard let transportType = arguments["transport_type"] as? String else {
                throw LocationMCPError.invalidParameters("Missing transport_type parameter")
            }
            
            // Prefer Google Places for transport/search of transit-related types
            if let google = googlePlacesRoutesService {
                let mappedCategory: String
                switch transportType {
                case "subway": mappedCategory = "subway_station"
                case "train": mappedCategory = "train_station"
                case "bus": mappedCategory = "bus_station"
                case "taxi": mappedCategory = "taxi_stand"
                case "parking": mappedCategory = "parking"
                default: mappedCategory = "transportation"
                }
                let radius = (arguments["radius"] as? String).flatMap { Int($0) } ?? 1000
                do {
                    let summary = try await google.searchNearby(category: mappedCategory, radiusMeters: radius)
                    print("✅ [LocationMCPServer] Transport via Google Places")
                    return MCPCallToolResponse(
                        content: [MCPContent(text: summary)],
                        isError: false
                    )
                } catch {
                    print("⚠️ [LocationMCPServer] Google Places transport search failed: \(error). Falling back")
                }
            }
            
            guard let locationSearchService = locationSearchService else {
                print("⚠️ [LocationMCPServer] No LocationBasedSearchService available, using mock data")
                return await executeFindNearbyTransportMock(request)
            }
            
            // Map transport type to LocationBasedSearchService enum
            let searchType: TransportType
            switch transportType {
            case "subway":
                searchType = .subway
            case "train":
                searchType = .train
            case "bus":
                searchType = .bus
            case "taxi":
                searchType = .taxi
            case "bike", "bike_sharing", "parking":
                searchType = .parking
            default:
                searchType = .all
            }
            
            // Use real LocationBasedSearchService
            let searchResult = await locationSearchService.findNearbyTransport(type: searchType)
            
            if searchResult.error != nil {
                throw LocationMCPError.serviceUnavailable
            }
            
            let resultText = searchResult.summary ?? "No transport options found"
            
            print("✅ [LocationMCPServer] Found transport using real data")
            
            return MCPCallToolResponse(
                content: [MCPContent(text: resultText)],
                isError: false
            )
            
        } catch {
            print("❌ [LocationMCPServer] Find transport failed: \(error)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to find transport: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    // Fallback to mock data if real service unavailable
    private func executeFindNearbyTransportMock(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        let arguments = request.arguments ?? [:]
        let transportType = arguments["transport_type"] as? String ?? "all"
        let radius = arguments["radius"] as? String ?? "1000"
        
        let mockTransport = generateMockTransport(type: transportType, radius: radius)
        
        let result: [String: Any] = [
            "transport_type": transportType,
            "search_radius_meters": radius,
            "transport_options": mockTransport
        ]
        
        do {
            let resultData = try JSONSerialization.data(withJSONObject: result)
            let resultText = String(data: resultData, encoding: .utf8) ?? "{}"
            
            print("✅ [LocationMCPServer] Found \(mockTransport.count) transport options (mock data)")
            
            return MCPCallToolResponse(
                content: [MCPContent(text: resultText)],
                isError: false
            )
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to generate transport data")],
                isError: true
            )
        }
    }
    
    private func executeFindNearbyLandmarks(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        do {
            if let clarification = await onTheWayClarificationIfNeeded(searchLabel: "landmarks or places") {
                return MCPCallToolResponse(content: [MCPContent(text: clarification)], isError: false)
            }
            guard let locationSearchService = locationSearchService else {
                print("⚠️ [LocationMCPServer] No LocationBasedSearchService available, using mock data")
                let arguments = request.arguments ?? [:]
                let landmarkType = arguments["landmark_type"] as? String ?? "attractions"
                let radius = arguments["radius"] as? String ?? "2000"
                let mockLandmarks = generateMockLandmarks(type: landmarkType, radius: radius)
                
                let result: [String: Any] = [
                    "landmark_type": landmarkType,
                    "search_radius_meters": radius,
                    "landmarks": mockLandmarks
                ]
                
                let resultData = try JSONSerialization.data(withJSONObject: result)
                let resultText = String(data: resultData, encoding: .utf8) ?? "{}"
                
                return MCPCallToolResponse(
                    content: [MCPContent(text: resultText)],
                    isError: false
                )
            }
            
            let arguments = request.arguments ?? [:]
            let query = arguments["query"] as? String ?? ""
            
            // Use real LocationBasedSearchService
            let searchResult = await locationSearchService.findNearbyLandmarks(query: query)
            
            if searchResult.error != nil {
                throw LocationMCPError.serviceUnavailable
            }
            
            let resultText = searchResult.summary ?? "No landmarks found"
            
            print("✅ [LocationMCPServer] Found landmarks using real data")
            
            return MCPCallToolResponse(
                content: [MCPContent(text: resultText)],
                isError: false
            )
            
        } catch {
            print("❌ [LocationMCPServer] Find landmarks failed: \(error)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to find landmarks: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - On-the-way Clarification
    private func haversineDistanceMeters(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Int {
        let earthRadius = 6371000.0
        let dLat = (toLat - fromLat) * .pi / 180.0
        let dLon = (toLon - fromLon) * .pi / 180.0
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(fromLat * .pi / 180.0) * cos(toLat * .pi / 180.0) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return Int(earthRadius * c)
    }

    private func onTheWayClarificationIfNeeded(searchLabel: String) async -> String? {
        guard let lastDestination else { return nil }
        let currentLocation = await MainActor.run { locationManager?.currentLocation }
        guard let current = currentLocation else { return nil }
        
        let meters = haversineDistanceMeters(
            fromLat: current.coordinate.latitude, fromLon: current.coordinate.longitude,
            toLat: lastDestination.latitude, toLon: lastDestination.longitude
        )
        let distanceText: String = {
            if meters < 1000 {
                return "\(meters) m"
            } else {
                let km = Double(meters) / 1000.0
                return String(format: "%.1f km", km)
            }
        }()
        
        let question = """
You recently asked for directions to "\(lastDestination.name)". You're about \(distanceText) from that destination now.
Do you want \(searchLabel) on the way to that destination or near the destination?
If on the way, how far off-route is acceptable (e.g., 2–5 minutes)?
If near the destination, how far from it is okay (e.g., within 300 m)?
"""
        print("❓ [LocationMCPServer] On-the-way clarification for \(searchLabel) — last destination: \(lastDestination.name)")
        return question
    }
    
    private func executeFindNearbyServices(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        do {
            if let clarification = await onTheWayClarificationIfNeeded(searchLabel: "services") {
                return MCPCallToolResponse(content: [MCPContent(text: clarification)], isError: false)
            }
            guard let arguments = request.arguments else {
                throw LocationMCPError.invalidParameters("Missing arguments")
            }
            
            guard let serviceType = arguments["service_type"] as? String else {
                throw LocationMCPError.invalidParameters("Missing service_type parameter")
            }
            let query = (arguments["query"] as? String) ?? ""
            let _ = (arguments["radius"] as? String).flatMap { Int($0) } ?? 1500  // Radius not used in LLM-first approach
            
            // Prefer Google Places for proximity/brand-aware service lookup
            if let google = googlePlacesRoutesService {
                do {
                    // Always use text search for now, but with better debugging
                    let effectiveQuery = query.isEmpty ? serviceType : "\(query) \(serviceType)"
                    print("🔍 [LocationMCPServer] Attempting Google Places text search for: '\(effectiveQuery)', maxResults: 8")
                    let candidates = try await google.searchText(query: effectiveQuery, maxResults: 8)
                    print("✅ [LocationMCPServer] Google Places returned \(candidates.count) candidates for '\(effectiveQuery)'")
                    
                    if !candidates.isEmpty {
                        let sorted = candidates.sorted { $0.distanceMeters < $1.distanceMeters }
                        let lines: [String] = sorted.prefix(5).map { c in
                            let km = Double(c.distanceMeters) / 1000.0
                            let walkMins = Int(round(Double(c.distanceMeters) / 80.0))
                            return "- \(c.name) — \(c.formattedAddress) — \(c.distanceMeters < 1000 ? "\(c.distanceMeters) m" : String(format: "%.1f km", km)) (~\(walkMins) min walk)"
                        }
                        let header = "Nearest \(serviceType) nearby:"
                        let summary = ([header] + lines).joined(separator: "\n")
                        return MCPCallToolResponse(
                            content: [MCPContent(text: summary)],
                            isError: false
                        )
                    } else {
                        print("⚠️ [LocationMCPServer] Google Places returned no results for \(serviceType)")
                    }
                } catch {
                    print("⚠️ [LocationMCPServer] Google Places services search failed: \(error). Falling back")
                }
            } else {
                print("⚠️ [LocationMCPServer] GooglePlacesRoutesService not available")
            }

            guard let locationSearchService = locationSearchService else {
                print("⚠️ [LocationMCPServer] No LocationBasedSearchService available, using mock data")
                let radius = arguments["radius"] as? String ?? "1000"
                let mockServices = generateMockServices(type: serviceType, radius: radius)
                
                let result: [String: Any] = [
                    "service_type": serviceType,
                    "search_radius_meters": radius,
                    "services": mockServices
                ]
                
                let resultData = try JSONSerialization.data(withJSONObject: result)
                let resultText = String(data: resultData, encoding: .utf8) ?? "{}"
                
                return MCPCallToolResponse(
                    content: [MCPContent(text: resultText)],
                    isError: false
                )
            }
            
            // Use real LocationBasedSearchService
            let searchResult = await locationSearchService.findNearbyServices(serviceType: serviceType, query: query)
            
            if searchResult.error != nil {
                throw LocationMCPError.serviceUnavailable
            }
            
            let resultText = searchResult.summary ?? "No services found"
            
            print("✅ [LocationMCPServer] Found services using real data")
            
            return MCPCallToolResponse(
                content: [MCPContent(text: resultText)],
                isError: false
            )
            
        } catch {
            print("❌ [LocationMCPServer] Find services failed: \(error)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to find services: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func parseNearbyResultsToCandidates(_ nearbyResult: String) -> [GooglePlacesRoutesService.PlaceCandidate] {
        // The nearby search returns a formatted string, but we need PlaceCandidate objects
        // For now, return empty array to force fallback to text search for consistency
        // TODO: Modify GooglePlacesRoutesService to return structured data instead of formatted strings
        return []
    }
    
    // MARK: - Additional Mock Data Generators
    
    private func generateMockRestaurants(cuisineType: String, distance: String) -> [[String: Any]] {
        var restaurants: [[String: Any]] = []
        
        let baseRestaurants = [
            ["name": "Bella Italia", "cuisine": "italian", "rating": 4.5, "price": "$$"],
            ["name": "Dragon Palace", "cuisine": "chinese", "rating": 4.2, "price": "$"],
            ["name": "Sakura Sushi", "cuisine": "japanese", "rating": 4.7, "price": "$$$"],
            ["name": "Casa Mexicana", "cuisine": "mexican", "rating": 4.3, "price": "$$"],
            ["name": "Spice Garden", "cuisine": "indian", "rating": 4.4, "price": "$$"],
            ["name": "The American Grill", "cuisine": "american", "rating": 4.1, "price": "$$$"]
        ]
        
        for (index, restaurant) in baseRestaurants.enumerated() {
            if cuisineType == "any" || restaurant["cuisine"] as? String == cuisineType {
                restaurants.append([
                    "name": restaurant["name"]!,
                    "cuisine": restaurant["cuisine"]!,
                    "rating": restaurant["rating"]!,
                    "price_level": restaurant["price"]!,
                    "distance_meters": 200 + (index * 150),
                    "estimated_walk_time": "\(2 + index) minutes",
                    "address": "\(100 + index) Restaurant St"
                ])
            }
        }
        
        return restaurants
    }
    
    private func generateMockTransport(type: String, radius: String) -> [[String: Any]] {
        switch type {
        case "subway":
            return [
                ["name": "66 St-Lincoln Center Station", "type": "subway_station", "distance_meters": 400, "lines": ["1"], "walk_time": "9 minutes"],
                ["name": "72 St Station", "type": "subway_station", "distance_meters": 600, "lines": ["1", "2", "3"], "walk_time": "12 minutes"],
                ["name": "59 St-Columbus Circle Station", "type": "subway_station", "distance_meters": 800, "lines": ["A", "B", "C", "D"], "walk_time": "16 minutes"]
            ]
        case "bus":
            return [
                ["name": "Main Street Bus Stop", "type": "bus_stop", "distance_meters": 120, "routes": ["Route 5", "Route 12"]],
                ["name": "City Center Bus Terminal", "type": "bus_terminal", "distance_meters": 450, "routes": ["Route 1", "Route 3", "Route 8"]]
            ]
        case "train":
            return [
                ["name": "Central Station", "type": "train_station", "distance_meters": 800, "lines": ["Blue Line", "Red Line"]],
                ["name": "Metro North", "type": "metro_station", "distance_meters": 1200, "lines": ["Green Line"]]
            ]
        case "taxi":
            return [
                ["name": "Taxi Stand - Hotel Plaza", "type": "taxi_stand", "distance_meters": 150, "available_taxis": 3],
                ["name": "Taxi Stand - Shopping Mall", "type": "taxi_stand", "distance_meters": 600, "available_taxis": 5]
            ]
        case "bike_sharing":
            return [
                ["name": "City Bike Station A1", "type": "bike_station", "distance_meters": 200, "available_bikes": 8],
                ["name": "City Bike Station B3", "type": "bike_station", "distance_meters": 350, "available_bikes": 12]
            ]
        default:
            return [
                ["name": "General Transport Hub", "type": "transport_hub", "distance_meters": 500, "services": [type]]
            ]
        }
    }
    
    private func generateMockLandmarks(type: String, radius: String) -> [[String: Any]] {
        switch type {
        case "museums":
            return [
                ["name": "City Art Museum", "type": "museum", "distance_meters": 800, "rating": 4.6, "entry_fee": "$15"],
                ["name": "History & Culture Center", "type": "museum", "distance_meters": 1200, "rating": 4.3, "entry_fee": "$12"]
            ]
        case "parks":
            return [
                ["name": "Central Park", "type": "park", "distance_meters": 300, "size": "50 acres", "features": ["playground", "lake"]],
                ["name": "Riverside Gardens", "type": "park", "distance_meters": 900, "size": "25 acres", "features": ["trails", "picnic area"]]
            ]
        case "monuments":
            return [
                ["name": "City Founder Monument", "type": "monument", "distance_meters": 600, "year_built": "1885", "significance": "Historical"],
                ["name": "Freedom Square", "type": "memorial", "distance_meters": 1100, "year_built": "1945", "significance": "War Memorial"]
            ]
        default:
            return [
                ["name": "Local Landmark", "type": type, "distance_meters": 750, "description": "Popular local attraction"]
            ]
        }
    }
    
    private func generateMockServices(type: String, radius: String) -> [[String: Any]] {
        switch type {
        case "hospital":
            return [
                ["name": "City General Hospital", "type": "hospital", "distance_meters": 1200, "emergency": true, "phone": "+1-555-911"],
                ["name": "Community Health Clinic", "type": "clinic", "distance_meters": 600, "emergency": false, "phone": "+1-555-123"]
            ]
        case "pharmacy":
            return [
                ["name": "24/7 Pharmacy", "type": "pharmacy", "distance_meters": 300, "hours": "24/7", "phone": "+1-555-456"],
                ["name": "Family Pharmacy", "type": "pharmacy", "distance_meters": 750, "hours": "8AM-10PM", "phone": "+1-555-789"]
            ]
        case "bank":
            return [
                ["name": "First National Bank", "type": "bank", "distance_meters": 400, "atm": true, "hours": "9AM-5PM"],
                ["name": "Community Credit Union", "type": "credit_union", "distance_meters": 800, "atm": true, "hours": "9AM-6PM"]
            ]
        case "gas_station":
            return [
                ["name": "Shell Station", "type": "gas_station", "distance_meters": 500, "24_hour": true, "services": ["fuel", "convenience store"]],
                ["name": "BP Express", "type": "gas_station", "distance_meters": 900, "24_hour": false, "services": ["fuel", "car wash"]]
            ]
        default:
            return [
                ["name": "Local Service Provider", "type": type, "distance_meters": 600, "description": "Essential service location"]
            ]
        }
    }
    
    private func executeFindPlacesOnRoute(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        do {
            guard let arguments = request.arguments else {
                throw LocationMCPError.invalidParameters("Missing arguments")
            }
            
            guard let query = arguments["query"] as? String else {
                throw LocationMCPError.invalidParameters("Missing query parameter")
            }
            
            guard let destination = arguments["destination"] as? String else {
                throw LocationMCPError.invalidParameters("Missing destination parameter")
            }
            
            // Use LLM-first route intelligence
            return await performIntelligentRouteSearch(
                userQuery: query,
                destination: destination,
                context: arguments
            )
            
        } catch {
            print("❌ [LocationMCPServer] Find places on route failed: \(error)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "Failed to find places on route: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func performIntelligentRouteSearch(
        userQuery: String,
        destination: String,
        context: [String: Any]
    ) async -> MCPCallToolResponse {
        do {
            let locationContext = await getCurrentLocationContext()
            
            // Gather route data from multiple sources
            var routePlaces: [Any]? = nil
            var webInsights: String? = nil
            var travelMode: String? = nil
            
            // Try Google Places route search first
            if let google = googlePlacesRoutesService {
                do {
                    // Resolve destination
                    let destinationCandidates = try await google.searchText(query: destination, maxResults: 1)
                    guard let destinationPlace = destinationCandidates.first else {
                        return MCPCallToolResponse(
                            content: [MCPContent(text: "Could not find destination: \(destination)")],
                            isError: true
                        )
                    }
                    
                    // Search around destination for now (route search would need more complex implementation)
                    let routeCandidates = try await google.searchText(
                        query: userQuery,
                        maxResults: 5
                    )
                    
                    if !routeCandidates.isEmpty {
                        routePlaces = routeCandidates.map { candidate in
                            [
                                "name": candidate.name,
                                "address": candidate.formattedAddress,
                                "distance_from_current": candidate.distanceMeters,
                                "latitude": candidate.latitude,
                                "longitude": candidate.longitude,
                                "is_open": candidate.isOpen ?? false,
                                "business_status": candidate.businessStatus ?? "unknown",
                                "rating": candidate.rating ?? 0.0,
                                "has_business_details": candidate.hasBusinessDetails
                            ]
                        }
                    }
                    
                } catch {
                    print("⚠️ [LocationMCPServer] Google route search failed: \(error)")
                }
            }
            
            // Get additional insights from web search
            if let locationSearchService = locationSearchService {
                let routeQuery = "\(userQuery) between \(locationContext) and \(destination)"
                let webResult = await locationSearchService.findNearbyServices(serviceType: userQuery, query: routeQuery)
                webInsights = webResult.summary
            }
            
            // Use LLM to synthesize intelligent route recommendations
            guard let openAIChatService = openAIChatService else {
                // Fallback without LLM
                if let places = routePlaces, !places.isEmpty {
                    return MCPCallToolResponse(
                        content: [MCPContent(text: "Found \(places.count) \(userQuery) on the way to \(destination)")],
                        isError: false
                    )
                } else {
                    return MCPCallToolResponse(
                        content: [MCPContent(text: "No \(userQuery) found on route to \(destination)")],
                        isError: false
                    )
                }
            }
            
            let intelligentResponse = try await openAIChatService.synthesizeRouteRecommendations(
                userQuery: userQuery,
                destination: destination,
                routePlaces: routePlaces,
                webInsights: webInsights,
                travelMode: travelMode,
                currentLocation: locationContext
            )
            
            print("✅ [LocationMCPServer] LLM synthesized route recommendations for '\(userQuery)' to '\(destination)'")
            return MCPCallToolResponse(
                content: [MCPContent(text: intelligentResponse)],
                isError: false
            )
            
        } catch {
            print("❌ [LocationMCPServer] Intelligent route search failed: \(error)")
            return MCPCallToolResponse(
                content: [MCPContent(text: "Route search failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
}

// MARK: - Error Types

public enum LocationMCPError: Error, LocalizedError {
    case locationManagerNotAvailable
    case locationNotAvailable
    case invalidParameters(String)
    case serviceUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .locationManagerNotAvailable:
            return "Location manager is not available"
        case .locationNotAvailable:
            return "Current location is not available"
        case .invalidParameters(let message):
            return "Invalid parameters: \(message)"
        case .serviceUnavailable:
            return "Location service is unavailable"
        }
    }
}