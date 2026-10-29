//  SDKToolEvent.swift
//  SwiftCode
//
//  Shared event contract for provider tool activity.
//
//  Workstreams A (OpenCode) and B (OpenRouter) publish events in this shape
//  (one JSON object per line over their NDJSON bridges); Workstream C's
//  store and views consume it. The contract is deliberately provider-neutral:
//  it carries no provider client, no registry type, and no SwiftUI, so the
//  store stays dependency-free and the views stay pure rendering.
//
//  Identity: `toolCallId` is the stable identity SwiftUI keys rows by. The
//  store merges every later event for the same `toolCallId` into the
//  first-seen row; it never appends a duplicate row for the same call.
//
//  State machine: requested -> running -> completed | failed | cancelled.
//  completed, failed, and cancelled are terminal. A merge never moves a
//  terminal event to a different terminal state, and never moves any event
//  backwards (running -> requested is an out-of-order duplicate and is
//  ignored). Skipping an intermediate non-terminal state (requested ->
//  completed, when no running event was observed) is forward progress, not
//  a regression, and is accepted. A later event in the *same* state may
//  refresh the payload (arguments, result, error, timestamps); a merge
//  never invents a result — a nil result on the newer event keeps the
//  existing result untouched.
//
//  NDJSON decoding note: the bridges decode these objects with
//  `JSONDecoder` using the `.iso8601` date strategy. This struct itself
//  sets no strategy; it only declares the field names, so the bridge and
//  this contract must agree on ISO 8601 timestamps.

import Foundation

/// Which tool ecosystem executed a tool call. Independent of the provider
/// runtime: in a combined session, one session can carry events from more
/// than one source, and each event is routed to its own UI by this value.
public enum SDKToolSource: String, Codable, Sendable {
    case swiftcode
    case openrouter
    case opencode
}

/// Execution state of a single tool call. Terminal states never regress.
public enum SDKToolState: String, Codable, Sendable {
    case requested
    case running
    case completed
    case failed
    case cancelled

    /// True for completed, failed, and cancelled.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .requested, .running:
            return false
        }
    }

    /// Monotonic rank used by `SDKToolEvent.updating(with:)`. Terminal
    /// states share the top rank; the same-state rule in the merge (not
    /// the rank) is what forbids completed -> failed and failed ->
    /// completed.
    var rank: Int {
        switch self {
        case .requested: return 0
        case .running: return 1
        case .completed, .failed, .cancelled: return 2
        }
    }

    /// User-facing label. "Pending" (not "requested") matches the
    /// Muse/native tool rows, which show a quiet dot for a call that has
    /// been requested but has not started running yet.
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

/// One tool call's observable state, as it evolves over a session.
///
/// `arguments` and `result` are safe representations: the bridges redact
/// sensitive values before publishing, and the views additionally display
/// only the redacted forms (`safeArguments`, `safeResult`, `safeError`),
/// so a raw credential can never reach the UI even if a bridge forgets
/// to redact.
public struct SDKToolEvent: Identifiable, Codable, Sendable, Equatable {
    /// Row identity for SwiftUI. Stable per tool call; the merge in
    /// `updating(with:)` keeps the first-seen id even if a later event
    /// for the same call carries a different one.
    public var id: UUID
    /// Provider runtime that served the session, e.g. "openrouter" or
    /// "opencode". Free-form: the routing key for views is `source`, not
    /// this string, so a provider rename can never misroute a row.
    public var provider: String
    /// Session this call belongs to. The store keys its rows by this value.
    public var sessionId: String
    /// Stable identity of the call itself. Rows are keyed by this value,
    /// not by `id` or by array position, so a merge never duplicates a row
    /// and never loses a row's expansion state.
    public var toolCallId: String
    /// Tool name exactly as reported by the runtime. Views display it
    /// as-is: no renaming, no prefix stripping (including the documented
    /// combined-mode `opencode_` prefix).
    public var toolName: String
    /// Purpose/description as reported by the runtime, when available.
    public var toolDescription: String?
    /// Which tool ecosystem executed the call. This — never the display
    /// name — decides which view renders the row.
    public var source: SDKToolSource
    public var state: SDKToolState
    /// Arguments in a readable, safe representation (typically compact
    /// JSON). Display only via `safeArguments`.
    public var arguments: String
    /// Actual result text, present once the call completes. Display only
    /// via `safeResult`.
    public var result: String?
    /// Structured error text for failed/cancelled calls. Display only
    /// via `safeError`.
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

    /// NDJSON field names. `toolDescription` is optional and decodes as
    /// nil when absent; every other name is the exact wire name.
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

    /// Redacted arguments for display. Always use this instead of
    /// `arguments` in any view.
    public var safeArguments: String {
        Self.redact(arguments)
    }

    /// Redacted result for display, when present.
    public var safeResult: String? {
        result.map(Self.redact)
    }

    /// Redacted error for display, when present.
    public var safeError: String? {
        error.map(Self.redact)
    }

    /// Duration in seconds when both timestamps are present and ordered.
    public var duration: TimeInterval? {
        guard let startedAt, let completedAt, completedAt >= startedAt else {
            return nil
        }
        return completedAt.timeIntervalSince(startedAt)
    }

    /// Applies a newer event for the same call to this event and returns
    /// the merged result. The receiver is never mutated in place; the
    /// store replaces the stored row with the return value.
    ///
    /// - Returns: `self` unchanged when the newer event belongs to a
    ///   different call/session, regresses the state, or moves a terminal
    ///   state to a different terminal state. Otherwise a copy with the
    ///   newer state and whichever newer payload fields are present.
    ///   Identity fields (`id`, `sessionId`, `toolCallId`) and the
    ///   first-seen `startedAt` are never overwritten.
    public func updating(with newer: SDKToolEvent) -> SDKToolEvent {
        guard newer.toolCallId == toolCallId, newer.sessionId == sessionId else {
            return self
        }
        let canAdvance: Bool
        if state.isTerminal {
            // Same terminal state may refresh its payload (e.g. a second
            // completed event carrying the result); it may never become a
            // different terminal state.
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
        // Never invent a result or an error: a nil field on the newer
        // event leaves the existing value untouched.
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

    // MARK: - Redaction

    /// Key fragments that mark a value sensitive, matched
    /// case-insensitively against JSON object keys, per the contract.
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

    /// Returns `text` with sensitive values replaced by "[redacted]".
    /// JSON objects and arrays are walked recursively so nested secrets
    /// are caught; non-JSON text is handled by plain-text patterns
    /// (key/value pairs and `Bearer <token>`). Values are replaced, keys
    /// are preserved, so the shape of the arguments stays readable.
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
        // key = value / key: value pairs, with the key as a whole word.
        // The replacement keeps the key and drops only the value.
        let pairPattern = #"(?i)\b(password|token|secret|authorization|api[-_]?key)\b\s*["']?\s*[:=]\s*["']?[^\s,"'}]+"#
        if let regex = try? NSRegularExpression(pattern: pairPattern) {
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = regex.stringByReplacingMatches(
                in: redacted,
                range: range,
                withTemplate: "$1: [redacted]"
            )
        }
        // Authorization header scheme.
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
