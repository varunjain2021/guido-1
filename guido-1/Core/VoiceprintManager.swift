//
//  VoiceprintManager.swift
//  guido-1
//

import Foundation

@MainActor
final class VoiceprintManager: ObservableObject {
    enum Status: Equatable {
        case unknown
        case loading
        case missing
        case available(VoiceprintPayload)
        case error(String)
    }
    
    static let shared = VoiceprintManager()
    
    @Published private(set) var status: Status = .unknown
    
    private var profileService: SupabaseProfileService?
    private var authService: AuthService?
    private let cacheKey = "voiceprint.local.cache"
    
    private init() {}
    
    func configure(profileService: SupabaseProfileService?, authService: AuthService) {
        self.profileService = profileService
        self.authService = authService
        Task {
            await refreshFromRemote()
        }
    }
    
    func refreshFromRemote() async {
        status = .loading
        let remote = await profileService?.fetchVoiceprint()
        if let payload = remote {
            print("[Voiceprint] ☁️ Loaded voiceprint from Supabase (vector: \(payload.vector.count))")
            saveLocalVoiceprint(payload)
            status = .available(payload)
            return
        }
        if let local = loadLocalVoiceprint() {
            print("[Voiceprint] 💾 Loaded voiceprint from local cache (vector: \(local.vector.count))")
            status = .available(local)
        } else {
            print("[Voiceprint] 🔍 No voiceprint found (remote/local)")
            status = .missing
        }
    }
    
    func saveVoiceprint(_ payload: VoiceprintPayload) async {
        status = .loading
        print("[Voiceprint] 📨 Saving voiceprint (vector: \(payload.vector.count), sr: \(Int(payload.metadata.sampleRate)))")
        let remoteSucceeded = await profileService?.saveVoiceprint(payload) ?? false
        let localSucceeded = saveLocalVoiceprint(payload)
        if remoteSucceeded || localSucceeded {
            print("[Voiceprint] ✅ Voiceprint save succeeded (remote: \(remoteSucceeded ? "yes" : "no"), local: \(localSucceeded ? "yes" : "no"))")
            status = .available(payload)
        } else {
            print("[Voiceprint] ❌ Voiceprint save failed (remote/local)")
            status = .error("Failed to save voiceprint")
        }
    }
    
    func requireVoiceprint() {
        switch status {
        case .available:
            break
        case .unknown, .loading, .missing, .error:
            status = .missing
        }
    }
    
    var hasVoiceprint: Bool {
        if case .available = status { return true }
        return false
    }
    
    func currentPayload() -> VoiceprintPayload? {
        if case .available(let payload) = status { return payload }
        return nil
    }
    
    // MARK: - Local cache fallback (when Supabase SDK unavailable)
    private func loadLocalVoiceprint() -> VoiceprintPayload? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(VoiceprintPayload.self, from: data)
    }
    
    @discardableResult
    private func saveLocalVoiceprint(_ payload: VoiceprintPayload) -> Bool {
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            return true
        }
        return false
    }
}

