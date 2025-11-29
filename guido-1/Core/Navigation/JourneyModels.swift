//
//  JourneyModels.swift
//  guido-1
//
//  Data models for turn-by-turn navigation journeys
//

import Foundation
import CoreLocation

// MARK: - Journey

/// Represents a complete navigation journey from origin to destination
struct NavigationJourney: Identifiable, Codable {
    let id: UUID
    var userId: String?
    var userEmail: String?
    var sessionId: String?
    
    // Origin
    var originAddress: String?
    var originLat: Double?
    var originLng: Double?
    
    // Destination
    let destinationAddress: String
    let destinationLat: Double
    let destinationLng: Double
    var destinationName: String?
    
    // Settings
    let travelMode: TravelMode
    
    // Timing
    let startedAt: Date
    var endedAt: Date?
    
    // Status
    var completed: Bool
    var cancelled: Bool
    
    // Route summary
    var totalDistanceMeters: Int?
    var totalTimeSeconds: Int?
    var initialStepsCount: Int?
    
    // Telemetry
    var checkpoints: [NavigationCheckpoint]
    var breadcrumbs: [NavigationBreadcrumb]
    
    // Rerouting
    var rerouteCount: Int
    var lastRerouteAt: Date?
    
    init(
        destinationAddress: String,
        destinationLat: Double,
        destinationLng: Double,
        destinationName: String? = nil,
        travelMode: TravelMode = .driving,
        userId: String? = nil,
        userEmail: String? = nil,
        sessionId: String? = nil
    ) {
        self.id = UUID()
        self.userId = userId
        self.userEmail = userEmail
        self.sessionId = sessionId
        self.destinationAddress = destinationAddress
        self.destinationLat = destinationLat
        self.destinationLng = destinationLng
        self.destinationName = destinationName
        self.travelMode = travelMode
        self.startedAt = Date()
        self.completed = false
        self.cancelled = false
        self.checkpoints = []
        self.breadcrumbs = []
        self.rerouteCount = 0
    }
    
    // MARK: - Computed Properties
    
    var isActive: Bool {
        return !completed && !cancelled && endedAt == nil
    }
    
    var destinationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: destinationLat, longitude: destinationLng)
    }
    
    var originCoordinate: CLLocationCoordinate2D? {
        guard let lat = originLat, let lng = originLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    var formattedDistance: String {
        guard let meters = totalDistanceMeters else { return "Unknown" }
        if meters >= 1609 { // 1 mile in meters
            let miles = Double(meters) / 1609.34
            return String(format: "%.1f mi", miles)
        } else {
            let feet = Double(meters) * 3.28084
            return String(format: "%.0f ft", feet)
        }
    }
    
    var formattedTime: String {
        guard let seconds = totalTimeSeconds else { return "Unknown" }
        let minutes = seconds / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(minutes) min"
        }
    }
    
    var durationSeconds: Int? {
        guard let end = endedAt else { return nil }
        return Int(end.timeIntervalSince(startedAt))
    }
    
    // MARK: - Mutating Methods
    
    mutating func setOrigin(address: String?, lat: Double, lng: Double) {
        self.originAddress = address
        self.originLat = lat
        self.originLng = lng
    }
    
    mutating func setRouteSummary(distanceMeters: Int, timeSeconds: Int, stepsCount: Int) {
        self.totalDistanceMeters = distanceMeters
        self.totalTimeSeconds = timeSeconds
        self.initialStepsCount = stepsCount
    }
    
    mutating func addCheckpoint(_ checkpoint: NavigationCheckpoint) {
        checkpoints.append(checkpoint)
    }
    
    mutating func addBreadcrumb(_ breadcrumb: NavigationBreadcrumb) {
        breadcrumbs.append(breadcrumb)
    }
    
    mutating func recordReroute() {
        rerouteCount += 1
        lastRerouteAt = Date()
    }
    
    mutating func markCompleted() {
        completed = true
        endedAt = Date()
    }
    
    mutating func markCancelled() {
        cancelled = true
        endedAt = Date()
    }
}

