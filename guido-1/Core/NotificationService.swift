import Combine
import CoreLocation
import Foundation
import UserNotifications
import UIKit

typealias CampaignCondition = () -> Bool

// MARK: - Dynamic Notification Copy Generator

/// Generates fresh, LLM-powered notification copy to keep engagement high
actor NotificationCopyGenerator {
    static let shared = NotificationCopyGenerator()
    
    private let defaults = UserDefaults.standard
    private let morningCopyKey = "notification.copy.morning"
    private let eveningCopyKey = "notification.copy.evening"
    private let lastGeneratedKey = "notification.copy.lastGenerated"
    
    private var apiKey: String {
        guard let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let configDict = NSDictionary(contentsOfFile: configPath),
              let key = configDict["OpenAI_API_Key"] as? String else {
            return ""
        }
        return key
    }
    
    struct NotificationCopy: Codable {
        let title: String
        let body: String
    }
    
    // MARK: - Public API
    
    /// Get fresh copy for morning notification, generating if needed
    func getMorningCopy() async -> NotificationCopy {
        await refreshCopyIfNeeded()
        return loadCopy(for: morningCopyKey) ?? NotificationCopy(
            title: "☕ Good morning!",
            body: "Start your day with Guido. One tap to discover something nearby."
        )
    }
    
    /// Get fresh copy for evening notification, generating if needed
    func getEveningCopy() async -> NotificationCopy {
        await refreshCopyIfNeeded()
        return loadCopy(for: eveningCopyKey) ?? NotificationCopy(
            title: "🌆 You've earned a break",
            body: "Wind down with Guido. One tap to find your next spot."
        )
    }
    
    /// Force regenerate copy (e.g., on app launch)
    func regenerateCopyIfStale() async {
        await refreshCopyIfNeeded()
    }
    
    /// Force regenerate copy regardless of staleness (for background refresh)
    func forceRegenerateCopy() async {
        await generateFreshCopy()
    }
    
    // MARK: - Private
    
    private func refreshCopyIfNeeded() async {
        let lastGenerated = defaults.object(forKey: lastGeneratedKey) as? Date ?? .distantPast
        let calendar = Calendar.current
        
        // Regenerate if it's a new day
        guard !calendar.isDateInToday(lastGenerated) else { return }
        
        await generateFreshCopy()
    }
    
    private func generateFreshCopy() async {
        guard !apiKey.isEmpty else {
            print("⚠️ [NotificationCopy] No API key, using defaults")
            return
        }
        
        let dayOfWeek = DateFormatter().weekdaySymbols[Calendar.current.component(.weekday, from: Date()) - 1]
        let hour = Calendar.current.component(.hour, from: Date())
        let isWeekend = Calendar.current.isDateInWeekend(Date())
        
        let prompt = """
        You are a world-class push notification copywriter for Guido, a voice-first AI travel companion app.
        
        TODAY: \(dayOfWeek) \(isWeekend ? "(Weekend)" : "(Weekday)")
        
        === ABOUT GUIDO ===
        Guido is your daily companion for discovering your own city. Users just speak naturally and Guido:
        • Finds nearby restaurants, cafes, bars, and spots you haven't tried yet
        • Gives hands-free voice navigation for walking (no looking at phone)
        • Helps you break out of routines and discover new local favorites
        • Finds bike share stations with real-time availability
        • Recommends based on mood: "somewhere quiet to work" or "best lunch spot nearby"
        • Perfect for daily errands, lunch breaks, after-work plans, and weekend exploring
        • Makes your everyday city feel fresh and full of possibilities
        
        === YOUR TASK ===
        Write 2 push notifications that integrate into the user's daily routine and make them WANT to open Guido.
        
        1. MORNING (8 AM) - Catch them as they start their day
           \(isWeekend ? "Weekend vibe: brunch, farmers markets, morning adventures, lazy cafe time" : "Weekday vibe: coffee run, breakfast spot, commute helper, morning energy boost")
        
        2. EVENING (5:30 PM) - Catch them winding down or making plans
           \(isWeekend ? "Weekend vibe: dinner plans, local events, evening activities, nightlife" : "Weekday vibe: happy hour, dinner ideas, treat yourself moment, evening escape")
        
        === COPYWRITING RULES ===
        
        TITLE (max 30 chars):
        • Start with ONE relevant emoji
        • Tap into a SPECIFIC moment or feeling
        • Questions work great
        • Be concrete, not abstract
        
        BODY (max 55 chars):
        • Encourage conversation with Guido naturally
        • Give a reason WHY now + hint at talking to Guido
        • Sound like a friend suggesting you chat with Guido
        • Be specific about the outcome
        
        === EXAMPLES WE LOVE ===
        ✅ "☕ Need coffee?" / "Just ask Guido—best spots in seconds."
        ✅ "🍜 Bored of your usual?" / "Tell Guido what you're feeling."
        ✅ "🍷 Long week?" / "Ask Guido for a drink nearby. You earned it."
        ✅ "🌮 Hungry?" / "Say 'tacos nearby' and Guido handles the rest."
        ✅ "🚴 Skip the subway?" / "Ask Guido—bikes available nearby."
        
        === EXAMPLES WE HATE ===
        ❌ "Ask Guido for a new cafe" (Too generic—what kind? why?)
        ❌ "Say what you're craving" (No context or reason)
        ❌ "On your way in" (In where? Be specific)
        ❌ "Guido finds a place" (Too vague—what place?)
        ❌ Just outcome, no conversation hint (we want users to TALK to Guido)
        
        === OUTPUT FORMAT ===
        Respond with ONLY valid JSON, no markdown:
        {"morning": {"title": "...", "body": "..."}, "evening": {"title": "...", "body": "..."}}
        """
        
        do {
            let response = try await callOpenAI(prompt: prompt)
            if let data = response.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let morning = json["morning"] as? [String: String],
               let evening = json["evening"] as? [String: String],
               let morningTitle = morning["title"],
               let morningBody = morning["body"],
               let eveningTitle = evening["title"],
               let eveningBody = evening["body"] {
                
                let morningCopy = NotificationCopy(title: morningTitle, body: morningBody)
                let eveningCopy = NotificationCopy(title: eveningTitle, body: eveningBody)
                
                saveCopy(morningCopy, for: morningCopyKey)
                saveCopy(eveningCopy, for: eveningCopyKey)
                defaults.set(Date(), forKey: lastGeneratedKey)
                
                print("✅ [NotificationCopy] Generated fresh copy for \(dayOfWeek)")
                print("   Morning: \(morningTitle) - \(morningBody)")
                print("   Evening: \(eveningTitle) - \(eveningBody)")
            }
        } catch {
            print("❌ [NotificationCopy] Failed to generate: \(error)")
        }
    }
    
    private func callOpenAI(prompt: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use gpt-5.1 with reasoning: none for fast, intelligent responses without chain-of-thought overhead
        // With reasoning=none, temperature is supported and no reasoning tokens are consumed
        let requestBody: [String: Any] = [
            "model": "gpt-5.1",
            "messages": [
                ["role": "system", "content": "You are an elite push notification copywriter who has driven millions in app engagement. You write copy that feels human, creates urgency, and makes users genuinely excited to open the app. You never sound corporate or generic. Respond only in valid JSON."],
                ["role": "user", "content": prompt]
            ],
            "max_completion_tokens": 500,
            "temperature": 0.9,
            "reasoning_effort": "none",
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "NotificationCopyGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ [NotificationCopy] API error \(httpResponse.statusCode): \(errorBody)")
            throw NSError(domain: "NotificationCopyGenerator", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API request failed with status \(httpResponse.statusCode)"])
        }
        
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?  // Can be null with reasoning models
                }
                let message: Message
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        
        // Debug: log raw response
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        print("🔍 [NotificationCopy] Raw API response: \(rawResponse)")
        
        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        let finishReason = chatResponse.choices.first?.finish_reason ?? "unknown"
        print("🔍 [NotificationCopy] Finish reason: \(finishReason)")
        
        guard let content = chatResponse.choices.first?.message.content, !content.isEmpty else {
            print("❌ [NotificationCopy] Empty content from API. Finish reason: \(finishReason)")
            throw NSError(domain: "NotificationCopyGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty content from API (finish_reason: \(finishReason))"])
        }
        
        print("🔍 [NotificationCopy] Parsed content: \(content)")
        return content
    }
    
    private func saveCopy(_ copy: NotificationCopy, for key: String) {
        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: key)
        }
    }
    
    private func loadCopy(for key: String) -> NotificationCopy? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NotificationCopy.self, from: data)
    }
}

