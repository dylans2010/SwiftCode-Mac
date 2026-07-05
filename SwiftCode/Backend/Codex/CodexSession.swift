import Foundation

struct CodexSession: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var messages: [AIMessage]
    var lastResponse: String
    var lastErrorMessage: String?

    var lastError: String? {
        get { lastErrorMessage }
        set { lastErrorMessage = newValue }
    }

    init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date(), messages: [AIMessage] = [], lastResponse: String = "", lastErrorMessage: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.lastResponse = lastResponse
        self.lastErrorMessage = lastErrorMessage
    }
}

enum CodexUsageMode: String, Codable {
    case unlimitedUserControlled
    case restrictedAppControlled
}

enum CodexTaskType: String, Codable, CaseIterable {
    case codeGeneration = "Code Generation"
    case debugging = "Debugging"
    case refactoring = "Refactoring"
    case general = "General"
}

enum CodexManagerError: LocalizedError {
    case requestInFlight

    var errorDescription: String? {
        switch self {
        case .requestInFlight:
            return "A Codex request is already running."
        }
    }
}

struct CodexResponseEnvelope: Decodable {
    let model: String
    let output: [CodexOutputItem]
    let usage: CodexUsage?

    var outputText: String? {
        output.compactMap(\.flattenedText).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CodexOutputItem: Decodable {
    let content: [CodexOutputContent]?

    var flattenedText: String? {
        content?.compactMap { item in
            if let text = item.text {
                return text
            }
            return item.summary?.compactMap(\.text).joined(separator: "\n")
        }.joined(separator: "\n")
    }
}

struct CodexOutputContent: Decodable {
    let text: String?
    let summary: [CodexSummaryText]?
}

struct CodexSummaryText: Decodable {
    let text: String
}

struct CodexUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

struct CodexStreamEvent: Decodable {
    let type: String
    let delta: String?
    let text: String?

    var deltaText: String? {
        delta ?? text
    }
}

struct CodexErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
        let message: String
    }

    let error: ErrorBody
}
