//
//  guido_1App.swift
//  guido-1
//
//  Created by Varun Jain on 7/26/25.
//

import SwiftUI
import UserNotifications
import GoogleMaps

@main
struct guido_1App: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Initialize Google Maps/Navigation SDK early
        initializeGoogleMapsSDK()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleDeepLink(url)
                    Task { await appState.authService.handleOpenURL(url) }
                }
                .onAppear {
                    print("🚀 Guido app launched successfully!")
                    print("💡 Tip: iOS Simulator messages above are normal system behavior")
                    print("📱 Look for emoji-prefixed messages for app-specific logs")
                    NotificationService.shared.requestAuthorizationIfNeeded()
                }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                HeatmapService.shared.flushActiveVisit(reason: "scene-background")
            case .inactive:
                HeatmapService.shared.flushActiveVisit(reason: "scene-inactive")
            default:
                break
            }
        }
    }
    
    private func initializeGoogleMapsSDK() {
        // Load API key from Config.plist
        guard let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let configDict = NSDictionary(contentsOfFile: configPath),
              let apiKey = configDict["Google_API_Key"] as? String,
              !apiKey.isEmpty else {
            print("⚠️ [GoogleMaps] Could not load API key from Config.plist")
            return
        }
        
        GMSServices.provideAPIKey(apiKey)
        print("✅ [GoogleMaps] SDK initialized with API key: \(apiKey.prefix(10))...")
    }
    
    private func handleDeepLink(_ url: URL) {
        print("🔗 Deep link received: \(url)")
        guard url.scheme == "guido" else { 
            print("❌ Invalid deep link scheme")
            return 
        }
        
        switch url.host {
        case "realtime":
            print("🎤 Opening realtime conversation via deep link")
            appState.showRealtimeConversation = true
        default:
            print("❌ Unknown deep link: \(url)")
        }
    }
}
