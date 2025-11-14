//
//  GBFSService.swift
//  guido-1
//
//  Created by AI Assistant on 11/14/25.
//

import Foundation
import CoreLocation

/// Actor responsible for interacting with GBFS feeds, caching results, and answering proximity queries.
actor GBFSService {
    
    // MARK: - Nested Types
    
    private struct FeedState<Value> {
        var value: Value?
        var ttl: TimeInterval?
        var lastFetched: Date?
        var lastRemoteUpdate: Date?
        var etag: String?
        
        var isStale: Bool {
            guard let ttl, let lastFetched else { return true }
            return Date().timeIntervalSince(lastFetched) > ttl
        }
    }
    
    private struct FeedMetadata {
        let ttl: TimeInterval?
        let lastUpdated: TimeInterval?
        let etag: String?
    }
    
    private enum FetchError: Error {
        case notModified
    }
    
    enum BikeTypeFilter: String {
        case bike
        case ebike
        case any
        
        static func fromArgument(_ value: Any?) -> BikeTypeFilter {
            guard let raw = value as? String, let filter = BikeTypeFilter(rawValue: raw.lowercased()) else {
                return .any
            }
            return filter
        }
    }
    
    // MARK: - Properties
    
    private let discoveryURL: URL
    private let urlSession: URLSession
    private let defaultRadius: Double = 500
    private let minTTL: TimeInterval = 30
    private let maxTTL: TimeInterval = 300
    
    private var discoveryState = FeedState<GBFSDiscoveryRoot>()
    private var stationInfoState = FeedState<[GBFSStationInformation]>()
    private var stationStatusState = FeedState<[GBFSStationStatus]>()
    private var vehicleTypesState = FeedState<[GBFSVehicleType]>()
    
    private var feedURLs: [String: URL] = [:]
    
    // MARK: - Initialization
    
    init(discoveryURL: URL, urlSession: URLSession = .shared) {
        self.discoveryURL = discoveryURL
        self.urlSession = urlSession
    }
    
    // MARK: - Public API
    
    func refreshIfNeeded() async throws {
        try await ensureDiscovery()
        try await ensureStationInformation()
        try await ensureStationStatus()
        try await ensureVehicleTypesIfAvailable()
    }
    
    func stationsNear(
        lat: Double,
        lon: Double,
        radiusMeters: Double? = nil,
        limit: Int = 10
    ) async throws -> [GBFSStationView] {
        let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let allStations = try await currentStationViews(center: center)
        let radius = radiusMeters ?? defaultRadius
        return Array(allStations
            .filter { station in
                guard let distance = station.distanceMeters else { return true }
                return distance <= radius
            }
            .prefix(limit))
    }
    
    func bikesNear(
        lat: Double,
        lon: Double,
        radiusMeters: Double? = nil,
        minCount: Int = 1,
        types: BikeTypeFilter = .any,
        limit: Int = 5
    ) async throws -> [GBFSStationView] {
        let stationViews = try await stationsNear(lat: lat, lon: lon, radiusMeters: radiusMeters, limit: Int.max)
        let filtered = stationViews.filter { station in
            guard station.isRenting else { return false }
            let ebikes = station.numEbikesAvailable
            let classic = max(station.numBikesAvailable - ebikes, 0)
            switch types {
            case .any:
                return station.numBikesAvailable >= minCount
            case .ebike:
                return ebikes >= minCount
            case .bike:
                return classic >= minCount
            }
        }
        return Array(filtered.prefix(limit))
    }
    
    func docksNear(
        lat: Double,
        lon: Double,
        radiusMeters: Double? = nil,
        minDocks: Int = 1,
        limit: Int = 5
    ) async throws -> [GBFSStationView] {
        let stationViews = try await stationsNear(lat: lat, lon: lon, radiusMeters: radiusMeters, limit: Int.max)
        let filtered = stationViews.filter { station in
            station.isReturning && station.numDocksAvailable >= minDocks
        }
        return Array(filtered.prefix(limit))
    }
    
    func availabilityFor(stationID: String, referenceLat: Double?, referenceLon: Double?) async throws -> GBFSStationView {
        let center: CLLocationCoordinate2D?
        if let lat = referenceLat, let lon = referenceLon {
            center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            center = nil
        }
        let allStations = try await currentStationViews(center: center)
        guard let match = allStations.first(where: { $0.stationID == stationID }) else {
            throw GBFSError.stationNotFound(stationID)
        }
        return match
    }
    
    func typeBreakdownNear(
        lat: Double,
        lon: Double,
        radiusMeters: Double? = nil
    ) async throws -> GBFSTypeBreakdown {
        let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let stations = try await stationsNear(lat: lat, lon: lon, radiusMeters: radiusMeters, limit: Int.max)
        let totalBikes = stations.reduce(0) { $0 + $1.numBikesAvailable }
        let totalEbikes = stations.reduce(0) { $0 + $1.numEbikesAvailable }
        let totalDocks = stations.reduce(0) { $0 + $1.numDocksAvailable }
        let now = Date()
        let stale = stationStatusState.isStale
        return GBFSTypeBreakdown(
            totalBikes: totalBikes,
            totalEbikes: totalEbikes,
            totalDocks: totalDocks,
            stationCount: stations.count,
            radiusMeters: radiusMeters ?? defaultRadius,
            centerLatitude: center.latitude,
            centerLongitude: center.longitude,
            asOf: now,
            stale: stale
        )
    }
    
    func parkingNearDestination(
        lat: Double,
        lon: Double,
        radiusMeters: Double? = nil,
        minDocks: Int = 1,
        limit: Int = 5
    ) async throws -> [GBFSStationView] {
        try await docksNear(lat: lat, lon: lon, radiusMeters: radiusMeters, minDocks: minDocks, limit: limit)
    }
    
    // MARK: - Private Helpers
    
    private func currentStationViews(center: CLLocationCoordinate2D?) async throws -> [GBFSStationView] {
        try await refreshIfNeeded()
        guard let infos = stationInfoState.value else {
            throw GBFSError.feedUnavailable("station_information")
        }
        guard let statuses = stationStatusState.value else {
            throw GBFSError.feedUnavailable("station_status")
        }
        let statusMap = Dictionary(uniqueKeysWithValues: statuses.map { ($0.stationID, $0) })
        let stale = stationStatusState.isStale
        let updatedAt = stationStatusState.lastFetched ?? Date()
        
        var views: [GBFSStationView] = []
        views.reserveCapacity(statuses.count)
        for info in infos {
            guard let status = statusMap[info.stationID] else { continue }
            // Skip stations that are not installed or renting/returning for relevant contexts
            guard status.isInstalled ?? true else { continue }
            let view = makeStationView(
                info: info,
                status: status,
                center: center,
                updatedAt: updatedAt,
                stale: stale
            )
            views.append(view)
        }
        return views.sorted { (lhs, rhs) -> Bool in
            let leftDistance = lhs.distanceMeters ?? Double.greatestFiniteMagnitude
            let rightDistance = rhs.distanceMeters ?? Double.greatestFiniteMagnitude
            return leftDistance < rightDistance
        }
    }
    
    private func makeStationView(
        info: GBFSStationInformation,
        status: GBFSStationStatus,
        center: CLLocationCoordinate2D?,
        updatedAt: Date,
        stale: Bool
    ) -> GBFSStationView {
        let stationCoordinate = CLLocationCoordinate2D(latitude: info.lat, longitude: info.lon)
        let distance: Double?
        if let center {
            distance = haversineDistance(from: center, to: stationCoordinate)
        } else {
            distance = nil
        }
        let ebikes = status.numEbikesAvailable ?? 0
        let docks = status.numDocksAvailable ?? 0
        let lastReported = status.lastReported.flatMap { Date(timeIntervalSince1970: $0) }
        return GBFSStationView(
            stationID: info.stationID,
            name: info.name,
            latitude: info.lat,
            longitude: info.lon,
            distanceMeters: distance,
            capacity: info.capacity,
            numBikesAvailable: status.numBikesAvailable,
            numEbikesAvailable: ebikes,
            numDocksAvailable: docks,
            isRenting: status.isRenting ?? true,
            isReturning: status.isReturning ?? true,
            lastReported: lastReported,
            updatedAt: updatedAt,
            address: info.address,
            regionID: info.regionID,
            rentalUris: info.rentalUris,
            isVirtual: info.isVirtualStation ?? false,
            isValet: info.isValetStation ?? false,
            stale: stale
        )
    }
    
    private func ensureDiscovery() async throws {
        guard discoveryState.value != nil, !discoveryState.isStale else {
            try await loadDiscovery()
            return
        }
    }
    
    private func ensureStationInformation() async throws {
        if stationInfoState.value == nil || stationInfoState.isStale {
            try await loadStationInformation()
        }
    }
    
    private func ensureStationStatus() async throws {
        if stationStatusState.value == nil || stationStatusState.isStale {
            try await loadStationStatus()
        }
    }
    
    private func ensureVehicleTypesIfAvailable() async throws {
        guard feedURLs["vehicle_types"] != nil else { return }
        if vehicleTypesState.value == nil || vehicleTypesState.isStale {
            try await loadVehicleTypes()
        }
    }
    
    private func loadDiscovery() async throws {
        do {
            let (root, metadata): (GBFSDiscoveryRoot, FeedMetadata) = try await fetch(url: discoveryURL, existingETag: discoveryState.etag)
            discoveryState.value = root
            discoveryState.ttl = clampedTTL(metadata.ttl)
            discoveryState.lastFetched = Date()
            discoveryState.lastRemoteUpdate = metadata.lastUpdated.map { Date(timeIntervalSince1970: $0) }
            discoveryState.etag = metadata.etag
            
            var urls: [String: URL] = [:]
            for locale in root.data.values {
                for feed in locale.feeds {
                    guard urls[feed.name] == nil, let url = URL(string: feed.url) else { continue }
                    urls[feed.name] = url
                }
            }
            feedURLs = urls
        } catch FetchError.notModified {
            discoveryState.lastFetched = Date()
        }
    }
    
    private func loadStationInformation() async throws {
        guard let url = feedURLs["station_information"] else {
            throw GBFSError.feedUnavailable("station_information")
        }
        do {
            let (root, metadata): (GBFSStationInformationRoot, FeedMetadata) = try await fetch(url: url, existingETag: stationInfoState.etag)
            stationInfoState.value = root.data.stations
            stationInfoState.ttl = clampedTTL(metadata.ttl)
            stationInfoState.lastFetched = Date()
            stationInfoState.lastRemoteUpdate = metadata.lastUpdated.map { Date(timeIntervalSince1970: $0) }
            stationInfoState.etag = metadata.etag
        } catch FetchError.notModified {
            stationInfoState.lastFetched = Date()
        }
    }
    
    private func loadStationStatus() async throws {
        guard let url = feedURLs["station_status"] else {
            throw GBFSError.feedUnavailable("station_status")
        }
        do {
            let (root, metadata): (GBFSStationStatusRoot, FeedMetadata) = try await fetch(url: url, existingETag: stationStatusState.etag)
            stationStatusState.value = root.data.stations
            stationStatusState.ttl = clampedTTL(metadata.ttl)
            stationStatusState.lastFetched = Date()
            stationStatusState.lastRemoteUpdate = metadata.lastUpdated.map { Date(timeIntervalSince1970: $0) }
            stationStatusState.etag = metadata.etag
        } catch FetchError.notModified {
            stationStatusState.lastFetched = Date()
        }
    }
    
    private func loadVehicleTypes() async throws {
        guard let url = feedURLs["vehicle_types"] else { return }
        do {
            let (root, metadata): (GBFSVehicleTypesRoot, FeedMetadata) = try await fetch(url: url, existingETag: vehicleTypesState.etag)
            vehicleTypesState.value = root.data.vehicleTypes
            vehicleTypesState.ttl = clampedTTL(metadata.ttl)
            vehicleTypesState.lastFetched = Date()
            vehicleTypesState.lastRemoteUpdate = metadata.lastUpdated.map { Date(timeIntervalSince1970: $0) }
            vehicleTypesState.etag = metadata.etag
        } catch FetchError.notModified {
            vehicleTypesState.lastFetched = Date()
        }
    }
    
    private func fetch<Response: Decodable>(url: URL, existingETag: String?) async throws -> (Response, FeedMetadata) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let existingETag {
            request.setValue(existingETag, forHTTPHeaderField: "If-None-Match")
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "GBFSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }
            
            if http.statusCode == 304 {
                throw FetchError.notModified
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "GBFSService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Response.self, from: data)
            let metadata = FeedMetadata(
                ttl: (try? decoder.decode(GBFSMetadataProbe.self, from: data))?.ttl,
                lastUpdated: (try? decoder.decode(GBFSMetadataProbe.self, from: data))?.lastUpdated,
                etag: http.value(forHTTPHeaderField: "ETag")
            )
            return (decoded, metadata)
        } catch {
            if error is FetchError {
                throw error
            }
            throw error
        }
    }
    
    private func clampedTTL(_ ttl: TimeInterval?) -> TimeInterval {
        guard let ttl else { return maxTTL }
        let positive = max(ttl, minTTL)
        return min(positive, maxTTL)
    }
    
    private func haversineDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dlat = lat2 - lat1
        let dlon = lon2 - lon1
        let a = pow(sin(dlat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dlon / 2), 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}

// MARK: - Metadata Probe

private struct GBFSMetadataProbe: Decodable {
    let ttl: TimeInterval?
    let lastUpdated: TimeInterval?
    
    enum CodingKeys: String, CodingKey {
        case ttl
        case lastUpdated = "last_updated"
    }
}


