//
//  SupabaseProfileService.swift
//  guido-1
//

import Foundation
@_exported import struct Foundation.UUID
#if canImport(Supabase)
import Supabase
#endif

struct Profile: Codable {
    let id: String
    let email: String?
    let first_name: String?
    let last_name: String?
}

private struct ProfileUpsert: Encodable {
    let id: UUID
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
            guard let client = try? (self.auth as? SupabaseAuthService)?.buildClient() else { return }
            guard let user = client.auth.currentUser else { return }
            let payload = ProfileUpsert(
                id: user.id,
                email: email ?? user.email,
                first_name: firstName,
                last_name: lastName
            )
            _ = try await client.database
                .from("profiles")
                .upsert(payload, onConflict: "id")
                .execute()
        } catch {
            // Non-fatal
        }
        #endif
    }
}

