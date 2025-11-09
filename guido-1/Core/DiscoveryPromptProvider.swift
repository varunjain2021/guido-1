import Foundation

struct DiscoveryPromptProvider {
    static func loadPrompt() -> String {
        if let url = Bundle.main.url(forResource: "DiscoveryOrchestrator", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        
        #if DEBUG
        let devPath = "/Users/varunjain/Documents/guido-1/guido-1/MCP/Servers/Prompts/DiscoveryOrchestrator.md"
        if let contents = try? String(contentsOfFile: devPath, encoding: .utf8) {
            return contents
        }
        #endif
        
        print("⚠️ [DiscoveryPromptProvider] DiscoveryOrchestrator prompt not found")
        return ""
    }
}

