//
//  SessionLogger.swift
//  guido-1
//
//  Created by CursorAI on 11/28/25.
//

import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

/// JSON representation that can round-trip arbitrary tool payloads.
enum SessionJSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([SessionJSONValue])
    case object([String: SessionJSONValue])
    case null
    
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let arrayValue = try? container.decode([SessionJSONValue].self) {
            self = .array(arrayValue)
        } else if let dictionaryValue = try? container.decode([String: SessionJSONValue].self) {
            self = .object(dictionaryValue)
        } else {
            throw DecodingError.typeMismatch(SessionJSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    static func fromEncodable<T: Encodable>(_ value: T) -> SessionJSONValue {
        if let string = value as? String { return .string(string) }
        if let bool = value as? Bool { return .bool(bool) }
        if let int = value as? Int { return .int(int) }
        if let double = value as? Double { return .double(double) }
        if let value = value as? SessionJSONValue { return value }
        if let data = try? JSONEncoder().encode(value),
           let jsonObject = try? JSONSerialization.jsonObject(with: data) {
            return SessionJSONValue.make(from: jsonObject) ?? .null
        }
        return .null
    }

    static func fromAny(_ value: Any) -> SessionJSONValue {
        return SessionJSONValue.make(from: value) ?? .string(String(describing: value))
    }

    private static func make(from value: Any) -> SessionJSONValue? {
        switch value {
        case let dict as [String: Any]:
            var mapped: [String: SessionJSONValue] = [:]
            for (key, entry) in dict {
                mapped[key] = make(from: entry) ?? .string(String(describing: entry))
            }
            return .object(mapped)
        case let array as [Any]:
            return .array(array.map { make(from: $0) ?? .string(String(describing: $0)) })
        case let string as String:
            return .string(string)
        case _ as NSNull:
            return .null
        case let date as Date:
            return .string(iso8601Formatter.string(from: date))
        case let url as URL:
            return .string(url.absoluteString)
        case let data as Data:
            return .string(data.base64EncodedString())
        case let value as SessionJSONValue:
            return value
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            } else if number.doubleValue == floor(number.doubleValue) {
                return .int(number.intValue)
            } else {
                return .double(number.doubleValue)
            }
        default:
            return nil
        }
    }
}

struct SessionMetadata: Codable, Equatable {
    var deviceModel: String?
    var osVersion: String?
    var appVersion: String?
    var buildNumber: String?
    var locale: String?
    var timezone: String?
    var platform: String?
    var connectionType: String?
    var experimentIds: [String]?
    var additionalInfo: [String: String]?

    static func makeDefault() -> SessionMetadata {
        SessionMetadata(
            deviceModel: SessionMetadata.deviceModel(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            platform: "iOS",
            connectionType: nil,
            experimentIds: nil,
            additionalInfo: nil
        )
    }

    private static func deviceModel() -> String? {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(String(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? nil : identifier
        #else
        return nil
        #endif
    }
}

struct SessionLocationSnapshot: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let source: String?
    let timestamp: Date

    #if canImport(CoreLocation)
    init(location: CLLocation, source: String? = nil) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.accuracyMeters = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        self.source = source
        self.timestamp = location.timestamp
    }
    #endif

    init(latitude: Double, longitude: Double, accuracyMeters: Double? = nil, source: String? = nil, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.source = source
        self.timestamp = timestamp
    }
}

struct SessionRecording: Identifiable, Codable {
    let id: UUID
    var sessionId: String
    var userId: String?
    var userEmail: String?
    var startedAt: Date
    var endedAt: Date?
    var events: [SessionEvent]
    var metadata: SessionMetadata
    var lastKnownLocation: SessionLocationSnapshot?
    var errorSummary: String?

    init(
        sessionId: String = UUID().uuidString,
        userId: String? = nil,
        userEmail: String? = nil,
        startedAt: Date = Date(),
        metadata: SessionMetadata = SessionMetadata.makeDefault()
    ) {
        self.id = UUID()
        self.sessionId = sessionId
        self.userId = userId
        self.userEmail = userEmail
        self.startedAt = startedAt
        self.events = []
        self.metadata = metadata
        self.lastKnownLocation = nil
    }
}

struct SessionEvent: Identifiable, Codable {
    enum EventType: String, Codable {
        case userMessage
        case assistantMessage
        case toolCall
        case toolResult
        case reasoning
        case location
        case lifecycle
        case speechEvent      // VAD speech started/stopped
        case responseEvent    // AI response created/done/cancelled
        case interruptEvent   // User interrupted AI
        case systemEvent      // General system events
    }

