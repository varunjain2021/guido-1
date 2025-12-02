//
//  HeatmapVisit.swift
//  guido-1
//
//  Created by GPT-5.1 Codex on 11/29/25.
//

import Foundation
import CoreLocation

struct HeatmapVisit: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: String?
    let hexId: String
    let centerLat: Double
    let centerLng: Double
    let placeName: String?
    let placeCategory: String?
    let placeAddress: String?
    let enteredAt: Date
    let exitedAt: Date
    let dwellSeconds: Int
    let dayOfWeek: String?       // e.g., "Monday", "Tuesday"
    let localHour: Int?          // 0-23, hour in user's local timezone
    let localTimeZone: String?   // e.g., "America/New_York"
    
    var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case hexId = "hex_id"
        case centerLat = "center_lat"
        case centerLng = "center_lng"
        case placeName = "place_name"
        case placeCategory = "category"
        case placeAddress = "place_address"
        case enteredAt = "entered_at"
        case exitedAt = "exited_at"
        case dwellSeconds = "dwell_seconds"
        case dayOfWeek = "day_of_week"
        case localHour = "local_hour"
        case localTimeZone = "local_timezone"
    }
    
    // Custom encoder so we let Supabase set user_id via DEFAULT auth.uid()
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hexId, forKey: .hexId)
        try container.encode(centerLat, forKey: .centerLat)
        try container.encode(centerLng, forKey: .centerLng)
        try container.encodeIfPresent(placeName, forKey: .placeName)
        try container.encodeIfPresent(placeCategory, forKey: .placeCategory)
        try container.encodeIfPresent(placeAddress, forKey: .placeAddress)
        try container.encode(enteredAt, forKey: .enteredAt)
        try container.encode(exitedAt, forKey: .exitedAt)
        try container.encode(dwellSeconds, forKey: .dwellSeconds)
        try container.encodeIfPresent(dayOfWeek, forKey: .dayOfWeek)
        try container.encodeIfPresent(localHour, forKey: .localHour)
        try container.encodeIfPresent(localTimeZone, forKey: .localTimeZone)
    }
}

