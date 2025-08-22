//
//  MCPProtocol.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  Model Context Protocol implementation for Swift/iOS
//

import Foundation

// MARK: - MCP Protocol Version

public enum MCPVersion: String, Codable {
    case v1_0 = "2024-11-05"
    
    static let current: MCPVersion = .v1_0
}

// MARK: - JSON-RPC 2.0 Base Types

public struct JSONRPCRequest: Codable {
    let jsonrpc: String = "2.0"
    let id: String
    let method: String
    let params: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }
    
    public init(id: String = UUID().uuidString, method: String, params: [String: Any]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        
        if container.contains(.params) {
            let paramsData = try container.decode(Data.self, forKey: .params)
            params = try JSONSerialization.jsonObject(with: paramsData) as? [String: Any]
        } else {
            params = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        
        if let params = params {
            // Sanitize params to ensure all values are JSON-serializable
            let sanitizedParams = sanitizeParamsForJSON(params)
            let paramsData = try JSONSerialization.data(withJSONObject: sanitizedParams)
            try container.encode(paramsData, forKey: .params)
        }
    }
    
    private func sanitizeParamsForJSON(_ params: [String: Any]) -> [String: Any] {
        return JSONSanitizer.sanitizeDictionary(params)
    }
}

public struct JSONRPCResponse<T: Codable>: Codable {
    let jsonrpc: String
    let id: String
    let result: T?
    let error: JSONRPCError?
    
