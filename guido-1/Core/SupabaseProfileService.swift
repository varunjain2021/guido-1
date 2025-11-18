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

private struct VoiceprintStoragePayload: Codable {
    let vector: [Double]
    let metadata: VoiceprintMetadata
    let created_at: Date
}

private struct VoiceprintRecord: Decodable {
    let voiceprint_v1: VoiceprintStoragePayload?
}

private struct VoiceprintUpsert: Encodable {
    let id: UUID
    let voiceprint_v1: VoiceprintStoragePayload
    let voiceprint_updated_at: Date
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
    
    func fetchVoiceprint() async -> VoiceprintPayload? {
        #if canImport(Supabase)
        do {
            guard let client = try? (self.auth as? SupabaseAuthService)?.buildClient(),
                  let user = client.auth.currentUser else { return nil }
            let response = try await client.database
                .from("profiles")
                .select("voiceprint_v1")
                .eq("id", value: user.id)
                .single()
                .execute()
            guard let data = response.data else { return nil }
            let record = try JSONDecoder().decode(VoiceprintRecord.self, from: data)
            if let stored = record.voiceprint_v1 {
                return VoiceprintPayload(vector: stored.vector, metadata: stored.metadata, createdAt: stored.created_at)
            }
        } catch {
            // Ignore; fallback handled by caller
        }
        #endif
        return nil
    }
    
    func saveVoiceprint(_ payload: VoiceprintPayload) async -> Bool {
        #if canImport(Supabase)
        do {
            guard let client = try? (self.auth as? SupabaseAuthService)?.buildClient(),
                  let user = client.auth.currentUser else { return false }
            let stored = VoiceprintStoragePayload(vector: payload.vector, metadata: payload.metadata, created_at: payload.createdAt)
            let upsert = VoiceprintUpsert(id: user.id, voiceprint_v1: stored, voiceprint_updated_at: Date())
            _ = try await client.database
                .from("profiles")
                .upsert(upsert, onConflict: "id")
                .execute()
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}

