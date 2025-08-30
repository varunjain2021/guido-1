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
    @Published var authStatus: AuthStatus = AuthStatus(isAuthenticated: false, user: nil)
    
    // API Keys - Loaded from Config.plist for security
    let openAIAPIKey: String
    let elevenLabsAPIKey: String
    let googleAPIKey: String
    let supabaseURL: String
    let supabaseAnonKey: String
    
    // Services
    lazy var openAIChatService = OpenAIChatService(apiKey: openAIAPIKey)
    lazy var elevenLabsService = ElevenLabsService(apiKey: elevenLabsAPIKey)
    lazy var locationManager = LocationManager()
    let authService: AuthService = SupabaseAuthService()

    init() {
        // Load API keys from Config.plist
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let configDict = NSDictionary(contentsOfFile: configPath) {
            self.openAIAPIKey = configDict["OpenAI_API_Key"] as? String ?? ""
            self.elevenLabsAPIKey = configDict["ElevenLabs_API_Key"] as? String ?? ""
            self.googleAPIKey = configDict["Google_API_Key"] as? String ?? ""
            self.supabaseURL = configDict["Supabase_URL"] as? String ?? ""
            self.supabaseAnonKey = configDict["Supabase_Anon_Key"] as? String ?? ""
            
            print("🔑 API Keys loaded from Config.plist")
            print("🔑 OpenAI API Key: \(openAIAPIKey.isEmpty ? "❌ MISSING" : "✅ LOADED (\(openAIAPIKey.prefix(10))...)")")
            print("🔑 ElevenLabs API Key: \(elevenLabsAPIKey.isEmpty ? "❌ MISSING" : "✅ LOADED (\(elevenLabsAPIKey.prefix(10))...)")")
            print("🔑 Google API Key: \(googleAPIKey.isEmpty ? "❌ MISSING" : "✅ LOADED (\(googleAPIKey.prefix(10))...)")")
            print("🔑 Supabase URL: \(supabaseURL.isEmpty ? "❌ MISSING" : "✅ LOADED")")
            print("🔑 Supabase Anon Key: \(supabaseAnonKey.isEmpty ? "❌ MISSING" : "✅ LOADED (\(supabaseAnonKey.prefix(6))...)")")
        } else {
            print("❌ Failed to load Config.plist - using empty API keys")
            self.openAIAPIKey = ""
            self.elevenLabsAPIKey = ""
            self.googleAPIKey = ""
            self.supabaseURL = ""
            self.supabaseAnonKey = ""
        }

        // Configure auth service
        authService.configure(url: supabaseURL, anonKey: supabaseAnonKey)

        // Read current auth status
        Task { [weak self] in
            guard let self else { return }
            self.authStatus = await self.authService.currentStatus()
        }
    }

    // MARK: - Auth Actions

    func signIn(email: String, password: String) async -> Result<Void, Error> {
        do {
            try await authService.signIn(email: email, password: password)
            self.authStatus = await authService.currentStatus()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func signUp(email: String, password: String) async -> Result<Void, Error> {
        do {
            try await authService.signUp(email: email, password: password)
            self.authStatus = await authService.currentStatus()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func updateProfile(firstName: String, lastName: String) async -> Result<Void, Error> {
        do {
            try await authService.updateProfile(firstName: firstName, lastName: lastName)
            self.authStatus = await authService.currentStatus()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func signInWithGoogle() async -> Result<Void, Error> {
        do {
            try await authService.signInWithGoogle()
            // Status will update on callback as well
            self.authStatus = await authService.currentStatus()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func signOut() async {
        do {
            try await authService.signOut()
        } catch {
            // Ignore for now
        }
        self.authStatus = await authService.currentStatus()
    }
} 