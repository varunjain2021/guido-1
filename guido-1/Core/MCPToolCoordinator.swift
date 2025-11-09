//
//  MCPToolCoordinator.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  MCP-aware tool coordinator that wraps RealtimeToolManager
//  Provides identical interface while routing to MCP or legacy systems
//

import Foundation
import CoreLocation

// MARK: - MCP Tool Coordinator

@MainActor
public class MCPToolCoordinator: ObservableObject {
    
    // MARK: - Published Properties (Same as RealtimeToolManager)
    
    @Published public var lastToolUsed: String?
    @Published public var toolResults: [String: Any] = [:]
    
    // MARK: - Private Properties
    
    private let mcpClient: MCPClient
    private let legacyManager: RealtimeToolManager
    private let featureFlags: FeatureFlags
    
    // Dependencies (same as RealtimeToolManager)
    private var locationManager: LocationManager?
    private var locationSearchService: LocationBasedSearchService?
    private var openAIChatService: OpenAIChatService?
    private var googlePlacesRoutesService: GooglePlacesRoutesService?
    private var weatherService: WeatherService?
    private var currencyService: CurrencyService?
    private var translationService: TranslationService?
    private var travelRequirementsService: TravelRequirementsService?
    
    // MCP Servers
    private var locationMCPServer: LocationMCPServer?
    private var travelMCPServer: TravelMCPServer?
    private var searchMCPServer: SearchMCPServer?
    private var safetyMCPServer: SafetyMCPServer?
    private var webSearchBridgeServer: WebSearchBridgeServer?
    private var reviewsServer: ReviewsServer?
    private var photosVibeServer: PhotosVibeServer?
    private var webContentServer: WebContentServer?
    private var menuOfferingsServer: MenuOfferingsServer?
    
    // MARK: - Initialization
    
    public init() {
        self.mcpClient = MCPClient(clientName: "Guido", clientVersion: "1.0.0")
        self.legacyManager = RealtimeToolManager()
        self.featureFlags = FeatureFlags.shared
        
        setupMCPClient()
        print("🔧 [MCPToolCoordinator] Initialized with migration state: \(featureFlags.migrationState.displayName)")
    }
    
    // MARK: - Public Interface (Identical to RealtimeToolManager)
    
    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
        legacyManager.setLocationManager(manager)
        
        // Initialize and configure LocationMCPServer
        locationMCPServer = LocationMCPServer(locationManager: manager)
        travelMCPServer = TravelMCPServer(locationManager: manager)
        safetyMCPServer = SafetyMCPServer(locationManager: manager)
        searchMCPServer = SearchMCPServer()
        webSearchBridgeServer = WebSearchBridgeServer(searchServer: searchMCPServer)
        reviewsServer = ReviewsServer()
        photosVibeServer = PhotosVibeServer()
        webContentServer = WebContentServer()
        menuOfferingsServer = MenuOfferingsServer()
        if let webContentServer {
            menuOfferingsServer?.setWebContentServer(webContentServer)
        }
        
        // Set services if they're available
        if let searchService = locationSearchService {
            locationMCPServer?.setLocationSearchService(searchService)
        }
        if let chatService = openAIChatService {
            locationMCPServer?.setOpenAIChatService(chatService)
            travelMCPServer?.setOpenAIChatService(chatService)
            searchMCPServer?.setOpenAIChatService(chatService)
            reviewsServer?.setOpenAIChatService(chatService)
            menuOfferingsServer?.setOpenAIChatService(chatService)
        }
        
