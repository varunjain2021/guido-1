//
//  SupabaseJourneySink.swift
//  guido-1
//
//  Persistence layer for navigation journeys to Supabase
//

import Foundation

// MARK: - Journey Sink Protocol

protocol JourneySink {
    func createJourney(_ journey: NavigationJourney) async throws -> NavigationJourney
    func updateJourney(_ journey: NavigationJourney) async throws
    func appendBreadcrumbs(_ breadcrumbs: [NavigationBreadcrumb], journeyId: UUID) async throws
    func appendCheckpoint(_ checkpoint: NavigationCheckpoint, journeyId: UUID) async throws
}

// MARK: - Supabase Implementation

final class SupabaseJourneySink: JourneySink {
    private let baseURL: String
    private let anonKey: String
    private let accessTokenProvider: () async -> String?
    private let urlSession: URLSession
    private let maxRetries: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private var journeysEndpoint: URL? {
        URL(string: baseURL)?.appendingPathComponent("rest/v1/navigation_journeys")
    }
    
    init(
        baseURL: String,
        anonKey: String,
        accessTokenProvider: @escaping () async -> String? = { nil },
        urlSession: URLSession = .shared,
        maxRetries: Int = 2
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessTokenProvider = accessTokenProvider
        self.urlSession = urlSession
        self.maxRetries = maxRetries
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }
    
    // MARK: - Create Journey
    
    func createJourney(_ journey: NavigationJourney) async throws -> NavigationJourney {
        guard let endpoint = journeysEndpoint else {
            throw JourneySinkError.invalidEndpoint
        }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        await configureHeaders(&request, prefer: "return=representation")
        
        let payload = JourneyCreatePayload(journey: journey)
        request.httpBody = try encoder.encode(payload)
        
        print("🗺️ [JourneySink] Creating journey to: \(journey.destinationAddress)")
        
        let data = try await send(request: request)
        
        // Parse response to get the created journey with server-generated fields
        if let responseArray = try? decoder.decode([NavigationJourney].self, from: data),
           let created = responseArray.first {
            print("✅ [JourneySink] Journey created with ID: \(created.id)")
            return created
        }
        
        // If we can't parse response, return original journey
        print("✅ [JourneySink] Journey created (ID: \(journey.id))")
        return journey
    }
    
    // MARK: - Update Journey
    
