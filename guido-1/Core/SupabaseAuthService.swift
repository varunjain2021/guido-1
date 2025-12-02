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
#if canImport(Auth)
import Auth
#endif

#if canImport(GoTrue)
typealias SupaUser = GoTrue.User
#elseif canImport(Auth)
typealias SupaUser = Auth.User
#endif

struct UserAccount: Equatable {
    let id: String
    let email: String?
    let firstName: String?
    let lastName: String?
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
    func updateProfile(firstName: String, lastName: String) async throws
    func signInWithGoogle() async throws
    func signOut() async throws
    func handleOpenURL(_ url: URL) async
    func currentAccessToken() async -> String?
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
                #if canImport(GoTrue) || canImport(Auth)
                return AuthStatus(
                    isAuthenticated: true,
                    user: buildUserAccount(from: user)
                )
                #else
                return AuthStatus(
                    isAuthenticated: true,
                    user: UserAccount(id: user.id.uuidString, email: user.email, firstName: nil, lastName: nil)
                )
                #endif
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
        cachedStatus = AuthStatus(isAuthenticated: true, user: UserAccount(id: UUID().uuidString, email: email, firstName: nil, lastName: nil))
        #endif
    }

    func signUp(email: String, password: String) async throws {
        #if canImport(Supabase)
        let client = try buildClient()
        _ = try await client.auth.signUp(email: email, password: password)
        #else
        cachedStatus = AuthStatus(isAuthenticated: true, user: UserAccount(id: UUID().uuidString, email: email, firstName: nil, lastName: nil))
        #endif
    }

    func updateProfile(firstName: String, lastName: String) async throws {
        #if canImport(Supabase)
        let client = try buildClient()
        #if canImport(GoTrue)
        let attributes = UserAttributes(data: ["first_name": firstName, "last_name": lastName])
        _ = try await client.auth.update(user: attributes)
        #endif
        #endif
        // Update cached status optimistically
        if cachedStatus.isAuthenticated {
            let current = cachedStatus.user
            cachedStatus = AuthStatus(
                isAuthenticated: true,
                user: UserAccount(
                    id: current?.id ?? UUID().uuidString,
                    email: current?.email,
                    firstName: firstName,
                    lastName: lastName
                )
            )
        }
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
                #if canImport(GoTrue) || canImport(Auth)
                cachedStatus = AuthStatus(isAuthenticated: true, user: buildUserAccount(from: user))
                #else
                cachedStatus = AuthStatus(isAuthenticated: true, user: UserAccount(id: user.id.uuidString, email: user.email, firstName: nil, lastName: nil))
                #endif
            }
        } catch {
            // Ignore; keep prior status
        }
        #endif
    }
    
    func currentAccessToken() async -> String? {
        #if canImport(Supabase)
        if let client = try? buildClient() {
            if let session = try? await client.auth.session {
                return session.accessToken
            }
        }
        #endif
        return nil
    }

    // MARK: - Private

    #if canImport(Supabase)
    internal func buildClient() throws -> SupabaseClient {
        if projectURL.isEmpty || anonKey.isEmpty {
            throw NSError(domain: "SupabaseAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Supabase config"])
        }
        return SupabaseClient(supabaseURL: URL(string: projectURL)!, supabaseKey: anonKey)
    }
    #endif

    #if canImport(GoTrue) || canImport(Auth)
    private func buildUserAccount(from user: SupaUser) -> UserAccount {
        var first: String? = nil
        var last: String? = nil

        // Try common metadata keys from OAuth providers
        if let meta = user.userMetadata as? [String: Any] {
            if let fn = stringFromMeta(meta["given_name"]) ?? stringFromMeta(meta["first_name"]) { first = fn }
            if let ln = stringFromMeta(meta["family_name"]) ?? stringFromMeta(meta["last_name"]) { last = ln }
            if (first == nil || last == nil) {
                if let full = stringFromMeta(meta["name"]) ?? stringFromMeta(meta["full_name"]) {
                    let parts = full.split(separator: " ")
                    if parts.count >= 2 {
                        first = first ?? String(parts.first!)
                        last = last ?? String(parts.last!)
                    } else if parts.count == 1 {
                        first = first ?? String(parts[0])
                    }
                }
            }
        }

        return UserAccount(
            id: user.id.uuidString,
            email: user.email,
            firstName: first,
            lastName: last
        )
    }

    private func stringFromMeta(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let s = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty || s == "null" ? nil : s
    }
    #endif
}


