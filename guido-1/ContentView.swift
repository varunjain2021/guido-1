//
//  ContentView.swift
//  guido-1
//
//  Created by Varun Jain on 7/26/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedExperience: ExperienceType = .immersive
    @State private var showSettings: Bool = false
    
    enum ExperienceType: String, CaseIterable {
        case immersive = "🌟 Immersive"
        case croatian = "🏖️ Croatian Beach"
        case realtime = "🎤 Classic"
        
        var description: String {
            switch self {
            case .immersive:
                return "Next-gen adaptive canvas with liquid glass overlays"
            case .croatian:
                return "Beautiful Croatian beach theme with floating results"
            case .realtime:
                return "Original conversation interface"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Experience selector (only show when not in immersive mode)
                if selectedExperience != .immersive {
                    experienceSelector
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Main experience view
                Group {
                    switch selectedExperience {
                    case .immersive:
                        ImmersiveConversationView(openAIAPIKey: appState.openAIAPIKey)
                    case .croatian:
                        CroatianBeachConversationView(openAIAPIKey: appState.openAIAPIKey)
                    case .realtime:
                        RealtimeConversationView(openAIAPIKey: appState.openAIAPIKey)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeInOut(duration: 0.3), value: selectedExperience)
            // Auth UI is now integrated into ImmersiveConversationView for a continuous canvas
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            appState.locationManager.requestLocationPermission()
        }
    }
    
    private var experienceSelector: some View {
        VStack(spacing: 16) {
            Text("Choose Your Experience")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(ExperienceType.allCases, id: \.rawValue) { experience in
                    experienceCard(for: experience)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
    }
    
    private func experienceCard(for experience: ExperienceType) -> some View {
        VStack(spacing: 8) {
            Text(experience.rawValue)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(selectedExperience == experience ? .white : .primary)
            
            Text(experience.description)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(selectedExperience == experience ? .white.opacity(0.9) : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedExperience == experience ? Color.blue : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(selectedExperience == experience ? 0 : 0.3), lineWidth: 1)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedExperience = experience
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
