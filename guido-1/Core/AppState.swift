//
//  AppState.swift
//  guido-1
//
//  Created by Varun Jain on 7/26/25.
//

import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var showListeningView = false
    @Published var showRealtimeConversation = false
    @Published var showSimpleConversation = false
    
    // API Keys - These should be configured externally for security
    let openAIAPIKey = Bundle.main.object(forInfoDictionaryKey: "OpenAI_API_Key") as? String ?? ""
    let elevenLabsAPIKey = Bundle.main.object(forInfoDictionaryKey: "ElevenLabs_API_Key") as? String ?? ""
    
    // Services
    lazy var openAIChatService = OpenAIChatService(apiKey: openAIAPIKey)
    lazy var elevenLabsService = ElevenLabsService(apiKey: elevenLabsAPIKey)
    lazy var locationManager = LocationManager()

    init() {
        // Initialization logic can go here
    }
} 