    func updateJourney(_ journey: NavigationJourney) async throws {
        guard let endpoint = journeysEndpoint else {
            throw JourneySinkError.invalidEndpoint
        }
        
        // Build URL with filter
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(journey.id.uuidString)")]
        
        guard let url = components.url else {
            throw JourneySinkError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        await configureHeaders(&request, prefer: "return=minimal")
        
        let payload = JourneyUpdatePayload(journey: journey)
        request.httpBody = try encoder.encode(payload)
        
        print("🗺️ [JourneySink] Updating journey: \(journey.id)")
        
        _ = try await send(request: request)
        
        print("✅ [JourneySink] Journey updated")
    }
    
    // MARK: - Append Breadcrumbs
    
    func appendBreadcrumbs(_ breadcrumbs: [NavigationBreadcrumb], journeyId: UUID) async throws {
        guard !breadcrumbs.isEmpty else { return }
        
        guard let endpoint = journeysEndpoint else {
            throw JourneySinkError.invalidEndpoint
        }
        
        // Use RPC to append to JSONB array
        guard let rpcEndpoint = URL(string: baseURL)?.appendingPathComponent("rest/v1/rpc/append_journey_breadcrumbs") else {
            // Fallback: fetch, merge, update
            try await appendBreadcrumbsFallback(breadcrumbs, journeyId: journeyId)
            return
        }
        
        var request = URLRequest(url: rpcEndpoint)
        request.httpMethod = "POST"
        await configureHeaders(&request, prefer: "return=minimal")
        
        let payload: [String: Any] = [
            "journey_id": journeyId.uuidString,
            "new_breadcrumbs": breadcrumbs.map { crumb in
                [
                    "lat": crumb.latitude,
                    "lng": crumb.longitude,
                    "timestamp": ISO8601DateFormatter().string(from: crumb.timestamp),
                    "speed_mps": crumb.speedMps as Any,
                    "accuracy_m": crumb.accuracyMeters as Any
                ]
            }
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        do {
            _ = try await send(request: request)
            print("📍 [JourneySink] Appended \(breadcrumbs.count) breadcrumbs")
        } catch {
            // RPC might not exist, use fallback
            print("⚠️ [JourneySink] RPC failed, using fallback: \(error)")
            try await appendBreadcrumbsFallback(breadcrumbs, journeyId: journeyId)
        }
    }
    
    private func appendBreadcrumbsFallback(_ breadcrumbs: [NavigationBreadcrumb], journeyId: UUID) async throws {
        // Fetch current journey, append breadcrumbs, update
        guard let endpoint = journeysEndpoint else {
            throw JourneySinkError.invalidEndpoint
        }
        
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(journeyId.uuidString)"),
            URLQueryItem(name: "select", value: "breadcrumbs")
        ]
        
        guard let fetchURL = components.url else {
            throw JourneySinkError.invalidEndpoint
        }
        
        var fetchRequest = URLRequest(url: fetchURL)
        fetchRequest.httpMethod = "GET"
        await configureHeaders(&fetchRequest, prefer: nil)
        
        let fetchData = try await send(request: fetchRequest)
        
        // Parse existing breadcrumbs
        var existingBreadcrumbs: [NavigationBreadcrumb] = []
        if let jsonArray = try? JSONSerialization.jsonObject(with: fetchData) as? [[String: Any]],
           let first = jsonArray.first,
           let crumbsData = first["breadcrumbs"] {
            if let crumbsArray = crumbsData as? [[String: Any]] {
                // Parse manually since it's raw JSON
                for crumb in crumbsArray {
                    if let lat = crumb["lat"] as? Double,
                       let lng = crumb["lng"] as? Double {
                        let breadcrumb = NavigationBreadcrumb(
                            latitude: lat,
                            longitude: lng,
                            speedMps: crumb["speed_mps"] as? Double,
                            accuracyMeters: crumb["accuracy_m"] as? Double
                        )
                        existingBreadcrumbs.append(breadcrumb)
                    }
                }
            }
        }
        
        // Merge and update
        let allBreadcrumbs = existingBreadcrumbs + breadcrumbs
        
        // Update with merged breadcrumbs
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(journeyId.uuidString)")]
        guard let updateURL = components.url else {
            throw JourneySinkError.invalidEndpoint
        }
        
        var updateRequest = URLRequest(url: updateURL)
        updateRequest.httpMethod = "PATCH"
        await configureHeaders(&updateRequest, prefer: "return=minimal")
        
        let updatePayload = ["breadcrumbs": allBreadcrumbs]
        updateRequest.httpBody = try encoder.encode(updatePayload)
        
        _ = try await send(request: updateRequest)
        print("📍 [JourneySink] Appended \(breadcrumbs.count) breadcrumbs (fallback)")
    }
    
    // MARK: - Append Checkpoint
    
    func appendCheckpoint(_ checkpoint: NavigationCheckpoint, journeyId: UUID) async throws {
        guard let endpoint = journeysEndpoint else {
            throw JourneySinkError.invalidEndpoint
        }
        
        // Similar fallback approach - fetch, append, update
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(journeyId.uuidString)"),
            URLQueryItem(name: "select", value: "checkpoints")
        ]
        
        guard let fetchURL = components.url else {
            throw JourneySinkError.invalidEndpoint
        }
        
        var fetchRequest = URLRequest(url: fetchURL)
        fetchRequest.httpMethod = "GET"
        await configureHeaders(&fetchRequest, prefer: nil)
        
        let fetchData = try await send(request: fetchRequest)
        
        // Parse existing checkpoints
        var existingCheckpoints: [NavigationCheckpoint] = []
        if let jsonArray = try? JSONSerialization.jsonObject(with: fetchData) as? [[String: Any]],
           let first = jsonArray.first,
           let checkpointsData = first["checkpoints"] as? [[String: Any]] {
            for cp in checkpointsData {
                if let stepIndex = cp["step_index"] as? Int,
                   let instruction = cp["instruction"] as? String,
                   let maneuver = cp["maneuver"] as? String,
                   let lat = cp["lat"] as? Double,
                   let lng = cp["lng"] as? Double {
                    let checkpoint = NavigationCheckpoint(
                        stepIndex: stepIndex,
                        instruction: instruction,
                        roadName: cp["road_name"] as? String,
                        maneuver: maneuver,
                        latitude: lat,
                        longitude: lng,
                        distanceFromPreviousMeters: cp["distance_from_previous_meters"] as? Int
                    )
                    existingCheckpoints.append(checkpoint)
                }
            }
        }
        
        // Append new checkpoint
        let allCheckpoints = existingCheckpoints + [checkpoint]
        
        // Update
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(journeyId.uuidString)")]
        guard let updateURL = components.url else {
            throw JourneySinkError.invalidEndpoint
        }
        
        var updateRequest = URLRequest(url: updateURL)
        updateRequest.httpMethod = "PATCH"
        await configureHeaders(&updateRequest, prefer: "return=minimal")
        
        let updatePayload = ["checkpoints": allCheckpoints]
        updateRequest.httpBody = try encoder.encode(updatePayload)
        
        _ = try await send(request: updateRequest)
        print("✅ [JourneySink] Appended checkpoint: \(checkpoint.instruction)")
    }
    
