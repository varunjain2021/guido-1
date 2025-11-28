//
//  SupabaseSessionLogSink.swift
//  guido-1
//
//  Created by CursorAI on 11/28/25.
//

import Foundation

private struct SupabaseSessionPayload: Encodable {
    let session_id: String
    let user_id: String?
    let user_email: String?
    let events: [SessionEvent]
    let metadata: SessionMetadata
    let last_known_location: SessionLocationSnapshot?
    let started_at: Date
    let ended_at: Date?
    let error_summary: String?
    
    init(recording: SessionRecording) {
        self.session_id = recording.sessionId
        self.user_id = recording.userId
        self.user_email = recording.userEmail
        self.events = recording.events
        self.metadata = recording.metadata
        self.last_known_location = recording.lastKnownLocation
        self.started_at = recording.startedAt
        self.ended_at = recording.endedAt
        self.error_summary = recording.errorSummary
    }
}

final class SupabaseSessionLogSink: SessionLogSink {
    private let endpoint: URL?
    private let anonKey: String
    private let accessTokenProvider: () -> String?
    private let urlSession: URLSession
    private let maxRetries: Int
    private let encoder: JSONEncoder
    
    init(
        baseURL: String,
        anonKey: String,
        accessTokenProvider: @escaping () -> String? = { nil },
        urlSession: URLSession = .shared,
        maxRetries: Int = 2
    ) {
        self.endpoint = URL(string: baseURL)?.appendingPathComponent("rest/v1/session_recordings")
        self.anonKey = anonKey
        self.accessTokenProvider = accessTokenProvider
        self.urlSession = urlSession
        self.maxRetries = maxRetries
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }
    
    func persist(recording: SessionRecording) async throws {
        guard let endpoint else {
            throw SessionLoggerError.sinkUnavailable
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let bearerToken = accessTokenProvider() ?? anonKey
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(SupabaseSessionPayload(recording: recording))
        
        try await send(request: request)
    }
    
    private func send(request: URLRequest) async throws {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw SessionLoggerError.sinkUnavailable
                }
                if (200..<300).contains(httpResponse.statusCode) {
                    return
                }
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "SupabaseSessionLogSink", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let backoff = UInt64(pow(2.0, Double(attempt))) * 200_000_000
                    try await Task.sleep(nanoseconds: backoff)
                    continue
                } else {
                    throw error
                }
            }
        }
        if let lastError {
            throw lastError
        }
    }
}

