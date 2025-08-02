//
//  ContentView.swift
//  guido-1
//
//  Created by Varun Jain on 7/26/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showProactiveGuide = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "figure.walk.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("Guido")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Your Solo Travel Companion")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    // Voice Features
                    VStack(spacing: 20) {

                        // Real-time Conversation Section
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "waveform.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Complex Real-time Chat")
                                    .font(.headline)
                                Spacer()
                                
                                // "COMPLEX" badge
                                Text("COMPLEX")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .cornerRadius(8)
                            }
                            
                            Text("Full-featured WebSocket implementation with custom VAD")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                            
                            Button(action: {
                                print("🎤 User tapped 'Start Real-time Chat' button")
                                appState.showRealtimeConversation = true
                            }) {
                                HStack {
                                    Image(systemName: "waveform")
                                    Text("Start Complex Chat")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                        

                        // Proactive Guide Section
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "location.circle.fill")
                                    .foregroundColor(.green)
                                Text("Proactive Guide")
                                    .font(.headline)
                                Spacer()
                            }
                            
                            Text("Get automatic location-based recommendations")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                            
                            Button(action: {
                                showProactiveGuide = true
                            }) {
                                HStack {
                                    Image(systemName: "location.fill")
                                    Text("Try Proactive Guide")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .navigationTitle("Guido")
        }

        .sheet(isPresented: $appState.showRealtimeConversation) {
            NavigationView {
                RealtimeConversationView(openAIAPIKey: appState.openAIAPIKey)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                appState.showRealtimeConversation = false
                            }
                        }
                    }
            }
        }

        .sheet(isPresented: $showProactiveGuide) {
            ProactiveGuideView(
                locationDescription: appState.locationManager.getCurrentLocationDescription()
            )
        }
        .onAppear {
            appState.locationManager.requestLocationPermission()
        }
        .onChange(of: appState.locationManager.shouldTriggerProactiveGuide) { shouldTrigger in
            if shouldTrigger {
                showProactiveGuide = true
                appState.locationManager.acknowledgeProactiveTrigger()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
