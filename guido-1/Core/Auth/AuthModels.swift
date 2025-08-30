//
//  AuthModels.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  Authentication models and user state management
//

import Foundation
import Supabase

// MARK: - Authentication State

enum AuthState: Equatable {
    case loading
    case unauthenticated
    case authenticated(User)
    case error(String)
}

// MARK: - User Model

struct User: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String?
    let fullName: String?
    let avatarUrl: String?
    let provider: AuthProvider
    let createdAt: Date
    let lastSignInAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case provider
        case createdAt = "created_at"
        case lastSignInAt = "last_sign_in_at"
    }
    
    init(from supabaseUser: Supabase.User) {
        self.id = supabaseUser.id
        self.email = supabaseUser.email
        self.fullName = supabaseUser.userMetadata["full_name"] as? String
        self.avatarUrl = supabaseUser.userMetadata["avatar_url"] as? String
        
        // Determine provider from app metadata
        if let providers = supabaseUser.appMetadata["providers"] as? [String],
           let firstProvider = providers.first {
            self.provider = AuthProvider(rawValue: firstProvider) ?? .email
        } else {
            self.provider = .email
        }
        
        self.createdAt = supabaseUser.createdAt
        self.lastSignInAt = supabaseUser.lastSignInAt
    }
    
    // Custom initializer for manual creation
    init(id: UUID, email: String?, fullName: String?, avatarUrl: String?, provider: AuthProvider, createdAt: Date, lastSignInAt: Date?) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.avatarUrl = avatarUrl
        self.provider = provider
        self.createdAt = createdAt
        self.lastSignInAt = lastSignInAt
    }
}

// MARK: - Authentication Provider

enum AuthProvider: String, CaseIterable, Codable {
    case email = "email"
    case google = "google"
    
    var displayName: String {
        switch self {
        case .email:
            return "Email"
        case .google:
            return "Google"
        }
    }
    
    var iconName: String {
        switch self {
        case .email:
            return "envelope.fill"
        case .google:
            return "globe"
        }
    }
}

// MARK: - Authentication Errors

enum AuthError: LocalizedError, Equatable {
    case invalidCredentials
    case userNotFound
    case emailAlreadyInUse
    case weakPassword
    case networkError
    case unknownError(String)
    case googleSignInCancelled
    case googleSignInFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password. Please check your credentials and try again."
        case .userNotFound:
            return "No account found with this email address."
        case .emailAlreadyInUse:
            return "An account with this email address already exists."
        case .weakPassword:
            return "Password is too weak. Please choose a stronger password."
        case .networkError:
            return "Network connection error. Please check your internet connection."
        case .unknownError(let message):
            return "An unexpected error occurred: \(message)"
        case .googleSignInCancelled:
            return "Google sign-in was cancelled."
        case .googleSignInFailed(let message):
            return "Google sign-in failed: \(message)"
        }
    }
}

// MARK: - Sign In/Up Request Models

struct SignInRequest {
    let email: String
    let password: String
}

struct SignUpRequest {
    let email: String
    let password: String
    let fullName: String?
}

// MARK: - User Profile Update

struct UserProfileUpdate {
    let fullName: String?
    let avatarUrl: String?
}

// MARK: - Authentication Response

struct AuthResponse {
    let user: UserSession
    let session: Session?
    
    init(user: UserSession, session: Session?) {
        self.user = user
        self.session = session
    }
}

// MARK: - User Session (for auth responses)

struct UserSession: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String?
    let fullName: String?
    let avatarUrl: String?
    let provider: AuthProvider
    let createdAt: Date
    let lastSignInAt: Date?
    
    init(from supabaseUser: Supabase.User) {
        self.id = supabaseUser.id
        self.email = supabaseUser.email
        self.fullName = supabaseUser.userMetadata["full_name"] as? String
        self.avatarUrl = supabaseUser.userMetadata["avatar_url"] as? String
        
        // Determine provider from app metadata
        if let providers = supabaseUser.appMetadata["providers"] as? [String],
           let firstProvider = providers.first {
            self.provider = AuthProvider(rawValue: firstProvider) ?? .email
        } else {
            self.provider = .email
        }
        
        self.createdAt = supabaseUser.createdAt
        self.lastSignInAt = supabaseUser.lastSignInAt
    }
}
