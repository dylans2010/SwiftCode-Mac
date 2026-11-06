import Foundation

// MARK: - SDKAssistTypes
//
// Ported from Legacy `SwiftCode/SDK/Host/Assist/SDKAssistTypes.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Types for the entitled `assist.invoke` IPC route. Sessions are
// host-owned: an extension may only touch sessions created under its
// own verified key, and only with tools the host approved at session
// creation. The host NEVER fabricates Assist responses — `send` and
// `sendStreaming` hit the backend boundary in `SDKAssistService` and
// throw `.serviceUnavailable` when no backend is attached.

public struct SDKAssistMessage: Sendable, Codable, Equatable {
    public enum Role: String, Sendable, Codable {
        case user
        case assistant
    }

    public let role: Role
    public let content: String
    public let timestamp: Date

    public init(role: Role, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public struct SDKAssistSessionOptions: Sendable, Codable, Equatable {
    /// Session title, at most 256 characters. Empty means no title.
    public let title: String?
    /// System prompt, at most 16 KiB. Empty means none.
    public let systemPrompt: String?
    /// Model identifier, at most 256 characters. Empty means host default.
    public let model: String?

    public init(title: String? = nil, systemPrompt: String? = nil, model: String? = nil) {
        self.title = title.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        self.systemPrompt = systemPrompt.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        self.model = model.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct SDKAssistSession: Sendable, Codable, Equatable {
    public let id: UUID
    public let extensionID: String
    public let title: String?
    public let systemPrompt: String?
    public let model: String?
    public let createdAt: Date
    public var isClosed: Bool
    public var messages: [SDKAssistMessage]
    /// Tool IDs the session may invoke — snapshotted from the host's
    /// ACTIVE grants at creation. Never extended afterwards.
    public let allowedToolIDs: [String]

    public init(
        id: UUID = UUID(),
        extensionID: String,
        title: String? = nil,
        systemPrompt: String? = nil,
        model: String? = nil,
        createdAt: Date = Date(),
        isClosed: Bool = false,
        messages: [SDKAssistMessage] = [],
        allowedToolIDs: [String] = []
    ) {
        self.id = id
        self.extensionID = extensionID
        self.title = title
        self.systemPrompt = systemPrompt
        self.model = model
        self.createdAt = createdAt
        self.isClosed = isClosed
        self.messages = messages
        self.allowedToolIDs = allowedToolIDs
    }
}

public struct SDKAssistResponse: Sendable, Codable, Equatable {
    public let sessionID: UUID
    public let text: String

    public init(sessionID: UUID, text: String) {
        self.sessionID = sessionID
        self.text = text
    }
}

public enum SDKAssistStreamEvent: Sendable, Equatable {
    case started
    case delta(String)
    case completed
    case failed(SDKError)
}

public struct SDKAssistToolCall: Sendable, Codable, Equatable {
    public let toolName: String
    public let arguments: [String: String]

    public init(toolName: String, arguments: [String: String] = [:]) {
        self.toolName = toolName
        self.arguments = arguments
    }
}

public struct SDKAssistToolResult: Sendable, Codable, Equatable {
    public let toolName: String
    public let succeeded: Bool
    public let output: String

    public init(toolName: String, succeeded: Bool, output: String) {
        self.toolName = toolName
        self.succeeded = succeeded
        self.output = output
    }
}
