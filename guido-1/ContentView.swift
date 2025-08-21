//
//  ContentView.swift
//  guido-1
//
//  Created by Varun Jain on 7/26/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        CroatianBeachConversationView(openAIAPIKey: appState.openAIAPIKey)
            .onAppear {
                appState.locationManager.requestLocationPermission()
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
