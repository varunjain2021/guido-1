//
//  SupabaseHeatmapSink.swift
//  guido-1
//
//  Created by GPT-5.1 Codex on 11/29/25.
//

import Foundation

enum HeatmapSinkError: Error, LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case serverError(statusCode: Int, body: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid Supabase endpoint for heatmap_visits"
        case .invalidResponse:
            return "Invalid response from Supabase"
        case .serverError(let code, let body):
            return "Supabase error (\(code)): \(body)"
        }
    }
}

final class SupabaseHeatmapSink {
    private let baseURL: String
    private let anonKey: String
    private let accessTokenProvider: () async -> String?
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private var visitsEndpoint: URL? {
        URL(string: baseURL)?.appendingPathComponent("rest/v1/heatmap_visits")
    }
    
    init(
        baseURL: String,
        anonKey: String,
        accessTokenProvider: @escaping () async -> String? = { nil },
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessTokenProvider = accessTokenProvider
        self.urlSession = urlSession
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }
    
    func insertVisit(_ visit: HeatmapVisit) async throws {
        guard let endpoint = visitsEndpoint else {
            throw HeatmapSinkError.invalidEndpoint
        }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        await setCommonHeaders(&request, prefer: "return=minimal")
        request.httpBody = try encoder.encode(visit)
        
        try await send(request: request)
    }
    
    func fetchVisits(userId: String, since: Date?) async throws -> [HeatmapVisit] {
        guard let endpoint = visitsEndpoint else {
            throw HeatmapSinkError.invalidEndpoint
        }
        
        // Supabase stores UUIDs in lowercase; normalize to match
        let normalizedUserId = userId.lowercased()
        
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "user_id", value: "eq.\(normalizedUserId)")
        ]
        if let since {
            let iso = ISO8601DateFormatter().string(from: since)
            queryItems.append(URLQueryItem(name: "entered_at", value: "gte.\(iso)"))
        }
        queryItems.append(URLQueryItem(name: "order", value: "entered_at.desc"))
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw HeatmapSinkError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        await setCommonHeaders(&request, prefer: nil)
        
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HeatmapSinkError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HeatmapSinkError.serverError(statusCode: http.statusCode, body: body)
        }
        
        return try decoder.decode([HeatmapVisit].self, from: data)
    }
    
    // MARK: - Helpers
    
    private func setCommonHeaders(_ request: inout URLRequest, prefer: String?) async {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let bearerToken = await accessTokenProvider() ?? anonKey
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }
    
    private func send(request: URLRequest) async throws {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HeatmapSinkError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HeatmapSinkError.serverError(statusCode: http.statusCode, body: body)
        }
    }
    
}

