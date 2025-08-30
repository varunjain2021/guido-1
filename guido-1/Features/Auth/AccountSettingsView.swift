//
//  AccountSettingsView.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  Account and settings view with logout functionality
//

import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var authService: SupabaseAuthService
    @State private var showingLogoutAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var isEditingProfile = false
    @State private var editedFullName = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Adaptive Canvas background (unified app style)
            AdaptiveCanvas(
                userSpeaking: false,
                guidoSpeaking: false,
                conversationState: .idle,
                audioLevel: 0.0,
                testEnvironment: nil
            )
            .ignoresSafeArea()
            
            // Foreground content
            VStack(spacing: 16) {
                // Top bar with liquid-glass Done bubble
                HStack {
                    Spacer()
                    LiquidGlassCard(intensity: 0.6, cornerRadius: 14, shadowIntensity: 0.15) {
                        Button(action: { dismiss() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("Done")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Profile section card
                        profileSection
                        
                        // Account settings card
                        accountSettingsSection
                        
                        // App settings card
                        appSettingsSection
                        
                        // Danger zone card
                        dangerZoneSection
                        
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
        .alert("Sign Out", isPresented: $showingLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) { signOut() }
        } message: { Text("Are you sure you want to sign out?") }
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { /* TODO: delete */ }
        } message: { Text("This action cannot be undone. All your data will be permanently deleted.") }
    }
    
    // MARK: - Profile Section
    
    private var profileSection: some View {
        LiquidGlassCard(intensity: 0.8, cornerRadius: 20, shadowIntensity: 0.25) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Profile")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    Button(isEditingProfile ? "Save" : "Edit") {
                        if isEditingProfile { saveProfile() } else { startEditingProfile() }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                }
                
                // Avatar + Info
                VStack(spacing: 12) {
                    profileAvatar
                    
                    VStack(spacing: 10) {
                        if isEditingProfile {
                            TextField("Full Name", text: $editedFullName)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal, 4)
                        } else {
                            Text(authService.currentUser?.fullName ?? "No Name")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        Text(authService.currentUser?.email ?? "No Email")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                        
                        if let provider = authService.currentUser?.provider {
                            HStack(spacing: 6) {
                                Image(systemName: provider.iconName)
                                    .font(.system(size: 12, weight: .medium))
                                Text("Signed in with \(provider.displayName)")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.secondary.opacity(0.08))
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
    }
    
    private var profileAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 80, height: 80)
            if let avatarUrl = authService.currentUser?.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { ProgressView().tint(.white) }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            } else if let fullName = authService.currentUser?.fullName, !fullName.isEmpty {
                Text(getInitials(from: fullName))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Account Settings Section
    
    private var accountSettingsSection: some View {
        LiquidGlassCard(intensity: 0.8, cornerRadius: 20, shadowIntensity: 0.25) {
            VStack(spacing: 0) {
                headerRow("Account Settings")
                settingsRow(icon: "key.fill", title: "Change Password", subtitle: "Update your password") { }
                Divider().padding(.leading, 44)
                settingsRow(icon: "envelope.fill", title: "Email Preferences", subtitle: "Manage notifications") { }
                Divider().padding(.leading, 44)
                settingsRow(icon: "shield.fill", title: "Privacy Settings", subtitle: "Control your data") { }
            }
            .padding(12)
        }
    }
    
    // MARK: - App Settings Section
    
    private var appSettingsSection: some View {
        LiquidGlassCard(intensity: 0.8, cornerRadius: 20, shadowIntensity: 0.25) {
            VStack(spacing: 0) {
                headerRow("App Settings")
                settingsRow(icon: "speaker.wave.2.fill", title: "Voice Settings", subtitle: "Adjust voice preferences") { }
                Divider().padding(.leading, 44)
                settingsRow(icon: "location.fill", title: "Location Services", subtitle: "Manage location access") { }
                Divider().padding(.leading, 44)
                settingsRow(icon: "info.circle.fill", title: "About Guido", subtitle: "Version info and credits") { }
            }
            .padding(12)
        }
    }
    
    // MARK: - Danger Zone Section
    
    private var dangerZoneSection: some View {
        LiquidGlassCard(intensity: 0.85, cornerRadius: 20, shadowIntensity: 0.3) {
            VStack(spacing: 10) {
                headerRow("Account Actions")
                
                // Sign out
                Button(action: { showingLogoutAlert = true }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .medium))
                        Text("Sign Out")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(.vertical, 10)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Delete account
                Button(action: { showingDeleteAccountAlert = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text("Delete Account")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(.vertical, 10)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(12)
        }
    }
    
    // MARK: - Helpers
    
    private func headerRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.bottom, 8)
    }
    
    private func settingsRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        SettingsRow(icon: icon, title: title, subtitle: subtitle, action: action)
            .padding(.vertical, 8)
    }
    
    private func getInitials(from name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.compactMap { $0.first }.prefix(2)
        return String(initials).uppercased()
    }
    
    private func startEditingProfile() {
        editedFullName = authService.currentUser?.fullName ?? ""
        isEditingProfile = true
    }
    
    private func saveProfile() {
        Task {
            do {
                let update = UserProfileUpdate(
                    fullName: editedFullName.isEmpty ? nil : editedFullName,
                    avatarUrl: nil
                )
                _ = try await authService.updateProfile(update)
                isEditingProfile = false
            } catch {
                print("Failed to update profile: \(error)")
            }
        }
    }
    
    private func signOut() {
        Task {
            do {
                try await authService.signOut()
            } catch {
                print("Failed to sign out: \(error)")
            }
        }
    }
}

// MARK: - Settings Row Component

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    AccountSettingsView(authService: SupabaseAuthService())
}
