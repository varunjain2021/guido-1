import Foundation
import CoreLocation
import UIKit

@MainActor
public final class RouteSnapshotService: ObservableObject {
    public struct SnapshotRequest: Hashable {
        public let latitude: Double
        public let longitude: Double
        public let heading: Double?      // degrees (0-360), nil => API auto
        public let fov: Int              // 10–120 (Street View Static API)
        public let pitch: Int            // -90 – 90 (down to up)
        public let size: CGSize          // pixels; API caps apply
        
        public init(latitude: Double,
                    longitude: Double,
                    heading: Double?,
                    fov: Int = 75,
                    pitch: Int = -5,
                    size: CGSize = .init(width: 640, height: 640)) {
            self.latitude = latitude
            self.longitude = longitude
            self.heading = heading.map { RouteSnapshotService.wrapHeading($0) }
            self.fov = max(10, min(fov, 120))
            self.pitch = max(-90, min(pitch, 90))
            self.size = size
        }
        
        public func cacheKey() -> String {
            let h = heading.map { String(format: "%.1f", $0) } ?? "auto"
            return String(format: "lat=%.6f|lng=%.6f|h=%@|fov=%d|pitch=%d|w=%d|h=%d",
                          latitude, longitude, h, fov, pitch, Int(size.width), Int(size.height))
        }
    }
    
    public struct RouteStepPoints {
        public let midpoint: CLLocationCoordinate2D
        public let turnPoint: CLLocationCoordinate2D
        public let approachBearing: Double?  // optional override
        public let exitBearing: Double?      // optional override
        
        public init(midpoint: CLLocationCoordinate2D,
                    turnPoint: CLLocationCoordinate2D,
                    approachBearing: Double? = nil,
                    exitBearing: Double? = nil) {
            self.midpoint = midpoint
            self.turnPoint = turnPoint
            self.approachBearing = approachBearing
            self.exitBearing = exitBearing
        }
    }
    
    public struct RouteSnapshot {
        public let imageData: Data
        public let request: SnapshotRequest
        public let fetchedAt: Date
        public let attribution: String = "Imagery © Google"
    }
    
    private struct CacheEntry: Codable {
        let data: Data
        let expiry: Date
    }
    
    private let googleAPIKey: String
    private let urlSession: URLSession
    private let ttlSeconds: TimeInterval
    private let memoryCache = NSCache<NSString, NSData>()
    private let diskCacheDirectory: URL
    private let maxRetries = 2
    
