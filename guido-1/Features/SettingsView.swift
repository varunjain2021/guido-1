//
//  SettingsView.swift
//  guido-1
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    var onClose: () -> Void = {}
    var onHelp: () -> Void = {}
    
    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                LiquidGlassCard(intensity: 0.85, cornerRadius: 28, shadowIntensity: 0.35, enableFloating: true) {
                    HStack {
                        Text("Settings")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))
                        Spacer()
                    }
                    .padding(20)
                }
                .padding(.horizontal, 24)
                
                LiquidGlassCard(intensity: 0.7, cornerRadius: 20, shadowIntensity: 0.25) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Color(.tertiaryLabel))
                            VStack(alignment: .leading, spacing: 2) {
                                if let first = appState.authStatus.user?.firstName, let last = appState.authStatus.user?.lastName, !(first.isEmpty && last.isEmpty) {
                                    Text("\(first) \(last)")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color(.secondaryLabel))
                                }
                                Text(appState.authStatus.user?.email ?? "Signed in")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            Spacer()
                        }
                        Divider().opacity(0.3)
                        
                        // Themes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Themes")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(.tertiaryLabel))
                            
                            // Theme options (formerly triple-tap test UI)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                                ForEach(Array(CanvasEnvironment.allCases.enumerated()), id: \.offset) { _, env in
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            appState.selectedTheme = env
                                        }
                                    }) {
                                        let isSelected = appState.selectedTheme == env
                                        ZStack(alignment: .topTrailing) {
                                            LiquidGlassCard(intensity: isSelected ? 0.6 : 0.4, cornerRadius: 10, shadowIntensity: isSelected ? 0.2 : 0.08) {
                                                Text(env.displayName)
                                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                                    .foregroundColor(isSelected ? .blue : Color(.secondaryLabel))
                                                    .frame(width: 44, height: 36)
                                            }
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(isSelected ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 2)
                                            )
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .accessibilityLabel("Select theme \(env.displayName)")
                                }
                            }
                        }
                        
                        Divider().opacity(0.3)
                        
                        // Language
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Language")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(.tertiaryLabel))
                            // Language options styled consistently with theme tiles
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                                ForEach(supportedLanguages, id: \.code) { lang in
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            appState.conversationLanguageCode = lang.code
                                        }
                                    }) {
                                        let isSelected = appState.conversationLanguageCode == lang.code
                                        ZStack {
                                            LiquidGlassCard(intensity: isSelected ? 0.6 : 0.4, cornerRadius: 10, shadowIntensity: isSelected ? 0.2 : 0.08) {
                                                Text(lang.displayName)
                                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                                    .foregroundColor(isSelected ? .blue : Color(.secondaryLabel))
                                                    .multilineTextAlignment(.center)
                                                    .frame(width: 96, height: 36)
                                                    .minimumScaleFactor(0.8)
                                            }
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(isSelected ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 2)
                                            )
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .accessibilityLabel("Select language \(lang.displayName)")
                                }
                            }
                        }
                        
                        Divider().opacity(0.3)
                        Button(action: {
                            onClose()
                            onHelp()
                        }) {
                            HStack {
                                Text("Help")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(.secondaryLabel))
                                Spacer()
                                Image(systemName: "questionmark.circle")
                            }
                            .foregroundColor(Color(.secondaryLabel))
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Divider().opacity(0.3)
                        Button(action: { Task { await appState.signOut() } }) {
                            HStack {
                                Text("Log out")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(.secondaryLabel))
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                            }
                            .foregroundColor(Color(.secondaryLabel))
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(16)
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Helpers
private func themeName(_ env: CanvasEnvironment) -> String {
    switch env {
    case .water: return "Blue Drop"
    case .beach: return "Beach"
    case .park: return "Park"
    case .urban: return "Urban"
    case .indoor: return "Indoor"
    case .mountain: return "Mountain"
    case .desert: return "Desert"
    case .unknown: return "Default"
    }
}

// MARK: - Supported Languages
private let supportedLanguages: [(code: String, displayName: String)] = [
    ("en", "English"),
    ("es", "Spanish"),
    ("fr", "French"),
    ("de", "German"),
    ("it", "Italian"),
    ("pt", "Portuguese"),
    ("ja", "Japanese"),
    ("ko", "Korean"),
    ("zh", "Chinese"),
    ("hi", "Hindi")
]


