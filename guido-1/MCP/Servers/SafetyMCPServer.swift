import Foundation

public class SafetyMCPServer {
    private weak var locationManager: LocationManager?
    private let serverInfo = MCPServerInfo(name: "Guido Safety Server", version: "1.0.0")
    
    init(locationManager: LocationManager? = nil) {
        self.locationManager = locationManager
    }
    
    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
    }
    
    public func getCapabilities() -> MCPCapabilities {
        return MCPCapabilities(tools: MCPToolsCapability(listChanged: true), resources: nil, prompts: nil, sampling: nil)
    }
    
    public func getServerInfo() -> MCPServerInfo { serverInfo }
    
    public func listTools() -> [MCPTool] {
        return [
            getSafetyInfoTool(),
            getEmergencyInfoTool()
        ]
    }
    
    public func callTool(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        print("🛡️ [SafetyMCPServer] Executing tool: \(request.name)")
        switch request.name {
        case "get_safety_info":
            return await executeSafetyInfo(request)
        case "get_emergency_info":
            return await executeEmergencyInfo(request)
        default:
            return MCPCallToolResponse(content: [MCPContent(text: "Tool '\(request.name)' not found")], isError: true)
        }
    }
    
    private func getSafetyInfoTool() -> MCPTool {
        return MCPTool(
            name: "get_safety_info",
            description: "Get safety information for a location",
            inputSchema: MCPToolInputSchema(properties: [
                "info_type": MCPPropertySchema(type: "string", description: "Type of safety info", enumValues: ["general","travel_advisory","health","crime","weather_alerts","emergency_contacts"]),
                "location": MCPPropertySchema(type: "string", description: "Target location (optional)")
            ], required: ["info_type"]) 
        )
    }
    
    private func getEmergencyInfoTool() -> MCPTool {
        return MCPTool(
            name: "get_emergency_info",
            description: "Get emergency contact numbers and locations",
            inputSchema: MCPToolInputSchema(properties: [
                "emergency_type": MCPPropertySchema(type: "string", description: "Type", enumValues: ["medical","police","fire","embassy","general","all"]),
                "location": MCPPropertySchema(type: "string", description: "Target location (optional)")
            ], required: ["emergency_type"]) 
        )
    }
    
    // Implementations compatible with legacy behavior
    private func executeSafetyInfo(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        let infoType = (request.arguments?["info_type"] as? String) ?? "general"
        if let provided = request.arguments?["location"] as? String, !provided.isEmpty {
            let text = "Safety information for \(provided) (\(infoType)): Generally safe area, normal precautions recommended. Emergency number: 911"
            return MCPCallToolResponse(content: [MCPContent(text: text)], isError: false)
        }
        let currentCity = await MainActor.run { locationManager?.currentCity }
        let city = currentCity ?? "current location"
        let text = "Safety information for \(city) (\(infoType)): Generally safe area, normal precautions recommended. Emergency number: 911"
        return MCPCallToolResponse(content: [MCPContent(text: text)], isError: false)
    }
    
    private func executeEmergencyInfo(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        let emergencyType = (request.arguments?["emergency_type"] as? String) ?? "general"
        if let provided = request.arguments?["location"] as? String, !provided.isEmpty {
            let text = "Emergency info for \(provided) (\(emergencyType)): Police 911, Fire 911, Nearest hospital details available on request."
            return MCPCallToolResponse(content: [MCPContent(text: text)], isError: false)
        }
        let currentCity = await MainActor.run { locationManager?.currentCity }
        let city = currentCity ?? "current location"
        let text = "Emergency info for \(city) (\(emergencyType)): Police 911, Fire 911, Nearest hospital details available on request."
        return MCPCallToolResponse(content: [MCPContent(text: text)], isError: false)
    }
}

