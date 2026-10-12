import Foundation

// MARK: - SDKCloudModelContracts
//
// IPC request contract for the `use.SwiftCodeModel` capability's
// `cloudModel.complete` method (Docs/Intro-to-SDK.md §10.4).
//
// The host answers with `{"response": "<assistant text>"}` — the raw model
// text only. The endpoint URL, device fingerprint, and quota internals are
// never part of any SDK contract: they stay host-side inside
// `SCCloudModel.swift` and the `SDKCloudModelAdapter`.

/// One conversation turn preceding the prompt.
public struct SDKCloudModelHistoryEntry: Codable, Sendable {
    /// Message role, e.g. "user" or "assistant".
    public let role: String
    /// Message content.
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Request for `cloudModel.complete`.
///
/// All fields are client-supplied content only — the host supplies the
/// endpoint, credentials, model resolution fallback, and quota enforcement.
public struct SDKCloudModelCompletionRequest: Codable, Sendable {
    /// The user prompt. Required, non-empty, bounded by the host.
    public let prompt: String
    /// Conversation history preceding the prompt. Bounded by the host.
    public let history: [SDKCloudModelHistoryEntry]
    /// Optional system prompt prepended by the host.
    public let systemPrompt: String?
    /// Optional model identifier (endpoint model name). When nil the host
    /// resolves its own default.
    public let modelIdentifier: String?

    public init(
        prompt: String,
        history: [SDKCloudModelHistoryEntry] = [],
        systemPrompt: String? = nil,
        modelIdentifier: String? = nil
    ) {
        self.prompt = prompt
        self.history = history
        self.systemPrompt = systemPrompt
        self.modelIdentifier = modelIdentifier
    }
}
