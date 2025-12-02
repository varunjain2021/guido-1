import Testing
import CoreLocation
import SwiftyH3
@testable import guido_1

struct HeatmapViewModelTests {
    @Test
    func testOverlayAggregationNormalizesIntensity() async throws {
        let latLngA = H3LatLng(latitudeDegs: 40.7812, longitudeDegs: -73.9665)
        let latLngB = H3LatLng(latitudeDegs: 40.745, longitudeDegs: -73.988)
        let cellA = try #require(latLngA.cell(at: .res9))
        let cellB = try #require(latLngB.cell(at: .res9))
        let centerA = try #require(cellA.center.coordinates)
        let centerB = try #require(cellB.center.coordinates)
        let now = Date()
        
        let visits = [
            HeatmapVisit(
                id: UUID(),
                userId: "user",
                hexId: cellA.description,
                centerLat: centerA.latitude,
                centerLng: centerA.longitude,
                placeName: "Cafe",
                placeCategory: "restaurant",
                enteredAt: now.addingTimeInterval(-3600),
                exitedAt: now.addingTimeInterval(-3000),
                dwellSeconds: 600
            ),
            HeatmapVisit(
                id: UUID(),
                userId: "user",
                hexId: cellA.description,
                centerLat: centerA.latitude,
                centerLng: centerA.longitude,
                placeName: nil,
                placeCategory: nil,
                enteredAt: now.addingTimeInterval(-2800),
                exitedAt: now.addingTimeInterval(-2500),
                dwellSeconds: 300
            ),
            HeatmapVisit(
                id: UUID(),
                userId: "user",
                hexId: cellB.description,
                centerLat: centerB.latitude,
                centerLng: centerB.longitude,
                placeName: "Station",
                placeCategory: "transit",
                enteredAt: now.addingTimeInterval(-2000),
                exitedAt: now.addingTimeInterval(-1000),
                dwellSeconds: 900
            )
        ]
        
        let overlays = HeatmapViewModel.overlays(from: visits)
        #expect(overlays.count == 2)
        
        let top = overlays.first(where: { $0.id == cellB.description })
        let other = overlays.first(where: { $0.id == cellA.description })
        #expect(top?.intensity ?? 0.0 == 1.0)
        #expect((other?.intensity ?? 0.0) < 1.0)
        #expect(top?.dwellSeconds == 900)
        #expect((other?.dwellSeconds ?? 0) == 900) // 600 + 300
    }
}

