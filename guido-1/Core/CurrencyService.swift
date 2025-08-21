import Foundation

@MainActor
class CurrencyService: ObservableObject {
    private let session: URLSession = .shared
    // Using exchangerate.host (free) — no key required
    
    func convert(amount: Double, from: String, to: String) async throws -> (Double, Double) {
        var comps = URLComponents(string: "https://api.exchangerate.host/convert")!
        comps.queryItems = [
            URLQueryItem(name: "from", value: from.uppercased()),
            URLQueryItem(name: "to", value: to.uppercased()),
            URLQueryItem(name: "amount", value: String(amount))
        ]
        let (data, response) = try await session.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "CurrencyService", code: 1, userInfo: [NSLocalizedDescriptionKey: "FX error: \(msg)"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? Double,
              let info = json["info"] as? [String: Any],
              let rate = info["rate"] as? Double else {
            throw NSError(domain: "CurrencyService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid FX JSON"])
        }
        return (result, rate)
    }
}