    public init(id: String, result: T) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }
    
    public init(id: String, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

public struct JSONRPCError: Codable, Error {
    let code: Int
    let message: String
    let data: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case code, message, data
    }
    
    public init(code: Int, message: String, data: [String: Any]? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        
        if container.contains(.data) {
            let dataRaw = try container.decode(Data.self, forKey: .data)
            data = try JSONSerialization.jsonObject(with: dataRaw) as? [String: Any]
        } else {
            data = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        
        if let data = data {
            let dataRaw = try JSONSerialization.data(withJSONObject: data)
            try container.encode(dataRaw, forKey: .data)
        }
    }
}

// MARK: - MCP Core Types

public struct MCPCapabilities: Codable {
    let tools: MCPToolsCapability?
    let resources: MCPResourcesCapability?
    let prompts: MCPPromptsCapability?
    let sampling: MCPSamplingCapability?
    
    public init(
        tools: MCPToolsCapability? = nil,
        resources: MCPResourcesCapability? = nil,
        prompts: MCPPromptsCapability? = nil,
        sampling: MCPSamplingCapability? = nil
    ) {
        self.tools = tools
        self.resources = resources
        self.prompts = prompts
        self.sampling = sampling
    }
}

public struct MCPToolsCapability: Codable {
    let listChanged: Bool?
    
    public init(listChanged: Bool? = true) {
        self.listChanged = listChanged
    }
}

public struct MCPResourcesCapability: Codable {
    let subscribe: Bool?
    let listChanged: Bool?
    
    public init(subscribe: Bool? = false, listChanged: Bool? = true) {
        self.subscribe = subscribe
        self.listChanged = listChanged
    }
}

public struct MCPPromptsCapability: Codable {
    let listChanged: Bool?
    
    public init(listChanged: Bool? = true) {
        self.listChanged = listChanged
    }
}

public struct MCPSamplingCapability: Codable {
    // Empty for now, may be extended in future MCP versions
}

// MARK: - MCP Tool Definitions

public struct MCPTool: Codable {
    let name: String
    let description: String
    let inputSchema: MCPToolInputSchema
    
    public init(name: String, description: String, inputSchema: MCPToolInputSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPToolInputSchema: Codable {
    let type: String
    let properties: [String: MCPPropertySchema]
    let required: [String]?
    let additionalProperties: Bool?
    
    public init(properties: [String: MCPPropertySchema], required: [String]? = nil, additionalProperties: Bool? = false) {
        self.type = "object"
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }
}

public struct MCPPropertySchema: Codable {
    let type: String
    let description: String?
    let `enum`: [String]?
    let format: String?
    
    public init(type: String, description: String? = nil, enumValues: [String]? = nil, format: String? = nil) {
        self.type = type
        self.description = description
        self.`enum` = enumValues
        self.format = format
    }
}

// MARK: - MCP Messages

public struct MCPInitializeRequest: Codable {
    let protocolVersion: String
    let capabilities: MCPCapabilities
    let clientInfo: MCPClientInfo
    
    public init(capabilities: MCPCapabilities, clientInfo: MCPClientInfo) {
        self.protocolVersion = MCPVersion.current.rawValue
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }
}

public struct MCPClientInfo: Codable {
    let name: String
    let version: String
    
    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct MCPInitializeResponse: Codable {
    let protocolVersion: String
    let capabilities: MCPCapabilities
    let serverInfo: MCPServerInfo
    
    public init(capabilities: MCPCapabilities, serverInfo: MCPServerInfo) {
        self.protocolVersion = MCPVersion.current.rawValue
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
}

public struct MCPServerInfo: Codable {
    let name: String
    let version: String
    
    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct MCPListToolsRequest: Codable {
    // Empty - no parameters needed for listing tools
}

public struct MCPListToolsResponse: Codable {
    let tools: [MCPTool]
    
    public init(tools: [MCPTool]) {
        self.tools = tools
    }
}

public struct MCPCallToolRequest: Codable {
    let name: String
    let arguments: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case name, arguments
    }
    
    public init(name: String, arguments: [String: Any]? = nil) {
        self.name = name
        self.arguments = arguments
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        
        if container.contains(.arguments) {
            let argsData = try container.decode(Data.self, forKey: .arguments)
            arguments = try JSONSerialization.jsonObject(with: argsData) as? [String: Any]
        } else {
            arguments = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        
        if let arguments = arguments {
            // Sanitize arguments to ensure all values are JSON-serializable
            let sanitizedArguments = sanitizeArgumentsForJSON(arguments)
            let argsData = try JSONSerialization.data(withJSONObject: sanitizedArguments)
            try container.encode(argsData, forKey: .arguments)
        }
    }
    
    private func sanitizeArgumentsForJSON(_ arguments: [String: Any]) -> [String: Any] {
        return JSONSanitizer.sanitizeDictionary(arguments)
    }
}

public struct MCPCallToolResponse: Codable {
    let content: [MCPContent]
    let isError: Bool?
    
    public init(content: [MCPContent], isError: Bool? = false) {
        self.content = content
        self.isError = isError
    }
}

public struct MCPContent: Codable {
    let type: String
    let text: String?
    let data: String?
    let mimeType: String?
    
    public init(text: String) {
        self.type = "text"
        self.text = text
        self.data = nil
        self.mimeType = nil
    }
    
    public init(data: String, mimeType: String) {
        self.type = "data"
        self.text = nil
        self.data = data
        self.mimeType = mimeType
    }
}

// MARK: - MCP Method Names

public enum MCPMethod: String {
    case initialize = "initialize"
    case initialized = "initialized"
    case ping = "ping"
    case listTools = "tools/list"
    case callTool = "tools/call"
    case listResources = "resources/list"
    case readResource = "resources/read"
    case listPrompts = "prompts/list"
    case getPrompt = "prompts/get"
    case createMessage = "sampling/createMessage"
}

// MARK: - Error Codes

public enum MCPErrorCode: Int {
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603
    case serverError = -32000
    case methodNotAllowed = -32001
    case invalidToolName = -32002
}

// MARK: - JSON Sanitization Utility

private struct JSONSanitizer {
    static func sanitizeDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        var sanitized: [String: Any] = [:]
        
        for (key, value) in dictionary {
            sanitized[key] = sanitizeValue(value)
        }
        
        return sanitized
    }
    
    static func sanitizeValue(_ value: Any) -> Any {
        switch value {
        case let stringValue as String:
            return stringValue
        case let numberValue as NSNumber:
            return numberValue
        case let boolValue as Bool:
            return boolValue
        case let arrayValue as [Any]:
            return arrayValue.map { sanitizeValue($0) }
        case let dictValue as [String: Any]:
            return sanitizeDictionary(dictValue)
        case is NSNull:
            return NSNull()
        default:
            // Convert any other type to string representation
            // This handles enum cases like "any" that aren't properly quoted
            return String(describing: value)
        }
    }
}

// MARK: - Protocol Extensions

extension JSONRPCError {
    public static func parseError(_ message: String = "Parse error") -> JSONRPCError {
        return JSONRPCError(code: MCPErrorCode.parseError.rawValue, message: message)
    }
    
    public static func invalidRequest(_ message: String = "Invalid request") -> JSONRPCError {
        return JSONRPCError(code: MCPErrorCode.invalidRequest.rawValue, message: message)
    }
    
    public static func methodNotFound(_ message: String = "Method not found") -> JSONRPCError {
        return JSONRPCError(code: MCPErrorCode.methodNotFound.rawValue, message: message)
    }
    
    public static func invalidParams(_ message: String = "Invalid params") -> JSONRPCError {
        return JSONRPCError(code: MCPErrorCode.invalidParams.rawValue, message: message)
    }
    
    public static func internalError(_ message: String = "Internal error") -> JSONRPCError {
        return JSONRPCError(code: MCPErrorCode.internalError.rawValue, message: message)
    }
    
    public static func invalidToolName(_ toolName: String) -> JSONRPCError {
        return JSONRPCError(code: MCPErrorCode.invalidToolName.rawValue, message: "Tool '\(toolName)' not found")
    }
}