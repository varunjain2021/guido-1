//
//  AuthCoordinator.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  Authentication coordinator for managing app flow
//

import SwiftUI
import Combine

@MainActor
class AuthCoordinator: ObservableObject {
    @Published var authService = SupabaseAuthService()
    @Published var showingSettings = false
    @Published var state: AuthState = .loading
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Monitor authentication state changes
        authService.$authState
            .sink { [weak self] state in
                self?.handleAuthStateChange(state)
                self?.state = state
            }
            .store(in: &cancellables)
    }
    
    private func handleAuthStateChange(_ state: AuthState) {
        switch state {
        case .authenticated(let user):
            print("✅ [AuthCoordinator] User authenticated: \(user.email ?? "Unknown")")
            
        case .unauthenticated:
            print("🔓 [AuthCoordinator] User unauthenticated")
            showingSettings = false
            
        case .loading:
            print("⏳ [AuthCoordinator] Authentication loading...")
            
        case .error(let message):
            print("❌ [AuthCoordinator] Authentication error: \(message)")
        }
    }
}

// MARK: - Root App View

struct RootAppView: View {
    @StateObject private var authCoordinator = AuthCoordinator()
    @State private var authVersion: Int = 0
    
    var body: some View {
        Group {
            switch authCoordinator.state {
            case .loading:
                LoadingView()
                
            case .unauthenticated, .error:
                AuthenticationView()
                    .environmentObject(authCoordinator.authService)
                    .environmentObject(authCoordinator)
                
            case .authenticated:
                MainAppView()
                    .environmentObject(authCoordinator.authService)
                    .environmentObject(authCoordinator)
            }
        }
        .id(authVersion)
        .onAppear {
            Task { await authCoordinator.authService.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await authCoordinator.authService.refresh() }
        }
        .onChange(of: authCoordinator.state) { newValue in
            print("🔁 [RootAppView] auth state -> \(newValue)")
            authVersion &+= 1
        }
        .animation(.easeInOut(duration: 0.3), value: authCoordinator.state)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Animated background
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.8),
                    Color.purple.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // App logo with animation
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .opacity(isAnimating ? 0.7 : 1.0)
                    
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
                
                // App name
                Text("Guido")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Main App View (Authenticated)

struct MainAppView: View {
    @EnvironmentObject var authService: SupabaseAuthService
    @EnvironmentObject var authCoordinator: AuthCoordinator
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        // Direct immersive conversation view with AdaptiveCanvas-only UI
        ImmersiveConversationView(realtimeService: appState.realtimeService)
            .environmentObject(authCoordinator)
            .environmentObject(authService)
            .environmentObject(appState)
            .ignoresSafeArea()
    }
    
    private func getInitials(from name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.compactMap { $0.first }.prefix(2)
        return String(initials).uppercased()
    }
}


