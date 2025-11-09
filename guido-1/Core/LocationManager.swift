//
//  LocationManager.swift
//  guido-1
//
//  Created by Varun Jain on 7/27/25.
//

import Foundation
import CoreLocation
import MapKit
import Combine
import Contacts

@MainActor
class LocationManager: NSObject, ObservableObject {
    @Published var currentLocation: CLLocation?
    @Published var currentAddress: String?
    @Published var isLocationAuthorized = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var nearbyPlaces: [NearbyPlace] = []
    @Published var currentCity: String?
    @Published var currentCountry: String?
    @Published var isMoving = false
    @Published var averageSpeed: Double = 0.0 // km/h
    @Published var shouldTriggerProactiveGuide = false
    @Published var currentNeighborhood: String?
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationHistory: [LocationReading] = []
    private var movementTimer: Timer?
    // Feature flag to disable MapKit nearby search
    private let nearbyPlacesEnabled: Bool = false
    
    // Proactive guidance tracking
    private var lastProactiveLocationTime: Date?
    private let proactiveLocationThreshold: TimeInterval = 300 // 5 minutes
    private let proactiveDistanceThreshold: CLLocationDistance = 500 // 500 meters
    
    // Location tracking configuration
    private let significantLocationThreshold: CLLocationDistance = 100 // meters
    private let speedCalculationWindow = 5 // number of recent locations to consider
    private let movementSpeedThreshold: Double = 1.0 // km/h to consider "moving"
    
    override init() {
        super.init()
        setupLocationManager()
        startMovementTracking()
        print("🗺️ LocationManager initialized")
    }
    
    deinit {
        Task { @MainActor in
            stopMovementTracking()
        }
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
        
        authorizationStatus = locationManager.authorizationStatus
        updateAuthorizationState()
    }
    
