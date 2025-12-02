//
//  HeatmapService.swift
//  guido-1
//
//  Created by GPT-5.1 Codex on 11/29/25.
//

import Foundation
import CoreLocation
import SwiftyH3
#if canImport(UIKit)
import UIKit
#endif

/// Central coordinator responsible for transforming raw location updates
/// into enriched heatmap observations and persisting them to Supabase.
@MainActor
final class HeatmapService: ObservableObject {
    
    static let shared = HeatmapService()
    
    // MARK: - Configuration
    
    private var googleService: GooglePlacesRoutesService?
    private var supabaseSink: SupabaseHeatmapSink?
    private var userIdProvider: () -> String? = { nil }
    
    private let locationManager = LocationManager.shared
    private let enrichmentThreshold: TimeInterval = 10 * 60 // seconds
    private let periodicFlushInterval: TimeInterval = 30 * 60 // seconds
    private let hexResolution: H3Cell.Resolution = .res9
    private let cacheTTL: TimeInterval = 24 * 60 * 60
    
    private let defaults = UserDefaults.standard
    private let trackingKey = "heatmap.tracking.enabled"
    
    // Cache keyed by hex id
    private var placeCache: [String: CachedPlace] = [:]
    
    // MARK: - Published state
    
    @Published private(set) var recentVisits: [HeatmapVisit] = []
    
    // MARK: - Internal state
    
    private var activeVisit: ActiveVisit?
    private var periodicFlushTimer: Timer?
#if canImport(UIKit)
    private var lifecycleObservers: [NSObjectProtocol] = []
#endif
    
    private init() {}
    
    func configure(
        googleAPIKey: String,
        supabaseURL: String,
        supabaseAnonKey: String,
        userIdProvider: @escaping () -> String?,
        accessTokenProvider: @escaping () async -> String?
    ) {
        self.googleService = GooglePlacesRoutesService(apiKey: googleAPIKey, locationManager: locationManager)
        if !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty {
            self.supabaseSink = SupabaseHeatmapSink(
                baseURL: supabaseURL,
                anonKey: supabaseAnonKey,
                accessTokenProvider: accessTokenProvider
            )
        }
        self.userIdProvider = userIdProvider
        
        setupLifecycleObservers()
        startPeriodicFlushTimer()
    }
    
    // MARK: - Public controls
    
    var isTrackingEnabled: Bool {
        if defaults.object(forKey: trackingKey) == nil {
            defaults.set(true, forKey: trackingKey)
        }
        return defaults.bool(forKey: trackingKey)
    }
    