    // MARK: - Helpers
    
    private func configureHeaders(_ request: inout URLRequest, prefer: String?) async {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer = prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let bearerToken = await accessTokenProvider() ?? anonKey
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }
    
    private func send(request: URLRequest) async throws -> Data {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw JourneySinkError.invalidResponse
                }
                if (200..<300).contains(httpResponse.statusCode) {
                    return data
                }
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw JourneySinkError.serverError(statusCode: httpResponse.statusCode, message: body)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let backoff = UInt64(pow(2.0, Double(attempt))) * 200_000_000
                    try await Task.sleep(nanoseconds: backoff)
                    continue
                } else {
                    throw error
                }
            }
        }
        throw lastError ?? JourneySinkError.unknown
    }
}

// MARK: - Payload Structs

private struct JourneyCreatePayload: Encodable {
    let id: UUID
    let user_id: String?
    let user_email: String?
    let session_id: String?
    let origin_address: String?
    let origin_lat: Double?
    let origin_lng: Double?
    let destination_address: String
    let destination_lat: Double
    let destination_lng: Double
    let destination_name: String?
    let travel_mode: String
    let started_at: Date
    let total_distance_meters: Int?
    let total_time_seconds: Int?
    let initial_steps_count: Int?
    let checkpoints: [NavigationCheckpoint]
    let breadcrumbs: [NavigationBreadcrumb]
    
    init(journey: NavigationJourney) {
        self.id = journey.id
        self.user_id = journey.userId
        self.user_email = journey.userEmail
        self.session_id = journey.sessionId
        self.origin_address = journey.originAddress
        self.origin_lat = journey.originLat
        self.origin_lng = journey.originLng
        self.destination_address = journey.destinationAddress
        self.destination_lat = journey.destinationLat
        self.destination_lng = journey.destinationLng
        self.destination_name = journey.destinationName
        self.travel_mode = journey.travelMode.rawValue
        self.started_at = journey.startedAt
        self.total_distance_meters = journey.totalDistanceMeters
        self.total_time_seconds = journey.totalTimeSeconds
        self.initial_steps_count = journey.initialStepsCount
        self.checkpoints = journey.checkpoints
        self.breadcrumbs = journey.breadcrumbs
    }
}

private struct JourneyUpdatePayload: Encodable {
    let ended_at: Date?
    let completed: Bool
    let cancelled: Bool
    let total_distance_meters: Int?
    let total_time_seconds: Int?
    let reroute_count: Int
    let last_reroute_at: Date?
    let checkpoints: [NavigationCheckpoint]
    let breadcrumbs: [NavigationBreadcrumb]
    
    init(journey: NavigationJourney) {
        self.ended_at = journey.endedAt
        self.completed = journey.completed
        self.cancelled = journey.cancelled
        self.total_distance_meters = journey.totalDistanceMeters
        self.total_time_seconds = journey.totalTimeSeconds
        self.reroute_count = journey.rerouteCount
        self.last_reroute_at = journey.lastRerouteAt
        self.checkpoints = journey.checkpoints
        self.breadcrumbs = journey.breadcrumbs
    }
}

// MARK: - Errors

enum JourneySinkError: Error, LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case serverError(statusCode: Int, message: String)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid Supabase endpoint"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .unknown:
            return "Unknown error"
        }
    }
}

