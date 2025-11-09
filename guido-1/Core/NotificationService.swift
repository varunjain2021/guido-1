import Foundation
import UserNotifications
import UIKit

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        print("❌ [Notifications] Authorization request error: \(error)")
                    } else {
                        print("🔔 [Notifications] Authorization granted: \(granted)")
                    }
                }
            }
        }
    }
    
    func sendDirectionsNotification(destination: String, summary: String, mapsURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Directions to \(destination)"
        content.body = summary.isEmpty ? "Open Google Maps to view directions." : summary
        content.sound = .default
        content.userInfo = ["maps_url": mapsURL.absoluteString]
        
        // Deliver immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("❌ [Notifications] Failed to schedule directions notification: \(error)")
            } else {
                print("✅ [Notifications] Directions notification scheduled for '\(destination)'")
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["maps_url"] as? String, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                print("🔔 [Notifications] Opening maps URL from notification: \(url.absoluteString)")
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        completionHandler()
    }
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show alert/sound even when app is foregrounded
        completionHandler([.banner, .sound, .list])
    }
}


