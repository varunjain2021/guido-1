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
}

final class SupabaseProfileService {
    private let auth: SupabaseAuthService
    
    // MARK: - Voiceprint fingerprint (short hash) for logging
    private func hashVector(_ vector: [Double]) -> String {
        var hash: UInt64 = 1469598103934665603 // FNV-1a 64-bit offset basis
        let prime: UInt64 = 1099511628211
        for d in vector {
            var bits = d.bitPattern
            for _ in 0..<8 {
                let byte = UInt8(bits & 0xFF)
                hash ^= UInt64(byte)
                hash = hash &* prime
                bits >>= 8
            }
        }
        return String(hash, radix: 16)
    }

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
            guard let client = try? (self.auth as? SupabaseAuthService)?.buildClient() else {
                print("[Voiceprint] ⚠️ fetchVoiceprint: Supabase client unavailable")
                return nil
            }
            guard let user = client.auth.currentUser else {
                print("[Voiceprint] ⚠️ fetchVoiceprint: no current user; skipping remote load")
                return nil
            }
            let response = try await client.database
                .from("profiles")
                .select("voiceprint_v1")
                .eq("id", value: user.id)
                .single()
                .execute()
            let data = response.data
            if let raw = String(data: data, encoding: .utf8) {
                let preview = raw.count > 300 ? String(raw.prefix(300)) + "…" : raw
                print("[Voiceprint] 🔎 fetchVoiceprint raw JSON (preview): \(preview)")
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let record = try? decoder.decode(VoiceprintRecord.self, from: data),
               let stored = record.voiceprint_v1 {
                let fp = hashVector(stored.vector)
                print("[Voiceprint] ☁️ fetchVoiceprint: found remote voiceprint (vector=\(stored.vector.count), fp=\(fp))")
                return VoiceprintPayload(vector: stored.vector, metadata: stored.metadata, createdAt: stored.created_at)
            }
            // Fallback: attempt manual parse to handle schema quirks
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let vp = root["voiceprint_v1"] {
                if let vpDict = vp as? [String: Any] {
                    // Parse vector
                    let anyVec = (vpDict["vector"] as? [Any]) ?? []
                    let vector: [Double] = anyVec.compactMap { ($0 as? Double) ?? ($0 as? NSNumber)?.doubleValue }
                    // Parse metadata
                    let md = vpDict["metadata"] as? [String: Any] ?? [:]
                    let meta = VoiceprintMetadata(
                        version: (md["version"] as? String) ?? "fft512_v1",
                        sampleRate: (md["sampleRate"] as? Double) ?? (md["sample_rate"] as? Double) ?? 48000,
                        frameSize: (md["frameSize"] as? Int) ?? (md["frame_size"] as? Int) ?? 512,
                        hopSize: (md["hopSize"] as? Int) ?? (md["hop_size"] as? Int) ?? 256,
                        fftSize: (md["fftSize"] as? Int) ?? (md["fft_size"] as? Int) ?? 512
                    )
                    // Parse created_at
                    let createdRaw = vpDict["created_at"] as? String
                    let createdAt: Date = {
                        if let s = createdRaw {
                            let fFrac = ISO8601DateFormatter()
                            fFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            return fFrac.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? Date()
                        }
                        return Date()
                    }()
                    if !vector.isEmpty {
                        let fp = hashVector(vector)
                        print("[Voiceprint] ☁️ fetchVoiceprint: manual parse succeeded (vector=\(vector.count), fp=\(fp))")
                        return VoiceprintPayload(vector: vector, metadata: meta, createdAt: createdAt)
                    }
                } else if let vpString = vp as? String,
                          let innerData = vpString.data(using: .utf8),
                          let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any] {
                    // Same as above, but when jsonb was returned as string
                    let anyVec = (inner["vector"] as? [Any]) ?? []
                    let vector: [Double] = anyVec.compactMap { ($0 as? Double) ?? ($0 as? NSNumber)?.doubleValue }
                    let md = inner["metadata"] as? [String: Any] ?? [:]
                    let meta = VoiceprintMetadata(
                        version: (md["version"] as? String) ?? "fft512_v1",
                        sampleRate: (md["sampleRate"] as? Double) ?? (md["sample_rate"] as? Double) ?? 48000,
                        frameSize: (md["frameSize"] as? Int) ?? (md["frame_size"] as? Int) ?? 512,
                        hopSize: (md["hopSize"] as? Int) ?? (md["hop_size"] as? Int) ?? 256,
                        fftSize: (md["fftSize"] as? Int) ?? (md["fft_size"] as? Int) ?? 512
                    )
                    let createdRaw = inner["created_at"] as? String
                    let createdAt: Date = {
                        if let s = createdRaw {
                            let fFrac = ISO8601DateFormatter()
                            fFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            return fFrac.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? Date()
                        }
                        return Date()
                    }()
                    if !vector.isEmpty {
                        let fp = hashVector(vector)
                        print("[Voiceprint] ☁️ fetchVoiceprint: manual parse (string) succeeded (vector=\(vector.count), fp=\(fp))")
                        return VoiceprintPayload(vector: vector, metadata: meta, createdAt: createdAt)
                    }
                }
            }
            // If we got here, both decoder and manual parse (object) failed; try string fallback too
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let vpString = root["voiceprint_v1"] as? String,
               let innerData = vpString.data(using: .utf8),
               let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any] {
                let anyVec = (inner["vector"] as? [Any]) ?? []
                let vector: [Double] = anyVec.compactMap { ($0 as? Double) ?? ($0 as? NSNumber)?.doubleValue }
                let md = inner["metadata"] as? [String: Any] ?? [:]
                let meta = VoiceprintMetadata(
                    version: (md["version"] as? String) ?? "fft512_v1",
                    sampleRate: (md["sampleRate"] as? Double) ?? (md["sample_rate"] as? Double) ?? 48000,
                    frameSize: (md["frameSize"] as? Int) ?? (md["frame_size"] as? Int) ?? 512,
                    hopSize: (md["hopSize"] as? Int) ?? (md["hop_size"] as? Int) ?? 256,
                    fftSize: (md["fftSize"] as? Int) ?? (md["fft_size"] as? Int) ?? 512
                )
                let createdRaw = inner["created_at"] as? String
                let createdAt: Date = {
                    if let s = createdRaw {
                        let fFrac = ISO8601DateFormatter()
                        fFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        return fFrac.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? Date()
                    }
                    return Date()
                }()
                if !vector.isEmpty {
                    print("[Voiceprint] ☁️ fetchVoiceprint: manual parse (string) succeeded (vector=\(vector.count))")
                    return VoiceprintPayload(vector: vector, metadata: meta, createdAt: createdAt)
                }
            }
        } catch {
            // Log and fallback handled by caller
            print("[Voiceprint] ❌ fetchVoiceprint failed: \(error.localizedDescription)")
        }
        #endif
        #if !canImport(Supabase)
        print("[Voiceprint] ⚠️ Supabase SDK unavailable — cannot fetch remote voiceprint")
        #endif
        return nil
    }
    
    func saveVoiceprint(_ payload: VoiceprintPayload) async -> Bool {
        #if canImport(Supabase)
        do {
            guard let client = try? (self.auth as? SupabaseAuthService)?.buildClient(),
                  let user = client.auth.currentUser else { return false }
            let stored = VoiceprintStoragePayload(vector: payload.vector, metadata: payload.metadata, created_at: payload.createdAt)
            let upsert = VoiceprintUpsert(id: user.id, voiceprint_v1: stored)
            let iso = ISO8601DateFormatter().string(from: Date())
            print("[Voiceprint] 💾 Upserting voiceprint to Supabase (user: \(user.id.uuidString), vector: \(payload.vector.count), sr: \(Int(payload.metadata.sampleRate))) @ \(iso)")
            _ = try await client.database
                .from("profiles")
                .upsert(upsert, onConflict: "id")
                .execute()
            print("[Voiceprint] ✅ Voiceprint committed to Supabase (profiles.voiceprint_v1) for user \(user.id.uuidString)")
            return true
        } catch {
            print("[Voiceprint] ❌ Supabase upsert failed: \(error.localizedDescription)")
            return false
        }
        #else
        print("[Voiceprint] ⚠️ Supabase SDK unavailable — skipping remote voiceprint save")
        return false
        #endif
    }
}

