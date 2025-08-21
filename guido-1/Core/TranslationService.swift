import Foundation

@MainActor
class TranslationService: ObservableObject {
    private let openAI: OpenAIChatService
    
    init(openAIChatService: OpenAIChatService) {
        self.openAI = openAIChatService
    }
    
    func translate(text: String, to target: String, source: String?) async throws -> String {
        let prompt = "Translate the following text to \(target). If a source language is specified, use it. Text: \n\n\(text)"
        return try await openAI.send(message: prompt, conversation: [])
    }
}

