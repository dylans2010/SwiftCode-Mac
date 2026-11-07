import Foundation

public enum SDKToolSource: String, Codable, Sendable {
    case swiftcode
    case openrouter
    case opencode
    case hermes
}

public enum SDKToolState: String, Codable, Sendable {
    case requested
    case running
    case completed
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .requested, .running:
            return false
        }
    }

    var rank: Int {
        switch self {
        case .requested: return 0
        case .running: return 1
        case .completed, .failed, .cancelled: return 2
        }
    }

    public var displayLabel: String {
        switch self {
        case .requested: return "Pending"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

public struct SDKToolEvent: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var provider: String
    public var sessionId: String
    public var toolCallId: String
    public var toolName: String
    public var toolDescription: String?
    public var source: SDKToolSource
    public var state: SDKToolState
    public var arguments: String
    public var result: String?
    public var error: String?
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        provider: String,
        sessionId: String,
        toolCallId: String,
        toolName: String,
        toolDescription: String? = nil,
        source: SDKToolSource,
        state: SDKToolState,
        arguments: String = "",
        result: String? = nil,
        error: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.provider = provider
        self.sessionId = sessionId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.toolDescription = toolDescription
        self.source = source
        self.state = state
        self.arguments = arguments
        self.result = result
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case sessionId
        case toolCallId
        case toolName
        case toolDescription
        case source
        case state
        case arguments
        case result
        case error
        case startedAt
        case completedAt
    }

    public var safeArguments: String {
        Self.redact(arguments)
    }

    public var safeResult: String? {
        result.map(Self.redact)
    }

    public var safeError: String? {
        error.map(Self.redact)
    }

    public var duration: TimeInterval? {
        guard let startedAt, let completedAt, completedAt >= startedAt else {
            return nil
        }
        return completedAt.timeIntervalSince(startedAt)
    }

    public func updating(with newer: SDKToolEvent) -> SDKToolEvent {
        guard newer.toolCallId == toolCallId, newer.sessionId == sessionId else {
            return self
        }
        let canAdvance: Bool
        if state.isTerminal {
            canAdvance = newer.state == state
        } else {
            canAdvance = newer.state.rank >= state.rank
        }
        guard canAdvance else {
            return self
        }

        var merged = self
        merged.state = newer.state
        if !newer.toolName.isEmpty {
            merged.toolName = newer.toolName
        }
        if let description = newer.toolDescription, !description.isEmpty {
            merged.toolDescription = description
        }
        if !newer.arguments.isEmpty {
            merged.arguments = newer.arguments
        }
        if let result = newer.result {
            merged.result = result
        }
        if let error = newer.error {
            merged.error = error
        }
        if merged.startedAt == nil {
            merged.startedAt = newer.startedAt
        }
        if let completedAt = newer.completedAt {
            merged.completedAt = completedAt
        }
        if merged.provider.isEmpty {
            merged.provider = newer.provider
        }
        return merged
    }

    private static let sensitiveKeyFragments = [
        "password",
        "token",
        "key",
        "secret",
        "authorization",
    ]

    private static func isSensitiveKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return sensitiveKeyFragments.contains { lower.contains($0) }
    }

    public static func redact(_ text: String) -> String {
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            let redacted = redactValue(json)
            if JSONSerialization.isValidJSONObject(redacted),
               let out = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
               let string = String(data: out, encoding: .utf8) {
                return string
            }
        }
        return redactPlainText(text)
    }

    private static func redactValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var redacted: [String: Any] = [:]
            redacted.reserveCapacity(dict.count)
            for (key, nested) in dict {
                redacted[key] = isSensitiveKey(key) ? "[redacted]" : redactValue(nested)
            }
            return redacted
        }
        if let array = value as? [Any] {
            return array.map(redactValue)
        }
        return value
    }

    private static func redactPlainText(_ text: String) -> String {
        var redacted = text
        let pairPattern = #"(?i)\b(password|token|secret|authorization|api[-_]?key)\b\s*["']?\s*[:=]\s*["']?[^\s,"'}]+"#
        if let regex = try? NSRegularExpression(pattern: pairPattern) {
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = regex.stringByReplacingMatches(
                in: redacted,
                range: range,
                withTemplate: "$1: [redacted]"
            )
        }
        let bearerPattern = #"(?i)Bearer\s+[A-Za-z0-9._\-~+/=]+"#
        if let regex = try? NSRegularExpression(pattern: bearerPattern) {
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = regex.stringByReplacingMatches(
                in: redacted,
                range: range,
                withTemplate: "Bearer [redacted]"
            )
        }
        return redacted
    }
}
