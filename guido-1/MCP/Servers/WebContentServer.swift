import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

public final class WebContentServer {
    private struct RobotsRules {
        let disallow: [String]
    }
    
    private let serverInfo = MCPServerInfo(name: "Guido Web Content Server", version: "1.0.0")
    private let session: URLSession
    private let userAgent: String
    private var robotsCache: [String: RobotsRules] = [:]
    private let cacheQueue = DispatchQueue(label: "WebContentServer.robots", attributes: .concurrent)
    private let contentCacheQueue = DispatchQueue(label: "WebContentServer.content", attributes: .concurrent)
    private var readableCache: [String: CacheEntry] = [:]
    private var linksCache: [String: CacheEntry] = [:]
    private let readableTTL: TimeInterval = 60 * 45
    private let linksTTL: TimeInterval = 60 * 45
    
    private struct CacheEntry {
        let timestamp: Date
        let payload: [String: Any]
    }
    
    init(session: URLSession = .shared, userAgent: String = "GuidoDiscoveryBot/1.0 (+https://guidoproject.app)") {
        self.session = session
        self.userAgent = userAgent
    }
    
    public func getCapabilities() -> MCPCapabilities {
        MCPCapabilities(tools: MCPToolsCapability(listChanged: true), resources: nil, prompts: nil, sampling: nil)
    }
    
    public func getServerInfo() -> MCPServerInfo { serverInfo }
    
    public func listTools() -> [MCPTool] {
        [
            webLinksDiscoverTool(),
            webReadableExtractTool(),
            pdfExtractTool(),
            webImagesDiscoverTool()
        ]
    }
    
    public func callTool(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        switch request.name {
        case "web_links_discover":
            return await executeLinksDiscover(request)
        case "web_readable_extract":
            return await executeReadableExtract(request)
        case "pdf_extract":
            return await executePDFExtract(request)
        case "web_images_discover":
            return await executeImagesDiscover(request)
        default:
            return MCPCallToolResponse(
                content: [MCPContent(text: "Tool '\(request.name)' not found")],
                isError: true
            )
        }
    }
    
    // MARK: - Tool Definitions
    
