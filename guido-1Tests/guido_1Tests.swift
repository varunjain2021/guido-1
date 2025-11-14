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

    @Test func testGBFSServiceBikesNear() async throws {
        let fixtures: [String: String] = [
            "https://example.com/gbfs.json": """
            {
              "last_updated": 1731600000,
              "ttl": 0,
              "data": {
                "en": {
                  "feeds": [
                    {"name": "station_information", "url": "https://example.com/station_information.json"},
                    {"name": "station_status", "url": "https://example.com/station_status.json"},
                    {"name": "vehicle_types", "url": "https://example.com/vehicle_types.json"}
                  ]
                }
              }
            }
            """,
            "https://example.com/station_information.json": """
            {
              "last_updated": 1731600000,
              "ttl": 30,
              "data": {
                "stations": [
                  {"station_id": "72", "name": "Hudson & 14", "lat": 40.741, "lon": -74.003, "capacity": 25, "address": "W 14th St", "region_id": "downtown"},
                  {"station_id": "79", "name": "Madison & 39", "lat": 40.749, "lon": -73.981, "capacity": 30, "address": "E 39th St"}
                ]
              }
            }
            """,
            "https://example.com/station_status.json": """
            {
              "last_updated": 1731600010,
              "ttl": 30,
              "data": {
                "stations": [
                  {"station_id": "72", "num_bikes_available": 8, "num_ebikes_available": 3, "num_docks_available": 12, "is_renting": true, "is_returning": true, "last_reported": 1731600005},
                  {"station_id": "79", "num_bikes_available": 2, "num_ebikes_available": 0, "num_docks_available": 18, "is_renting": true, "is_returning": true, "last_reported": 1731600005}
                ]
              }
            }
            """,
            "https://example.com/vehicle_types.json": """
            {
              "last_updated": 1731600000,
              "ttl": 60,
              "data": {
                "vehicle_types": [
                  {"vehicle_type_id": "bike", "form_factor": "bicycle", "propulsion_type": "human"},
                  {"vehicle_type_id": "ebike", "form_factor": "bicycle", "propulsion_type": "electric_assist"}
                ]
              }
            }
            """
        ]

        MockURLProtocol.requestHandler = { request in
            guard
                let url = request.url,
                let body = fixtures[url.absoluteString],
                let data = body.data(using: .utf8)
            else {
                throw TestError.missingFixture
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, data)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let service = GBFSService(discoveryURL: URL(string: "https://example.com/gbfs.json")!, urlSession: session)

        let results = try await service.bikesNear(
            lat: 40.742,
            lon: -74.0,
            radiusMeters: 2000,
            minCount: 1,
            types: .any,
            limit: 5
        )

        #expect(results.count == 2)
        #expect(results.first?.stationID == "72")
        #expect(results.first?.numEbikesAvailable == 3)
        #expect(results.first?.stale == false)

        let breakdown = try await service.typeBreakdownNear(
            lat: 40.742,
            lon: -74.0,
            radiusMeters: 2000
        )

        #expect(breakdown.totalBikes == 10)
        #expect(breakdown.totalEbikes == 3)
        #expect(breakdown.stationCount == 2)
    }
}

private enum TestError: Error {
    case missingFixture
}

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: TestError.missingFixture)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
