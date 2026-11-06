import Foundation

/// One message in a Codex session (ported from Legacy's `CodexSession`).
///
/// Legacy stored `AIMessage` (a Core type owned by another slice); this
/// local struct carries the same two fields the Responses API needs — the
/// role string (`"user"` / `"assistant"`) and the text — so the Codex
/// client does not depend on another slice's message type.
public struct CodexMessage: Codable, Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    public static func user(_ content: String) -> CodexMessage {
        CodexMessage(role: "user", content: content)
    }

    public static func assistant(_ content: String) -> CodexMessage {
        CodexMessage(role: "assistant", content: content)
    }
}

/// One Codex conversation (ported from Legacy's `CodexSession`).
public struct CodexSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public var messages: [CodexMessage]
    public var lastResponse: String
    public var lastErrorMessage: String?

    public var lastError: String? {
        get { lastErrorMessage }
        set { lastErrorMessage = newValue }
    }

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date(), messages: [CodexMessage] = [], lastResponse: String = "", lastErrorMessage: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.lastResponse = lastResponse
        self.lastErrorMessage = lastErrorMessage
    }
}

/// Which key funds Codex usage: the user's own API key, or the app-owned key.
public enum CodexUsageMode: String, Codable, Sendable {
    case unlimitedUserControlled
    case restrictedAppControlled
}

/// What kind of work a prompt is (drives the system prompt's task line).
public enum CodexTaskType: String, Codable, CaseIterable, Sendable {
    case codeGeneration = "Code Generation"
    case debugging = "Debugging"
    case refactoring = "Refactoring"
    case general = "General"
}

public enum CodexManagerError: LocalizedError {
    case requestInFlight

    public var errorDescription: String? {
        switch self {
        case .requestInFlight:
            return "A Codex request is already running."
        }
    }
}

/// The OpenAI Responses API envelope (`POST /v1/responses`).
public struct CodexResponseEnvelope: Decodable {
    public let model: String
    public let output: [CodexOutputItem]
    public let usage: CodexUsage?

    public var outputText: String? {
        output.compactMap(\.flattenedText).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct CodexOutputItem: Decodable {
    public let content: [CodexOutputContent]?

    public var flattenedText: String? {
        content?.compactMap { item in
            if let text = item.text {
                return text
            }
            return item.summary?.compactMap(\.text).joined(separator: "\n")
        }.joined(separator: "\n")
    }
}

public struct CodexOutputContent: Decodable {
    public let text: String?
    public let summary: [CodexSummaryText]?
}

public struct CodexSummaryText: Decodable {
    public let text: String
}

public struct CodexUsage: Decodable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

/// One streamed event from the Responses API.
public struct CodexStreamEvent: Decodable {
    public let type: String
    public let delta: String?
    public let text: String?

    public var deltaText: String? {
        delta ?? text
    }
}

/// The error envelope the Responses API returns on failure.
public struct CodexErrorEnvelope: Decodable {
    public struct ErrorBody: Decodable {
        public let message: String
    }

    public let error: ErrorBody
}
