//
//  RealtimeTools.swift
//  guido-1
//
//  Created by Varun Jain on 7/27/25.
//

import Foundation
import CoreLocation
import EventKit
import MapKit

// MARK: - Tool Definitions

struct RealtimeToolDefinition: Codable {
    let type: String = "function"
    let name: String
    let description: String
    let parameters: ToolParameters
}

struct ToolParameters: Codable {
    let type: String = "object"
    let properties: [String: ParameterProperty]
    let required: [String]
    let strict: Bool = true
}

struct ParameterProperty: Codable {
    let type: String
    let description: String
    let `enum`: [String]?
    
    init(type: String, description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enum = enumValues
    }
}

// MARK: - Tool Manager

@MainActor
class RealtimeToolManager: ObservableObject {
    @Published var lastToolUsed: String?
    @Published var toolResults: [String: Any] = [:]
    
    private var locationManager: LocationManager?
    private var eventStore = EKEventStore()
    private var locationSearchService: LocationBasedSearchService?
    private var openAIChatService: OpenAIChatService?
    
    init() {
        print("🔧 RealtimeToolManager initialized")
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
    
    // MARK: - Tool Definitions
    
    static func getAllToolDefinitions() -> [RealtimeToolDefinition] {
        return [
            getLocationTool(),
            getNearbyPlacesTool(),
            getDirectionsTool(),
            getWeatherTool(),
            getCalendarTool(),
            getLocalTimeTool(),
            getTransportationTool(),
            getLocalEventsTool(),
            // New location search tools
            findNearbyRestaurantsTool(),
            findNearbyTransportTool(),
            findNearbyLandmarksTool(),
            findNearbyServicesTool(),
            getRestaurantRecommendationsTool(),
            getCurrencyTool(),
            getLanguageTranslationTool(),
            getSafetyInfoTool(),
            getTravelDocumentsTool(),
            getEmergencyInfoTool(),
            // AI and web search tools
            getWebSearchTool(),
            getAIResponseTool()
        ]
    }
    
    // MARK: - Individual Tool Definitions
    
    private static func getLocationTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "get_user_location",
            description: "Get the user's current location, movement status, and nearby area information for personalized travel recommendations",
            parameters: ToolParameters(
                properties: [:],
                required: []
            )
        )
    }
    
    private static func getNearbyPlacesTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "find_nearby_places",
            description: "Find nearby places of interest like restaurants, attractions, hotels, or transportation hubs",
            parameters: ToolParameters(
                properties: [
                    "category": ParameterProperty(
                        type: "string",
                        description: "Type of place to search for",
                        enumValues: ["restaurants", "attractions", "hotels", "transportation", "shopping", "entertainment", "medical", "gas_stations"]
                    ),
                    "radius": ParameterProperty(
                        type: "string",
                        description: "Search radius in meters (default: 1000)",
                        enumValues: ["500", "1000", "2000", "5000"]
                    )
                ],
                required: ["category"]
            )
        )
    }
    
    private static func getDirectionsTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "get_directions",
            description: "Get turn-by-turn directions to a destination with estimated travel time",
            parameters: ToolParameters(
                properties: [
                    "destination": ParameterProperty(
                        type: "string",
                        description: "The destination address or place name"
                    ),
                    "transportation_mode": ParameterProperty(
                        type: "string",
                        description: "Mode of transportation",
                        enumValues: ["walking", "driving", "transit", "cycling"]
                    )
                ],
                required: ["destination", "transportation_mode"]
            )
        )
    }
    
    private static func getWeatherTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "get_weather",
            description: "Get current weather conditions and forecast for the user's location or a specified city",
            parameters: ToolParameters(
                properties: [
                    "location": ParameterProperty(
                        type: "string",
                        description: "City name (optional - uses current location if not provided)"
                    ),
                    "forecast_days": ParameterProperty(
                        type: "string",
                        description: "Number of forecast days to include",
                        enumValues: ["1", "3", "5", "7"]
                    )
                ],
                required: []
            )
        )
    }
    
    private static func getCalendarTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "check_calendar",
            description: "Check the user's calendar for upcoming appointments or free time for travel planning",
            parameters: ToolParameters(
                properties: [
                    "time_range": ParameterProperty(
                        type: "string",
                        description: "Time range to check",
                        enumValues: ["today", "tomorrow", "this_week", "next_week"]
                    )
                ],
                required: ["time_range"]
            )
        )
    }
    
    private static func getLocalTimeTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "get_local_time",
            description: "Get the current local time and timezone information for any city or the user's current location",
            parameters: ToolParameters(
                properties: [
                    "city": ParameterProperty(
                        type: "string",
                        description: "City name (optional - uses current location if not provided)"
                    )
                ],
                required: []
            )
        )
    }
    
    private static func getTransportationTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "find_transportation",
            description: "Find available transportation options like rideshare, public transit, bike share, or car rentals",
            parameters: ToolParameters(
                properties: [
                    "transport_type": ParameterProperty(
                        type: "string",
                        description: "Type of transportation to find",
                        enumValues: ["rideshare", "public_transit", "bike_share", "car_rental", "taxi", "all"]
                    ),
                    "destination": ParameterProperty(
                        type: "string",
                        description: "Destination for route planning (optional)"
                    )
                ],
                required: ["transport_type"]
            )
        )
    }
    
    private static func getLocalEventsTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "find_local_events",
            description: "Find local events, festivals, concerts, or activities happening nearby",
            parameters: ToolParameters(
                properties: [
                    "event_type": ParameterProperty(
                        type: "string",
                        description: "Type of events to search for",
                        enumValues: ["music", "food", "art", "sports", "cultural", "nightlife", "family", "all"]
                    ),
                    "time_frame": ParameterProperty(
                        type: "string",
                        description: "When to look for events",
                        enumValues: ["today", "tonight", "tomorrow", "this_weekend", "this_week"]
                    )
                ],
                required: ["event_type", "time_frame"]
            )
        )
    }
    
    private static func getRestaurantRecommendationsTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "recommend_restaurants",
            description: "Get personalized restaurant recommendations based on cuisine, price, location, and user preferences",
            parameters: ToolParameters(
                properties: [
                    "cuisine_type": ParameterProperty(
                        type: "string",
                        description: "Type of cuisine",
                        enumValues: ["local", "italian", "asian", "mexican", "american", "indian", "french", "mediterranean", "any"]
                    ),
                    "price_range": ParameterProperty(
                        type: "string",
                        description: "Price range preference",
                        enumValues: ["budget", "moderate", "upscale", "fine_dining", "any"]
                    ),
                    "dining_style": ParameterProperty(
                        type: "string",
                        description: "Dining style preference",
                        enumValues: ["quick_bite", "casual", "romantic", "family_friendly", "business", "any"]
                    )
                ],
                required: ["cuisine_type"]
            )
        )
    }
    
    private static func getCurrencyTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "currency_converter",
            description: "Convert currency amounts and get current exchange rates for travel planning",
            parameters: ToolParameters(
                properties: [
                    "from_currency": ParameterProperty(
                        type: "string",
                        description: "Source currency code (e.g., USD, EUR, GBP)"
                    ),
                    "to_currency": ParameterProperty(
                        type: "string",
                        description: "Target currency code"
                    ),
                    "amount": ParameterProperty(
                        type: "string",
                        description: "Amount to convert (optional, defaults to 1)"
                    )
                ],
                required: ["from_currency", "to_currency"]
            )
        )
    }
    
    private static func getLanguageTranslationTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "translate_text",
            description: "Translate text or phrases to help with local communication while traveling",
            parameters: ToolParameters(
                properties: [
                    "text": ParameterProperty(
                        type: "string",
                        description: "Text to translate"
                    ),
                    "target_language": ParameterProperty(
                        type: "string",
                        description: "Target language code (e.g., es, fr, de, it, ja, ko, zh)"
                    ),
                    "source_language": ParameterProperty(
                        type: "string",
                        description: "Source language code (optional, auto-detect if not provided)"
                    )
                ],
                required: ["text", "target_language"]
            )
        )
    }
    
    private static func getSafetyInfoTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "get_safety_info",
            description: "Get safety information, travel advisories, and local safety tips for the current location or destination",
            parameters: ToolParameters(
                properties: [
                    "location": ParameterProperty(
                        type: "string",
                        description: "Location to check (optional - uses current location if not provided)"
                    ),
                    "info_type": ParameterProperty(
                        type: "string",
                        description: "Type of safety information",
                        enumValues: ["general", "travel_advisory", "health", "crime", "weather_alerts", "emergency_contacts"]
                    )
                ],
                required: ["info_type"]
            )
        )
    }
    
    private static func getTravelDocumentsTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "check_travel_requirements",
            description: "Check visa requirements, passport validity, and travel document needs for international travel",
            parameters: ToolParameters(
                properties: [
                    "destination_country": ParameterProperty(
                        type: "string",
                        description: "Destination country name or code"
                    ),
                    "passport_country": ParameterProperty(
                        type: "string",
                        description: "Passport issuing country"
                    ),
                    "travel_purpose": ParameterProperty(
                        type: "string",
                        description: "Purpose of travel",
                        enumValues: ["tourism", "business", "transit", "study", "work"]
                    )
                ],
                required: ["destination_country", "passport_country", "travel_purpose"]
            )
        )
    }
    
    private static func getEmergencyInfoTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "get_emergency_info",
            description: "Get emergency contact numbers, nearest hospitals, police stations, and embassies for the current location",
            parameters: ToolParameters(
                properties: [
                    "emergency_type": ParameterProperty(
                        type: "string",
                        description: "Type of emergency information needed",
                        enumValues: ["medical", "police", "fire", "embassy", "general", "all"]
                    ),
                    "location": ParameterProperty(
                        type: "string",
                        description: "Location to check (optional - uses current location if not provided)"
                    )
                ],
                required: ["emergency_type"]
            )
        )
    }
    
    private static func getWebSearchTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "web_search",
            description: "Search the internet for real-time information about travel destinations, local businesses, events, and current conditions",
            parameters: ToolParameters(
                properties: [
                    "query": ParameterProperty(
                        type: "string",
                        description: "Search query for finding current information on the web"
                    ),
                    "location": ParameterProperty(
                        type: "string",
                        description: "Optional location context to refine search results (uses current location if not provided)"
                    )
                ],
                required: ["query"]
            )
        )
    }
    
    private static func getAIResponseTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "ai_response",
            description: "Get intelligent responses and analysis using OpenAI's advanced reasoning capabilities for complex travel planning and recommendations",
            parameters: ToolParameters(
                properties: [
                    "prompt": ParameterProperty(
                        type: "string",
                        description: "Detailed prompt for generating intelligent travel advice, recommendations, or analysis"
                    ),
                    "context": ParameterProperty(
                        type: "string",
                        description: "Optional context about the user's location, preferences, or current situation"
                    )
                ],
                required: ["prompt"]
            )
        )
    }
    
    // MARK: - Location Search Tool Definitions
    
    private static func findNearbyRestaurantsTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "find_nearby_restaurants",
            description: "Find restaurants, cafes, and dining options near the current location using real-time web search",
            parameters: ToolParameters(
                properties: [
                    "query": ParameterProperty(
                        type: "string", 
                        description: "Specific restaurant name or type of food (optional)"
                    ),
                    "cuisine": ParameterProperty(
                        type: "string",
                        description: "Type of cuisine (e.g., Italian, Chinese, Mexican) (optional)"
                    )
                ],
                required: []
            )
        )
    }
    
    private static func findNearbyTransportTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "find_nearby_transport",
            description: "Find public transportation, taxi services, and parking options near the current location",
            parameters: ToolParameters(
                properties: [
                    "transport_type": ParameterProperty(
                        type: "string",
                        description: "Type of transportation to find",
                        enumValues: ["all", "subway", "bus", "train", "taxi", "parking"]
                    )
                ],
                required: []
            )
        )
    }
    
    private static func findNearbyLandmarksTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "find_nearby_landmarks",
            description: "Find landmarks, tourist attractions, and points of interest near the current location",
            parameters: ToolParameters(
                properties: [
                    "query": ParameterProperty(
                        type: "string",
                        description: "Specific landmark or type of attraction to search for (optional)"
                    )
                ],
                required: []
            )
        )
    }
    
    private static func findNearbyServicesTool() -> RealtimeToolDefinition {
        return RealtimeToolDefinition(
            name: "find_nearby_services",
            description: "Find specific services like banks, pharmacies, gas stations, or other businesses near the current location",
            parameters: ToolParameters(
                properties: [
                    "service_type": ParameterProperty(
                        type: "string",
                        description: "Type of service to find (e.g., bank, pharmacy, gas station, ATM, hospital)"
                    ),
                    "query": ParameterProperty(
                        type: "string",
                        description: "Additional search terms or specific business name (optional)"
                    )
                ],
                required: ["service_type"]
            )
        )
    }
    
    // MARK: - Tool Execution
    
    func executeTool(name: String, parameters: [String: Any]) async -> ToolResult {
        lastToolUsed = name
        print("🔧 Executing tool: \(name) with parameters: \(parameters)")
        
        switch name {
        case "get_user_location":
            return await executeLocationTool()
            
        case "find_nearby_places":
            return await executeNearbyPlacesTool(parameters: parameters)
            
        case "get_directions":
            return await executeDirectionsTool(parameters: parameters)
            
        case "get_weather":
            return await executeWeatherTool(parameters: parameters)
            
        case "check_calendar":
            return await executeCalendarTool(parameters: parameters)
            
        case "get_local_time":
            return await executeLocalTimeTool(parameters: parameters)
            
        case "find_transportation":
            return await executeTransportationTool(parameters: parameters)
            
        case "find_local_events":
            return await executeLocalEventsTool(parameters: parameters)
            
        case "recommend_restaurants":
            return await executeRestaurantTool(parameters: parameters)
            
        case "currency_converter":
            return await executeCurrencyTool(parameters: parameters)
            
        case "translate_text":
            return await executeTranslationTool(parameters: parameters)
            
        case "get_safety_info":
            return await executeSafetyTool(parameters: parameters)
            
        case "check_travel_requirements":
            return await executeTravelDocumentsTool(parameters: parameters)
            
        case "get_emergency_info":
            return await executeEmergencyTool(parameters: parameters)
            
        // New location search tools
        case "find_nearby_restaurants":
            return await executeFindNearbyRestaurants(parameters: parameters)
            
        case "find_nearby_transport":
            return await executeFindNearbyTransport(parameters: parameters)
            
        case "find_nearby_landmarks":
            return await executeFindNearbyLandmarks(parameters: parameters)
            
        case "find_nearby_services":
            return await executeFindNearbyServices(parameters: parameters)
            
        case "web_search":
            return await executeWebSearch(parameters: parameters)
            
        case "ai_response":
            return await executeAIResponse(parameters: parameters)
            
        default:
            return ToolResult(success: false, data: "Unknown tool: \(name)")
        }
    }
    
    // MARK: - Tool Implementations
    
    private func executeLocationTool() async -> ToolResult {
        guard let locationManager = locationManager else {
            return ToolResult(success: false, data: "Location manager not available")
        }
        
        let context = locationManager.getCurrentLocationContext()
        let friendly = locationManager.friendlyLocationString()
        let clampedSpeed = min(max(context.speed, 0), 200.0)
        let localTime = DateFormatter.localizedString(from: context.timestamp, dateStyle: .none, timeStyle: .short)
        
        let locationData: [String: Any] = [
            "latitude": context.location?.coordinate.latitude ?? 0,
            "longitude": context.location?.coordinate.longitude ?? 0,
            "address": context.address ?? "Unknown",
            "city": context.city ?? "Unknown",
            "country": context.country ?? "Unknown",
            "neighborhood": context.neighborhood ?? "",
            "is_moving": context.isMoving,
            "speed_kmh": clampedSpeed,
            "local_time": localTime,
            "friendly_location": friendly,
            "nearby_places_count": context.nearbyPlaces.count,
            "timestamp": ISO8601DateFormatter().string(from: context.timestamp)
        ]
        
        return ToolResult(success: true, data: locationData)
    }
    
    private func executeNearbyPlacesTool(parameters: [String: Any]) async -> ToolResult {
        guard let locationManager = locationManager,
              let location = locationManager.currentLocation else {
            return ToolResult(success: false, data: "Location not available")
        }
        
        let category = parameters["category"] as? String ?? "restaurants"
        let radiusString = parameters["radius"] as? String ?? "1000"
        let radius = Double(radiusString) ?? 1000.0
        
        // Simulate finding nearby places (in real implementation, use Maps API)
        let mockPlaces = [
            "Found 5 \(category) within \(Int(radius))m of your location",
            "Search results are personalized based on your current area: \(locationManager.currentAddress ?? "your location")"
        ]
        
        return ToolResult(success: true, data: mockPlaces.joined(separator: ". "))
    }
    
    private func executeDirectionsTool(parameters: [String: Any]) async -> ToolResult {
        guard let destination = parameters["destination"] as? String,
              let transportMode = parameters["transportation_mode"] as? String else {
            return ToolResult(success: false, data: "Missing required parameters")
        }
        
        // Simulate directions (in real implementation, use Maps API)
        let directions = "Route to \(destination) via \(transportMode): Estimated time 15 minutes, distance 2.3 km from your current location."
        
        return ToolResult(success: true, data: directions)
    }
    
    private func executeWeatherTool(parameters: [String: Any]) async -> ToolResult {
        let location = parameters["location"] as? String ?? locationManager?.currentCity ?? "current location"
        let forecastDays = Int(parameters["forecast_days"] as? String ?? "1") ?? 1
        
        // Simulate weather data (in real implementation, use weather API)
        let weather = "Weather for \(location): Currently 22°C, partly cloudy. \(forecastDays)-day forecast shows mild temperatures with occasional rain."
        
        return ToolResult(success: true, data: weather)
    }
    
    private func executeCalendarTool(parameters: [String: Any]) async -> ToolResult {
        guard let timeRange = parameters["time_range"] as? String else {
            return ToolResult(success: false, data: "Missing time range parameter")
        }
        
        // Request calendar access and check events
        let status = EKEventStore.authorizationStatus(for: .event)
        
        if status != .authorized {
            return ToolResult(success: false, data: "Calendar access not authorized. Please enable calendar permissions to check your schedule.")
        }
        
        // Simulate calendar check (in real implementation, query actual calendar)
        let calendar = "Calendar check for \(timeRange): You have 2 meetings scheduled, with free time between 2-4 PM."
        
        return ToolResult(success: true, data: calendar)
    }
    
    private func executeLocalTimeTool(parameters: [String: Any]) async -> ToolResult {
        let city = parameters["city"] as? String
        let currentLocation = locationManager?.currentCity
        
        let targetLocation = city ?? currentLocation ?? "current location"
        let currentTime = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        
        let timeInfo = "Local time in \(targetLocation): \(currentTime) (\(TimeZone.current.identifier))"
        
        return ToolResult(success: true, data: timeInfo)
    }
    
    private func executeTransportationTool(parameters: [String: Any]) async -> ToolResult {
        guard let transportType = parameters["transport_type"] as? String else {
            return ToolResult(success: false, data: "Missing transport type parameter")
        }
        
        let destination = parameters["destination"] as? String
        let destText = destination != nil ? " to \(destination!)" : " from your location"
        
        // Simulate transportation options
        let transport = "Available \(transportType) options\(destText): Uber (3 min), Lyft (5 min), Public bus (Route 12, 8 min walk to stop)"
        
        return ToolResult(success: true, data: transport)
    }
    
    private func executeLocalEventsTool(parameters: [String: Any]) async -> ToolResult {
        guard let eventType = parameters["event_type"] as? String,
              let timeFrame = parameters["time_frame"] as? String else {
            return ToolResult(success: false, data: "Missing required parameters")
        }
        
        // Simulate local events
        let events = "Local \(eventType) events \(timeFrame): Jazz concert at Blue Note (8 PM), Food festival in Central Park (all day), Art gallery opening in SoHo (6 PM)"
        
        return ToolResult(success: true, data: events)
    }
    
    private func executeRestaurantTool(parameters: [String: Any]) async -> ToolResult {
        guard let cuisineType = parameters["cuisine_type"] as? String else {
            return ToolResult(success: false, data: "Missing cuisine type parameter")
        }
        
        let priceRange = parameters["price_range"] as? String ?? "any"
        let diningStyle = parameters["dining_style"] as? String ?? "any"
        
        // Simulate restaurant recommendations
        let restaurants = "Top \(cuisineType) restaurants near you (\(priceRange) price range, \(diningStyle) style): Mario's Italian Bistro (4.5⭐), Sakura Sushi (4.7⭐), Local Harvest Cafe (4.3⭐)"
        
        return ToolResult(success: true, data: restaurants)
    }
    
    private func executeCurrencyTool(parameters: [String: Any]) async -> ToolResult {
        guard let fromCurrency = parameters["from_currency"] as? String,
              let toCurrency = parameters["to_currency"] as? String else {
            return ToolResult(success: false, data: "Missing currency parameters")
        }
        
        let amount = Double(parameters["amount"] as? String ?? "1") ?? 1.0
        
        // Simulate currency conversion (in real implementation, use exchange rate API)
        let rate = 1.08 // Mock rate
        let converted = amount * rate
        
        let conversion = "\(amount) \(fromCurrency) = \(String(format: "%.2f", converted)) \(toCurrency) (Rate: \(rate))"
        
        return ToolResult(success: true, data: conversion)
    }
    
    private func executeTranslationTool(parameters: [String: Any]) async -> ToolResult {
        guard let text = parameters["text"] as? String,
              let targetLanguage = parameters["target_language"] as? String else {
            return ToolResult(success: false, data: "Missing translation parameters")
        }
        
        // Simulate translation (in real implementation, use translation API)
        let translation = "Translation to \(targetLanguage): [Simulated translation of '\(text)']"
        
        return ToolResult(success: true, data: translation)
    }
    
    private func executeSafetyTool(parameters: [String: Any]) async -> ToolResult {
        guard let infoType = parameters["info_type"] as? String else {
            return ToolResult(success: false, data: "Missing safety info type parameter")
        }
        
        let location = parameters["location"] as? String ?? locationManager?.currentCity ?? "current location"
        
        // Simulate safety information
        let safety = "Safety information for \(location) (\(infoType)): Generally safe area, normal precautions recommended. Emergency number: 911"
        
        return ToolResult(success: true, data: safety)
    }
    
    private func executeTravelDocumentsTool(parameters: [String: Any]) async -> ToolResult {
        guard let destinationCountry = parameters["destination_country"] as? String,
              let passportCountry = parameters["passport_country"] as? String,
              let travelPurpose = parameters["travel_purpose"] as? String else {
            return ToolResult(success: false, data: "Missing travel document parameters")
        }
        
        // Simulate travel requirements check
        let requirements = "Travel requirements for \(passportCountry) passport holders visiting \(destinationCountry) for \(travelPurpose): Visa required, 6-month passport validity, return ticket needed"
        
        return ToolResult(success: true, data: requirements)
    }
    
    private func executeEmergencyTool(parameters: [String: Any]) async -> ToolResult {
        guard let emergencyType = parameters["emergency_type"] as? String else {
            return ToolResult(success: false, data: "Missing emergency type parameter")
        }
        
        let location = parameters["location"] as? String ?? locationManager?.currentCity ?? "current location"
        
        // Simulate emergency information
        let emergency = "Emergency contacts for \(location) (\(emergencyType)): Police: 911, Medical: 911, Fire: 911, Nearest hospital: City Medical Center (2.3 km)"
        
        return ToolResult(success: true, data: emergency)
    }
    
    // MARK: - Location Search Tool Implementations
    
    private func executeFindNearbyRestaurants(parameters: [String: Any]) async -> ToolResult {
        guard let searchService = locationSearchService else {
            return ToolResult(success: false, data: "Location search service not available")
        }
        
        let query = parameters["query"] as? String ?? ""
        let cuisine = parameters["cuisine"] as? String ?? ""
        
        let result = await searchService.findNearbyRestaurants(query: query, cuisine: cuisine)
        
        if let error = result.error {
            return ToolResult(success: false, data: "Error finding restaurants: \(error)")
        }
        
        let summary = formatLocationSearchResult(result)
        return ToolResult(success: true, data: summary)
    }
    
    private func executeFindNearbyTransport(parameters: [String: Any]) async -> ToolResult {
        guard let searchService = locationSearchService else {
            return ToolResult(success: false, data: "Location search service not available")
        }
        
        let transportTypeString = parameters["transport_type"] as? String ?? "all"
        let transportType = TransportType(rawValue: transportTypeString) ?? .all
        
        let result = await searchService.findNearbyTransport(type: transportType)
        
        if let error = result.error {
            return ToolResult(success: false, data: "Error finding transportation: \(error)")
        }
        
        let summary = formatLocationSearchResult(result)
        return ToolResult(success: true, data: summary)
    }
    
    private func executeFindNearbyLandmarks(parameters: [String: Any]) async -> ToolResult {
        guard let searchService = locationSearchService else {
            return ToolResult(success: false, data: "Location search service not available")
        }
        
        let query = parameters["query"] as? String ?? ""
        
        let result = await searchService.findNearbyLandmarks(query: query)
        
        if let error = result.error {
            return ToolResult(success: false, data: "Error finding landmarks: \(error)")
        }
        
        let summary = formatLocationSearchResult(result)
        return ToolResult(success: true, data: summary)
    }
    
    private func executeFindNearbyServices(parameters: [String: Any]) async -> ToolResult {
        guard let searchService = locationSearchService else {
            return ToolResult(success: false, data: "Location search service not available")
        }
        
        guard let serviceType = parameters["service_type"] as? String else {
            return ToolResult(success: false, data: "Service type is required")
        }
        
        let query = parameters["query"] as? String ?? ""
        
        let result = await searchService.findNearbyServices(serviceType: serviceType, query: query)
        
        if let error = result.error {
            return ToolResult(success: false, data: "Error finding services: \(error)")
        }
        
        let summary = formatLocationSearchResult(result)
        return ToolResult(success: true, data: summary)
    }
    
    // MARK: - AI and Web Search Tool Implementations
    
    private func executeWebSearch(parameters: [String: Any]) async -> ToolResult {
        guard let searchService = locationSearchService else {
            return ToolResult(success: false, data: "Location search service not available")
        }
        
        guard let query = parameters["query"] as? String else {
            return ToolResult(success: false, data: "Search query is required")
        }
        
        let location = parameters["location"] as? String
        
        // Use general services search for web search functionality
        let searchQuery = location != nil ? "\(query) in \(location!)" : query
        let result = await searchService.findNearbyServices(serviceType: "general search", query: searchQuery)
        
        if let error = result.error {
            return ToolResult(success: false, data: "Web search error: \(error)")
        }
        
        let summary = formatLocationSearchResult(result)
        return ToolResult(success: true, data: summary)
    }
    
    private func executeAIResponse(parameters: [String: Any]) async -> ToolResult {
        guard let openAIChatService = openAIChatService else {
            return ToolResult(success: false, data: "OpenAI Chat service not available")
        }
        
        guard let prompt = parameters["prompt"] as? String else {
            return ToolResult(success: false, data: "Prompt is required")
        }
        
        let context = parameters["context"] as? String
        
        // Build enhanced prompt with location context if available
        let locationContext = locationManager?.getCurrentLocationContext()
        let enhancedPrompt = buildEnhancedPrompt(prompt: prompt, context: context, locationContext: locationContext)
        
        do {
            let response = try await openAIChatService.send(message: enhancedPrompt, conversation: [])
            return ToolResult(success: true, data: response)
        } catch {
            return ToolResult(success: false, data: "AI response error: \(error.localizedDescription)")
        }
    }
    
    private func buildEnhancedPrompt(prompt: String, context: String?, locationContext: LocationContext?) -> String {
        var enhancedPrompt = prompt
        
        if let context = context, !context.isEmpty {
            enhancedPrompt += "\n\nAdditional context: \(context)"
        }
        
        if let locationContext = locationContext {
            enhancedPrompt += "\n\nCurrent location context:"
            enhancedPrompt += "\n- Location: \(locationContext.address ?? "Unknown")"
            enhancedPrompt += "\n- City: \(locationContext.city ?? "Unknown")"
            enhancedPrompt += "\n- Country: \(locationContext.country ?? "Unknown")"
            enhancedPrompt += "\n- Movement: \(locationContext.isMoving ? "Moving (\(String(format: "%.1f", locationContext.speed)) km/h)" : "Stationary")"
            
            if !locationContext.nearbyPlaces.isEmpty {
                enhancedPrompt += "\n- Nearby places: \(locationContext.nearbyPlaces.map { $0.name }.joined(separator: ", "))"
            }
        }
        
        return enhancedPrompt
    }
    
    // MARK: - Helper Methods
    
    private func formatLocationSearchResult(_ result: LocationSearchResult) -> String {
        var formatted = ""
        
        if let summary = result.summary, !summary.isEmpty {
            formatted += summary + "\n\n"
        }
        
        if result.results.isEmpty {
            formatted += "No results found for \(result.query) near \(result.locationContext.address)"
        } else {
            formatted += "Found \(result.results.count) \(result.type.displayName.lowercased()) near \(result.locationContext.city):\n\n"
            
            for (index, place) in result.results.enumerated() {
                formatted += "\(index + 1). **\(place.name)**\n"
                formatted += "   📍 \(place.address)\n"
                
                if let description = place.description {
                    formatted += "   ℹ️ \(description)\n"
                }
                
                if let rating = place.rating {
                    formatted += "   ⭐ Rating: \(String(format: "%.1f", rating))\n"
                }
                
                if let url = place.url {
                    formatted += "   🔗 \(url.absoluteString)\n"
                }
                
                formatted += "\n"
            }
        }
        
        return formatted
    }
}

// MARK: - Supporting Types

struct ToolResult {
    let success: Bool
    let data: Any
}

// MARK: - Tool Call Events

struct ToolCallEvent: Codable {
    let type: String = "conversation.item.create"
    let eventId: String
    let item: ToolCallItem
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case item
    }
}

struct ToolCallItem: Codable {
    let type: String = "function_call"
    let name: String
    let callId: String
    let arguments: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case name
        case callId = "call_id"
        case arguments
    }
}

struct ToolResponseEvent: Codable {
    let type: String = "conversation.item.create"
    let eventId: String
    let item: ToolResponseItem
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case item
    }
}

struct ToolResponseItem: Codable {
    let type: String = "function_call_output"
    let callId: String
    let output: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case output
    }
} 