    let id: UUID
    let type: EventType
    let timestamp: Date
    let message: SessionMessagePayload?
    let toolCall: SessionToolCallPayload?
    let toolResult: SessionToolResultPayload?
    let reasoning: SessionReasoningPayload?
    let location: SessionLocationSnapshot?
    let lifecycle: SessionLifecyclePayload?
    let speech: SessionSpeechPayload?
    let response: SessionResponsePayload?
    let interrupt: SessionInterruptPayload?
    let system: SessionSystemPayload?
    let metadata: [String: String]?

    init(
        type: EventType,
        timestamp: Date = Date(),
        message: SessionMessagePayload? = nil,
        toolCall: SessionToolCallPayload? = nil,
        toolResult: SessionToolResultPayload? = nil,
        reasoning: SessionReasoningPayload? = nil,
        location: SessionLocationSnapshot? = nil,
        lifecycle: SessionLifecyclePayload? = nil,
        speech: SessionSpeechPayload? = nil,
        response: SessionResponsePayload? = nil,
        interrupt: SessionInterruptPayload? = nil,
        system: SessionSystemPayload? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.message = message
        self.toolCall = toolCall
        self.toolResult = toolResult
        self.reasoning = reasoning
        self.location = location
        self.lifecycle = lifecycle
        self.speech = speech
        self.response = response
        self.interrupt = interrupt
        self.system = system
        self.metadata = metadata
    }
}

struct SessionMessagePayload: Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
        case system
        case tool
    }

    let role: Role
    let content: String
    let model: String?
    let latencyMs: Double?
    let languageCode: String?
}

struct SessionToolCallPayload: Codable, Equatable {
    let name: String
    let invocationId: String?
    let parameters: SessionJSONValue?
    let locationContext: SessionLocationSnapshot?
    let latencyMs: Double?
}

struct SessionToolResultPayload: Codable, Equatable {
    let name: String
    let invocationId: String?
    let success: Bool
    let output: SessionJSONValue?
    let errorDescription: String?
    let latencyMs: Double?
}

struct SessionReasoningPayload: Codable, Equatable {
    let content: String
    let model: String?
    let tokenCount: Int?
    let traceId: String?
}

struct SessionLifecyclePayload: Codable, Equatable {
    enum Phase: String, Codable {
        case started
        case ended
        case error
        case backgrounded
        case foregrounded
    }

    let phase: Phase
    let detail: String?
}

struct SessionSpeechPayload: Codable, Equatable {
    enum Action: String, Codable {
        case started
        case stopped
        case committed
        case ignored  // Too short, etc.
    }
    
    let action: Action
    let durationSeconds: Double?
    let reason: String?
}

struct SessionResponsePayload: Codable, Equatable {
    enum Action: String, Codable {
        case created
        case completed
        case cancelled
        case failed
    }
    
    let action: Action
    let responseId: String?
    let status: String?
    let durationSeconds: Double?
}

struct SessionInterruptPayload: Codable, Equatable {
    let reason: String
    let wasAIResponding: Bool
    let wasToolExecuting: Bool
    let cancelledResponseId: String?
}

struct SessionSystemPayload: Codable, Equatable {
    let event: String
    let detail: String?
    let rawData: SessionJSONValue?
}

extension SessionRecording {
    mutating func append(_ event: SessionEvent) {
        events.append(event)
        if let locationEvent = event.location {
            lastKnownLocation = locationEvent
        }
    }
}

protocol SessionLogSink {
    func persist(recording: SessionRecording) async throws
}

enum SessionLoggerError: Error {
    case sinkUnavailable
}

@MainActor
final class SessionLogger: ObservableObject {
    private let sink: SessionLogSink
    private var recording: SessionRecording
    private var lastFlushTask: Task<Void, Never>?

    init(
        sink: SessionLogSink,
        sessionId: String = UUID().uuidString,
        userId: String? = nil,
        metadata: SessionMetadata = .makeDefault()
    ) {
        self.sink = sink
        self.recording = SessionRecording(
            sessionId: sessionId,
            userId: userId,
            startedAt: Date(),
            metadata: metadata
        )
        appendLifecycle(.started, detail: "Session created")
    }

