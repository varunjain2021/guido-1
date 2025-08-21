//
//  MCPPhase1Tests.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  Basic tests for Phase 1 MCP implementation
//

import Foundation

// MARK: - MCP Phase 1 Test Suite

@MainActor
public class MCPPhase1Tests {
    
    private let mcpClient: MCPClient
    private let locationServer: LocationMCPServer
    private let featureFlags: FeatureFlags
    
    public init() {
        self.mcpClient = MCPClient()
        self.locationServer = LocationMCPServer()
        self.featureFlags = FeatureFlags.shared
    }
    
    // MARK: - Simple Test
    
    public func testBasicFunctionality() async {
        print("🧪 [MCPPhase1Tests] Testing basic MCP functionality...")
        
        // Test MCP client connection
        do {
            try await mcpClient.connect()
            print("✅ MCP client connected successfully")
        } catch {
            print("❌ MCP client connection failed: \(error)")
        }
        
        // Test tool listing
        let tools = locationServer.listTools()
        print("✅ Found \(tools.count) location tools")
        
        print("✅ [MCPPhase1Tests] Basic tests completed")
    }
    
    // MARK: - Integration Test
    
    public func testMCPToolCoordinatorIntegration() async {
        print("🧪 Testing MCPToolCoordinator integration...")
        
        let coordinator = MCPToolCoordinator()
        
        // Test tool execution through coordinator
        let result = await coordinator.executeTool(name: "get_user_location", parameters: [:])
        
        if result.success {
            print("✅ MCPToolCoordinator executed location tool successfully")
        } else {
            print("⚠️ MCPToolCoordinator execution result: \(result.success)")
        }
        
        // Print debug info
        coordinator.printDebugInfo()
    }
    
    // MARK: - Cleanup
    
    public func cleanup() async {
        await mcpClient.disconnect()
        print("🧹 [MCPPhase1Tests] Cleanup completed")
    }
}

// MARK: - Test Runner

@MainActor
public class MCPTestRunner {
    
    public static func runPhase1Tests() async {
        let tests = MCPPhase1Tests()
        
        await tests.testBasicFunctionality()
        await tests.testMCPToolCoordinatorIntegration()
        await tests.cleanup()
    }
}