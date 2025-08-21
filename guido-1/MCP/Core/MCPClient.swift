//
//  MCPClient.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  MCP Client implementation for connecting to MCP servers
//

import Foundation

// MARK: - MCP Client Protocol

public protocol MCPClientDelegate: AnyObject {
    func mcpClient(_ client: MCPClient, didReceiveNotification method: String, params: [String: Any]?)
    func mcpClient(_ client: MCPClient, didEncounterError error: Error)
    func mcpClient(_ client: MCPClient, didChangeConnectionState state: MCPConnectionState)
}

public enum MCPConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case initializing
    case ready
    case error(String)
    
    public static func == (lhs: MCPConnectionState, rhs: MCPConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.initializing, .initializing),
             (.ready, .ready):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - MCP Client Implementation

public class MCPClient {
    
    // MARK: - Properties
    
    public weak var delegate: MCPClientDelegate?
    
    private var connectionState: MCPConnectionState = .disconnected {
        didSet {
            delegate?.mcpClient(self, didChangeConnectionState: connectionState)
        }
    }
    
    private var capabilities: MCPCapabilities?
    private var serverInfo: MCPServerInfo?
    private var availableTools: [MCPTool] = []
    
    private let clientInfo: MCPClientInfo
    private let requestedCapabilities: MCPCapabilities
    
    // For in-process communication (Phase 1 - wrapping existing tools)
    private var toolHandlers: [String: (MCPCallToolRequest) async throws -> MCPCallToolResponse] = [:]
    
    // MARK: - Initialization
    
    public init(
        clientName: String = "Guido",
        clientVersion: String = "1.0.0",
        capabilities: MCPCapabilities = MCPCapabilities(tools: MCPToolsCapability())
    ) {
        self.clientInfo = MCPClientInfo(name: clientName, version: clientVersion)
        self.requestedCapabilities = capabilities
    }
    
    // MARK: - Connection Management
    
    public func connect() async throws {
        connectionState = .connecting
        
        // For Phase 1, we're simulating a connection to an in-process MCP server
        // This will be replaced with actual networking in later phases
        try await initializeInProcessConnection()
    }
    
    public func disconnect() async {
        connectionState = .disconnected
        availableTools.removeAll()
        toolHandlers.removeAll()
    }
    
    // MARK: - Tool Operations
    
    public func listTools() async throws -> [MCPTool] {
        guard connectionState == .ready else {
            throw MCPClientError.notConnected
        }
        
        return availableTools
    }
    
    public func callTool(name: String, arguments: [String: Any]? = nil) async throws -> MCPCallToolResponse {
        guard connectionState == .ready else {
            throw MCPClientError.notConnected
        }
        
        guard let handler = toolHandlers[name] else {
            throw MCPClientError.toolNotFound(name)
        }
        
        let request = MCPCallToolRequest(name: name, arguments: arguments)
        
        do {
            let response = try await handler(request)
            print("🔧 [MCP] Tool '\(name)' executed successfully")
            return response
        } catch {
            print("❌ [MCP] Tool '\(name)' execution failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Tool Registration (Phase 1 - In-Process)
    
    public func registerTool(
        _ tool: MCPTool,
        handler: @escaping (MCPCallToolRequest) async throws -> MCPCallToolResponse
    ) {
        toolHandlers[tool.name] = handler
        
        // Add to available tools if not already present
        if !availableTools.contains(where: { $0.name == tool.name }) {
            availableTools.append(tool)
        }
        
        print("🔧 [MCP] Registered tool: \(tool.name)")
    }
    
    public func unregisterTool(_ toolName: String) {
        toolHandlers.removeValue(forKey: toolName)
        availableTools.removeAll { $0.name == toolName }
        print("🔧 [MCP] Unregistered tool: \(toolName)")
    }
    
    // MARK: - Private Methods
    
    private func initializeInProcessConnection() async throws {
        connectionState = .initializing
        
        // Simulate MCP initialization handshake
        let serverInfo = MCPServerInfo(name: "Guido In-Process MCP Server", version: "1.0.0")
        let serverCapabilities = MCPCapabilities(
            tools: MCPToolsCapability(listChanged: true),
            resources: nil,
            prompts: nil,
            sampling: nil
        )
        
        self.serverInfo = serverInfo
        self.capabilities = serverCapabilities
        
        connectionState = .ready
        print("✅ [MCP] Connected to in-process MCP server")
    }
}

// MARK: - Error Types

public enum MCPClientError: Error, LocalizedError {
    case notConnected
    case connectionFailed(Error)
    case initializationFailed(Error)
    case toolNotFound(String)
    case invalidResponse
    case protocolError(String)
    case internalError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "MCP client is not connected"
        case .connectionFailed(let error):
            return "MCP connection failed: \(error.localizedDescription)"
        case .initializationFailed(let error):
            return "MCP initialization failed: \(error.localizedDescription)"
        case .toolNotFound(let name):
            return "MCP tool '\(name)' not found"
        case .invalidResponse:
            return "Invalid MCP response received"
        case .protocolError(let message):
            return "MCP protocol error: \(message)"
        case .internalError(let message):
            return "MCP internal error: \(message)"
        }
    }
}

// MARK: - Convenience Extensions

extension MCPClient {
    
    /// Get current connection state
    public var isConnected: Bool {
        switch connectionState {
        case .ready:
            return true
        default:
            return false
        }
    }
    
    /// Get server information (available after successful connection)
    public var connectedServerInfo: MCPServerInfo? {
        return serverInfo
    }
    
    /// Get server capabilities (available after successful connection)
    public var serverCapabilities: MCPCapabilities? {
        return capabilities
    }
    
    /// Check if a specific tool is available
    public func hasToolAvailable(_ toolName: String) -> Bool {
        return availableTools.contains { $0.name == toolName }
    }
    
    /// Get information about a specific tool
    public func getToolInfo(_ toolName: String) -> MCPTool? {
        return availableTools.first { $0.name == toolName }
    }
}

// MARK: - Debug Extensions

extension MCPClient {
    
    /// Print debug information about the client state
    public func printDebugInfo() {
        print("🔧 [MCP] Client Debug Info:")
        print("  Connection State: \(connectionState)")
        print("  Server Info: \(serverInfo?.name ?? "Unknown") v\(serverInfo?.version ?? "Unknown")")
        print("  Available Tools: \(availableTools.count)")
        
        for tool in availableTools {
            print("    - \(tool.name): \(tool.description)")
        }
        
        if let capabilities = capabilities {
            print("  Server Capabilities:")
            print("    Tools: \(capabilities.tools != nil ? "✅" : "❌")")
            print("    Resources: \(capabilities.resources != nil ? "✅" : "❌")")
            print("    Prompts: \(capabilities.prompts != nil ? "✅" : "❌")")
            print("    Sampling: \(capabilities.sampling != nil ? "✅" : "❌")")
        }
    }
}