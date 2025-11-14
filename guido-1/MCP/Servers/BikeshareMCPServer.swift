//
//  BikeshareMCPServer.swift
//  guido-1
//
//  Created by AI Assistant on 11/14/25.
//

import Foundation
import CoreLocation

public final class BikeshareMCPServer {
    
    // MARK: - Properties
    
    private weak var locationManager: LocationManager?
    private var gbfsService: GBFSService?
    private let serverInfo = MCPServerInfo(name: "Guido Bikeshare Server", version: "1.0.0")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    
    // MARK: - Configuration
    
    @MainActor
    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
    }
    
    func setGBFSService(_ service: GBFSService) {
        self.gbfsService = service
    }
    
    // MARK: - MCP Interface
    
    public func getCapabilities() -> MCPCapabilities {
        MCPCapabilities(
            tools: MCPToolsCapability(listChanged: true),
            resources: nil,
            prompts: nil,
            sampling: nil
        )
    }
    
    public func getServerInfo() -> MCPServerInfo { serverInfo }
    
    public func listTools() -> [MCPTool] {
        [
            bikesNearbyTool(),
            docksNearbyTool(),
            stationAvailabilityTool(),
            typeBreakdownTool(),
            parkingNearDestinationTool()
        ]
    }
    
    public func callTool(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        switch request.name {
        case "bikes_nearby":
            return await executeBikesNearby(request)
        case "docks_nearby":
            return await executeDocksNearby(request)
        case "station_availability":
            return await executeStationAvailability(request)
        case "type_breakdown_nearby":
            return await executeTypeBreakdown(request)
        case "parking_near_destination":
            return await executeParkingNearDestination(request)
        default:
            return MCPCallToolResponse(content: [MCPContent(text: "Unknown tool \(request.name)")], isError: true)
        }
    }
    
    // MARK: - Tool Definitions
    
    private func bikesNearbyTool() -> MCPTool {
        MCPTool(
            name: "bikes_nearby",
            description: "List nearby Citi Bike stations with available bikes/e-bikes",
            inputSchema: MCPToolInputSchema(properties: [
                "radius_m": MCPPropertySchema(type: "number", description: "Search radius in meters (default 500)"),
                "limit": MCPPropertySchema(type: "number", description: "Maximum number of stations to return (default 5)"),
                "min_bikes": MCPPropertySchema(type: "number", description: "Minimum bikes required at station (default 1)"),
                "types": MCPPropertySchema(type: "string", description: "Filter by bike type", enumValues: ["any","bike","ebike"]),
                "lat": MCPPropertySchema(type: "number", description: "Override latitude for search (optional)"),
                "lon": MCPPropertySchema(type: "number", description: "Override longitude for search (optional)")
            ], required: [])
        )
    }
    
    private func docksNearbyTool() -> MCPTool {
        MCPTool(
            name: "docks_nearby",
            description: "Find nearby stations with available docks for parking",
            inputSchema: MCPToolInputSchema(properties: [
                "radius_m": MCPPropertySchema(type: "number", description: "Search radius in meters (default 500)"),
                "limit": MCPPropertySchema(type: "number", description: "Maximum number of stations to return (default 5)"),
                "min_docks": MCPPropertySchema(type: "number", description: "Minimum docks required (default 1)"),
                "lat": MCPPropertySchema(type: "number", description: "Override latitude (optional)"),
                "lon": MCPPropertySchema(type: "number", description: "Override longitude (optional)")
            ], required: [])
        )
    }
    
    private func stationAvailabilityTool() -> MCPTool {
        MCPTool(
            name: "station_availability",
            description: "Get live availability for a specific station id",
            inputSchema: MCPToolInputSchema(properties: [
                "station_id": MCPPropertySchema(type: "string", description: "Citi Bike station ID"),
                "reference_lat": MCPPropertySchema(type: "number", description: "Optional latitude to compute distance"),
                "reference_lon": MCPPropertySchema(type: "number", description: "Optional longitude to compute distance")
            ], required: ["station_id"])
        )
    }
    
    private func typeBreakdownTool() -> MCPTool {
        MCPTool(
            name: "type_breakdown_nearby",
            description: "Summarize bikes, e-bikes, and docks near the current location",
            inputSchema: MCPToolInputSchema(properties: [
                "radius_m": MCPPropertySchema(type: "number", description: "Radius in meters (default 500)"),
                "lat": MCPPropertySchema(type: "number", description: "Override latitude (optional)"),
                "lon": MCPPropertySchema(type: "number", description: "Override longitude (optional)")
            ], required: [])
        )
    }
    
    private func parkingNearDestinationTool() -> MCPTool {
        MCPTool(
            name: "parking_near_destination",
            description: "Find docking stations near a specified destination",
            inputSchema: MCPToolInputSchema(properties: [
                "lat": MCPPropertySchema(type: "number", description: "Destination latitude"),
                "lon": MCPPropertySchema(type: "number", description: "Destination longitude"),
                "radius_m": MCPPropertySchema(type: "number", description: "Search radius in meters (default 500)"),
                "limit": MCPPropertySchema(type: "number", description: "Maximum stations to return (default 5)"),
                "min_docks": MCPPropertySchema(type: "number", description: "Minimum available docks (default 1)")
            ], required: ["lat", "lon"])
        )
    }
    
    // MARK: - Tool Execution
    
    private func executeBikesNearby(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let service = gbfsService else {
            return MCPCallToolResponse(content: [MCPContent(text: "GBFS service unavailable")], isError: true)
        }
        guard let coordinate = await resolveCoordinate(arguments: request.arguments) else {
            return MCPCallToolResponse(content: [MCPContent(text: GBFSError.locationUnavailable.localizedDescription)], isError: true)
        }
        let radius = (request.arguments?["radius_m"] as? Double) ?? 500
        let limit = Int((request.arguments?["limit"] as? Double) ?? 5)
        let minBikes = Int((request.arguments?["min_bikes"] as? Double) ?? 1)
        let types = GBFSService.BikeTypeFilter.fromArgument(request.arguments?["types"])
        
        do {
            let results = try await service.bikesNear(
                lat: coordinate.latitude,
                lon: coordinate.longitude,
                radiusMeters: radius,
                minCount: minBikes,
                types: types,
                limit: limit
            )
            return encodeSuccess(results)
        } catch {
            return encodeError(error)
        }
    }
    
    private func executeDocksNearby(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let service = gbfsService else {
            return MCPCallToolResponse(content: [MCPContent(text: "GBFS service unavailable")], isError: true)
        }
        guard let coordinate = await resolveCoordinate(arguments: request.arguments) else {
            return MCPCallToolResponse(content: [MCPContent(text: GBFSError.locationUnavailable.localizedDescription)], isError: true)
        }
        let radius = (request.arguments?["radius_m"] as? Double) ?? 500
        let limit = Int((request.arguments?["limit"] as? Double) ?? 5)
        let minDocks = Int((request.arguments?["min_docks"] as? Double) ?? 1)
        
        do {
            let results = try await service.docksNear(
                lat: coordinate.latitude,
                lon: coordinate.longitude,
                radiusMeters: radius,
                minDocks: minDocks,
                limit: limit
            )
            return encodeSuccess(results)
        } catch {
            return encodeError(error)
        }
    }
    
    private func executeStationAvailability(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let service = gbfsService else {
            return MCPCallToolResponse(content: [MCPContent(text: "GBFS service unavailable")], isError: true)
        }
        guard let stationID = request.arguments?["station_id"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "station_id is required")], isError: true)
        }
        let referenceLat = request.arguments?["reference_lat"] as? Double
        let referenceLon = request.arguments?["reference_lon"] as? Double
        
        do {
            let view = try await service.availabilityFor(stationID: stationID, referenceLat: referenceLat, referenceLon: referenceLon)
            return encodeSuccess(view)
        } catch {
            return encodeError(error)
        }
    }
    
    private func executeTypeBreakdown(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let service = gbfsService else {
            return MCPCallToolResponse(content: [MCPContent(text: "GBFS service unavailable")], isError: true)
        }
        guard let coordinate = await resolveCoordinate(arguments: request.arguments) else {
            return MCPCallToolResponse(content: [MCPContent(text: GBFSError.locationUnavailable.localizedDescription)], isError: true)
        }
        let radius = (request.arguments?["radius_m"] as? Double) ?? 500
        
        do {
            let breakdown = try await service.typeBreakdownNear(
                lat: coordinate.latitude,
                lon: coordinate.longitude,
                radiusMeters: radius
            )
            return encodeSuccess(breakdown)
        } catch {
            return encodeError(error)
        }
    }
    
    private func executeParkingNearDestination(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let service = gbfsService else {
            return MCPCallToolResponse(content: [MCPContent(text: "GBFS service unavailable")], isError: true)
        }
        guard
            let lat = request.arguments?["lat"] as? Double,
            let lon = request.arguments?["lon"] as? Double
        else {
            return MCPCallToolResponse(content: [MCPContent(text: "lat and lon are required")], isError: true)
        }
        let radius = (request.arguments?["radius_m"] as? Double) ?? 500
        let limit = Int((request.arguments?["limit"] as? Double) ?? 5)
        let minDocks = Int((request.arguments?["min_docks"] as? Double) ?? 1)
        
        do {
            let results = try await service.parkingNearDestination(
                lat: lat,
                lon: lon,
                radiusMeters: radius,
                minDocks: minDocks,
                limit: limit
            )
            return encodeSuccess(results)
        } catch {
            return encodeError(error)
        }
    }
    
    // MARK: - Helpers
    
    private func resolveCoordinate(arguments: [String: Any]?) async -> CLLocationCoordinate2D? {
        if
            let lat = arguments?["lat"] as? Double,
            let lon = arguments?["lon"] as? Double
        {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return await MainActor.run { locationManager?.currentLocation?.coordinate }
    }
    
    private func encodeSuccess<T: Encodable>(_ value: T) -> MCPCallToolResponse {
        do {
            let data = try encoder.encode(value)
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return MCPCallToolResponse(content: [MCPContent(text: text)], isError: false)
        } catch {
            return MCPCallToolResponse(content: [MCPContent(text: "Encoding error: \(error.localizedDescription)")], isError: true)
        }
    }
    
    private func encodeError(_ error: Error) -> MCPCallToolResponse {
        let message: String
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            message = description
        } else {
            message = error.localizedDescription
        }
        return MCPCallToolResponse(content: [MCPContent(text: message)], isError: true)
    }
}


