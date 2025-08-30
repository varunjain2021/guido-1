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
                            .foregroundColor(.primary)
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
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading) {
                                Text(appState.authStatus.user?.email ?? "Signed in")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Text(appState.authStatus.user?.id ?? "")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        Divider().opacity(0.3)
                        Button(action: { Task { await appState.signOut() } }) {
                            HStack {
                                Text("Log out")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                            }
                            .foregroundColor(.primary)
                            .padding(.vertical, 8)
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


