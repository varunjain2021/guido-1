import Foundation
import CoreLocation

@MainActor
class GooglePlacesRoutesService: ObservableObject {
    public struct PlaceCandidate {
        public let name: String
        public let formattedAddress: String
        public let latitude: Double
        public let longitude: Double
        public let distanceMeters: Int
        public let isOpen: Bool?
        public let businessStatus: String?
        public let rating: Double?
        public let userRatingCount: Int?
        public let phoneNumber: String?
        public let resourceName: String?          // Google Places resource name (e.g., "places/ChIJ...")
        public let googleMapsUri: String?         // Shareable Google Maps URL
        
        public init(name: String, formattedAddress: String, latitude: Double, longitude: Double, distanceMeters: Int, isOpen: Bool? = nil, businessStatus: String? = nil, rating: Double? = nil, userRatingCount: Int? = nil, phoneNumber: String? = nil, resourceName: String? = nil, googleMapsUri: String? = nil) {
            self.name = name
            self.formattedAddress = formattedAddress
            self.latitude = latitude
            self.longitude = longitude
            self.distanceMeters = distanceMeters
            self.isOpen = isOpen
            self.businessStatus = businessStatus
            self.rating = rating
            self.userRatingCount = userRatingCount
            self.phoneNumber = phoneNumber
            self.resourceName = resourceName
            self.googleMapsUri = googleMapsUri
        }
        
        // Helper to determine if this is a reliable business for LLM decision making
        public var hasBusinessDetails: Bool {
            return businessStatus != nil || rating != nil || phoneNumber != nil
        }
    }

    public struct RouteSummary {
        let destination: String
        let travelMode: String
        let distanceMeters: Int
        let durationSeconds: Int
        let summaryText: String
        let stepInstructions: [String]
    }
    private let apiKey: String
    private let locationManager: LocationManager
    private let session: URLSession = .shared
    
    init(apiKey: String, locationManager: LocationManager) {
        self.apiKey = apiKey
        self.locationManager = locationManager
    }

    // MARK: - URL Builders

    func buildDirectionsURLs(to destinationAddress: String, mode: String) -> (web: URL, app: URL?)? {
        guard let encodedDest = destinationAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("[Directions] ❌ Failed to percent-encode destination: \(destinationAddress)")
            return nil
        }

        let travelModeQuery = mapModeForURL(mode)
        let webURLString = "https://www.google.com/maps/dir/?api=1&destination=\(encodedDest)&travelmode=\(travelModeQuery)"
        let appURLString = "comgooglemaps://?daddr=\(encodedDest)&directionsmode=\(travelModeQuery)"

        guard let webURL = URL(string: webURLString) else {
            print("[Directions] ❌ Failed to build web directions URL from: \(webURLString)")
            return nil
        }

        let appURL = URL(string: appURLString)

        print("[Directions] ✅ Built Google Maps URLs for destination='\(destinationAddress)' mode='\(travelModeQuery)'")
        print("[Directions] 🌐 Web URL: \(webURL.absoluteString)")
        if let appURL {
            print("[Directions] 📱 App URL: \(appURL.absoluteString)")
        } else {
            print("[Directions] ⚠️ App URL could not be created")
        }

