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
        if let payload = await profileService?.fetchVoiceprint() ?? loadLocalVoiceprint() {
            saveLocalVoiceprint(payload)
            status = .available(payload)
        } else {
            status = .missing
        }
    }
    
    func saveVoiceprint(_ payload: VoiceprintPayload) async {
        status = .loading
        let succeeded = await profileService?.saveVoiceprint(payload) ?? saveLocalVoiceprint(payload)
        if succeeded {
            saveLocalVoiceprint(payload)
            status = .available(payload)
        } else {
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

