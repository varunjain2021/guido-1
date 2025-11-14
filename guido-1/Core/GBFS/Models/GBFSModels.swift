//
//  GBFSModels.swift
//  guido-1
//
//  Created by AI Assistant on 11/14/25.
//

import Foundation

// MARK: - Discovery

struct GBFSDiscoveryRoot: Codable {
    let lastUpdated: TimeInterval?
    let ttl: TimeInterval?
    let data: [String: GBFSDiscoveryLocaleFeeds]
    
    enum CodingKeys: String, CodingKey {
        case lastUpdated = "last_updated"
        case ttl
        case data
    }
}

struct GBFSDiscoveryLocaleFeeds: Codable {
    let feeds: [GBFSDiscoveryFeed]
}

struct GBFSDiscoveryFeed: Codable {
    let name: String
    let url: String
}

// MARK: - System Information

struct GBFSSystemInformationRoot: Codable {
    let lastUpdated: TimeInterval?
    let ttl: TimeInterval?
    let data: GBFSSystemInformation
    
    enum CodingKeys: String, CodingKey {
        case lastUpdated = "last_updated"
        case ttl
        case data
    }
}

struct GBFSSystemInformation: Codable {
    let systemID: String?
    let language: String?
    let name: String?
    
    enum CodingKeys: String, CodingKey {
        case systemID = "system_id"
        case language
        case name
    }
}

// MARK: - Station Information

struct GBFSStationInformationRoot: Codable {
    let lastUpdated: TimeInterval?
    let ttl: TimeInterval?
    let data: GBFSStationInformationContainer
    
    enum CodingKeys: String, CodingKey {
        case lastUpdated = "last_updated"
        case ttl
        case data
    }
}

struct GBFSStationInformationContainer: Codable {
    let stations: [GBFSStationInformation]
}

struct GBFSStationInformation: Codable {
    let stationID: String
    let name: String
    let lat: Double
    let lon: Double
    let capacity: Int?
    let regionID: String?
    let address: String?
    let postCode: String?
    let rentalUris: GBFSRentalURIs?
    let rentalMethods: [String]?
    let parkingType: String?
    let isValetStation: Bool?
    let isVirtualStation: Bool?
    
    enum CodingKeys: String, CodingKey {
        case stationID = "station_id"
        case name
        case lat
        case lon
        case capacity
        case regionID = "region_id"
        case address
        case postCode = "post_code"
        case rentalUris = "rental_uris"
        case rentalMethods = "rental_methods"
        case parkingType = "parking_type"
        case isValetStation = "is_valet_station"
        case isVirtualStation = "is_virtual_station"
    }
}

struct GBFSRentalURIs: Codable {
    let android: String?
    let ios: String?
    let web: String?
}

// MARK: - Station Status

struct GBFSStationStatusRoot: Codable {
    let lastUpdated: TimeInterval?
    let ttl: TimeInterval?
    let data: GBFSStationStatusContainer
    
    enum CodingKeys: String, CodingKey {
        case lastUpdated = "last_updated"
        case ttl
        case data
    }
}

struct GBFSStationStatusContainer: Codable {
    let stations: [GBFSStationStatus]
}

struct GBFSStationStatus: Codable {
    let stationID: String
    let numBikesAvailable: Int
    let numEbikesAvailable: Int?
    let numBikesDisabled: Int?
    let numDocksAvailable: Int?
    let numDocksDisabled: Int?
    let isInstalled: Bool?
    let isRenting: Bool?
    let isReturning: Bool?
    let lastReported: TimeInterval?
    let vehiclesAvailable: [GBFSVehicleAvailability]?
    
    enum CodingKeys: String, CodingKey {
        case stationID = "station_id"
        case numBikesAvailable = "num_bikes_available"
        case numEbikesAvailable = "num_ebikes_available"
        case numBikesDisabled = "num_bikes_disabled"
        case numDocksAvailable = "num_docks_available"
        case numDocksDisabled = "num_docks_disabled"
        case isInstalled = "is_installed"
        case isRenting = "is_renting"
        case isReturning = "is_returning"
        case lastReported = "last_reported"
        case vehiclesAvailable = "vehicle_types_available"
    }

    // Custom decoding to handle GBFS feeds that encode booleans as 0/1 or strings
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // station_id can be a string or number
        if let idString = try? container.decode(String.self, forKey: .stationID) {
            stationID = idString
        } else if let idInt = try? container.decode(Int.self, forKey: .stationID) {
            stationID = String(idInt)
        } else {
            stationID = try container.decode(String.self, forKey: .stationID)
        }
        
        // Int fields with flexible decoding
        numBikesAvailable = GBFSDecoders.decodeFlexibleInt(container, key: .numBikesAvailable) ?? 0
        numEbikesAvailable = GBFSDecoders.decodeFlexibleInt(container, key: .numEbikesAvailable)
        numBikesDisabled = GBFSDecoders.decodeFlexibleInt(container, key: .numBikesDisabled)
        numDocksAvailable = GBFSDecoders.decodeFlexibleInt(container, key: .numDocksAvailable)
        numDocksDisabled = GBFSDecoders.decodeFlexibleInt(container, key: .numDocksDisabled)
        