        // Register servers with MCP client based on feature flags
        if featureFlags.shouldUseMCPForTool("get_user_location") {
            registerLocationMCPServer()
        }
        if featureFlags.shouldUseMCPForTool("get_weather") {
            registerTravelMCPServer()
        }
        if featureFlags.shouldUseMCPForTool("web_search") {
            registerSearchMCPServer()
        }
        if featureFlags.shouldUseMCPForTool("get_safety_info") {
            registerSafetyMCPServer()
        }
        if featureFlags.shouldUseMCPForTool("search_web") || featureFlags.shouldUseMCPForTool("search_candidates_for_facet") {
            registerWebSearchBridgeServer()
        }
        if featureFlags.shouldUseMCPForTool("reviews_list") || featureFlags.shouldUseMCPForTool("reviews_aspects_summarize") {
            registerReviewsServer()
        }
        if featureFlags.shouldUseMCPForTool("photos_list") || featureFlags.shouldUseMCPForTool("vibe_analyze") {
            registerPhotosVibeServer()
        }
        if featureFlags.shouldUseMCPForTool("web_links_discover") || featureFlags.shouldUseMCPForTool("web_readable_extract") || featureFlags.shouldUseMCPForTool("pdf_extract") {
            registerWebContentServer()
        }
        if featureFlags.shouldUseMCPForTool("menu_parse") || featureFlags.shouldUseMCPForTool("catalog_classify") {
            registerMenuOfferingsServer()
        }
    }
    
    func setLocationSearchService(_ service: LocationBasedSearchService) {
        self.locationSearchService = service
        legacyManager.setLocationSearchService(service)
        
        // Update LocationMCPServer if it exists
        locationMCPServer?.setLocationSearchService(service)
        searchMCPServer?.setLocationSearchService(service)
    }
    
    func setOpenAIChatService(_ service: OpenAIChatService) {
        self.openAIChatService = service
        legacyManager.setOpenAIChatService(service)
        
        // Update LocationMCPServer if it exists
        locationMCPServer?.setOpenAIChatService(service)
        travelMCPServer?.setOpenAIChatService(service)
        searchMCPServer?.setOpenAIChatService(service)
        reviewsServer?.setOpenAIChatService(service)
        menuOfferingsServer?.setOpenAIChatService(service)
        // Bridge server relies on search server for execution, ensure linkage stays up to date
        if let searchMCPServer {
            webSearchBridgeServer?.setSearchServer(searchMCPServer)
        }
    }
    
    func setGooglePlacesRoutesService(_ service: GooglePlacesRoutesService) {
        self.googlePlacesRoutesService = service
        // Update LocationMCPServer if it exists
        locationMCPServer?.setGooglePlacesRoutesService(service)
    }
    
    // MARK: - Accessors
    
    /// Expose GooglePlacesRoutesService for read-only access (used by discovery wiring).
    func getGooglePlacesRoutesService() -> GooglePlacesRoutesService? {
        return googlePlacesRoutesService
    }
    
    func setTravelServices(weather: WeatherService, currency: CurrencyService, translation: TranslationService, travelRequirements: TravelRequirementsService) {
        self.weatherService = weather
        self.currencyService = currency
        self.translationService = translation
        self.travelRequirementsService = travelRequirements
        travelMCPServer?.setWeatherService(weather)
        travelMCPServer?.setCurrencyService(currency)
        travelMCPServer?.setTranslationService(translation)
        travelMCPServer?.setTravelRequirementsService(travelRequirements)
    }
    
    static func getAllToolDefinitions() -> [RealtimeToolDefinition] {
        // For now, return the same definitions as the legacy system
        // In Phase 2, we'll convert these to MCP format
        return RealtimeToolManager.getAllToolDefinitions()
    }
    
    func executeTool(name: String, parameters: [String: Any]) async -> ToolResult {
        let startTime = Date()
        let shouldUseMCP = featureFlags.shouldUseMCPForTool(name)
        
        if featureFlags.debugLoggingEnabled {
            print("🔧 [MCPToolCoordinator] Executing '\(name)' via \(shouldUseMCP ? "MCP" : "Legacy")")
        }
        
        var result: ToolResult
        var usedMCP = false
        
        if shouldUseMCP && mcpClient.isConnected {
            // Try MCP first
            do {
                result = try await executeToolViaMCP(name: name, parameters: parameters)
                usedMCP = true
                
                if featureFlags.debugLoggingEnabled {
                    print("✅ [MCPToolCoordinator] MCP execution successful for '\(name)'")
                }
                
            } catch {
                print("❌ [MCPToolCoordinator] MCP execution failed for '\(name)': \(error)")
                
                // Check if we should fallback to legacy
                if featureFlags.shouldFallbackToLegacy(for: name, mcpError: error) {
                    print("🔄 [MCPToolCoordinator] Falling back to legacy for '\(name)'")
                    result = await executeToolViaLegacy(name: name, parameters: parameters)
                    usedMCP = false
                } else {
                    // MCP-only mode, return the error
                    result = ToolResult(success: false, data: error.localizedDescription)
                    usedMCP = true
                }
            }
        } else {
            // Use legacy system
            result = await executeToolViaLegacy(name: name, parameters: parameters)
            usedMCP = false
        }
        
        // Record performance metrics
        let duration = Date().timeIntervalSince(startTime)
        featureFlags.recordToolExecution(
            toolName: name,
            usedMCP: usedMCP,
            duration: duration,
            success: result.success,
            error: result.success ? nil : NSError(domain: "ToolExecution", code: -1, userInfo: [NSLocalizedDescriptionKey: result.data as? String ?? "Unknown error"])
        )
        
        // Update published properties
        lastToolUsed = name
        toolResults[name] = result.data
        
        return result
    }
    
    // MARK: - Private Execution Methods
    
    private func executeToolViaMCP(name: String, parameters: [String: Any]) async throws -> ToolResult {
        // For Phase 1, we're routing through the legacy system but via MCP interface
        // This will be replaced with actual MCP server calls in Phase 2
        
        guard mcpClient.hasToolAvailable(name) else {
            throw MCPClientError.toolNotFound(name)
        }
        
        let mcpResponse = try await mcpClient.callTool(name: name, arguments: parameters)
        
        // Convert MCP response to ToolResult
        if mcpResponse.isError == true {
            let errorMessage = mcpResponse.content.first?.text ?? "Unknown MCP error"
            return ToolResult(success: false, data: errorMessage)
        }
        
        // Extract result data from MCP content
        var resultData: [String: Any] = [:]
        
        for content in mcpResponse.content {
            if content.type == "text", let text = content.text {
                // Try to parse as JSON, fallback to plain text
                if let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    resultData.merge(json) { _, new in new }
                } else {
                    resultData["text"] = text
                }
            }
        }
        
        return ToolResult(success: true, data: resultData)
    }
    
    private func executeToolViaLegacy(name: String, parameters: [String: Any]) async -> ToolResult {
        // Direct call to legacy system
        return await legacyManager.executeTool(name: name, parameters: parameters)
    }
    
    // MARK: - MCP Setup
    
    private func registerLocationMCPServer() {
        guard let locationMCPServer = locationMCPServer else {
            print("❌ [MCPToolCoordinator] LocationMCPServer not initialized")
            return
        }
        
        // Register all location tools from the MCP server
        let locationTools = locationMCPServer.listTools()
        
        for tool in locationTools {
            mcpClient.registerTool(tool) { [weak self, weak locationMCPServer] request in
                guard let self = self,
                      let server = locationMCPServer else {
                    throw MCPClientError.internalError("Server or coordinator deallocated")
                }
                
                print("🗺️ [MCPToolCoordinator] Routing '\(request.name)' to LocationMCPServer")
                return await server.callTool(request)
            }
        }
        
        print("✅ [MCPToolCoordinator] Registered \(locationTools.count) location tools with MCP client")
    }
    
    private func registerTravelMCPServer() {
        guard let travelMCPServer = travelMCPServer else {
            print("❌ [MCPToolCoordinator] TravelMCPServer not initialized")
            return
        }
        let tools = travelMCPServer.listTools()
        for tool in tools {
            mcpClient.registerTool(tool) { [weak self, weak travelMCPServer] request in
                guard let _ = self, let server = travelMCPServer else {
                    throw MCPClientError.internalError("Server or coordinator deallocated")
                }
                print("🧳 [MCPToolCoordinator] Routing '\(request.name)' to TravelMCPServer")
                return await server.callTool(request)
            }
        }
        print("✅ [MCPToolCoordinator] Registered \(tools.count) travel tools with MCP client")
    }

    private func registerSearchMCPServer() {
        guard let searchMCPServer = searchMCPServer else {
            print("❌ [MCPToolCoordinator] SearchMCPServer not initialized")
            return
        }
        let tools = searchMCPServer.listTools()
        for tool in tools {
            mcpClient.registerTool(tool) { [weak self, weak searchMCPServer] request in
                guard let _ = self, let server = searchMCPServer else {
                    throw MCPClientError.internalError("Server or coordinator deallocated")
                }
                print("🔎 [MCPToolCoordinator] Routing '\(request.name)' to SearchMCPServer")
                return await server.callTool(request)
            }
        }
        print("✅ [MCPToolCoordinator] Registered \(tools.count) search tools with MCP client")
    }

    private func registerSafetyMCPServer() {
        guard let safetyMCPServer = safetyMCPServer else {
            print("❌ [MCPToolCoordinator] SafetyMCPServer not initialized")
            return
        }
        let tools = safetyMCPServer.listTools()
        for tool in tools {
            mcpClient.registerTool(tool) { [weak self, weak safetyMCPServer] request in
                guard let _ = self, let server = safetyMCPServer else {
                    throw MCPClientError.internalError("Server or coordinator deallocated")
                }
                print("🛡️ [MCPToolCoordinator] Routing '\(request.name)' to SafetyMCPServer")
                return await server.callTool(request)
            }
        }
        print("✅ [MCPToolCoordinator] Registered \(tools.count) safety tools with MCP client")
    }
    
    private func registerWebSearchBridgeServer() {
        guard let webSearchBridgeServer = webSearchBridgeServer else {
            print("❌ [MCPToolCoordinator] WebSearchBridgeServer not initialized")
            return
        }
        let tools = webSearchBridgeServer.listTools()
        for tool in tools {
            if mcpClient.hasToolAvailable(tool.name) { continue }
            mcpClient.registerTool(tool) { [weak self, weak webSearchBridgeServer] request in
                guard let _ = self, let server = webSearchBridgeServer else {
                    throw MCPClientError.internalError("Server or coordinator deallocated")
                }
                print("🌐 [MCPToolCoordinator] Routing '\(request.name)' to WebSearchBridgeServer")
                return await server.callTool(request)
            }
        }
        if !tools.isEmpty {
            print("✅ [MCPToolCoordinator] Registered \(tools.count) discovery search tools with MCP client")
        }
    }
    
    private func registerReviewsServer() {
        guard let reviewsServer = reviewsServer else {
            print("❌ [MCPToolCoordinator] ReviewsServer not initialized")
            return
        }
        let tools = reviewsServer.listTools()
        for tool in tools {
            if mcpClient.hasToolAvailable(tool.name) { continue }
            mcpClient.registerTool(tool) { [weak self, weak reviewsServer] request in
                guard let _ = self, let server = reviewsServer else {
                    throw MCPClientError.internalError("Server or coordinator deallocated")
                }
                print("📝 [MCPToolCoordinator] Routing '\(request.name)' to ReviewsServer")
                return await server.callTool(request)
            }
        }
        if !tools.isEmpty {
            print("✅ [MCPToolCoordinator] Registered \(tools.count) reviews tools with MCP client")
        }
    }
    
    private func registerPhotosVibeServer() {
        guard let photosVibeServer = photosVibeServer else {
            print("❌ [MCPToolCoordinator] PhotosVibeServer not initialized")
            return
        }
        let tools = photosVibeServer.listTools()
        for tool in tools {
            if mcpClient.hasToolAvailable(tool.name) { continue }
            mcpClient.registerTool(tool) { [weak self, weak photosVibeServer] request in
                guard let _ = self, let server = photosVibeServer else {
                    throw MCPClientError.internalError("Server or coordinator deallocated")
                }
                print("📸 [MCPToolCoordinator] Routing '\(request.name)' to PhotosVibeServer")
                return await server.callTool(request)
            }
        }
        if !tools.isEmpty {
            print("✅ [MCPToolCoordinator] Registered \(tools.count) vibe tools with MCP client")
        }
    }
    
    private func registerWebContentServer() {
        guard let webContentServer = webContentServer else {
            print("❌ [MCPToolCoordinator] WebContentServer not initialized")
            return
        }
        let tools = webContentServer.listTools()
        for tool in tools {
            if mcpClient.hasToolAvailable(tool.name) { continue }
            mcpClient.registerTool(tool) { [weak self, weak webContentServer] request in
                guard let _ = self, let server = webContentServer else {
                    throw MCPClientError.internalError("Server or coordinator deallocated")
                }
                print("🕸️ [MCPToolCoordinator] Routing '\(request.name)' to WebContentServer")
                return await server.callTool(request)
            }
        }
        if !tools.isEmpty {
            print("✅ [MCPToolCoordinator] Registered \(tools.count) web content tools with MCP client")
        }
    }
    
    private func registerMenuOfferingsServer() {
        guard let menuOfferingsServer = menuOfferingsServer else {
            print("❌ [MCPToolCoordinator] MenuOfferingsServer not initialized")
            return
        }
        let tools = menuOfferingsServer.listTools()
        for tool in tools {
            if mcpClient.hasToolAvailable(tool.name) { continue }
            mcpClient.registerTool(tool) { [weak self, weak menuOfferingsServer] request in
                guard let _ = self, let server = menuOfferingsServer else {
                    throw MCPClientError.internalError("Server or coordinator deallocated")
                }
                print("🍽️ [MCPToolCoordinator] Routing '\(request.name)' to MenuOfferingsServer")
                return await server.callTool(request)
            }
        }
        if !tools.isEmpty {
            print("✅ [MCPToolCoordinator] Registered \(tools.count) menu/catalog tools with MCP client")
        }
    }
    
    private func setupMCPClient() {
        // Set up MCP client delegate
        mcpClient.delegate = self
        
        // Connect to in-process MCP servers
        Task {
            do {
                try await mcpClient.connect()
                await registerLegacyToolsWithMCP()
            } catch {
                print("❌ [MCPToolCoordinator] Failed to connect MCP client: \(error)")
            }
        }
    }
    
    private func registerLegacyToolsWithMCP() async {
        // For Phase 1, register all legacy tools with the MCP client
        // This creates the MCP wrapper layer
        
        let toolDefinitions = RealtimeToolManager.getAllToolDefinitions()
        
        for toolDef in toolDefinitions {
            let mcpTool = convertToMCPTool(toolDef)
            
            mcpClient.registerTool(mcpTool) { [weak self] request in
                guard let self = self else {
                    throw MCPClientError.internalError("Tool coordinator deallocated")
                }
                
                return await self.handleMCPToolCall(request)
            }
        }
        
        print("✅ [MCPToolCoordinator] Registered \(toolDefinitions.count) tools with MCP client")
    }
    
    private func convertToMCPTool(_ toolDef: RealtimeToolDefinition) -> MCPTool {
        // Convert RealtimeToolDefinition to MCPTool
        var properties: [String: MCPPropertySchema] = [:]
        
        for (key, param) in toolDef.parameters.properties {
            properties[key] = MCPPropertySchema(
                type: param.type,
                description: param.description,
                enumValues: param.enum
            )
        }
        
        let inputSchema = MCPToolInputSchema(
            properties: properties,
            required: toolDef.parameters.required
        )
        
        return MCPTool(
            name: toolDef.name,
            description: toolDef.description,
            inputSchema: inputSchema
        )
    }
    
    private func handleMCPToolCall(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        // Execute the tool via legacy system and convert response
        let legacyResult = await legacyManager.executeTool(
            name: request.name,
            parameters: request.arguments ?? [:]
        )
        
        if legacyResult.success {
            // Convert successful result to MCP content
            let resultText: String
            if let dict = legacyResult.data as? [String: Any] {
                // Sanitize and encode dictionary
                let sanitized = JSONSanitizer.sanitizeDictionary(dict)
                if let data = try? JSONSerialization.data(withJSONObject: sanitized),
                   let text = String(data: data, encoding: .utf8) {
                    resultText = text
                } else {
                    resultText = "{}"
                }
            } else if let array = legacyResult.data as? [Any] {
                // Encode array
                if let data = try? JSONSerialization.data(withJSONObject: array),
                   let text = String(data: data, encoding: .utf8) {
                    resultText = text
                } else {
                    resultText = "[]"
                }
            } else if let str = legacyResult.data as? String {
                // Plain text result
                resultText = str
            } else if let num = legacyResult.data as? NSNumber {
                resultText = num.stringValue
            } else if legacyResult.data is NSNull {
                resultText = "null"
            } else {
                // Fallback stringification for unsupported types
                resultText = String(describing: legacyResult.data)
            }

            return MCPCallToolResponse(
                content: [MCPContent(text: resultText)],
                isError: false
            )
        } else {
            // Convert error to MCP content
            let errorText = legacyResult.data as? String ?? "Unknown error"
            return MCPCallToolResponse(
                content: [MCPContent(text: errorText)],
                isError: true
            )
        }
    }
}

