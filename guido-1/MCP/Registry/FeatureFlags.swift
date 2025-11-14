//
//  FeatureFlags.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  Feature flag system for safe MCP migration and rollback
//

import Foundation

// MARK: - Tool Categories

public enum ToolCategory: String, CaseIterable {
    case location = "location"
    case travel = "travel"
    case search = "search"
    case safety = "safety"
    case calendar = "calendar"
    case transport = "transport"
    case discovery = "discovery"
    
    public var displayName: String {
        switch self {
        case .location: return "Location"
        case .travel: return "Travel"
        case .search: return "Search"
        case .safety: return "Safety"
        case .calendar: return "Calendar"
        case .transport: return "Transport"
        case .discovery: return "Discovery"
        }
    }
    
    public var toolNames: [String] {
        switch self {
        case .location:
            return [
                "get_user_location", 
                "find_nearby_places", 
                "get_directions",
                "find_places_on_route",
                "find_nearby_restaurants",
                "find_nearby_transport", 
                "find_nearby_landmarks",
                "find_nearby_services"
            ]
        case .travel:
            return ["get_weather", "currency_converter", "translate_text", "check_travel_requirements"]
        case .search:
            return ["web_search", "ai_response"]
        case .safety:
            return ["get_safety_info", "get_emergency_info"]
        case .calendar:
            return ["check_calendar", "get_local_time"]
        case .transport:
            return [
                "find_transportation",
                "find_local_events",
                "bikes_nearby",
                "docks_nearby",
                "station_availability",
                "type_breakdown_nearby",
                "parking_near_destination"
            ]
        case .discovery:
            return [
                "search_web",
                "search_candidates_for_facet",
                "reviews_list",
                "reviews_aspects_summarize",
                "photos_list",
                "vibe_analyze",
                "web_links_discover",
                "web_readable_extract",
                "pdf_extract",
                "web_images_discover",
                "menu_parse",
                "catalog_classify"
            ]
        }
    }
}

// MARK: - Migration States

public enum ToolMigrationState: String, CaseIterable {
    case legacy = "legacy"                    // Use old RealtimeToolManager exclusively
    case hybrid = "hybrid"                    // Some tools via MCP, some via legacy (based on enabledMCPCategories)
    case mcpWithFallback = "mcp_with_fallback" // MCP first, fallback to legacy on error
    case mcpOnly = "mcp_only"                 // All tools via MCP (production target)
    
    public var displayName: String {
        switch self {
        case .legacy: return "Legacy Only"
        case .hybrid: return "Hybrid (Gradual Migration)"
        case .mcpWithFallback: return "MCP with Legacy Fallback"
        case .mcpOnly: return "MCP Only"
        }
    }
    
    public var description: String {
        switch self {
        case .legacy:
            return "All tools use the existing RealtimeToolManager. No MCP components active."
        case .hybrid:
            return "Tools in enabled categories use MCP, others use legacy system."
        case .mcpWithFallback:
            return "All tools attempt MCP first, fallback to legacy on any error."
        case .mcpOnly:
            return "All tools use MCP exclusively. Legacy system disabled."
        }
    }
}

// MARK: - Feature Flags Manager

