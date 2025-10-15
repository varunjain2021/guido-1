import Foundation

struct NavigationStyleGuard {
    struct Result { let text: String; let violations: [String] }

    static func enforce(_ text: String) -> Result {
        var output = text
        var violations: [String] = []

        // 1) Remove compass directions
        let compassPattern = "(?i)\\b(north|south|east|west|northeast|northwest|southeast|southwest|ne|nw|se|sw)\\b"
        if let regex = try? NSRegularExpression(pattern: compassPattern) {
            if regex.firstMatch(in: output, range: NSRange(location: 0, length: output.utf16.count)) != nil {
                violations.append("compass")
                output = regex.stringByReplacingMatches(in: output, options: [], range: NSRange(location: 0, length: output.utf16.count), withTemplate: "")
            }
        }

        // 2) Replace arbitrary measurements with relational phrasing
        let unitsPattern = "(?i)\\b(\\d+\\s?(ft|feet|foot|meter|meters|m|km|kilometer|kilometers|yard|yards|yd|yds))\\b"
        if let regex = try? NSRegularExpression(pattern: unitsPattern) {
            if regex.firstMatch(in: output, range: NSRange(location: 0, length: output.utf16.count)) != nil {
                violations.append("units")
                output = regex.stringByReplacingMatches(in: output, options: [], range: NSRange(location: 0, length: output.utf16.count), withTemplate: "about a block")
            }
        }

        // 2b) Obstacle safety rephrase (avoid telling users to face/walk into walls/barriers)
        let obstaclePattern = "(?i)(face|turn (to|toward)|walk (into|toward)|go (into|toward)) (the )?(wall|fence|railing|barrier)"
        if let regex = try? NSRegularExpression(pattern: obstaclePattern) {
            if regex.firstMatch(in: output, range: NSRange(location: 0, length: output.utf16.count)) != nil {
                violations.append("obstacle")
                // Soft rewrite: orient along the obstacle and follow sidewalk
                output = regex.stringByReplacingMatches(
                    in: output,
                    options: [],
                    range: NSRange(location: 0, length: output.utf16.count),
                    withTemplate: "keep the wall on your left or right and follow the sidewalk"
                )
                // Append an explicit safety nudge
                output += " Use the open sidewalk or marked entrance rather than moving into a barrier."
            }
        }

        // 3) Limit to at most two actionable steps
        let sentences = splitIntoSentences(output)
        let directiveKeywords = ["turn", "walk", "go", "head", "continue", "cross", "keep", "take", "follow"]
        let directives = sentences.filter { s in
            let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return directiveKeywords.contains(where: { lower.contains($0) })
        }
        if directives.count > 2 {
            violations.append("too_many_steps")
            let kept = directives.prefix(2).joined(separator: " ")
            // Keep any intro/orientation sentence before directives
            let intro = sentences.first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            output = intro.isEmpty ? kept : (intro + " " + kept)
        }

        // 4) Ensure checkpoint confirmation cue
        if output.range(of: "Let me know when you reach", options: .caseInsensitive) == nil {
            violations.append("missing_checkpoint")
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.hasSuffix(".") { output += "." }
            output += " Let me know when you reach that."
        }

        // Normalize whitespace
        output = output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return Result(text: output.trimmingCharacters(in: .whitespacesAndNewlines), violations: violations)
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        // Simple sentence splitter suitable for short guidance
        let separators = CharacterSet(charactersIn: ".!?\n")
        return text.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