    private func webLinksDiscoverTool() -> MCPTool {
        MCPTool(
            name: "web_links_discover",
            description: "Discover relevant links on a page matching patterns (menu, catalog, policy). Respects robots.txt.",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "url": MCPPropertySchema(type: "string", description: "Canonical page URL"),
                    "patterns": MCPPropertySchema(type: "string", description: "Comma-separated substring filters (e.g. menu,catalog,return)"),
                    "maxLinks": MCPPropertySchema(type: "string", description: "Maximum links to return (default 6)")
                ],
                required: ["url"]
            )
        )
    }
    
    private func webReadableExtractTool() -> MCPTool {
        MCPTool(
            name: "web_readable_extract",
            description: "Fetches readable text from a web page (scripts/styles stripped, HTML entities decoded). Respects robots.txt.",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "url": MCPPropertySchema(type: "string", description: "Page URL to extract")
                ],
                required: ["url"]
            )
        )
    }
    
    private func pdfExtractTool() -> MCPTool {
        MCPTool(
            name: "pdf_extract",
            description: "Extracts text from a remote PDF (e.g., menu PDF).",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "url": MCPPropertySchema(type: "string", description: "HTTP/HTTPS URL to the PDF document"),
                    "maxCharacters": MCPPropertySchema(type: "string", description: "Optional maximum characters to return (default 4000)")
                ],
                required: ["url"]
            )
        )
    }
    
    private func webImagesDiscoverTool() -> MCPTool {
        MCPTool(
            name: "web_images_discover",
            description: "Discover image URLs from a page (img src, og:image, image_src). Respects robots.txt.",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "url": MCPPropertySchema(type: "string", description: "Canonical page URL"),
                    "maxImages": MCPPropertySchema(type: "string", description: "Maximum images to return (default 6)")
                ],
                required: ["url"]
            )
        )
    }
    
    // MARK: - Tool Implementations
    
    private func executeLinksDiscover(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let urlString = request.arguments?["url"] as? String,
              let url = URL(string: urlString) else {
            return MCPCallToolResponse(content: [MCPContent(text: "Invalid or missing URL")], isError: true)
        }
        let patterns = parseListArgument(request.arguments?["patterns"])
        let maxLinks = parseInt(request.arguments?["maxLinks"], defaultValue: 6, min: 1, max: 20)
        let cacheKey = cacheKeyForLinks(urlString: url.absoluteString, patterns: patterns, maxLinks: maxLinks)
        
        if let cached = cachedLinksPayload(for: cacheKey) {
            do {
                let json = try encodeJSON(cached)
                return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
            } catch {
                // ignore cache failure and fetch fresh data
            }
        }
        
        do {
            guard try await isAllowed(url: url) else {
                return MCPCallToolResponse(
                    content: [MCPContent(text: "robots.txt disallows fetching \(url.path)")],
                    isError: true
                )
            }
            
            let html = try await fetchHTML(url: url)
            let links = discoverLinks(
                in: html,
                baseURL: url,
                patterns: patterns,
                limit: maxLinks
            )
            let payload: [String: Any] = [
                "url": url.absoluteString,
                "patterns": patterns,
                "links": links.map { link in
                    [
                        "title": link.title,
                        "href": link.url.absoluteString,
                        "rel": link.rel,
                        "match": link.match
                    ]
                }
            ]
            storeLinksPayload(payload, for: cacheKey)
            let json = try encodeJSON(payload)
            return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "web_links_discover failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func executeReadableExtract(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let urlString = request.arguments?["url"] as? String,
              let url = URL(string: urlString) else {
            return MCPCallToolResponse(content: [MCPContent(text: "Invalid or missing URL")], isError: true)
        }
        let cacheKey = cacheKeyForReadable(urlString: url.absoluteString)
        
        if let cached = cachedReadablePayload(for: cacheKey) {
            do {
                let json = try encodeJSON(cached)
                return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
            } catch {
                // continue to fetch fresh
            }
        }
        
        do {
            guard try await isAllowed(url: url) else {
                return MCPCallToolResponse(
                    content: [MCPContent(text: "robots.txt disallows fetching \(url.path)")],
                    isError: true
                )
            }
            
            let html = try await fetchHTML(url: url)
            let readable = extractReadableText(from: html)
            let payload: [String: Any] = [
                "url": url.absoluteString,
                "content": readable,
                "length": readable.count
            ]
            storeReadablePayload(payload, for: cacheKey)
            let json = try encodeJSON(payload)
            return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "web_readable_extract failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func executePDFExtract(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let urlString = request.arguments?["url"] as? String,
              let url = URL(string: urlString) else {
            return MCPCallToolResponse(content: [MCPContent(text: "Invalid or missing URL")], isError: true)
        }
        let maxCharacters = parseInt(request.arguments?["maxCharacters"], defaultValue: 4000, min: 500, max: 20000)
        
        #if canImport(PDFKit)
        do {
            guard try await isAllowed(url: url) else {
                return MCPCallToolResponse(
                    content: [MCPContent(text: "robots.txt disallows fetching \(url.path)")],
                    isError: true
                )
            }
            let data = try await fetchData(url: url)
            guard let document = PDFDocument(data: data) else {
                throw NSError(domain: "WebContentServer", code: 40, userInfo: [NSLocalizedDescriptionKey: "Unable to parse PDF"])
            }
            var text = ""
            for index in 0..<document.pageCount {
                if let page = document.page(at: index),
                   let pageText = page.string {
                    text.append(pageText)
                    text.append("\n")
                    if text.count >= maxCharacters {
                        break
                    }
                }
            }
            if text.count > maxCharacters {
                let endIndex = text.index(text.startIndex, offsetBy: maxCharacters)
                text = String(text[..<endIndex])
            }
            let payload: [String: Any] = [
                "url": url.absoluteString,
                "characters": text.count,
                "content": text
            ]
            let json = try encodeJSON(payload)
            return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "pdf_extract failed: \(error.localizedDescription)")],
                isError: true
            )
        }
        #else
        return MCPCallToolResponse(
            content: [MCPContent(text: "PDF extraction is not supported on this platform")],
            isError: true
        )
        #endif
    }
    
    // MARK: - Shared Helpers
    
    struct DiscoveredLink {
        let title: String
        let url: URL
        let rel: String
        let match: String
    }
    
    private func discoverLinks(in html: String, baseURL: URL, patterns: [String], limit: Int) -> [DiscoveredLink] {
        var results: [DiscoveredLink] = []
        let lowercasedPatterns = patterns.map { $0.lowercased() }
        
        let regex = try? NSRegularExpression(pattern: "<a\\s[^>]*href\\s*=\\s*['\"]([^'\"]+)['\"][^>]*>(.*?)</a>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let htmlRange = NSRange(location: 0, length: (html as NSString).length)
        let matches = regex?.matches(in: html, options: [], range: htmlRange) ?? []
        
        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let hrefRange = match.range(at: 1)
            let textRange = match.range(at: 2)
            let href = (html as NSString).substring(with: hrefRange)
            let title = sanitizeHTMLString((html as NSString).substring(with: textRange))
            
            guard let resolvedURL = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }
            if lowercasedPatterns.isEmpty {
                results.append(DiscoveredLink(title: title, url: resolvedURL, rel: "", match: ""))
            } else {
                let hrefLower = href.lowercased()
                let titleLower = title.lowercased()
                if let matchedPattern = lowercasedPatterns.first(where: { pattern in
                    hrefLower.contains(pattern) || titleLower.contains(pattern)
                }) {
                    results.append(DiscoveredLink(title: title, url: resolvedURL, rel: "", match: matchedPattern))
                }
            }
            if results.count >= limit {
                break
            }
        }
        return results
    }
    
    private func executeImagesDiscover(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let urlString = request.arguments?["url"] as? String,
              let url = URL(string: urlString) else {
            return MCPCallToolResponse(content: [MCPContent(text: "Invalid or missing URL")], isError: true)
        }
        let maxImages = parseInt(request.arguments?["maxImages"], defaultValue: 6, min: 1, max: 20)
        
        do {
            guard try await isAllowed(url: url) else {
                return MCPCallToolResponse(
                    content: [MCPContent(text: "robots.txt disallows fetching \(url.path)")],
                    isError: true
                )
            }
            let html = try await fetchHTML(url: url)
            let images = discoverImages(in: html, baseURL: url, limit: maxImages)
            let payload: [String: Any] = [
                "url": url.absoluteString,
                "images": images
            ]
            let json = try encodeJSON(payload)
            return MCPCallToolResponse(content: [MCPContent(text: json)], isError: false)
        } catch {
            return MCPCallToolResponse(
                content: [MCPContent(text: "web_images_discover failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func discoverImages(in html: String, baseURL: URL, limit: Int) -> [String] {
        var urls: [String] = []
        var seen = Set<String>()
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        
        // og:image
        if let metaRegex = try? NSRegularExpression(pattern: "<meta\\s+property=[\"']og:image[\"']\\s+content=[\"']([^\"']+)[\"'][^>]*>", options: [.caseInsensitive]) {
            for match in metaRegex.matches(in: html, options: [], range: range) {
                if match.numberOfRanges >= 2 {
                    let content = nsHTML.substring(with: match.range(at: 1))
                    if let resolved = URL(string: content, relativeTo: baseURL)?.absoluteURL.absoluteString, seen.insert(resolved).inserted {
                        urls.append(resolved)
                        if urls.count >= limit { return urls }
                    }
                }
            }
        }
        
        // link rel=image_src
        if let linkRegex = try? NSRegularExpression(pattern: "<link\\s+rel=[\"']image_src[\"']\\s+href=[\"']([^\"']+)[\"'][^>]*>", options: [.caseInsensitive]) {
            for match in linkRegex.matches(in: html, options: [], range: range) {
                if match.numberOfRanges >= 2 {
                    let href = nsHTML.substring(with: match.range(at: 1))
                    if let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL.absoluteString, seen.insert(resolved).inserted {
                        urls.append(resolved)
                        if urls.count >= limit { return urls }
                    }
                }
            }
        }
        
        // <img src="">
        if let imgRegex = try? NSRegularExpression(pattern: "<img\\s+[^>]*src\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>", options: [.caseInsensitive]) {
            for match in imgRegex.matches(in: html, options: [], range: range) {
                if match.numberOfRanges >= 2 {
                    let src = nsHTML.substring(with: match.range(at: 1))
                    if let resolved = URL(string: src, relativeTo: baseURL)?.absoluteURL.absoluteString, seen.insert(resolved).inserted {
                        urls.append(resolved)
                        if urls.count >= limit { break }
                    }
                }
            }
        }
        
        return urls
    }
    
    private func extractReadableText(from html: String) -> String {
        var sanitized = html
        sanitized = sanitized.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(of: "<noscript[^>]*>[\\s\\S]*?</noscript>", with: "", options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(of: "&nbsp;", with: " ")
        sanitized = sanitized.replacingOccurrences(of: "\r", with: "\n")
        sanitized = sanitized.replacingOccurrences(of: "\n+", with: "\n", options: .regularExpression)
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return decodeHTMLEntities(in: sanitized)
    }
    
    func decodeHTMLEntities(in text: String) -> String {
        guard let data = text.data(using: .utf8) else {
            return text
        }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return text
    }
    
    private func sanitizeHTMLString(_ text: String) -> String {
        let decoded = decodeHTMLEntities(in: text)
        let collapsedWhitespace = decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsedWhitespace
    }
    
    private func fetchHTML(url: URL) async throws -> String {
        let data = try await fetchData(url: url)
        guard let html = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "WebContentServer", code: 30, userInfo: [NSLocalizedDescriptionKey: "Unable to decode HTML using UTF-8 or ISO-8859-1"])
        }
        return html
    }
    
    private func fetchData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "WebContentServer", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode) for \(url.absoluteString): \(body)"])
        }
        return data
    }
    
    private func parseListArgument(_ value: Any?) -> [String] {
        if let array = value as? [String] {
            return array.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let string = value as? String {
            return string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }
    
    private func parseInt(_ value: Any?, defaultValue: Int, min: Int, max: Int) -> Int {
        if let string = value as? String, let int = Int(string) {
            return Swift.max(min, Swift.min(max, int))
        }
        if let number = value as? NSNumber {
            return Swift.max(min, Swift.min(max, number.intValue))
        }
        return defaultValue
    }
    
    private func encodeJSON(_ dictionary: [String: Any]) throws -> String {
        let sanitized = JSONSanitizer.sanitizeDictionary(dictionary)
        let data = try JSONSerialization.data(withJSONObject: sanitized, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "WebContentServer", code: 32, userInfo: [NSLocalizedDescriptionKey: "Unable to encode JSON as UTF-8"])
        }
        return text
    }
    
    // MARK: - Content Cache
    
    private func cacheKeyForReadable(urlString: String) -> String {
        urlString
    }
    
    private func cacheKeyForLinks(urlString: String, patterns: [String], maxLinks: Int) -> String {
        let normalizedPatterns = patterns.joined(separator: "|")
        return "\(urlString)|\(normalizedPatterns)|\(maxLinks)"
    }
    
    private func cachedReadablePayload(for key: String) -> [String: Any]? {
        var entry: CacheEntry?
        contentCacheQueue.sync {
            entry = readableCache[key]
        }
        guard let entry else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > readableTTL {
            contentCacheQueue.async(flags: .barrier) {
                self.readableCache.removeValue(forKey: key)
            }
            return nil
        }
        return entry.payload
    }
    
    private func storeReadablePayload(_ payload: [String: Any], for key: String) {
        let entry = CacheEntry(timestamp: Date(), payload: payload)
        contentCacheQueue.async(flags: .barrier) {
            self.readableCache[key] = entry
            self.readableCache = self.pruneCache(self.readableCache, ttl: self.readableTTL, limit: 80)
        }
    }
    
    private func cachedLinksPayload(for key: String) -> [String: Any]? {
        var entry: CacheEntry?
        contentCacheQueue.sync {
            entry = linksCache[key]
        }
        guard let entry else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > linksTTL {
            contentCacheQueue.async(flags: .barrier) {
                self.linksCache.removeValue(forKey: key)
            }
            return nil
        }
        return entry.payload
    }
    
    private func storeLinksPayload(_ payload: [String: Any], for key: String) {
        let entry = CacheEntry(timestamp: Date(), payload: payload)
        contentCacheQueue.async(flags: .barrier) {
            self.linksCache[key] = entry
            self.linksCache = self.pruneCache(self.linksCache, ttl: self.linksTTL, limit: 120)
        }
    }
    
    private func pruneCache(_ cache: [String: CacheEntry], ttl: TimeInterval, limit: Int) -> [String: CacheEntry] {
        let now = Date()
        var filtered = cache.filter { now.timeIntervalSince($0.value.timestamp) <= ttl }
        if filtered.count > limit {
            let sortedKeys = filtered.sorted { $0.value.timestamp > $1.value.timestamp }.map { $0.key }
            let keysToKeep = Set(sortedKeys.prefix(limit))
            filtered = filtered.filter { keysToKeep.contains($0.key) }
        }
        return filtered
    }
    
    // MARK: - Robots.txt handling
    
    private func isAllowed(url: URL) async throws -> Bool {
        guard let host = url.host else { return false }
        let rules = try await robotsRules(forHost: host, scheme: url.scheme ?? "https")
        guard let rules else { return true } // No robots.txt => allow
        let path = url.path.isEmpty ? "/" : url.path
        return !rules.disallow.contains { path.hasPrefix($0) }
    }
    
    private func robotsRules(forHost host: String, scheme: String) async throws -> RobotsRules? {
        if let cached = cachedRules(for: host) {
            return cached
        }
        
        let robotsURLString = "\(scheme)://\(host)/robots.txt"
        guard let robotsURL = URL(string: robotsURLString) else { return nil }
        
        do {
            var request = URLRequest(url: robotsURL, timeoutInterval: 5)
            request.httpMethod = "GET"
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                cacheRules(nil, for: host)
                return nil
            }
            guard let content = String(data: data, encoding: .utf8) else {
                cacheRules(nil, for: host)
                return nil
            }
            let disallow = parseRobots(content: content)
            let rules = RobotsRules(disallow: disallow)
            cacheRules(rules, for: host)
            return rules
        } catch {
            cacheRules(nil, for: host)
            return nil
        }
    }
    
    private func parseRobots(content: String) -> [String] {
        var disallow: [String] = []
        var inUserAgentStar = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.lowercased().hasPrefix("user-agent:") {
                let agent = trimmed.dropFirst("user-agent:".count).trimmingCharacters(in: .whitespaces).lowercased()
                inUserAgentStar = (agent == "*" || agent.isEmpty)
            } else if inUserAgentStar && trimmed.lowercased().hasPrefix("disallow:") {
                let path = trimmed.dropFirst("disallow:".count).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty {
                    disallow.append(path)
                }
            }
        }
        return disallow
    }
    
    private func cachedRules(for host: String) -> RobotsRules? {
        var rules: RobotsRules?
        cacheQueue.sync {
            rules = robotsCache[host]
        }
        return rules
    }
    
    private func cacheRules(_ rules: RobotsRules?, for host: String) {
        cacheQueue.async(flags: .barrier) {
            self.robotsCache[host] = rules
        }
    }
}

