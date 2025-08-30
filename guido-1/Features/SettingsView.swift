//
//  SettingsView.swift
//  guido-1
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
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


