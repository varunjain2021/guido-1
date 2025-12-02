//
//  HeatmapViewModel.swift
//  guido-1
//
//  Created by GPT-5.1 Codex on 11/29/25.
//

import Foundation
import MapKit
import SwiftyH3

enum HeatmapRange: CaseIterable, Identifiable {
    case last7Days
    case last30Days
    case allTime
    
    var id: String { title }
    
    var title: String {
        switch self {
        case .last7Days: return "7d"
        case .last30Days: return "30d"
        case .allTime: return "All"
        }
    }
    
    var dateBoundary: Date? {
        let now = Date()
        switch self {
        case .last7Days:
            return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .last30Days:
            return Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .allTime:
            return nil
        }
    }
}

struct HeatmapHexOverlay: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let center: CLLocationCoordinate2D
    let dwellSeconds: Int
    let intensity: Double
    let resolution: Int
}

@MainActor
final class HeatmapViewModel: ObservableObject {
    @Published var overlays: [HeatmapHexOverlay] = []
    @Published var region: MKCoordinateRegion = HeatmapViewModel.defaultRegion()
    @Published var selectedRange: HeatmapRange = .last30Days
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentResolution: Int = 9 // H3 resolution based on zoom
    
    private let heatmapService = HeatmapService.shared
    
    /// Cached visits for re-aggregation on zoom changes
    private var cachedVisits: [HeatmapVisit] = []
    
    /// H3 resolution range: 1 (continent) to 9 (neighborhood)
    static let minResolution = 1
    static let maxResolution = 9
    
    func loadInitial() async {
        await refresh()
    }
    
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        let since = selectedRange.dateBoundary
        print("🗺️ [Heatmap] Fetching visits since: \(since?.description ?? "all time")")
        let visits = await heatmapService.fetchVisits(since: since)
        print("🗺️ [Heatmap] Fetched \(visits.count) visits from service")
        
        // Cache visits for zoom-based re-aggregation
        cachedVisits = visits
        