// MARK: - MCP Client Delegate

extension MCPToolCoordinator: MCPClientDelegate {
    
    nonisolated public func mcpClient(_ client: MCPClient, didReceiveNotification method: String, params: [String: Any]?) {
        Task { @MainActor in
            if featureFlags.debugLoggingEnabled {
                print("🔔 [MCPToolCoordinator] Received MCP notification: \(method)")
            }
        }
    }
    
    nonisolated public func mcpClient(_ client: MCPClient, didEncounterError error: Error) {
        print("❌ [MCPToolCoordinator] MCP client error: \(error)")
        
        // Check if this should trigger an emergency rollback
        if case MCPClientError.connectionFailed = error {
            Task { @MainActor in
                featureFlags.emergencyRollbackToLegacy(reason: "MCP client connection failed: \(error.localizedDescription)")
            }
        }
    }
    
    nonisolated public func mcpClient(_ client: MCPClient, didChangeConnectionState state: MCPConnectionState) {
        switch state {
        case .ready:
            print("✅ [MCPToolCoordinator] MCP client ready")
            
        case .error(let error):
            print("❌ [MCPToolCoordinator] MCP client error state: \(error)")
            
        case .disconnected:
            print("🔌 [MCPToolCoordinator] MCP client disconnected")
            
        default:
            Task { @MainActor in
                if featureFlags.debugLoggingEnabled {
                    print("🔧 [MCPToolCoordinator] MCP client state: \(state)")
                }
            }
        }
    }
}