        return (web: webURL, app: appURL)
    }
    
    // MARK: - Places (Nearby by category)
    
    func searchNearby(category: String, radiusMeters: Int) async throws -> String {
        guard let location = locationManager.currentLocation else {
            throw NSError(domain: "GooglePlacesRoutesService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location not available"])
        }
        let includedTypes = mapCategoryToIncludedTypes(category)
        let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.currentOpeningHours.openNow,places.googleMapsUri", forHTTPHeaderField: "X-Goog-FieldMask")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "locationRestriction": [
                "circle": [
                    "center": [
                        "latitude": location.coordinate.latitude,
                        "longitude": location.coordinate.longitude
                    ],
                    "radius": radiusMeters
                ]
            ],
            "includedTypes": includedTypes,
            "maxResultCount": 10,
            "rankPreference": "DISTANCE",
            "openNow": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GooglePlacesRoutesService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Places error: \(msg)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "GooglePlacesRoutesService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid Places response"])
        }
        
        return summarizePlaces(json: json, category: category)
    }
    
    // MARK: - Places (Text Search by name)
    
    func searchText(query: String, maxResults: Int = 5) async throws -> [PlaceCandidate] {
        guard let origin = locationManager.currentLocation else {
            throw NSError(domain: "GooglePlacesRoutesService", code: 7, userInfo: [NSLocalizedDescriptionKey: "Location not available"])
        }
        print("🔍 [GooglePlacesService] Text search for '\(query)' from location: \(origin.coordinate.latitude), \(origin.coordinate.longitude)")
        let url = URL(string: "https://places.googleapis.com/v1/places:searchText")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.name,places.googleMapsUri,places.displayName,places.formattedAddress,places.location,places.currentOpeningHours.openNow,places.businessStatus,places.rating,places.userRatingCount,places.nationalPhoneNumber,places.internationalPhoneNumber", forHTTPHeaderField: "X-Goog-FieldMask")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "textQuery": query,
            "maxResultCount": maxResults,
            "rankPreference": "DISTANCE",
            "locationBias": [
                "circle": [
                    "center": [
                        "latitude": origin.coordinate.latitude,
                        "longitude": origin.coordinate.longitude
                    ],
                    "radius": 3000
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        let responseStr = String(data: data, encoding: .utf8) ?? "No response body"
        guard let http = response as? HTTPURLResponse else {
            print("❌ [GooglePlacesService] Invalid HTTP response for text search")
            throw NSError(domain: "GooglePlacesRoutesService", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        print("📡 [GooglePlacesService] Text search response status: \(http.statusCode)")
        guard http.statusCode == 200 else {
            print("❌ [GooglePlacesService] Text search failed with status \(http.statusCode): \(responseStr)")
            throw NSError(domain: "GooglePlacesRoutesService", code: 8, userInfo: [NSLocalizedDescriptionKey: "Places text search error (\(http.statusCode)): \(responseStr)"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "GooglePlacesRoutesService", code: 9, userInfo: [NSLocalizedDescriptionKey: "Invalid Places text search response"])
        }
        let places = (json["places"] as? [[String: Any]]) ?? []
        print("📍 [GooglePlacesService] Found \(places.count) places in response")
        let candidates: [PlaceCandidate] = places.compactMap { place in
            guard let loc = place["location"] as? [String: Any],
                  let lat = loc["latitude"] as? Double,
                  let lng = loc["longitude"] as? Double else { 
                print("⚠️ [GooglePlacesService] Skipping place with invalid location data")
                return nil 
            }
            let resourceName = place["name"] as? String
            let gmapsUri = place["googleMapsUri"] as? String
            let nameText = ((place["displayName"] as? [String: Any])?["text"] as? String) ?? "Unknown"
            let addr = (place["formattedAddress"] as? String) ?? ""
            let dist = computeDistanceMeters(from: origin.coordinate, to: CLLocationCoordinate2D(latitude: lat, longitude: lng))
            
            // Extract enhanced business data for LLM intelligence
            let isOpen = (place["currentOpeningHours"] as? [String: Any])?["openNow"] as? Bool
            let businessStatus = place["businessStatus"] as? String
            let rating = place["rating"] as? Double
            let userRatingCount = place["userRatingCount"] as? Int
            let phoneNumber = (place["nationalPhoneNumber"] as? String) ?? (place["internationalPhoneNumber"] as? String)
            
            print("📍 [GooglePlacesService] Found: \(nameText) at \(addr), \(dist)m away")
            print("   - Business Status: \(businessStatus ?? "unknown"), Open: \(isOpen?.description ?? "unknown"), Rating: \(rating?.description ?? "none")")
            
            return PlaceCandidate(
                name: nameText, 
                formattedAddress: addr, 
                latitude: lat, 
                longitude: lng, 
                distanceMeters: dist,
                isOpen: isOpen,
                businessStatus: businessStatus,
                rating: rating,
                userRatingCount: userRatingCount,
                phoneNumber: phoneNumber,
                resourceName: resourceName,
                googleMapsUri: gmapsUri
            )
        }
        print("✅ [GooglePlacesService] Returning \(candidates.count) valid candidates")
        return candidates
    }
    
    func buildConfirmationSummary(for candidate: PlaceCandidate) -> String {
        let km = Double(candidate.distanceMeters) / 1000.0
        let approxWalkMins = Int(round(Double(candidate.distanceMeters) / 80.0)) // ~80 m/min walking
        return "I found \(candidate.name) at \(candidate.formattedAddress), about \(String(format: "%.1f", km)) km away (~\(approxWalkMins) min walk). Is this the right place, and how are you getting there (walking/driving/transit/cycling)?"
    }
    
    // MARK: - Directions via Routes API
    
    func computeRoute(to destinationAddress: String, mode: String) async throws -> RouteSummary {
        guard let originLocation = locationManager.currentLocation else {
            throw NSError(domain: "GooglePlacesRoutesService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Location not available"])
        }
        let travelMode = mapMode(mode)
        let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("routes.distanceMeters,routes.duration,routes.legs.steps.navigationInstruction,routes.legs.steps.distanceMeters", forHTTPHeaderField: "X-Goog-FieldMask")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "origin": [
                "location": [
                    "latLng": [
                        "latitude": originLocation.coordinate.latitude,
                        "longitude": originLocation.coordinate.longitude
                    ]
                ]
            ],
            // Destination address must be a scalar string per Routes API
            "destination": [
                "address": destinationAddress
            ],
            "travelMode": travelMode
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GooglePlacesRoutesService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Routes error: \(msg)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "GooglePlacesRoutesService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid Routes response"])
        }
        
        return try summarizeRoute(json: json, mode: mode, destination: destinationAddress)
    }
    
    // MARK: - Helpers
    
    private func mapCategoryToIncludedTypes(_ category: String) -> [String] {
        switch category {
        case "restaurants": return ["restaurant", "cafe"]
        case "attractions": return ["tourist_attraction", "museum", "park"]
        case "hotels": return ["lodging"]
        case "transportation": return ["subway_station", "bus_station", "train_station", "taxi_stand", "parking"]
        case "shopping": return ["shopping_mall", "store"]
        case "entertainment": return ["movie_theater", "night_club", "bowling_alley", "amusement_park"]
        case "medical": return ["hospital", "pharmacy"]
        case "gas_stations": return ["gas_station"]
        default: return [category]
        }
    }
    
    private func mapMode(_ mode: String) -> String {
        switch mode {
        case "walking": return "WALK"
        case "driving": return "DRIVE"
        case "transit": return "TRANSIT"
        case "cycling": return "BICYCLE"
        default: return "DRIVE"
        }
    }

    private func mapModeForURL(_ mode: String) -> String {
        switch mode {
        case "walking": return "walking"
        case "driving": return "driving"
        case "transit": return "transit"
        case "cycling": return "bicycling"
        default: return "driving"
        }
    }
    
    private func summarizePlaces(json: [String: Any], category: String) -> String {
        let places = (json["places"] as? [[String: Any]]) ?? []
        if places.isEmpty {
            return "No \(category) found nearby"
        }
        // Sort by distance from current location
        let sorted: [[String: Any]] = places.sorted { a, b in
            let aLoc = ((a["location"] as? [String: Any])?["latLng"] as? [String: Any])
            let bLoc = ((b["location"] as? [String: Any])?["latLng"] as? [String: Any])
            let aLat = aLoc?["latitude"] as? Double ?? 0
            let aLng = aLoc?["longitude"] as? Double ?? 0
            let bLat = bLoc?["latitude"] as? Double ?? 0
            let bLng = bLoc?["longitude"] as? Double ?? 0
            guard let origin = locationManager.currentLocation else { return false }
            let aDist = computeDistanceMeters(from: origin.coordinate, to: CLLocationCoordinate2D(latitude: aLat, longitude: aLng))
            let bDist = computeDistanceMeters(from: origin.coordinate, to: CLLocationCoordinate2D(latitude: bLat, longitude: bLng))
            return aDist < bDist
        }
        let lines: [String] = sorted.prefix(5).compactMap { place in
            let name = ((place["displayName"] as? [String: Any])?["text"] as? String) ?? "Unknown"
            let addr = (place["formattedAddress"] as? String) ?? ""
            let loc = ((place["location"] as? [String: Any])?["latLng"] as? [String: Any])
            let lat = loc?["latitude"] as? Double ?? 0
            let lng = loc?["longitude"] as? Double ?? 0
            let openNow = ((place["currentOpeningHours"] as? [String: Any])?["openNow"] as? Bool)
            guard let origin = locationManager.currentLocation else { return nil }
            let meters = computeDistanceMeters(from: origin.coordinate, to: CLLocationCoordinate2D(latitude: lat, longitude: lng))
            let distText = formatDistance(meters: meters)
            let walkMins = Int(round(Double(meters) / 80.0))
            let openText = openNow == true ? " (open now)" : ""
            return "- \(name) — \(addr) — \(distText) (~\(walkMins) min walk)\(openText)"
        }
        return "Found \(places.count) \(category) nearby:\n" + lines.joined(separator: "\n")
    }
    
    private func summarizeRoute(json: [String: Any], mode: String, destination: String) throws -> RouteSummary {
        guard let routes = json["routes"] as? [[String: Any]], let first = routes.first else {
            throw NSError(domain: "GooglePlacesRoutesService", code: 7, userInfo: [NSLocalizedDescriptionKey: "No route found to \(destination)"])
        }
        let distance = first["distanceMeters"] as? Int ?? 0
        let durationISO = first["duration"] as? String ?? ""
        let distanceText = formatDistance(meters: distance)
        let durationSeconds = parseDurationSeconds(iso8601Seconds: durationISO)
        let durationText = formatDuration(iso8601Seconds: durationISO)
        let summaryText = "Route to \(destination) via \(mode): \(distanceText), \(durationText)"
        var stepInstructions: [String] = []
        if let legs = first["legs"] as? [[String: Any]], let leg = legs.first, let steps = leg["steps"] as? [[String: Any]] {
            stepInstructions = steps.compactMap { step in
                (step["navigationInstruction"] as? [String: Any])?["instructions"] as? String
            }
        }
        let tail = Array(stepInstructions.suffix(3))
        return RouteSummary(
            destination: destination,
            travelMode: mode,
            distanceMeters: distance,
            durationSeconds: durationSeconds,
            summaryText: summaryText,
            stepInstructions: tail
        )
    }

    private func formatDistance(meters: Int) -> String {
        if meters < 1000 {
            return "\(meters) m"
        }
        let km = Double(meters) / 1000.0
        return String(format: "%.1f km", km)
    }

    private func formatDuration(iso8601Seconds: String) -> String {
        // Duration is typically like "1873s"
        if let seconds = Int(iso8601Seconds.replacingOccurrences(of: "s", with: "")) {
            let minutes = Int(round(Double(seconds) / 60.0))
            return "~\(minutes) min"
        }
        return iso8601Seconds
    }

    private func parseDurationSeconds(iso8601Seconds: String) -> Int {
        return Int(iso8601Seconds.replacingOccurrences(of: "s", with: "")) ?? 0
    }
    
    private func computeDistanceMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Int {
        let earthRadius = 6371000.0
        let dLat = (to.latitude - from.latitude) * .pi / 180.0
        let dLon = (to.longitude - from.longitude) * .pi / 180.0
        let a = sin(dLat/2) * sin(dLat/2) + cos(from.latitude * .pi / 180.0) * cos(to.latitude * .pi / 180.0) * sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return Int(earthRadius * c)
    }
}