    public init(googleAPIKey: String,
                urlSession: URLSession = .shared,
                ttlSeconds: TimeInterval = 2 * 60 * 60) { // default 2 hours per plan
        self.googleAPIKey = googleAPIKey
        self.urlSession = urlSession
        self.ttlSeconds = ttlSeconds
        
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskCacheDirectory = cachesDir.appendingPathComponent("StreetViewSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
        
        memoryCache.countLimit = 128
        memoryCache.totalCostLimit = 64 * 1024 * 1024 // 64 MB
    }
    
    // MARK: - Public API
    
    /// Fetches candidate snapshots for a route step using approach and exit headings.
    /// Returns in best-effort order: approach, exit, auto.
    public func fetchCandidates(for step: RouteStepPoints,
                                fov: Int = 75,
                                denseIntersection: Bool = false,
                                pitch: Int = -5,
                                size: CGSize = .init(width: 640, height: 640)) async -> [RouteSnapshot] {
        let selectedFOV = denseIntersection ? max(10, min(60, fov)) : fov
        let approachHeading = step.approachBearing ?? Self.computeBearing(from: step.midpoint, to: step.turnPoint)
        let exitHeading = step.exitBearing ?? Self.computeBearing(from: step.turnPoint, to: step.midpoint)
        
        let approachReq = SnapshotRequest(latitude: step.midpoint.latitude,
                                          longitude: step.midpoint.longitude,
                                          heading: approachHeading,
                                          fov: selectedFOV,
                                          pitch: pitch,
                                          size: size)
        let exitReq = SnapshotRequest(latitude: step.turnPoint.latitude,
                                      longitude: step.turnPoint.longitude,
                                      heading: exitHeading,
                                      fov: selectedFOV,
                                      pitch: pitch,
                                      size: size)
        let autoReq = SnapshotRequest(latitude: step.turnPoint.latitude,
                                      longitude: step.turnPoint.longitude,
                                      heading: nil,
                                      fov: selectedFOV,
                                      pitch: pitch,
                                      size: size)
        
        async let a = fetchSnapshotIfAvailable(approachReq)
        async let b = fetchSnapshotIfAvailable(exitReq)
        async let c = fetchSnapshotIfAvailable(autoReq)
        
        let results = await [a, b, c].compactMap { $0 }
        return results
    }
    
    /// Fetch a single snapshot; applies transient cache, TTL, and retries/fallbacks.
    public func fetchSnapshot(_ request: SnapshotRequest) async -> RouteSnapshot? {
        if let cached = readCache(for: request.cacheKey()) {
            return RouteSnapshot(imageData: cached, request: request, fetchedAt: Date())
        }
        
        // Try main request; on failure, attempt limited fallbacks
        var attempts: [SnapshotRequest] = [request]
        if let h = request.heading {
            // fallback to slight +/- heading to mitigate misalignment
            attempts.append(SnapshotRequest(latitude: request.latitude, longitude: request.longitude, heading: Self.wrapHeading(h + 20), fov: request.fov, pitch: request.pitch, size: request.size))
            attempts.append(SnapshotRequest(latitude: request.latitude, longitude: request.longitude, heading: Self.wrapHeading(h - 20), fov: request.fov, pitch: request.pitch, size: request.size))
            // final fallback: auto heading
            attempts.append(SnapshotRequest(latitude: request.latitude, longitude: request.longitude, heading: nil, fov: request.fov, pitch: request.pitch, size: request.size))
        }
        
        for (idx, attempt) in attempts.enumerated() {
            if let data = try? await downloadImageData(for: attempt) {
                writeCache(data, for: attempt.cacheKey())
                return RouteSnapshot(imageData: data, request: attempt, fetchedAt: Date())
            }
            if idx >= maxRetries { break }
        }
        return nil
    }
    
    // MARK: - Internals
    
    private func fetchSnapshotIfAvailable(_ request: SnapshotRequest) async -> RouteSnapshot? {
        return await fetchSnapshot(request)
    }
    
    private func downloadImageData(for request: SnapshotRequest) async throws -> Data {
        guard let url = buildStreetViewURL(for: request) else {
            throw URLError(.badURL)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 10
        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "RouteSnapshotService", code: code, userInfo: [NSLocalizedDescriptionKey: "Street View fetch failed (")
        }
        // Some error responses may be images with error text; basic guard on size
        if data.count < 512 { // too small, likely error
            throw NSError(domain: "RouteSnapshotService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Image too small"])
        }
        return data
    }
    
    private func buildStreetViewURL(for request: SnapshotRequest) -> URL? {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/streetview")
        let sizeParam = "\(Int(request.size.width))x\(Int(request.size.height))"
        var query: [URLQueryItem] = [
            .init(name: "size", value: sizeParam),
            .init(name: "location", value: String(format: "%.6f,%.6f", request.latitude, request.longitude)),
            .init(name: "fov", value: String(request.fov)),
            .init(name: "pitch", value: String(request.pitch)),
            .init(name: "key", value: googleAPIKey)
        ]
        if let heading = request.heading {
            query.append(.init(name: "heading", value: String(format: "%.1f", Self.wrapHeading(heading))))
        }
        components?.queryItems = query
        return components?.url
    }
    
    // MARK: - Caching
    
    private func cacheURL(for key: String) -> URL {
        let hashed = String(key.hashValue)
        return diskCacheDirectory.appendingPathComponent(hashed).appendingPathExtension("json")
    }
    
    private func readCache(for key: String) -> Data? {
        let nsKey = key as NSString
        if let mem = memoryCache.object(forKey: nsKey) {
            return Data(referencing: mem)
        }
        let url = cacheURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else { return nil }
        if Date() <= entry.expiry {
            memoryCache.setObject(entry.data as NSData, forKey: nsKey, cost: entry.data.count)
            return entry.data
        } else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
    
    private func writeCache(_ data: Data, for key: String) {
        let nsKey = key as NSString
        memoryCache.setObject(data as NSData, forKey: nsKey, cost: data.count)
        let entry = CacheEntry(data: data, expiry: Date().addingTimeInterval(ttlSeconds))
        let url = cacheURL(for: key)
        if let payload = try? JSONEncoder().encode(entry) {
            try? payload.write(to: url, options: [.atomic])
        }
    }
    
    // MARK: - Utilities
    
    private static func wrapHeading(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360.0)
        if d < 0 { d += 360.0 }
        return d
    }
    
    public static func computeBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let brng = atan2(y, x) * 180 / .pi
        return wrapHeading(brng)
    }
}