    func updateUser(id: String?, email: String? = nil) {
        recording.userId = id
        if let email = email {
            recording.userEmail = email
        }
    }

    func updateMetadata(_ mutate: (inout SessionMetadata) -> Void) {
        mutate(&recording.metadata)
    }

    func logUserMessage(text: String, languageCode: String?, latency: TimeInterval? = nil, metadata: [String: String]? = nil) {
        let payload = SessionMessagePayload(
            role: .user,
            content: text,
            model: nil,
            latencyMs: SessionLogger.ms(from: latency),
            languageCode: languageCode
        )
        let event = SessionEvent(type: .userMessage, message: payload, metadata: metadata)
        recording.append(event)
        print("📝 [SessionLogger] user message logged")
    }

    func logAssistantMessage(text: String, model: String?, latency: TimeInterval?, metadata: [String: String]? = nil) {
        let payload = SessionMessagePayload(
            role: .assistant,
            content: text,
            model: model,
            latencyMs: SessionLogger.ms(from: latency),
            languageCode: nil
        )
        let event = SessionEvent(type: .assistantMessage, message: payload, metadata: metadata)
        recording.append(event)
        print("🤖 [SessionLogger] assistant message logged")
    }

    func logToolCall(
        name: String,
        invocationId: String?,
        parameters: SessionJSONValue?,
        locationContext: SessionLocationSnapshot?,
        latency: TimeInterval? = nil,
        metadata: [String: String]? = nil
    ) {
        let payload = SessionToolCallPayload(
            name: name,
            invocationId: invocationId,
            parameters: parameters,
            locationContext: locationContext,
            latencyMs: SessionLogger.ms(from: latency)
        )
        let event = SessionEvent(type: .toolCall, toolCall: payload, metadata: metadata)
        recording.append(event)
        if let locationContext {
            recording.lastKnownLocation = locationContext
        }
        print("🛠️ [SessionLogger] tool call logged: \(name)")
    }

    func logToolResult(
        name: String,
        invocationId: String?,
        success: Bool,
        output: SessionJSONValue?,
        errorDescription: String? = nil,
        latency: TimeInterval? = nil,
        metadata: [String: String]? = nil
    ) {
        let payload = SessionToolResultPayload(
            name: name,
            invocationId: invocationId,
            success: success,
            output: output,
            errorDescription: errorDescription,
            latencyMs: SessionLogger.ms(from: latency)
        )
        let event = SessionEvent(type: .toolResult, toolResult: payload, metadata: metadata)
        recording.append(event)
        print("✅ [SessionLogger] tool result logged for \(name) (success: \(success))")
    }

    func logReasoning(content: String, model: String?, tokenCount: Int?, traceId: String?) {
        let payload = SessionReasoningPayload(content: content, model: model, tokenCount: tokenCount, traceId: traceId)
        let event = SessionEvent(type: .reasoning, reasoning: payload)
        recording.append(event)
        print("🧠 [SessionLogger] reasoning log appended")
    }

    func logLocation(_ snapshot: SessionLocationSnapshot, metadata: [String: String]? = nil) {
        recording.lastKnownLocation = snapshot
        let event = SessionEvent(type: .location, location: snapshot, metadata: metadata)
        recording.append(event)
        print("📍 [SessionLogger] location update: \(snapshot.latitude), \(snapshot.longitude)")
    }

    func appendLifecycle(_ phase: SessionLifecyclePayload.Phase, detail: String? = nil, metadata: [String: String]? = nil) {
        let payload = SessionLifecyclePayload(phase: phase, detail: detail)
        let event = SessionEvent(type: .lifecycle, lifecycle: payload, metadata: metadata)
        recording.append(event)
    }
    
    // MARK: - Speech Events (VAD)
    
    func logSpeechStarted(metadata: [String: String]? = nil) {
        let payload = SessionSpeechPayload(action: .started, durationSeconds: nil, reason: nil)
        let event = SessionEvent(type: .speechEvent, speech: payload, metadata: metadata)
        recording.append(event)
    }
    
    func logSpeechStopped(durationSeconds: Double, metadata: [String: String]? = nil) {
        let payload = SessionSpeechPayload(action: .stopped, durationSeconds: durationSeconds, reason: nil)
        let event = SessionEvent(type: .speechEvent, speech: payload, metadata: metadata)
        recording.append(event)
    }
    
