import Foundation
import Observation

public struct DiagnosticEvent: Identifiable, Codable, Equatable {
    public let id: UUID
    public let component: String
    public let timestamp: Date
    public let provider: String
    public let model: String
    public let executionMode: String
    public let severity: String // "INFO", "WARN", "ERROR", "DEBUG", "SUCCESS"
    public let errorDescription: String?
    public let category: String // "network", "auth", "json", "stream", "tool", "switch", "system"
    public let message: String
}

@Observable
@MainActor
public final class DiagnosticEventBus {
    public static let shared = DiagnosticEventBus()

    public var events: [DiagnosticEvent] = []

    private init() {}

    nonisolated public func logEvent(
        component: String,
        provider: String = "None",
        model: String = "None",
        executionMode: String = "None",
        severity: String = "INFO",
        errorDescription: String? = nil,
        category: String = "system",
        message: String
    ) {
        // Redact any potential API keys in message/description
        let cleanMessage = redactSecrets(message)
        let cleanDesc = errorDescription.map { redactSecrets($0) }

        let event = DiagnosticEvent(
            id: UUID(),
            component: component,
            timestamp: Date(),
            provider: provider,
            model: model,
            executionMode: executionMode,
            severity: severity,
            errorDescription: cleanDesc,
            category: category,
            message: cleanMessage
        )

        Task { @MainActor in
            DiagnosticEventBus.shared.events.append(event)
        }
    }

    nonisolated private func redactSecrets(_ text: String) -> String {
        // Redact standard sk-... API keys safely
        let pattern = #"(sk-[a-zA-Z0-9-]{12,})"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[REDACTED_API_KEY]")
        }
        return text
    }

    public func clear() {
        events.removeAll()
    }
}
