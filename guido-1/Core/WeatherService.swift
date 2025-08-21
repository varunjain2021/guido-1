import Foundation
import CoreLocation

@MainActor
class WeatherService: ObservableObject {
    private let apiKey: String
    private let session: URLSession = .shared
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func getCurrentWeather(lat: Double, lon: Double) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "WeatherService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Weather API key missing"])
        }
        var comps = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
        comps.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "appid", value: apiKey)
        ]
        let (data, response) = try await session.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "WeatherService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Weather error: \(msg)"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "WeatherService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid weather JSON"])
        }
        return summarizeWeather(json: json)
    }
    
    private func summarizeWeather(json: [String: Any]) -> String {
        let name = json["name"] as? String ?? "Current location"
        let main = json["main"] as? [String: Any]
        let temp = main?["temp"] as? Double ?? 0
        let weatherArray = (json["weather"] as? [[String: Any]]) ?? []
        let desc = weatherArray.first?["description"] as? String ?? ""
        return "Weather for \(name): \(Int(round(temp)))°C, \(desc)"
    }
}