        generateOverlays(from: visits, atResolution: currentResolution)
        print("🗺️ [Heatmap] Generated \(overlays.count) overlays at resolution \(currentResolution)")
    }
    
    /// Called when map zoom level changes
    func updateForZoom(latitudeDelta: Double) {
        let newResolution = Self.resolutionForZoom(latitudeDelta: latitudeDelta)
        guard newResolution != currentResolution else { return }
        
        print("🗺️ [Heatmap] Zoom changed: latDelta=\(String(format: "%.4f", latitudeDelta)) → resolution \(newResolution)")
        currentResolution = newResolution
        
        // Re-aggregate at new resolution
        generateOverlays(from: cachedVisits, atResolution: newResolution)
    }
    
    /// Map latitude delta (zoom) to H3 resolution
    /// Smaller delta = more zoomed in = higher resolution
    /// H3 edge lengths: res0 ~1100km, res1 ~420km, res2 ~158km, res3 ~60km, res4 ~22km, res5 ~8km, res6 ~3km, res7 ~1.2km, res8 ~460m, res9 ~174m
    static func resolutionForZoom(latitudeDelta: Double) -> Int {
        // Approximate mapping based on what looks good at each zoom:
        // latDelta >= 100  → res 1 (continent scale, ~420km hexes)
        // latDelta >= 50   → res 2 (large country, ~158km hexes)
        // latDelta >= 20   → res 3 (country/multi-state, ~60km hexes)
        // latDelta >= 8    → res 4 (state/region, ~22km hexes)
        // latDelta >= 3    → res 5 (metro area, ~8km hexes)
        // latDelta >= 1    → res 6 (city, ~3km hexes)
        // latDelta >= 0.3  → res 7 (district, ~1.2km hexes)
        // latDelta >= 0.08 → res 8 (neighborhood, ~460m hexes)
        // latDelta < 0.08  → res 9 (block, ~174m hexes)
        switch latitudeDelta {
        case 100...:
            return 1
        case 50..<100:
            return 2
        case 20..<50:
            return 3
        case 8..<20:
            return 4
        case 3..<8:
            return 5
        case 1..<3:
            return 6
        case 0.3..<1:
            return 7
        case 0.08..<0.3:
            return 8
        default:
            return 9
        }
    }
    
    private func generateOverlays(from visits: [HeatmapVisit], atResolution resolution: Int) {
        guard !visits.isEmpty else {
            overlays = []
            region = HeatmapViewModel.defaultRegion()
            return
        }
        
        // Generate overlays at the specified resolution
        let allOverlays = Self.overlays(from: visits, atResolution: resolution)
        
        self.overlays = allOverlays
        updateRegion(from: allOverlays)
    }
    
    static func overlays(from visits: [HeatmapVisit], atResolution targetResolution: Int = 9) -> [HeatmapHexOverlay] {
        guard !visits.isEmpty else {
            print("🗺️ [Heatmap] overlays(from:) called with empty visits")
            return []
        }
        
        struct Bucket {
            var dwellSeconds: Int = 0
            var latSum: Double = 0
            var lngSum: Double = 0
            var count: Int = 0
        }
        
        var buckets: [String: Bucket] = [:]
        
        // Re-parent each visit's hex to the target resolution
        visits.forEach { visit in
            let parentHexId: String
            
            if targetResolution == 9 {
                // Use original hex (stored at res 9)
                parentHexId = visit.hexId
            } else {
                // Re-parent to coarser resolution
                if let cell = try? H3Cell(visit.hexId),
                   let resolution = H3Cell.Resolution(rawValue: Int32(targetResolution)),
                   let parentCell = try? cell.parent(at: resolution) {
                    parentHexId = parentCell.description
                } else {
                    // Fallback to original if re-parenting fails
                    parentHexId = visit.hexId
                }
            }
            
            var bucket = buckets[parentHexId, default: Bucket()]
            bucket.dwellSeconds += visit.dwellSeconds
            bucket.latSum += visit.centerLat
            bucket.lngSum += visit.centerLng
            bucket.count += 1
            buckets[parentHexId] = bucket
        }
        
        print("🗺️ [Heatmap] Aggregated \(visits.count) visits into \(buckets.count) hexes at resolution \(targetResolution)")
        
        let maxDwell = buckets.values.map(\.dwellSeconds).max() ?? 0
        var failedCells = 0
        let result = buckets.compactMap { hexId, bucket -> HeatmapHexOverlay? in
            guard let cell = try? H3Cell(hexId) else {
                print("⚠️ [Heatmap] Failed to parse H3Cell from hexId: \(hexId)")
                failedCells += 1
                return nil
            }
            guard let boundaryLatLng = try? cell.boundary else {
                print("⚠️ [Heatmap] Failed to get boundary for hexId: \(hexId)")
                failedCells += 1
                return nil
            }
            let coordinates = boundaryLatLng.map { CLLocationCoordinate2D(latitude: $0.latitudeDegs, longitude: $0.longitudeDegs) }
            guard coordinates.count >= 3 else {
                print("⚠️ [Heatmap] Boundary has < 3 coordinates for hexId: \(hexId)")
                failedCells += 1
                return nil
            }
            let center = CLLocationCoordinate2D(
                latitude: bucket.latSum / Double(bucket.count),
                longitude: bucket.lngSum / Double(bucket.count)
            )
            let normalized = maxDwell > 0 ? Double(bucket.dwellSeconds) / Double(maxDwell) : 0
            return HeatmapHexOverlay(
                id: hexId,
                coordinates: coordinates,
                center: center,
                dwellSeconds: bucket.dwellSeconds,
                intensity: max(0.08, normalized),
                resolution: targetResolution
            )
        }
        .sorted { $0.dwellSeconds > $1.dwellSeconds }
        
        if failedCells > 0 {
            print("⚠️ [Heatmap] \(failedCells) hexes failed to convert to overlays")
        }
        print("🗺️ [Heatmap] Successfully created \(result.count) overlays at resolution \(targetResolution)")
        
        return result
    }
    
    private func updateRegion(from overlays: [HeatmapHexOverlay]) {
        // Always center on current location if available
        let currentCoordinate = LocationManager.shared.currentLocation?.coordinate
        
        guard !overlays.isEmpty else {
            region = HeatmapViewModel.defaultRegion()
            return
        }
        
        // For initial load, use neighborhood-level zoom (res 9)
        // Cap at 0.05 latDelta to stay at neighborhood scale
        let maxInitialSpan: Double = 0.05
        
        // Center on current location if available, otherwise center on overlays
        let center: CLLocationCoordinate2D
        if let current = currentCoordinate {
            center = current
        } else {
            // Calculate center of overlays
            var minLat = overlays[0].center.latitude
            var maxLat = overlays[0].center.latitude
            var minLng = overlays[0].center.longitude
            var maxLng = overlays[0].center.longitude
            
            for overlay in overlays {
                minLat = min(minLat, overlay.center.latitude)
                maxLat = max(maxLat, overlay.center.latitude)
                minLng = min(minLng, overlay.center.longitude)
                maxLng = max(maxLng, overlay.center.longitude)
            }
            
            center = CLLocationCoordinate2D(
                latitude: (maxLat + minLat) / 2,
                longitude: (maxLng + minLng) / 2
            )
        }
        
        region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: maxInitialSpan, longitudeDelta: maxInitialSpan)
        )
    }
    
    /// Default region at neighborhood level (~0.05 latDelta corresponds to res 9)
    static func defaultRegion() -> MKCoordinateRegion {
        // Use a span that maps to resolution 9 (< 0.08 latDelta)
        let neighborhoodSpan = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        
        if let coordinate = LocationManager.shared.currentLocation?.coordinate {
            return MKCoordinateRegion(
                center: coordinate,
                span: neighborhoodSpan
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7812, longitude: -73.9665), // Upper West Side
            span: neighborhoodSpan
        )
    }
}