@MainActor
public class FeatureFlags: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var migrationState: ToolMigrationState = .mcpWithFallback
    @Published public var enabledMCPCategories: Set<ToolCategory> = []
    @Published public var rollbackTriggers: [String: Bool] = [:]
    @Published public var isPerformanceMonitoringEnabled: Bool = true
    @Published public var debugLoggingEnabled: Bool = false
    
    // MARK: - Performance Metrics
    
    @Published public var performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    
    // MARK: - Singleton
    
    public static let shared = FeatureFlags()
    
    private init() {
        loadFromUserDefaults()
        setupRollbackTriggers()
        ensureTransportCategoryEnabled()
    }
    
    // MARK: - Migration Control
    
    public func shouldUseMCPForTool(_ toolName: String) -> Bool {
        switch migrationState {
        case .legacy:
            return false
            
        case .hybrid:
            // Check if this tool's category is enabled for MCP
            let toolCategory = getToolCategory(for: toolName)
            return enabledMCPCategories.contains(toolCategory)
            
        case .mcpWithFallback, .mcpOnly:
            return true
        }
    }
    
    public func shouldFallbackToLegacy(for toolName: String, mcpError: Error) -> Bool {
        switch migrationState {
        case .legacy:
            return true // Always use legacy
            
        case .hybrid:
            // In hybrid mode, if MCP fails, fall back to legacy
            return true
            
        case .mcpWithFallback:
            // Check if this specific tool has triggered too many errors
            let errorKey = "mcp_errors_\(toolName)"
            let errorCount = UserDefaults.standard.integer(forKey: errorKey)
            
            if errorCount >= 3 {
                print("⚠️ [FeatureFlags] Tool '\(toolName)' has failed \(errorCount) times, forcing legacy fallback")
                return true
            }
            
            return true // Allow fallback in this mode
            
        case .mcpOnly:
            return false // No fallback, MCP must work
        }
    }
    
    public func enableMCPForCategory(_ category: ToolCategory) {
        enabledMCPCategories.insert(category)
        saveToUserDefaults()
        print("✅ [FeatureFlags] Enabled MCP for category: \(category.displayName)")
    }
    
    public func disableMCPForCategory(_ category: ToolCategory) {
        enabledMCPCategories.remove(category)
        saveToUserDefaults()
        print("❌ [FeatureFlags] Disabled MCP for category: \(category.displayName)")
    }
    
    public func enableAllMCPCategories() {
        enabledMCPCategories = Set(ToolCategory.allCases)
        saveToUserDefaults()
        print("✅ [FeatureFlags] Enabled MCP for all categories")
    }
    
    public func disableAllMCPCategories() {
        enabledMCPCategories.removeAll()
        saveToUserDefaults()
        print("❌ [FeatureFlags] Disabled MCP for all categories")
    }
    
    // MARK: - Emergency Rollback
    
    public func emergencyRollbackToLegacy(reason: String) {
        let previousState = migrationState
        migrationState = .legacy
        enabledMCPCategories.removeAll()
        
        // Log the rollback
        print("🚨 [FeatureFlags] EMERGENCY ROLLBACK: \(reason)")
        print("🚨 [FeatureFlags] Previous state: \(previousState.displayName)")
        print("🚨 [FeatureFlags] All tools now using legacy system")
        
        // Save rollback reason and timestamp
        UserDefaults.standard.set(reason, forKey: "last_rollback_reason")
        UserDefaults.standard.set(Date(), forKey: "last_rollback_timestamp")
        
        saveToUserDefaults()
        
        // Trigger notification for monitoring systems
        NotificationCenter.default.post(
            name: .mcpEmergencyRollback,
            object: nil,
            userInfo: ["reason": reason, "previous_state": previousState.rawValue]
        )
    }
    
    // MARK: - Performance Monitoring
    
    public func recordToolExecution(
        toolName: String,
        usedMCP: Bool,
        duration: TimeInterval,
        success: Bool,
        error: Error? = nil
    ) {
        performanceMetrics.recordExecution(
            toolName: toolName,
            usedMCP: usedMCP,
            duration: duration,
            success: success,
            error: error
        )
        
        // Check for performance degradation
        if duration > 5.0 && usedMCP {
            let slowExecutionKey = "slow_mcp_\(toolName)"
            let slowCount = UserDefaults.standard.integer(forKey: slowExecutionKey) + 1
            UserDefaults.standard.set(slowCount, forKey: slowExecutionKey)
            
            if slowCount >= 3 {
                print("⚠️ [FeatureFlags] Tool '\(toolName)' via MCP is consistently slow (\(duration)s)")
                // Could trigger automatic rollback here if desired
            }
        }
        
        // Record errors for fallback decision making
        if !success, let error = error, usedMCP {
            let errorKey = "mcp_errors_\(toolName)"
            let errorCount = UserDefaults.standard.integer(forKey: errorKey) + 1
            UserDefaults.standard.set(errorCount, forKey: errorKey)
            
            print("❌ [FeatureFlags] MCP error for '\(toolName)' (count: \(errorCount)): \(error)")
        }
    }
    
    // MARK: - Utility Methods
    
    private func getToolCategory(for toolName: String) -> ToolCategory {
        for category in ToolCategory.allCases {
            if category.toolNames.contains(toolName) {
                return category
            }
        }
        
        // Default fallback
        print("⚠️ [FeatureFlags] Unknown tool category for '\(toolName)', defaulting to location")
        return .location
    }
    
    private func setupRollbackTriggers() {
        rollbackTriggers = [
            "voice_quality_degradation": false,
            "audio_pipeline_errors": false,
            "high_tool_failure_rate": false,
            "performance_degradation": false,
            "user_complaints": false
        ]
    }
    
    private func ensureTransportCategoryEnabled() {
        if !enabledMCPCategories.contains(.transport) {
            enabledMCPCategories.insert(.transport)
            saveToUserDefaults()
            print("🚲 [FeatureFlags] Transport category auto-enabled for bikeshare tools")
        }
    }
    
    // MARK: - Persistence
    
    private func saveToUserDefaults() {
        UserDefaults.standard.set(migrationState.rawValue, forKey: "mcp_migration_state")
        
        let categoryStrings = enabledMCPCategories.map { $0.rawValue }
        UserDefaults.standard.set(categoryStrings, forKey: "mcp_enabled_categories")
        
        UserDefaults.standard.set(isPerformanceMonitoringEnabled, forKey: "mcp_performance_monitoring")
        UserDefaults.standard.set(debugLoggingEnabled, forKey: "mcp_debug_logging")
    }
    
    private func loadFromUserDefaults() {
        if let stateString = UserDefaults.standard.string(forKey: "mcp_migration_state"),
           let state = ToolMigrationState(rawValue: stateString) {
            migrationState = state
        }
        
        if let categoryStrings = UserDefaults.standard.array(forKey: "mcp_enabled_categories") as? [String] {
            enabledMCPCategories = Set(categoryStrings.compactMap { ToolCategory(rawValue: $0) })
        }
        
        isPerformanceMonitoringEnabled = UserDefaults.standard.bool(forKey: "mcp_performance_monitoring")
        debugLoggingEnabled = UserDefaults.standard.bool(forKey: "mcp_debug_logging")
    }
}

