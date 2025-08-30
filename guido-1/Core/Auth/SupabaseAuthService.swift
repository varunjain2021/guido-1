//
//  SupabaseAuthService.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  Supabase authentication service with email/password and Google OAuth
//

import Foundation
import Supabase
import GoogleSignIn
import Combine

@MainActor
class SupabaseAuthService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var authState: AuthState = .loading
    @Published var currentUser: User?
    @Published var isLoading = false
    
    // MARK: - Private Properties
    
    private let supabase: SupabaseClient
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    
    private struct Config {
        // Use the configured SupabaseConfig
        static let supabaseURL = SupabaseConfig.supabaseURL
        static let supabaseAnonKey = SupabaseConfig.supabaseAnonKey
        static let googleClientID = SupabaseConfig.googleClientID
    }
    
    // MARK: - Initialization
    
    init() {
        // Initialize Supabase client
        self.supabase = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
        
        // Configure Google Sign-In
        configureGoogleSignIn()
        
        // Set up authentication state listener and check current session
        Task {
            await setupAuthStateListener()
            await checkCurrentSession()
        }
    }
    
    // MARK: - Public Authentication Methods
    
    func signUp(email: String, password: String, fullName: String?) async throws -> AuthResponse {
        isLoading = true
        defer { isLoading = false }
        
        do {
            var metadata: [String: AnyJSON] = [:]
            if let fullName = fullName {
                metadata["full_name"] = AnyJSON.string(fullName)
            }
            
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: metadata
            )
            
            let authResponse = AuthResponse(user: UserSession(from: response.user), session: response.session)
            await updateAuthState(with: User(from: response.user))
            
            print("✅ [Auth] User signed up successfully: \(email)")
            return authResponse
            
        } catch {
            let authError = mapSupabaseError(error)
            await updateAuthState(error: authError)
            throw authError
        }
    }
    
    /// Refresh current auth session and publish state
    func refresh() async {
        await checkCurrentSession()
    }
    
    func signIn(email: String, password: String) async throws -> AuthResponse {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            
            await updateAuthState(with: User(from: response.user))
            
            print("✅ [Auth] User signed in successfully: \(email)")
            return AuthResponse(user: UserSession(from: response.user), session: response)
            
        } catch {
            let authError = mapSupabaseError(error)
            await updateAuthState(error: authError)
            throw authError
        }
    }
    
    func signInWithGoogle() async throws -> AuthResponse {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Get the root view controller for presenting Google sign-in
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                throw AuthError.googleSignInFailed("Could not find root view controller")
            }
            
            // Ensure GoogleSignIn is configured
            guard GIDSignIn.sharedInstance.configuration?.clientID != nil else {
                throw AuthError.googleSignInFailed("Google Client ID not configured")
            }
            
            // Present in-app Google sign-in
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            
            // Extract tokens
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.googleSignInFailed("Failed to get ID token")
            }
            let accessToken = result.user.accessToken.tokenString
            
            // Pass tokens to Supabase for session
            let response = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken
                )
            )
            
            let authResponse = AuthResponse(user: UserSession(from: response.user), session: response)
            await updateAuthState(with: User(from: response.user))
            
            print("✅ [Auth] Google sign-in completed in-app")
            return authResponse
            
        } catch {
            let authError: AuthError
            if error is CancellationError {
                authError = .googleSignInCancelled
            } else {
                authError = .googleSignInFailed(error.localizedDescription)
            }
            await updateAuthState(error: authError)
            throw authError
        }
    }
    
    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await supabase.auth.signOut()
            await updateAuthState(unauthenticated: true)
            
            print("✅ [Auth] User signed out successfully")
            
        } catch {
            let authError = mapSupabaseError(error)
            print("❌ [Auth] Sign out failed: \(authError.localizedDescription)")
            throw authError
        }
    }
    
    func resetPassword(email: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await supabase.auth.resetPasswordForEmail(email)
            print("✅ [Auth] Password reset email sent to: \(email)")
            
        } catch {
            let authError = mapSupabaseError(error)
            throw authError
        }
    }
    
    func updateProfile(_ update: UserProfileUpdate) async throws -> User {
        isLoading = true
        defer { isLoading = false }
        
        guard currentUser != nil else {
            throw AuthError.userNotFound
        }
        
        do {
            var attributes: [String: AnyJSON] = [:]
            
            if let fullName = update.fullName {
                attributes["full_name"] = AnyJSON.string(fullName)
            }
            
            if let avatarUrl = update.avatarUrl {
                attributes["avatar_url"] = AnyJSON.string(avatarUrl)
            }
            
            let response = try await supabase.auth.update(user: UserAttributes(data: attributes))
            
            let updatedUser = User(from: response)
            await updateAuthState(with: updatedUser)
            
            print("✅ [Auth] User profile updated successfully")
            return updatedUser
            
        } catch {
            let authError = mapSupabaseError(error)
            throw authError
        }
    }
    
    // MARK: - Private Methods
    
    private func configureGoogleSignIn() {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            print("⚠️ [Auth] GoogleService-Info.plist not found or CLIENT_ID missing")
            return
        }
        
        let config = GIDConfiguration(clientID: clientId)
        GIDSignIn.sharedInstance.configuration = config
        print("✅ [Auth] Google Sign-In configured successfully")
    }
    
    private func setupAuthStateListener() async {
        await supabase.auth.onAuthStateChange { [weak self] event, session in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch event {
                case .signedIn:
                    if let user = session?.user {
                        await self.updateAuthState(with: User(from: user))
                        print("🔐 [Auth] User signed in: \(user.email ?? "Unknown")")
                    }
                    
                case .signedOut:
                    await self.updateAuthState(unauthenticated: true)
                    print("🔓 [Auth] User signed out")
                    
                case .tokenRefreshed:
                    print("🔄 [Auth] Token refreshed")
                    
                default:
                    break
                }
            }
        }
    }
    
    private func checkCurrentSession() async {
        do {
            let session = try await supabase.auth.session
            let guidoUser = User(from: session.user)
            await updateAuthState(with: guidoUser)
            print("✅ [Auth] Current session found for: \(guidoUser.email ?? "Unknown")")
        } catch {
            await updateAuthState(unauthenticated: true)
            print("ℹ️ [Auth] No current session found")
        }
    }
    
    private func updateAuthState(with user: User) async {
        self.currentUser = user
        self.authState = .authenticated(user)
    }
    
    private func updateAuthState(unauthenticated: Bool) async {
        self.currentUser = nil
        self.authState = .unauthenticated
    }
    
    private func updateAuthState(error: AuthError) async {
        self.authState = .error(error.localizedDescription)
    }
    
    private func mapSupabaseError(_ error: Error) -> AuthError {
        // Map Supabase errors to our custom AuthError enum
        let errorString = error.localizedDescription.lowercased()
        
        if errorString.contains("invalid") && errorString.contains("credentials") {
            return .invalidCredentials
        } else if errorString.contains("user not found") {
            return .userNotFound
        } else if errorString.contains("email") && errorString.contains("already") {
            return .emailAlreadyInUse
        } else if errorString.contains("password") && errorString.contains("weak") {
            return .weakPassword
        } else if errorString.contains("network") || errorString.contains("connection") {
            return .networkError
        } else {
            return .unknownError(error.localizedDescription)
        }
    }
}

// MARK: - Configuration Helper

extension SupabaseAuthService {
    
    /// Check if authentication is properly configured
    var isConfigured: Bool {
        return !Config.supabaseURL.contains("your-project-id") && 
               !Config.supabaseAnonKey.contains("your-anon-key") &&
               !Config.supabaseURL.isEmpty &&
               !Config.supabaseAnonKey.isEmpty
    }
    
    /// Get configuration status for debugging
    var configurationStatus: String {
        var status: [String] = []
        
        if Config.supabaseURL.contains("your-project-id") || Config.supabaseURL.isEmpty {
            status.append("Supabase URL not configured")
        }
        
        if Config.supabaseAnonKey.contains("your-anon-key") || Config.supabaseAnonKey.isEmpty {
            status.append("Supabase Anon Key not configured")
        }
        
        if GIDSignIn.sharedInstance.configuration == nil {
            status.append("Google Sign-In not configured")
        }
        
        return status.isEmpty ? "✅ All configured" : "⚠️ " + status.joined(separator: ", ")
    }
}
