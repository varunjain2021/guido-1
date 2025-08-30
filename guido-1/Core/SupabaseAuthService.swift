//
//  SupabaseAuthService.swift
//  guido-1
//
//  Lightweight auth wrapper with graceful fallbacks when Supabase SDK is missing
//

import Foundation
import SwiftUI
#if canImport(Supabase)
import Supabase
#endif
#if canImport(GoTrue)
import GoTrue
#endif

struct UserAccount: Equatable {
    let id: String
    let email: String?
}

struct AuthStatus: Equatable {
    let isAuthenticated: Bool
    let user: UserAccount?
}

protocol AuthService {
    func configure(url: String, anonKey: String)
    func currentStatus() async -> AuthStatus
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String) async throws
    func signInWithGoogle() async throws
    func signOut() async throws
    func handleOpenURL(_ url: URL) async
}

final class SupabaseAuthService: AuthService {
    private var projectURL: String = ""
    private var anonKey: String = ""

    // In-memory mock state if SDK is unavailable
    private var cachedStatus: AuthStatus = AuthStatus(isAuthenticated: false, user: nil)

    func configure(url: String, anonKey: String) {
        self.projectURL = url
        self.anonKey = anonKey
    }

    func currentStatus() async -> AuthStatus {
        #if canImport(Supabase)
        if let client = try? buildClient() {
            if let user = client.auth.currentUser {
                return AuthStatus(
                    isAuthenticated: true,
                    user: UserAccount(id: user.id.uuidString, email: user.email)
                )
            }
        }
        #endif
        return cachedStatus
    }

    func signIn(email: String, password: String) async throws {
        #if canImport(Supabase)
        let client = try buildClient()
        _ = try await client.auth.signIn(email: email, password: password)
        #else
        // Mock for build safety without SDK
        cachedStatus = AuthStatus(isAuthenticated: true, user: UserAccount(id: UUID().uuidString, email: email))
        #endif
    }

    func signUp(email: String, password: String) async throws {
        #if canImport(Supabase)
        let client = try buildClient()
        _ = try await client.auth.signUp(email: email, password: password)
        #else
        cachedStatus = AuthStatus(isAuthenticated: true, user: UserAccount(id: UUID().uuidString, email: email))
        #endif
    }

    func signInWithGoogle() async throws {
        #if canImport(Supabase)
        let client = try buildClient()
        // Note: Set your redirect URL in Supabase dashboard to match this scheme
        // Example: guido://auth-callback
        let redirect = URL(string: "guido://auth-callback")!
        _ = try await client.auth.signInWithOAuth(provider: .google, redirectTo: redirect)
        #else
        // Mock immediate success
        cachedStatus = AuthStatus(isAuthenticated: true, user: UserAccount(id: UUID().uuidString, email: nil))
        #endif
    }

    func signOut() async throws {
        #if canImport(Supabase)
        let client = try buildClient()
        try await client.auth.signOut()
        #endif
        cachedStatus = AuthStatus(isAuthenticated: false, user: nil)
    }

    func handleOpenURL(_ url: URL) async {
        #if canImport(Supabase)
        guard let client = try? buildClient() else { return }
        do {
            // supabase-swift handles OAuth callback via this API
            _ = try await client.auth.session(from: url)
            if let user = client.auth.currentUser {
                cachedStatus = AuthStatus(isAuthenticated: true, user: UserAccount(id: user.id.uuidString, email: user.email))
            }
        } catch {
            // Ignore; keep prior status
        }
        #endif
    }

    // MARK: - Private

    #if canImport(Supabase)
    private func buildClient() throws -> SupabaseClient {
        if projectURL.isEmpty || anonKey.isEmpty {
            throw NSError(domain: "SupabaseAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Supabase config"])
        }
        return SupabaseClient(supabaseURL: URL(string: projectURL)!, supabaseKey: anonKey)
    }
    #endif
}


