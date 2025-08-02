//
//  guido_1App.swift
//  guido-1
//
//  Created by Varun Jain on 7/26/25.
//

import SwiftUI

@main
struct guido_1App: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    print("🚀 Guido app launched successfully!")
                    print("💡 Tip: iOS Simulator messages above are normal system behavior")
                    print("📱 Look for emoji-prefixed messages for app-specific logs")
                }
        }
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
