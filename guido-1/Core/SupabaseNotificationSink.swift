//
//  SupabaseNotificationSink.swift
//  guido-1
//
//  Logs notification delivery and click events to Supabase for analytics
//

import Foundation
import UIKit

// MARK: - Notification Log Model

struct NotificationLogEntry: Encodable {
    let device_id: String
    let user_id: String?
    let campaign_id: String
    let notification_title: String
    let notification_body: String
    let scheduled_at: Date
    let delivered_at: Date
    let app_version: String?
    let os_version: String
    let timezone: String
}

struct NotificationClickUpdate: Encodable {
    let clicked: Bool
    let clicked_at: Date
}

// MARK: - Supabase Notification Sink

final class SupabaseNotificationSink {
    static let shared = SupabaseNotificationSink()
    
    private let tableName = "notification_logs"
    private var baseURL: String = ""
    private var anonKey: String = ""
    private var accessTokenProvider: (() async -> String?)?
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let defaults = UserDefaults.standard
    private let deviceIdKey = "notification.deviceId"
    
    private init() {
        self.urlSession = .shared
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }
    
    // MARK: - Configuration
    
    func configure(baseURL: String, anonKey: String, accessTokenProvider: @escaping () async -> String?) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessTokenProvider = accessTokenProvider
        print("✅ [NotificationSink] Configured with Supabase")
    }
    
    // MARK: - Device ID
    
    private var deviceId: String {
        if let existing = defaults.string(forKey: deviceIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        defaults.set(newId, forKey: deviceIdKey)
        return newId
    }
    
    // MARK: - Logging
    
    /// Log a notification when it's scheduled/delivered
    func logNotificationDelivered(
        campaignId: String,
        title: String,
        body: String,
        scheduledAt: Date,
        userId: String? = nil
    ) async {
        guard !baseURL.isEmpty else {
            print("⚠️ [NotificationSink] Not configured, skipping log")
            return
        }
        
        let entry = NotificationLogEntry(
            device_id: deviceId,
            user_id: userId,
            campaign_id: campaignId,
            notification_title: title,
            notification_body: body,
            scheduled_at: scheduledAt,
            delivered_at: Date(),
            app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            os_version: UIDevice.current.systemVersion,
            timezone: TimeZone.current.identifier
        )
        
        do {
            try await insertLog(entry)
            print("✅ [NotificationSink] Logged delivery for '\(campaignId)'")
            
            // Store the log ID locally for click tracking
            storeLastLogId(for: campaignId)
        } catch {
            print("❌ [NotificationSink] Failed to log delivery: \(error)")
        }
    }
    
    /// Log when a user clicks on a notification
    func logNotificationClicked(campaignId: String) async {
        guard !baseURL.isEmpty else { return }
        
        do {
            try await updateClickStatus(campaignId: campaignId, deviceId: deviceId)
            print("✅ [NotificationSink] Logged click for '\(campaignId)'")
        } catch {
            print("❌ [NotificationSink] Failed to log click: \(error)")
        }
    }
    
    // MARK: - Private API Methods
    
    private func insertLog(_ entry: NotificationLogEntry) async throws {
        guard let url = URL(string: baseURL)?.appendingPathComponent("rest/v1/\(tableName)") else {
            throw NSError(domain: "SupabaseNotificationSink", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let bearerToken = await accessTokenProvider?() ?? anonKey
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = try encoder.encode(entry)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "SupabaseNotificationSink", code: 2, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "SupabaseNotificationSink", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }
        
        // Parse response to get the inserted ID
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let firstRow = jsonArray.first,
           let id = firstRow["id"] as? String {
            storeLogId(id, for: entry.campaign_id)
        }
    }
    
    private func updateClickStatus(campaignId: String, deviceId: String) async throws {
        // Find the most recent notification log for this campaign and device
        guard let url = URL(string: baseURL)?.appendingPathComponent("rest/v1/\(tableName)") else {
            throw NSError(domain: "SupabaseNotificationSink", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Build URL with query params to find the latest unclicked notification for this campaign/device
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "device_id", value: "eq.\(deviceId)"),
            URLQueryItem(name: "campaign_id", value: "eq.\(campaignId)"),
            URLQueryItem(name: "clicked", value: "eq.false"),
            URLQueryItem(name: "order", value: "delivered_at.desc"),
            URLQueryItem(name: "limit", value: "1")
        ]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let bearerToken = await accessTokenProvider?() ?? anonKey
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        
        let update = NotificationClickUpdate(clicked: true, clicked_at: Date())
        request.httpBody = try encoder.encode(update)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "SupabaseNotificationSink", code: 2, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "SupabaseNotificationSink", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
    
    // MARK: - Local Storage for Log IDs
    
    private func storeLogId(_ id: String, for campaignId: String) {
        defaults.set(id, forKey: "notification.logId.\(campaignId)")
    }
    
    private func storeLastLogId(for campaignId: String) {
        // Mark that we have a pending notification for this campaign
        defaults.set(Date(), forKey: "notification.lastDelivered.\(campaignId)")
    }
    
    private func getStoredLogId(for campaignId: String) -> String? {
        defaults.string(forKey: "notification.logId.\(campaignId)")
    }
}