// MARK: - Scheduled Notification Model

struct ScheduledNotification: Identifiable {
    let id: String
    let title: String
    let body: String
    let hour: Int
    let minute: Int
    let category: String
    let userInfo: [AnyHashable: Any]
    let isEnabled: Bool
    let condition: CampaignCondition?
    let isDynamic: Bool  // If true, copy is generated by LLM
    
    init(
        id: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        category: String,
        userInfo: [AnyHashable: Any] = [:],
        isEnabled: Bool = true,
        condition: CampaignCondition? = nil,
        isDynamic: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.hour = hour
        self.minute = minute
        self.category = category
        self.userInfo = userInfo
        self.isEnabled = isEnabled
        self.condition = condition
        self.isDynamic = isDynamic
    }
    
    var shouldSchedule: Bool {
        guard isEnabled else { return false }
        return condition?() ?? true
    }
}

extension ScheduledNotification {
    // NOTE: Times set to 11:15 PM for testing. Revert to 8:00, 17:30, 9:00 for production.
    static let defaultCampaigns: [ScheduledNotification] = [
        ScheduledNotification(
            id: "morning-engagement",
            title: "☕ Good morning!",  // Placeholder, replaced dynamically
            body: "Start your day with Guido.",
            hour: 8,
            minute: 0,
            category: "engagement",
            isDynamic: true
        ),
        ScheduledNotification(
            id: "evening-engagement",
            title: "🌆 You've earned a break",  // Placeholder, replaced dynamically
            body: "Wind down with Guido.",
            hour: 17,
            minute: 30,
            category: "engagement",
            isDynamic: true
        ),
        ScheduledNotification(
            id: "location-permission-nudge",
            title: "🌍 Your personal heatmap is empty...",
            body: "Save your frequent spots without lifting a finger. Tap to unlock your heatmap.",
            hour: 9,
            minute: 0,
            category: "permission",
            condition: {
                CLLocationManager().authorizationStatus != .authorizedAlways
            }
        )
    ]
}