// MARK: - Performance Metrics

public struct PerformanceMetrics {
    public private(set) var mcpExecutions: [ToolExecution] = []
    public private(set) var legacyExecutions: [ToolExecution] = []
    
    public struct ToolExecution {
        public let toolName: String
        public let timestamp: Date
        public let duration: TimeInterval
        public let success: Bool
        public let error: String?
        
        public init(toolName: String, duration: TimeInterval, success: Bool, error: Error? = nil) {
            self.toolName = toolName
            self.timestamp = Date()
            self.duration = duration
            self.success = success
            self.error = error?.localizedDescription
        }
    }
    
    public mutating func recordExecution(
        toolName: String,
        usedMCP: Bool,
        duration: TimeInterval,
        success: Bool,
        error: Error? = nil
    ) {
        let execution = ToolExecution(toolName: toolName, duration: duration, success: success, error: error)
        
        if usedMCP {
            mcpExecutions.append(execution)
            // Keep only last 100 executions
            if mcpExecutions.count > 100 {
                mcpExecutions.removeFirst(mcpExecutions.count - 100)
            }
        } else {
            legacyExecutions.append(execution)
            if legacyExecutions.count > 100 {
                legacyExecutions.removeFirst(legacyExecutions.count - 100)
            }
        }
    }
    
    public var mcpAverageLatency: TimeInterval {
        guard !mcpExecutions.isEmpty else { return 0 }
        return mcpExecutions.map { $0.duration }.reduce(0, +) / Double(mcpExecutions.count)
    }
    
    public var legacyAverageLatency: TimeInterval {
        guard !legacyExecutions.isEmpty else { return 0 }
        return legacyExecutions.map { $0.duration }.reduce(0, +) / Double(legacyExecutions.count)
    }
    
    public var mcpSuccessRate: Double {
        guard !mcpExecutions.isEmpty else { return 1.0 }
        let successCount = mcpExecutions.filter { $0.success }.count
        return Double(successCount) / Double(mcpExecutions.count)
    }
    
    public var legacySuccessRate: Double {
        guard !legacyExecutions.isEmpty else { return 1.0 }
        let successCount = legacyExecutions.filter { $0.success }.count
        return Double(successCount) / Double(legacyExecutions.count)
    }
}

// MARK: - Notifications

extension Notification.Name {
    public static let mcpEmergencyRollback = Notification.Name("MCPEmergencyRollback")
    public static let mcpMigrationStateChanged = Notification.Name("MCPMigrationStateChanged")
    public static let mcpCategoryEnabled = Notification.Name("MCPCategoryEnabled")
    public static let mcpCategoryDisabled = Notification.Name("MCPCategoryDisabled")
}