//
//  guido_1Tests.swift
//  guido-1Tests
//
//  Created by Varun Jain on 7/26/25.
//

import Testing
@testable import guido_1

struct guido_1Tests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @MainActor
    @Test func testBuildDirectionsURLs() async throws {
        let locationManager = LocationManager()
        let service = GooglePlacesRoutesService(apiKey: "test-key", locationManager: locationManager)

        let destination = "1600 Amphitheatre Parkway, Mountain View, CA"
        let walkingURLs = service.buildDirectionsURLs(to: destination, mode: "walking")

        #expect(walkingURLs != nil, "Expected walking URLs to be generated")
        if let urls = walkingURLs {
            #expect(urls.web.absoluteString.contains("travelmode=walking"))
            #expect(urls.web.absoluteString.contains("destination=1600%20Amphitheatre%20Parkway"))
            #expect(urls.app != nil)
            #expect(urls.app?.absoluteString.contains("directionsmode=walking") == true)
        }

        let fallbackURLs = service.buildDirectionsURLs(to: destination, mode: "scooter")
        #expect(fallbackURLs != nil, "Expected fallback URLs to be generated")
        if let urls = fallbackURLs {
            #expect(urls.web.absoluteString.contains("travelmode=driving"))
        }
    }
}