    func setTrackingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: trackingKey)
        if !enabled {
            flushActiveVisit(reason: "tracking-disabled")
            stopPeriodicFlushTimer()
        } else {
            startPeriodicFlushTimer()
        }
    }
    
    func fetchVisits(since: Date?) async -> [HeatmapVisit] {
        let userId = userIdProvider()
        print("🗺️ [Heatmap] fetchVisits called - userId: \(userId ?? "nil"), supabaseSink: \(supabaseSink != nil ? "configured" : "nil")")
        
        if let userId,
           let supabaseSink {
            do {
                let visits = try await supabaseSink.fetchVisits(userId: userId, since: since)
                print("🗺️ [Heatmap] Supabase returned \(visits.count) visits")
                return visits
            } catch {
                print("⚠️ [Heatmap] Failed to fetch visits from Supabase: \(error.localizedDescription)")
            }
        }
        
        print("🗺️ [Heatmap] Falling back to in-memory recentVisits (\(recentVisits.count) items)")
        guard let since else { return recentVisits }
        return recentVisits.filter { $0.enteredAt >= since }
    }
    
    // MARK: - Location ingestion
    
    func processLocation(_ location: CLLocation) {
        guard isTrackingEnabled else { return }
        guard let cell = makeCell(from: location.coordinate) else {
            print("🧊 [Heatmap] Unable to compute H3 cell for \(location.coordinate)")
            return
        }
        
        let now = Date()
        if var current = activeVisit {
            if current.cell == cell {
                current.lastLocation = location
                current.lastUpdate = now
                activeVisit = current
            } else {
                let visitToFinalize = current
                activeVisit = ActiveVisit(cell: cell, enteredAt: now, lastUpdate: now, lastLocation: location)
                Task {
                    await self.finalizeVisit(visitToFinalize, exitedAt: now, reason: "moved-to-new-hex")
                }
            }
        } else {
            activeVisit = ActiveVisit(cell: cell, enteredAt: now, lastUpdate: now, lastLocation: location)
        }
    }
    
    func handleVisit(_ visit: CLVisit) {
        guard visit.departureDate != .distantFuture else { return }
        guard let cell = makeCell(from: visit.coordinate) else { return }
        let visitLocation = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        let clVisit = ActiveVisit(cell: cell, enteredAt: visit.arrivalDate, lastUpdate: visit.departureDate, lastLocation: visitLocation)
        Task {
            await self.finalizeVisit(clVisit, exitedAt: visit.departureDate, reason: "clvisit")
        }
    }
    
    func flushActiveVisit(reason: String = "manual-flush") {
        guard let current = activeVisit else { return }
        activeVisit = nil
        Task {
            await self.finalizeVisit(current, exitedAt: Date(), reason: reason)
        }
    }
    
    deinit {
        stopPeriodicFlushTimer()
#if canImport(UIKit)
        removeLifecycleObservers()
#endif
    }
    
    // MARK: - Visit lifecycle
    
    private func finalizeVisit(_ visit: ActiveVisit, exitedAt: Date, reason: String) async {
        let dwell = max(0, exitedAt.timeIntervalSince(visit.enteredAt))
        let dwellSeconds = Int(dwell)
        guard dwellSeconds > 0 else { return }
        
        let hexId = visit.cell.description
        let center = (try? visit.cell.center.coordinates) ?? visit.lastLocation.coordinate
        let shouldEnrichPlace = dwell >= enrichmentThreshold
        
        var placeName: String?
        var placeCategory: String?
        var placeAddress: String?
        
        if shouldEnrichPlace {
            // Full enrichment: place name, category, and address from Google Places
            let enrichment = await resolvePlace(for: hexId, coordinate: visit.lastLocation.coordinate)
            placeName = enrichment.placeName
            placeCategory = enrichment.placeCategory
            placeAddress = enrichment.placeAddress
        } else {
            // For shorter visits, still get the address via reverse geocoding
            placeAddress = await reverseGeocode(coordinate: visit.lastLocation.coordinate)
        }
        
        // Calculate day of week and local hour from entry time
        let (dayOfWeek, localHour, localTimeZone) = extractTimeInfo(from: visit.enteredAt)
        
        let visitRecord = HeatmapVisit(
            id: UUID(),
            userId: userIdProvider(),
            hexId: hexId,
            centerLat: center.latitude,
            centerLng: center.longitude,
            placeName: placeName,
            placeCategory: placeCategory,
            placeAddress: placeAddress,
            enteredAt: visit.enteredAt,
            exitedAt: exitedAt,
            dwellSeconds: dwellSeconds,
            dayOfWeek: dayOfWeek,
            localHour: localHour,
            localTimeZone: localTimeZone
        )
        
        recentVisits.append(visitRecord)
        recentVisits = Array(recentVisits.suffix(200))
        
        await persistVisit(visitRecord)
        
        print("🔥 [Heatmap] Finalized visit \(hexId) (\(dwellSeconds)s, reason=\(reason)) place=\(placeName ?? "unknown") @ \(placeAddress ?? "no address") [\(dayOfWeek ?? "?") \(localHour ?? -1):00]")
    }
    
    /// Extract day of week, hour, and timezone from a date
    private func extractTimeInfo(from date: Date) -> (dayOfWeek: String?, localHour: Int?, localTimeZone: String?) {
        let calendar = Calendar.current
        let timeZone = TimeZone.current
        
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let dayOfWeek = weekday >= 1 && weekday <= 7 ? dayNames[weekday - 1] : nil
        
        return (dayOfWeek, hour, timeZone.identifier)
    }
    
    private func startPeriodicFlushTimer() {
        periodicFlushTimer?.invalidate()
        guard isTrackingEnabled, periodicFlushInterval > 0 else { return }
        periodicFlushTimer = Timer.scheduledTimer(withTimeInterval: periodicFlushInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.flushActiveVisit(reason: "periodic-flush")
        }
    }
    
    nonisolated private func stopPeriodicFlushTimer() {
        Task { @MainActor in
            periodicFlushTimer?.invalidate()
            periodicFlushTimer = nil
        }
    }
    
