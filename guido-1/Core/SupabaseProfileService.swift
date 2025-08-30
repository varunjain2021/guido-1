//
//  SupabaseProfileService.swift
//  guido-1
//

import Foundation

struct Profile: Codable {
    let id: String
    let email: String?
    let first_name: String?
    let last_name: String?
}

final class SupabaseProfileService {
    private let auth: SupabaseAuthService

    init(auth: SupabaseAuthService) {
        self.auth = auth
    }

    func upsertCurrentUserProfile(firstName: String?, lastName: String?, email: String?) async {
        #if canImport(Supabase)
        do {
            guard let client = try? self.auth.performClientBuild() else { return }
            guard let user = client.auth.currentUser else { return }
            let payload: [String: Any?] = [
                "id": user.id.uuidString,
                "email": email ?? user.email,
                "first_name": firstName,
                "last_name": lastName
            ]
            // Using RPC via proxy_execute would be ideal; here we rely on supabase-swift Postgrest
            _ = try await client.database.from("profiles").upsert(values: payload).execute()
        } catch {
            // Non-fatal
        }
        #endif
    }
}

extension SupabaseAuthService {
    // Expose client builder for sibling service (guarded build-only)
    #if canImport(Supabase)
    func performClientBuild() throws -> SupabaseClient { try buildClient() }
    #endif
}