        // Boolean flags as true/false, 1/0, or strings
        isInstalled = GBFSDecoders.decodeFlexibleBool(container, key: .isInstalled)
        isRenting = GBFSDecoders.decodeFlexibleBool(container, key: .isRenting)
        isReturning = GBFSDecoders.decodeFlexibleBool(container, key: .isReturning)
        
        // last_reported can be seconds (Int), Double, or ISO string
        if let seconds = GBFSDecoders.decodeFlexibleDouble(container, key: .lastReported) {
            lastReported = seconds
        } else if let iso = try? container.decode(String.self, forKey: .lastReported) {
            // best-effort parse ISO8601 to seconds
            if let date = ISO8601DateFormatter().date(from: iso) {
                lastReported = date.timeIntervalSince1970
            } else {
                lastReported = nil
            }
        } else {
            lastReported = nil
        }
        
        vehiclesAvailable = try? container.decode([GBFSVehicleAvailability].self, forKey: .vehiclesAvailable)
    }
}

struct GBFSVehicleAvailability: Codable {
    let vehicleTypeID: String
    let count: Int
    
    enum CodingKeys: String, CodingKey {
        case vehicleTypeID = "vehicle_type_id"
        case count
    }
}

// MARK: - Vehicle Types

struct GBFSVehicleTypesRoot: Codable {
    let lastUpdated: TimeInterval?
    let ttl: TimeInterval?
    let data: GBFSVehicleTypesContainer
    
    enum CodingKeys: String, CodingKey {
        case lastUpdated = "last_updated"
        case ttl
        case data
    }
}

struct GBFSVehicleTypesContainer: Codable {
    let vehicleTypes: [GBFSVehicleType]
    
    enum CodingKeys: String, CodingKey {
        case vehicleTypes = "vehicle_types"
    }
}

struct GBFSVehicleType: Codable {
    let vehicleTypeID: String
    let formFactor: String?
    let propulsionType: String?
    let name: String?
    let maxRangeMeters: Double?
    
    enum CodingKeys: String, CodingKey {
        case vehicleTypeID = "vehicle_type_id"
        case formFactor = "form_factor"
        case propulsionType = "propulsion_type"
        case name
        case maxRangeMeters = "max_range_meters"
    }
}

// MARK: - Aggregated Views

struct GBFSStationView: Codable {
    let stationID: String
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double?
    let capacity: Int?
    let numBikesAvailable: Int
    let numEbikesAvailable: Int
    let numDocksAvailable: Int
    let isRenting: Bool
    let isReturning: Bool
    let lastReported: Date?
    let updatedAt: Date
    let address: String?
    let regionID: String?
    let rentalUris: GBFSRentalURIs?
    let isVirtual: Bool
    let isValet: Bool
    let stale: Bool
}

struct GBFSTypeBreakdown: Codable {
    let totalBikes: Int
    let totalEbikes: Int
    let totalDocks: Int
    let stationCount: Int
    let radiusMeters: Double
    let centerLatitude: Double
    let centerLongitude: Double
    let asOf: Date
    let stale: Bool
}

enum GBFSError: Error, LocalizedError {
    case invalidDiscoveryURL
    case feedUnavailable(String)
    case stationNotFound(String)
    case locationUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidDiscoveryURL:
            return "GBFS discovery URL is invalid or missing."
        case .feedUnavailable(let name):
            return "GBFS feed '\(name)' is unavailable."
        case .stationNotFound(let id):
            return "Station with id \(id) was not found."
        case .locationUnavailable:
            return "Current location is unavailable."
        }
    }
}

// MARK: - Flexible Decoders

enum GBFSDecoders {
    static func decodeFlexibleBool<Key>(_ container: KeyedDecodingContainer<Key>, key: Key) -> Bool? where Key: CodingKey {
        if let b = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return b
        }
        if let i = try? container.decodeIfPresent(Int.self, forKey: key) {
            return i != 0
        }
        if let s = try? container.decodeIfPresent(String.self, forKey: key) {
            let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lower == "true" || lower == "1" { return true }
            if lower == "false" || lower == "0" { return false }
        }
        return nil
    }
    
    static func decodeFlexibleInt<Key>(_ container: KeyedDecodingContainer<Key>, key: Key) -> Int? where Key: CodingKey {
        if let i = try? container.decodeIfPresent(Int.self, forKey: key) {
            return i
        }
        if let d = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(d.rounded())
        }
        if let s = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(s)
        }
        return nil
    }
    
    static func decodeFlexibleDouble<Key>(_ container: KeyedDecodingContainer<Key>, key: Key) -> Double? where Key: CodingKey {
        if let d = try? container.decodeIfPresent(Double.self, forKey: key) {
            return d
        }
        if let i = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(i)
        }
        if let s = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(s)
        }
        return nil
    }
}


