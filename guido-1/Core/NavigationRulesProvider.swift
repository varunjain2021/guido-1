import Foundation

struct NavigationRulesProvider {
    static func loadRulesText() -> String {
        // Prefer bundle resource
        if let url = Bundle.main.url(forResource: "navigation-rules", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let text = format(jsonData: data) { return text }

        #if DEBUG
        // Fallback to repo path in debug/dev
        let devPath = "/Users/varunjain/Documents/guido-1/navigation-rules.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: devPath)),
           let text = format(jsonData: data) { return text }
        #endif

        return ""
    }

    private static func format(jsonData: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
        // Preserve section order if numbers exist; otherwise alphabetical
        let keys = obj.keys.sorted { a, b in
            let na = Int(a.split(separator: ".").first ?? "") ?? Int.max
            let nb = Int(b.split(separator: ".").first ?? "") ?? Int.max
            return (na, a) < (nb, b)
        }
        var lines: [String] = []
        for key in keys {
            lines.append("- \(key):")
            if let arr = obj[key] as? [String] {
                for rule in arr {
                    lines.append("  • \(rule)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