    func logSpeechIgnored(durationSeconds: Double, reason: String, metadata: [String: String]? = nil) {
        let payload = SessionSpeechPayload(action: .ignored, durationSeconds: durationSeconds, reason: reason)
        let event = SessionEvent(type: .speechEvent, speech: payload, metadata: metadata)
        recording.append(event)
    }
    
    func logSpeechCommitted(metadata: [String: String]? = nil) {
        let payload = SessionSpeechPayload(action: .committed, durationSeconds: nil, reason: nil)
        let event = SessionEvent(type: .speechEvent, speech: payload, metadata: metadata)
        recording.append(event)
    }
    
    // MARK: - Response Events
    
    func logResponseCreated(responseId: String?, metadata: [String: String]? = nil) {
        let payload = SessionResponsePayload(action: .created, responseId: responseId, status: nil, durationSeconds: nil)
        let event = SessionEvent(type: .responseEvent, response: payload, metadata: metadata)
        recording.append(event)
    }
    
    func logResponseCompleted(responseId: String?, status: String?, durationSeconds: Double? = nil, metadata: [String: String]? = nil) {
        let payload = SessionResponsePayload(action: .completed, responseId: responseId, status: status, durationSeconds: durationSeconds)
        let event = SessionEvent(type: .responseEvent, response: payload, metadata: metadata)
        recording.append(event)
    }
    
    func logResponseCancelled(responseId: String?, reason: String? = nil, metadata: [String: String]? = nil) {
        let payload = SessionResponsePayload(action: .cancelled, responseId: responseId, status: reason, durationSeconds: nil)
        let event = SessionEvent(type: .responseEvent, response: payload, metadata: metadata)
        recording.append(event)
    }
    
    // MARK: - Interrupt Events
    
    func logInterrupt(reason: String, wasAIResponding: Bool, wasToolExecuting: Bool, cancelledResponseId: String? = nil, metadata: [String: String]? = nil) {
        let payload = SessionInterruptPayload(reason: reason, wasAIResponding: wasAIResponding, wasToolExecuting: wasToolExecuting, cancelledResponseId: cancelledResponseId)
        let event = SessionEvent(type: .interruptEvent, interrupt: payload, metadata: metadata)
        recording.append(event)
    }
    
    // MARK: - System Events
    
    func logSystemEvent(_ eventName: String, detail: String? = nil, rawData: SessionJSONValue? = nil, metadata: [String: String]? = nil) {
        let payload = SessionSystemPayload(event: eventName, detail: detail, rawData: rawData)
        let event = SessionEvent(type: .systemEvent, system: payload, metadata: metadata)
        recording.append(event)
    }

    func endSession(errorSummary: String? = nil) {
        recording.endedAt = Date()
        recording.errorSummary = errorSummary
        appendLifecycle(errorSummary == nil ? .ended : .error, detail: errorSummary)
    }

    func snapshot() -> SessionRecording {
        recording
    }

    func flush() {
        lastFlushTask?.cancel()
        let currentRecording = recording
        lastFlushTask = Task {
            do {
                try await sink.persist(recording: currentRecording)
                print("💾 [SessionLogger] session \(currentRecording.sessionId) flushed (\(currentRecording.events.count) events)")
            } catch {
                print("⚠️ [SessionLogger] failed to flush session \(currentRecording.sessionId): \(error)")
            }
        }
    }

    func flushNow() async {
        let currentRecording = recording
        do {
            try await sink.persist(recording: currentRecording)
            print("💾 [SessionLogger] session \(currentRecording.sessionId) flushed synchronously (\(currentRecording.events.count) events)")
        } catch {
            print("⚠️ [SessionLogger] synchronous flush failed for \(currentRecording.sessionId): \(error)")
        }
    }

    private static func ms(from interval: TimeInterval?) -> Double? {
        guard let interval else { return nil }
        return interval * 1000.0
    }
}

struct ConsoleSessionLogSink: SessionLogSink {
    func persist(recording: SessionRecording) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(recording),
           let json = String(data: data, encoding: .utf8) {
            print("🧾 [ConsoleSessionLogSink] \(json)")
        } else {
            print("🧾 [ConsoleSessionLogSink] Stored session \(recording.sessionId) with \(recording.events.count) events")
        }
    }
}

