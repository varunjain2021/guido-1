//
//  guido_1App.swift
//  guido-1
//
//  Created by Varun Jain on 7/26/25.
//

import SwiftUI
import GoogleSignIn

@main
struct guido_1App: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            RootAppView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    print("🚀 Guido app launched successfully!")
                    print("💡 Tip: iOS Simulator messages above are normal system behavior")
                    print("📱 Look for emoji-prefixed messages for app-specific logs")
                    
                    // Configure Google Sign-In
                    configureGoogleSignIn()
                }
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        print("🔗 Deep link received: \(url)")
        
        // Handle Google Sign-In callback
        if GoogleSignIn.GIDSignIn.sharedInstance.handle(url) {
            return
        }
        
        // Handle different URL schemes
        switch url.scheme {
        case "guido":
            switch url.host {
            case "realtime":
                print("🎤 Opening realtime conversation via deep link")
                appState.showRealtimeConversation = true
            default:
                print("❌ Unknown guido deep link: \(url)")
            }
            
        case "com.vjventures.guido-1":
            // Handle Supabase OAuth callback
            if url.host == "auth" && url.path == "/callback" {
                print("🔐 [Auth] Handling Supabase OAuth callback")
                // The auth state listener will automatically handle the session
                // No additional action needed - Supabase handles the token exchange
            } else {
                print("❌ Unknown auth callback: \(url)")
            }
            
        default:
            print("❌ Unknown deep link scheme: \(url)")
        }
    }
    
    private func configureGoogleSignIn() {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            print("⚠️ [App] GoogleService-Info.plist not found or CLIENT_ID missing")
            return
        }
        
        // Configure with iOS client ID
        let config = GIDConfiguration(clientID: clientId)
        GIDSignIn.sharedInstance.configuration = config
        print("✅ [App] Google Sign-In configured successfully")
    }
}