// MARK: - Travel Mode

enum TravelMode: String, Codable, CaseIterable {
    case driving
    case walking
    case transit
    case cycling
    
    var displayName: String {
        switch self {
        case .driving: return "Driving"
        case .walking: return "Walking"
        case .transit: return "Transit"
        case .cycling: return "Cycling"
        }
    }
    
    var googleMapsMode: String {
        return rawValue
    }
}

// MARK: - Checkpoint

/// A navigation step/turn that the user has passed through
struct NavigationCheckpoint: Codable, Identifiable {
    let id: UUID
    let stepIndex: Int
    let instruction: String
    let roadName: String?
    let maneuver: String
    let arrivedAt: Date
    let latitude: Double
    let longitude: Double
    let distanceFromPreviousMeters: Int?
    
    init(
        stepIndex: Int,
        instruction: String,
        roadName: String?,
        maneuver: String,
        latitude: Double,
        longitude: Double,
        distanceFromPreviousMeters: Int? = nil
    ) {
        self.id = UUID()
        self.stepIndex = stepIndex
        self.instruction = instruction
        self.roadName = roadName
        self.maneuver = maneuver
        self.arrivedAt = Date()
        self.latitude = latitude
        self.longitude = longitude
        self.distanceFromPreviousMeters = distanceFromPreviousMeters
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Breadcrumb

/// A location sample recorded during navigation for telemetry
struct NavigationBreadcrumb: Codable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let speedMps: Double? // meters per second
    let accuracyMeters: Double?
    let heading: Double? // degrees from north
    
    init(location: CLLocation) {
        self.id = UUID()
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.timestamp = location.timestamp
        self.speedMps = location.speed >= 0 ? location.speed : nil
        self.accuracyMeters = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        self.heading = location.course >= 0 ? location.course : nil
    }
    
    init(latitude: Double, longitude: Double, speedMps: Double? = nil, accuracyMeters: Double? = nil, heading: Double? = nil) {
        self.id = UUID()
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = Date()
        self.speedMps = speedMps
        self.accuracyMeters = accuracyMeters
        self.heading = heading
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var speedKmh: Double? {
        guard let mps = speedMps else { return nil }
        return mps * 3.6
    }
    
    var speedMph: Double? {
        guard let mps = speedMps else { return nil }
        return mps * 2.237
    }
}

// MARK: - Navigation Step (from SDK)

/// Represents a single step in the navigation route
struct NavigationStep: Codable, Identifiable {
    let id: UUID
    let stepIndex: Int
    let instruction: String
    let roadName: String
    let maneuver: String
    let distanceMeters: Int
    let durationSeconds: Int?
    let latitude: Double?
    let longitude: Double?
    
    init(
        stepIndex: Int,
        instruction: String,
        roadName: String,
        maneuver: String,
        distanceMeters: Int,
        durationSeconds: Int? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = UUID()
        self.stepIndex = stepIndex
        self.instruction = instruction
        self.roadName = roadName
        self.maneuver = maneuver
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.latitude = latitude
        self.longitude = longitude
    }
    
    var formattedDistance: String {
        if distanceMeters >= 1609 {
            let miles = Double(distanceMeters) / 1609.34
            return String(format: "%.1f mi", miles)
        } else if distanceMeters >= 161 { // ~0.1 miles
            let miles = Double(distanceMeters) / 1609.34
            return String(format: "%.1f mi", miles)
        } else {
            let feet = Double(distanceMeters) * 3.28084
            return String(format: "%.0f ft", feet)
        }
    }
    
    /// Generates a spoken instruction for voice announcements
    var spokenInstruction: String {
        if roadName.isEmpty {
            return instruction
        }
        
        // Clean up the instruction for speech
        var spoken = instruction
        
        // Remove HTML tags if any
        spoken = spoken.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        return spoken
    }
}

// MARK: - Navigation State

/// Current state of an active navigation session
enum NavigationState: String, Codable {
    case idle
    case calculating
    case enroute
    case rerouting
    case arrived
    case stopped
    case error
    
    var isActive: Bool {
        switch self {
        case .enroute, .rerouting:
            return true
        default:
            return false
        }
    }
}

// MARK: - Navigation Event

/// Events that occur during navigation, for logging/announcements
enum NavigationEvent {
    case started(journey: NavigationJourney)
    case stepCompleted(step: NavigationStep, journey: NavigationJourney)
    case initialDirections(current: NavigationStep, next: NavigationStep?)
    case approachingTurn(step: NavigationStep, distanceMeters: Int)
    case rerouting(reason: String)
    case arrived(journey: NavigationJourney)
    case cancelled(journey: NavigationJourney)
    case error(message: String)
    
    var announcementText: String? {
        switch self {
        case .started(let journey):
            let dest = journey.destinationName ?? journey.destinationAddress
            let time = journey.formattedTime
            return "Starting navigation to \(dest). Estimated time: \(time)."
        case .initialDirections(let current, let next):
            if let next = next {
                return "\(current.spokenInstruction). After that, \(next.spokenInstruction.lowercased())."
            } else {
                return current.spokenInstruction
            }
            
        case .approachingTurn(let step, let distance):
            let distanceFeet = Int(Double(distance) * 3.28084)
            if distanceFeet <= 100 {
                return step.spokenInstruction
            } else if distanceFeet <= 500 {
                return "In \(distanceFeet) feet, \(step.spokenInstruction.lowercased())"
            } else {
                let distanceMiles = Double(distance) / 1609.34
                if distanceMiles >= 0.1 {
                    return String(format: "In %.1f miles, %@", distanceMiles, step.spokenInstruction.lowercased())
                } else {
                    return "In \(distanceFeet) feet, \(step.spokenInstruction.lowercased())"
                }
            }
            
        case .stepCompleted:
            return nil // Usually don't announce step completion
            
        case .rerouting:
            return "Recalculating route."
            
        case .arrived(let journey):
            let dest = journey.destinationName ?? "your destination"
            return "You have arrived at \(dest)."
            
        case .cancelled:
            return "Navigation cancelled."
            
        case .error(let message):
            return "Navigation error: \(message)"
        }
    }
}

// MARK: - Codable Keys (for Supabase compatibility)

extension NavigationJourney {
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userEmail = "user_email"
        case sessionId = "session_id"
        case originAddress = "origin_address"
        case originLat = "origin_lat"
        case originLng = "origin_lng"
        case destinationAddress = "destination_address"
        case destinationLat = "destination_lat"
        case destinationLng = "destination_lng"
        case destinationName = "destination_name"
        case travelMode = "travel_mode"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case completed
        case cancelled
        case totalDistanceMeters = "total_distance_meters"
        case totalTimeSeconds = "total_time_seconds"
        case initialStepsCount = "initial_steps_count"
        case checkpoints
        case breadcrumbs
        case rerouteCount = "reroute_count"
        case lastRerouteAt = "last_reroute_at"
    }
}

extension NavigationCheckpoint {
    enum CodingKeys: String, CodingKey {
        case id
        case stepIndex = "step_index"
        case instruction
        case roadName = "road_name"
        case maneuver
        case arrivedAt = "arrived_at"
        case latitude = "lat"
        case longitude = "lng"
        case distanceFromPreviousMeters = "distance_from_previous_meters"
    }
}

extension NavigationBreadcrumb {
    enum CodingKeys: String, CodingKey {
        case id
        case latitude = "lat"
        case longitude = "lng"
        case timestamp
        case speedMps = "speed_mps"
        case accuracyMeters = "accuracy_m"
        case heading
    }
}

