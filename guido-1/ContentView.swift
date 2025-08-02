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
                        // Simple WebRTC Chat Section  
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(.purple)
                                Text("Simple WebRTC Chat")
                                    .font(.headline)
                                Spacer()
                                
                                // "SIMPLE" badge
                                Text("SIMPLE")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.purple)
                                    .cornerRadius(8)
                            }
                            
                            Text("Clean WebRTC implementation following OpenAI's reference")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                            
                            Button(action: {
                                print("🌐 User tapped 'Start Simple Chat' button")
                                appState.showSimpleConversation = true
                            }) {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                    Text("Start Simple Chat")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)

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
                        
                        // Push-to-Talk Section
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "mic.circle.fill")
                                    .foregroundColor(.red)
                                Text("Push-to-Talk")
                                    .font(.headline)
                                Spacer()
                            }
                            
                            Text("Traditional tap-to-talk conversation mode")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                            
                            Button(action: {
                                print("🎤 User tapped 'Start Listening' button")
                                appState.showListeningView = true
                            }) {
                                HStack {
                                    Image(systemName: "mic.fill")
                                    Text("Start Push-to-Talk")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
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
                    
                    // Quick Actions
                    VStack(spacing: 16) {
                        Text("Quick Actions")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                appState.showRealtimeConversation = true
                            }) {
                                VStack {
                                    Image(systemName: "waveform.circle")
                                        .font(.title)
                                        .foregroundColor(.blue)
                                    Text("Real-time")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }
                            
                            Button(action: {
                                appState.showListeningView = true
                            }) {
                                VStack {
                                    Image(systemName: "mic.circle")
                                        .font(.title)
                                        .foregroundColor(.red)
                                    Text("Push-Talk")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(12)
                            }
                            
                            Button(action: {
                                showProactiveGuide = true
                            }) {
                                VStack {
                                    Image(systemName: "location.circle")
                                        .font(.title)
                                        .foregroundColor(.green)
                                    Text("Guide")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)
                            }
                            
                            Button(action: {
                                // Settings action
                            }) {
                                VStack {
                                    Image(systemName: "gearshape.circle")
                                        .font(.title)
                                    Text("Settings")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.blue)
                        .padding()
                        .onTapGesture {
                            appState.showListeningView = true
                        }
                    
                    Text("Tap to Talk to Guido")
                        .font(.headline)
                    
                    Spacer()
                }
            }
            .navigationTitle("Guido")
        }
        .sheet(isPresented: $appState.showListeningView) {
            ListeningView(
                openAIAPIKey: appState.openAIAPIKey,
                elevenLabsAPIKey: appState.elevenLabsAPIKey
            )
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
        .sheet(isPresented: $appState.showSimpleConversation) {
            NavigationView {
                SimpleConversationView(openAIAPIKey: appState.openAIAPIKey)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                appState.showSimpleConversation = false
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