    private func updateAuthorizationState() {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isLocationAuthorized = true
            startLocationUpdates()
        case .denied, .restricted:
            isLocationAuthorized = false
            print("❌ Location access denied")
        case .notDetermined:
            isLocationAuthorized = false
        @unknown default:
            isLocationAuthorized = false
        }
    }
    
    // MARK: - Public Methods
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startLocationUpdates() {
        guard isLocationAuthorized else {
            requestLocationPermission()
            return
        }
        
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        print("📍 Started location tracking")
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        print("📍 Stopped location tracking")
    }
    
    // MARK: - Movement Tracking
    
    private func startMovementTracking() {
        movementTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.analyzeMovement()
            }
        }
    }
    
    private func stopMovementTracking() {
        movementTimer?.invalidate()
        movementTimer = nil
    }
    
    private func analyzeMovement() {
        guard locationHistory.count >= 2 else {
            isMoving = false
            averageSpeed = 0.0
            return
        }
        
        // Calculate speed over recent locations
        let recentLocations = Array(locationHistory.suffix(speedCalculationWindow))
        guard recentLocations.count >= 2 else { return }
        
        var totalDistance: CLLocationDistance = 0
        var totalTime: TimeInterval = 0
        
        for i in 1..<recentLocations.count {
            let previousLocation = recentLocations[i-1]
            let currentLocation = recentLocations[i]
            
            let distance = previousLocation.location.distance(from: currentLocation.location)
            let time = currentLocation.timestamp.timeIntervalSince(previousLocation.timestamp)
            
            totalDistance += distance
            totalTime += time
        }
        
        // Calculate average speed in km/h
        if totalTime > 0 {
            averageSpeed = (totalDistance / totalTime) * 3.6 // Convert m/s to km/h
            isMoving = averageSpeed > movementSpeedThreshold
            
            print("🚶‍♂️ Movement: \(isMoving ? "Moving" : "Stationary") - Speed: \(String(format: "%.1f", averageSpeed)) km/h")
        }
    }
    
    // MARK: - Location Context
    
    func getCurrentLocationContext() -> LocationContext {
        return LocationContext(
            location: currentLocation,
            address: currentAddress,
            city: currentCity,
            country: currentCountry,
            neighborhood: currentNeighborhood,
            nearbyPlaces: nearbyPlaces,
            isMoving: isMoving,
            speed: averageSpeed,
            timestamp: Date()
        )
    }
    
    // MARK: - Proactive Guidance
    
    func getCurrentLocationDescription() -> String {
        var description = "Currently at an unknown location"
        
        if let address = currentAddress {
            description = "Currently at \(address)"
        } else if let city = currentCity {
            description = "Currently in \(city)"
        } else if let country = currentCountry {
            description = "Currently in \(country)"
        }
        
        if isMoving {
            description += ", moving at \(String(format: "%.1f", averageSpeed)) km/h"
        } else {
            description += ", stationary"
        }
        
        if !nearbyPlaces.isEmpty {
            let nearbyNames = nearbyPlaces.prefix(3).map { $0.name }.joined(separator: ", ")
            description += ". Nearby places: \(nearbyNames)"
        }
        
        return description
    }
    
    func getProactivePrompt() -> String {
        let locationDescription = getCurrentLocationDescription()
        let timeOfDay = getTimeOfDayDescription()
        
        return """
        Based on the user's current location and context, provide a helpful, proactive suggestion.
        
        Location: \(locationDescription)
        Time: \(timeOfDay)
        Movement: \(isMoving ? "Moving" : "Stationary")
        
        Provide a brief, helpful suggestion (1-2 sentences) that could be useful given their current context. 
        Consider things like nearby places, time of day, movement status, and general travel assistance.
        Keep it conversational and natural.
        """
    }
    
    func acknowledgeProactiveTrigger() {
        shouldTriggerProactiveGuide = false
        lastProactiveLocationTime = Date()
    }
    
    private func getTimeOfDayDescription() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 6..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        case 17..<21:
            return "Evening"
        default:
            return "Night"
        }
    }
    
    private func checkForProactiveOpportunity() {
        guard let currentLocation = currentLocation else { return }
        
        // Don't trigger if we recently triggered
        if let lastTime = lastProactiveLocationTime,
           Date().timeIntervalSince(lastTime) < proactiveLocationThreshold {
            return
        }
        
        // Check if user has moved a significant distance
        if let lastLocation = locationHistory.dropLast().last?.location {
            let distance = currentLocation.distance(from: lastLocation)
            
            if distance > proactiveDistanceThreshold {
                shouldTriggerProactiveGuide = true
            }
        } else if lastProactiveLocationTime == nil {
            // First time getting location
            shouldTriggerProactiveGuide = true
        }
    }
    
    // MARK: - Nearby Places
    
    private func findNearbyPlaces() {
        // Disabled by feature flag
        guard nearbyPlacesEnabled else { return }
        guard let location = currentLocation else { return }
        
        // Search for nearby points of interest
        let request = MKLocalSearch.Request()
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
        
        // Prefer POI filter over a long comma-separated natural language query (prevents MKError -8)
        if #available(iOS 14.0, *) {
            var categories: [MKPointOfInterestCategory] = [
                .restaurant,
                .cafe,
                .museum,
                .park,
                .hotel
            ]
            // Public transport category (if available)
            categories.append(.publicTransport)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
            request.resultTypes = .pointOfInterest
        } else {
            // Fallback simple query for older OS versions
            request.naturalLanguageQuery = "restaurants"
        }
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            Task { @MainActor in
                if let error = error {
                    // Handle MKErrorDomain (e.g., -8) by falling back to multiple simpler searches
                    if (error as NSError).domain == MKErrorDomain {
                        let queries = ["restaurants", "attractions", "hotels", "transportation"]
                        self?.fallbackNearbyPlacesSearch(queries: queries, around: location)
                    } else {
                        print("❌ Failed to find nearby places: \(error)")
                    }
                    return
                }
                
                guard let response = response else { return }
                
                self?.nearbyPlaces = response.mapItems.prefix(10).map { item in
                    NearbyPlace(
                        name: item.name ?? "Unknown",
                        category: item.pointOfInterestCategory?.rawValue ?? "Unknown",
                        location: CLLocation(
                            latitude: item.placemark.coordinate.latitude,
                            longitude: item.placemark.coordinate.longitude
                        ),
                        distance: location.distance(from: CLLocation(
                            latitude: item.placemark.coordinate.latitude,
                            longitude: item.placemark.coordinate.longitude
                        ))
                    )
                }
                
                print("📍 Found \(self?.nearbyPlaces.count ?? 0) nearby places")
            }
        }
    }
    
    private func fallbackNearbyPlacesSearch(queries: [String], around location: CLLocation) {
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
        
        let group = DispatchGroup()
        var collected: [MKMapItem] = []
        
        for q in queries {
            group.enter()
            let r = MKLocalSearch.Request()
            r.naturalLanguageQuery = q
            r.region = region
            let s = MKLocalSearch(request: r)
            s.start { response, _ in
                if let items = response?.mapItems {
                    collected.append(contentsOf: items)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            // Deduplicate by coordinate+name and limit
            var seen = Set<String>()
            let unique = collected.filter { item in
                let key = "\(item.name ?? "Unknown")|\(item.placemark.coordinate.latitude),\(item.placemark.coordinate.longitude)"
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }
            
            self?.nearbyPlaces = unique.prefix(10).map { item in
                NearbyPlace(
                    name: item.name ?? "Unknown",
                    category: item.pointOfInterestCategory?.rawValue ?? "Unknown",
                    location: CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    ),
                    distance: location.distance(from: CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    ))
                )
            }
            print("📍 Fallback found \(self?.nearbyPlaces.count ?? 0) nearby places")
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            
            // Update current location
            currentLocation = location
            
            // Add to location history
            let reading = LocationReading(location: location, timestamp: Date())
            locationHistory.append(reading)
            
            // Keep history manageable
            if locationHistory.count > 20 {
                locationHistory.removeFirst(locationHistory.count - 20)
            }
            
            // Reverse geocode for address information
            reverseGeocodeLocation(location)
            
            // Find nearby places if location changed significantly
            if shouldUpdateNearbyPlaces(newLocation: location) {
                findNearbyPlaces()
            }
            
            // Check for proactive guidance opportunities
            checkForProactiveOpportunity()
            
            print("📍 Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            authorizationStatus = status
            updateAuthorizationState()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager error: \(error)")
    }
    
    private func shouldUpdateNearbyPlaces(newLocation: CLLocation) -> Bool {
        guard let lastLocation = locationHistory.dropLast().last?.location else { return true }
        return newLocation.distance(from: lastLocation) > significantLocationThreshold
    }
    
    private func reverseGeocodeLocation(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            Task { @MainActor in
                if let error = error {
                    print("❌ Reverse geocoding error: \(error)")
                    return
                }
                
                guard let placemark = placemarks?.first else { return }
                
                // Prefer Contacts formatter for a complete address when available
                if let postal = placemark.postalAddress {
                    let formatter = CNPostalAddressFormatter()
                    var formatted = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
                    formatted = formatted.replacingOccurrences(of: "\n", with: ", ")
                    self?.currentAddress = formatted
                    self?.currentCity = postal.city
                    self?.currentCountry = postal.country
                    if !postal.subLocality.isEmpty { self?.currentNeighborhood = postal.subLocality }
                } else {
                    // Fallback: assemble from available components
                    var addressComponents: [String] = []
                    if let subThoroughfare = placemark.subThoroughfare { addressComponents.append(subThoroughfare) }
                    if let thoroughfare = placemark.thoroughfare { addressComponents.append(thoroughfare) }
                    if let subLocality = placemark.subLocality { addressComponents.append(subLocality); self?.currentNeighborhood = subLocality }
                    if let locality = placemark.locality { addressComponents.append(locality); self?.currentCity = locality }
                    if let administrativeArea = placemark.administrativeArea { addressComponents.append(administrativeArea) }
                    if let postalCode = placemark.postalCode { addressComponents.append(postalCode) }
                    self?.currentCountry = placemark.country
                    if addressComponents.isEmpty, let name = placemark.name {
                        addressComponents.append(name)
                    }
                    self?.currentAddress = addressComponents.joined(separator: ", ")
                }
                
                print("📍 Address: \(self?.currentAddress ?? "Unknown")")
            }
        }
    }

    // MARK: - Friendly Formatting
    func friendlyLocationString() -> String {
        var parts: [String] = []
        if let address = currentAddress { parts.append(address) }
        if let neighborhood = currentNeighborhood, !neighborhood.isEmpty {
            if parts.isEmpty || !(parts.joined(separator: ", ").contains(neighborhood)) {
                parts.append(neighborhood)
            }
        }
        if let city = currentCity { parts.append(city) }
        if let country = currentCountry { parts.append(country) }
        return parts.isEmpty ? "Unknown location" : parts.joined(separator: ", ")
    }
}

// MARK: - Supporting Types

struct LocationReading {
    let location: CLLocation
    let timestamp: Date
}

struct NearbyPlace {
    let name: String
    let category: String
    let location: CLLocation
    let distance: CLLocationDistance
}

struct LocationContext {
    let location: CLLocation?
    let address: String?
    let city: String?
    let country: String?
    let neighborhood: String?
    let nearbyPlaces: [NearbyPlace]
    let isMoving: Bool
    let speed: Double
    let timestamp: Date
}

// MARK: - Missing MapKit Import
import MapKit 