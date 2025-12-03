//
//  guido_1App.swift
//  guido-1
//
//  Created by Varun Jain on 7/26/25.
//

import SwiftUI
import UserNotifications
import GoogleMaps
import BackgroundTasks

@main
struct guido_1App: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Initialize Google Maps/Navigation SDK early
        initializeGoogleMapsSDK()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleDeepLink(url)
                    Task { await appState.authService.handleOpenURL(url) }
                }
                .onAppear {
                    print("🚀 Guido app launched successfully!")
                    print("💡 Tip: iOS Simulator messages above are normal system behavior")
                    print("📱 Look for emoji-prefixed messages for app-specific logs")
                    
                    // Configure notification analytics sink
                    configureNotificationSink()
                    
                    NotificationScheduler.shared.requestAuthorizationAndSchedule()
                }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                HeatmapService.shared.flushActiveVisit(reason: "scene-background")
                // Schedule background refresh when entering background
                BackgroundNotificationRefreshManager.shared.scheduleAppRefresh()
            case .inactive:
                HeatmapService.shared.flushActiveVisit(reason: "scene-inactive")
            default:
                break
            }
        }
    }
    
    private func initializeGoogleMapsSDK() {
        // Load API key from Config.plist
        guard let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let configDict = NSDictionary(contentsOfFile: configPath),
              let apiKey = configDict["Google_API_Key"] as? String,
              !apiKey.isEmpty else {
            print("⚠️ [GoogleMaps] Could not load API key from Config.plist")
            return
        }
        
        GMSServices.provideAPIKey(apiKey)
        print("✅ [GoogleMaps] SDK initialized with API key: \(apiKey.prefix(10))...")
    }
    
    private func handleDeepLink(_ url: URL) {
        print("🔗 Deep link received: \(url)")
        guard url.scheme == "guido" else { 
            print("❌ Invalid deep link scheme")
            return 
        }
        
        switch url.host {
        case "realtime":
            print("🎤 Opening realtime conversation via deep link")
            appState.showRealtimeConversation = true
        default:
            print("❌ Unknown deep link: \(url)")
        }
    }
    
    private func configureNotificationSink() {
        // Configure Supabase notification sink for analytics
        guard !appState.supabaseURL.isEmpty, !appState.supabaseAnonKey.isEmpty else {
            print("⚠️ [NotificationSink] Supabase not configured, analytics disabled")
            return
        }
        
        SupabaseNotificationSink.shared.configure(
            baseURL: appState.supabaseURL,
            anonKey: appState.supabaseAnonKey,
            accessTokenProvider: { [weak appState] in
                await appState?.authService.currentAccessToken()
            }
        )
        
        // Set user ID if authenticated
        Task {
            let status = await appState.authService.currentStatus()
            if status.isAuthenticated {
                await MainActor.run {
                    NotificationScheduler.shared.configureAnalytics(userId: status.user?.id)
                }
            }
        }
    }
}

// MARK: - App Delegate for Background Tasks

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Register background task handler
        BackgroundNotificationRefreshManager.shared.registerBackgroundTask()
        return true
    }
}

// MARK: - Background Notification Refresh Manager

/// Manages background app refresh to keep notification copy fresh
final class BackgroundNotificationRefreshManager {
    static let shared = BackgroundNotificationRefreshManager()
    
    private let taskIdentifier = "com.guido.notificationCopyRefresh"
    
    private init() {}
    
    /// Register the background task handler - call from AppDelegate
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(task: refreshTask)
        }
        print("✅ [BackgroundRefresh] Registered background task: \(taskIdentifier)")
    }
    
    /// Schedule the next background refresh - call when app enters background
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // Request to run early morning (around 5 AM) so fresh copy is ready before 8 AM notification
        request.earliestBeginDate = nextRefreshDate()
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ [BackgroundRefresh] Scheduled next refresh for \(request.earliestBeginDate?.description ?? "ASAP")")
        } catch {
            print("❌ [BackgroundRefresh] Failed to schedule: \(error)")
        }
    }
    
    /// Handle the background refresh task
    private func handleAppRefresh(task: BGAppRefreshTask) {
        print("🔄 [BackgroundRefresh] Starting background notification copy refresh")
        
        // Schedule the next refresh before doing work
        scheduleAppRefresh()
        
        // Create a task to generate fresh copy
        let refreshOperation = Task {
            await NotificationCopyGenerator.shared.forceRegenerateCopy()
            await NotificationScheduler.shared.refreshConditionalCampaignsAsync()
        }
        
        // Handle task expiration
        task.expirationHandler = {
            refreshOperation.cancel()
            print("⚠️ [BackgroundRefresh] Task expired before completion")
        }
        
        // Complete the task when done
        Task {
            await refreshOperation.value
            task.setTaskCompleted(success: true)
            print("✅ [BackgroundRefresh] Completed background refresh")
        }
    }
    
    /// Calculate next refresh date (5 AM daily, before 8 AM morning notification)
    private func nextRefreshDate() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 5
        components.minute = 0
        
        // If it's already past the target time today, schedule for tomorrow
        if let targetDate = calendar.date(from: components), targetDate > Date() {
            return targetDate
        } else {
            components.day! += 1
            return calendar.date(from: components) ?? Date().addingTimeInterval(24 * 60 * 60)
        }
    }
}
