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
    @Published var showRealtimeConversation = false
    
    // API Keys - Loaded from Config.plist for security
    let openAIAPIKey: String
    let elevenLabsAPIKey: String
    let googleAPIKey: String
    
    // Services
    lazy var openAIChatService = OpenAIChatService(apiKey: openAIAPIKey)
    lazy var elevenLabsService = ElevenLabsService(apiKey: elevenLabsAPIKey)
    lazy var locationManager = LocationManager()

    init() {
        // Load API keys from Config.plist
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let configDict = NSDictionary(contentsOfFile: configPath) {
            self.openAIAPIKey = configDict["OpenAI_API_Key"] as? String ?? ""
            self.elevenLabsAPIKey = configDict["ElevenLabs_API_Key"] as? String ?? ""
            self.googleAPIKey = configDict["Google_API_Key"] as? String ?? ""
            
            print("🔑 API Keys loaded from Config.plist")
            print("🔑 OpenAI API Key: \(openAIAPIKey.isEmpty ? "❌ MISSING" : "✅ LOADED (\(openAIAPIKey.prefix(10))...)")")
            print("🔑 ElevenLabs API Key: \(elevenLabsAPIKey.isEmpty ? "❌ MISSING" : "✅ LOADED (\(elevenLabsAPIKey.prefix(10))...)")")
            print("🔑 Google API Key: \(googleAPIKey.isEmpty ? "❌ MISSING" : "✅ LOADED (\(googleAPIKey.prefix(10))...)")")
        } else {
            print("❌ Failed to load Config.plist - using empty API keys")
            self.openAIAPIKey = ""
            self.elevenLabsAPIKey = ""
            self.googleAPIKey = ""
        }
    }
} 