// MARK: - Debug and Monitoring

extension MCPToolCoordinator {
    
    /// Print debug information about current state
    public func printDebugInfo() {
        print("🔧 [MCPToolCoordinator] Debug Info:")
        print("  Migration State: \(featureFlags.migrationState.displayName)")
        print("  Enabled MCP Categories: \(featureFlags.enabledMCPCategories.map { $0.displayName }.joined(separator: ", "))")
        print("  MCP Client Connected: \(mcpClient.isConnected)")
        print("  Available Tools: \(RealtimeToolManager.getAllToolDefinitions().count)")
        
        let metrics = featureFlags.performanceMetrics
        print("  Performance Metrics:")
        print("    MCP Executions: \(metrics.mcpExecutions.count)")
        print("    Legacy Executions: \(metrics.legacyExecutions.count)")
        print("    MCP Avg Latency: \(String(format: "%.3f", metrics.mcpAverageLatency))s")
        print("    Legacy Avg Latency: \(String(format: "%.3f", metrics.legacyAverageLatency))s")
        print("    MCP Success Rate: \(String(format: "%.1f", metrics.mcpSuccessRate * 100))%")
        print("    Legacy Success Rate: \(String(format: "%.1f", metrics.legacySuccessRate * 100))%")
        
        mcpClient.printDebugInfo()
    }
    
    /// Get current performance comparison
    public func getPerformanceComparison() -> [String: Any] {
        let metrics = featureFlags.performanceMetrics
        
        return [
            "migration_state": featureFlags.migrationState.rawValue,
            "mcp_enabled_categories": featureFlags.enabledMCPCategories.map { $0.rawValue },
            "mcp_connected": mcpClient.isConnected,
            "mcp_executions": metrics.mcpExecutions.count,
            "legacy_executions": metrics.legacyExecutions.count,
            "mcp_avg_latency": metrics.mcpAverageLatency,
            "legacy_avg_latency": metrics.legacyAverageLatency,
            "mcp_success_rate": metrics.mcpSuccessRate,
            "legacy_success_rate": metrics.legacySuccessRate,
            "performance_monitoring_enabled": featureFlags.isPerformanceMonitoringEnabled
        ]
    }
}