#if canImport(UIKit)
    private func setupLifecycleObservers() {
        removeLifecycleObserversSync()
        let center = NotificationCenter.default
        let backgroundObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushActiveVisit(reason: "app-background")
        }
        let terminateObserver = center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushActiveVisit(reason: "app-terminate")
        }
        lifecycleObservers = [backgroundObserver, terminateObserver]
    }
    
    private func removeLifecycleObserversSync() {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers.removeAll()
    }
    
    nonisolated private func removeLifecycleObservers() {
        Task { @MainActor in
            lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
            lifecycleObservers.removeAll()
        }
    }
#endif
    
    private func persistVisit(_ visit: HeatmapVisit) async {
        guard let supabaseSink else { return }
        do {
            try await supabaseSink.insertVisit(visit)
        } catch {
            print("⚠️ [Heatmap] Failed to persist visit: \(error.localizedDescription)")
        }
    }
    
    private func resolvePlace(for hexId: String, coordinate: CLLocationCoordinate2D) async -> (placeName: String?, placeCategory: String?, placeAddress: String?) {
        if let cached = placeCache[hexId], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return (cached.name, cached.category, cached.address)
        }
        
        guard let googleService else {
            return (nil, nil, nil)
        }
        
        do {
            // Use a smaller radius (50m) for better precision, and get address
            if let candidate = try await googleService.lookupPlace(at: coordinate, radiusMeters: 50) {
                let category = mapCategory(from: candidate)
                let address = candidate.formattedAddress
                placeCache[hexId] = CachedPlace(name: candidate.name, category: category, address: address, timestamp: Date())
                return (candidate.name, category, address)
            } else {
                // No place found, try reverse geocoding for just the address
                let address = await reverseGeocode(coordinate: coordinate)
                placeCache[hexId] = CachedPlace(name: nil, category: nil, address: address, timestamp: Date())
                return (nil, nil, address)
            }
        } catch {
            print("⚠️ [Heatmap] Failed to resolve place: \(error)")
            // Fall back to reverse geocoding for address
            let address = await reverseGeocode(coordinate: coordinate)
            return (nil, nil, address)
        }
    }
    
    /// Reverse geocode to get address when no place is found
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                var addressParts: [String] = []
                if let streetNumber = placemark.subThoroughfare {
                    addressParts.append(streetNumber)
                }
                if let street = placemark.thoroughfare {
                    addressParts.append(street)
                }
                if let city = placemark.locality {
                    addressParts.append(city)
                }
                if let state = placemark.administrativeArea {
                    addressParts.append(state)
                }
                if let postalCode = placemark.postalCode {
                    addressParts.append(postalCode)
                }
                return addressParts.isEmpty ? nil : addressParts.joined(separator: ", ")
            }
        } catch {
            print("⚠️ [Heatmap] Reverse geocoding failed: \(error.localizedDescription)")
        }
        return nil
    }
    
    // MARK: - Helpers
    
    private func makeCell(from coordinate: CLLocationCoordinate2D) -> H3Cell? {
        let latLng = H3LatLng(latitudeDegs: coordinate.latitude, longitudeDegs: coordinate.longitude)
        return try? latLng.cell(at: hexResolution)
    }
    
    private func mapCategory(from candidate: GooglePlacesRoutesService.PlaceCandidate) -> String? {
        guard let types = candidate.types else { return nil }
        for type in types {
            if ["restaurant", "meal_takeaway", "cafe", "bar", "bakery"].contains(type) {
                return "restaurant"
            } else if ["store", "shopping_mall", "supermarket", "clothing_store"].contains(type) {
                return "store"
            } else if ["transit_station", "subway_station", "bus_station", "train_station"].contains(type) {
                return "transit"
            } else if ["park", "tourist_attraction", "point_of_interest"].contains(type) {
                return "amenity"
            } else if ["bank", "atm", "post_office", "pharmacy", "hospital"].contains(type) {
                return "service"
            }
        }
        return candidate.primaryType
    }
}

// MARK: - Supporting Types

private struct ActiveVisit {
    let cell: H3Cell
    let enteredAt: Date
    var lastUpdate: Date
    var lastLocation: CLLocation
}

private struct CachedPlace {
    let name: String?
    let category: String?
    let address: String?
    let timestamp: Date
}