@MainActor
final class NotificationScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()
    
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let calendar = Calendar.current
    private var campaigns: [ScheduledNotification]
    private var currentUserId: String?
    
    private override init() {
        campaigns = ScheduledNotification.defaultCampaigns
        super.init()
        notificationCenter.delegate = self
        Task { await refreshAuthorizationStatus() }
    }
    
    /// Configure with user context for analytics
    func configureAnalytics(userId: String?) {
        self.currentUserId = userId
    }
    
    func requestAuthorizationIfNeeded() {
        Task { _ = await requestAuthorization() }
    }
    
    func requestAuthorizationAndSchedule() {
        Task {
            let status = await requestAuthorization()
            guard Self.isAuthorized(status) else { return }
            // Force regenerate copy on every app launch for testing
            // TODO: Change back to regenerateCopyIfStale() for production
            await NotificationCopyGenerator.shared.forceRegenerateCopy()
            await scheduleAll()
        }
    }
    
    func requestAuthorization() async -> UNAuthorizationStatus {
        let currentSettings = await fetchSettings()
        authorizationStatus = currentSettings.authorizationStatus
        
        guard currentSettings.authorizationStatus == .notDetermined else {
            return currentSettings.authorizationStatus
        }
        
        let granted = await withCheckedContinuation { continuation in
            notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    print("❌ [Notifications] Authorization request error: \(error)")
                } else {
                    print("🔔 [Notifications] Authorization granted: \(granted)")
                }
                continuation.resume(returning: granted)
            }
        }
        
        await refreshAuthorizationStatus()
        return authorizationStatus
    }
    
    func refreshAuthorizationStatus() async {
        let settings = await fetchSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    func refreshConditionalCampaigns() {
        Task { await scheduleAll() }
    }
    
    /// Async version for background task usage
    func refreshConditionalCampaignsAsync() async {
        await scheduleAll()
    }
    
    func replaceCampaigns(_ campaigns: [ScheduledNotification], reschedule: Bool = true) {
        self.campaigns = campaigns
        if reschedule {
            refreshConditionalCampaigns()
        }
    }
    
    func cancelCampaign(withID identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    func cancelAllCampaigns() {
        let identifiers = campaigns.map(\.id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    func sendDirectionsNotification(destination: String, summary: String, mapsURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Directions to \(destination)"
        content.body = summary.isEmpty ? "Open Google Maps to view directions." : summary
        content.sound = .default
        content.userInfo = ["maps_url": mapsURL.absoluteString]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error {
                print("❌ [Notifications] Failed to schedule directions notification: \(error)")
            } else {
                print("✅ [Notifications] Directions notification scheduled for '\(destination)'")
            }
        }
    }
    
    // MARK: - Scheduling
    
    private func scheduleAll() async {
        guard Self.isAuthorized(authorizationStatus) else { return }
        
        let managedIdentifiers = campaigns.map(\.id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: managedIdentifiers)
        
        for campaign in campaigns where campaign.shouldSchedule {
            await schedule(campaign)
        }
    }
    
    private func schedule(_ campaign: ScheduledNotification) async {
        let content = UNMutableNotificationContent()
        
        // Use dynamic LLM-generated copy if available
        if campaign.isDynamic {
            let copy: NotificationCopyGenerator.NotificationCopy
            if campaign.id == "morning-engagement" {
                copy = await NotificationCopyGenerator.shared.getMorningCopy()
            } else if campaign.id == "evening-engagement" {
                copy = await NotificationCopyGenerator.shared.getEveningCopy()
            } else {
                copy = NotificationCopyGenerator.NotificationCopy(title: campaign.title, body: campaign.body)
            }
            content.title = copy.title
            content.body = copy.body
        } else {
            content.title = campaign.title
            content.body = campaign.body
        }
        
        content.sound = .default
        content.categoryIdentifier = campaign.category
        
        // Add campaign ID to userInfo for click tracking
        var userInfo = campaign.userInfo
        userInfo["campaign_id"] = campaign.id
        content.userInfo = userInfo
        
        var components = DateComponents()
        components.calendar = calendar
        components.hour = campaign.hour
        components.minute = campaign.minute
        
        // Calculate the next scheduled time for logging
        let scheduledAt = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) ?? Date()
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: campaign.id, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            print("✅ [Notifications] Scheduled campaign '\(campaign.id)' at \(campaign.hour):\(String(format: "%02d", campaign.minute)) - \"\(content.title)\"")
            
            // Log to Supabase
            await SupabaseNotificationSink.shared.logNotificationDelivered(
                campaignId: campaign.id,
                title: content.title,
                body: content.body,
                scheduledAt: scheduledAt,
                userId: currentUserId
            )
        } catch {
            print("❌ [Notifications] Failed to schedule campaign '\(campaign.id)': \(error)")
        }
    }
    
    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Track notification click in Supabase
        if let campaignId = userInfo["campaign_id"] as? String {
            Task {
                await SupabaseNotificationSink.shared.logNotificationClicked(campaignId: campaignId)
            }
        }
        
        // Handle maps URL if present
        if let urlString = userInfo["maps_url"] as? String, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        completionHandler()
    }
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    
    // MARK: - Helpers
    
    private func fetchSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }
}

// MARK: - Async helpers

private extension UNUserNotificationCenter {
    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
