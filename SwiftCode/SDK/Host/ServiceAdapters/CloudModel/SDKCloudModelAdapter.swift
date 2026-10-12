import Foundation

// MARK: - SDKCloudModelAdapter
//
// THE ONLY CLOUD-MODEL PATH EXTENSIONS MAY USE (spec §8.5, capability
// `use.SwiftCodeModel`).
//
// This adapter is the single host-owned bridge between the SDK surface and
// the real `SCCloudModelClient`. It exposes exactly one operation —
// `complete` — and nothing else from the cloud-model system.
//
// Host-secret confinement (verified against
// `SwiftCode/Backend/Assist/SCCloudModel.swift`):
// - The endpoint URL, device fingerprint, and request-building are owned
//   entirely by `SCCloudModelClient`/`SCCloudConfiguration` in the host
//   process. This adapter passes ONLY extension-supplied content
//   (prompt, history, system prompt, optional model identifier) and
//   receives ONLY the assistant's text. No payload, error, or log in this
//   file carries the endpoint URL, the fingerprint, or key material.
// - Quota is enforced by the host's `SCCloudRateLimiter` on every call:
//   a non-consuming gate pre-check rejects exhausted quota BEFORE any
//   network use, and `SCCloudModelClient.complete` itself re-checks the
//   gate and records each completed round-trip (recordRequest). Quota can
//   never be bypassed through this path — a denial never fabricates a
//   model response.
//
// Authorization: `complete` authorizes FIRST via
// `SDKCapabilityBroker.authorize(.useSwiftCodeModel, for:)` on every call.
// Without the grant the request is denied with typed `.permissionDenied`
// before any host state is touched.
//
// Input bounds: extension-supplied strings are validated and bounded here
// so the host never forwards unbounded payloads to the model endpoint.

public actor SDKCloudModelAdapter {

    public static let shared = SDKCloudModelAdapter()

    private init() {}

    // MARK: - Input bounds

    /// Max UTF-8 bytes of the prompt.
    private static let maxPromptBytes = 64 * 1024
    /// Max history turns.
    private static let maxHistoryEntries = 100
    /// Max UTF-8 bytes of one history entry's content.
    private static let maxHistoryEntryBytes = 16 * 1024
    /// Max length of a history role string.
    private static let maxHistoryRoleLength = 32
    /// Max UTF-8 bytes of the system prompt.
    private static let maxSystemPromptBytes = 16 * 1024
    /// Max length of the model identifier string.
    private static let maxModelIdentifierLength = 256

    // MARK: - Completion

    /// Runs one cloud-model completion through the host's real client.
    ///
    /// Pipeline:
    /// 1. Authorize `.useSwiftCodeModel` at the capability broker.
    /// 2. Validate and bound all extension-supplied content (→ `.invalidArgument`).
    /// 3. Non-consuming quota gate pre-check (→ `.resourceLimitExceeded` when exhausted).
    /// 4. `SCCloudModelClient.shared.complete` — the real host call; it
    ///    re-checks and consumes quota itself.
    ///
    /// Errors are typed `SDKError`s only. Quota denial never fabricates a
    /// model response; endpoint and credential details never leave the host.
    public func complete(
        request: SDKCloudModelCompletionRequest,
        caller: SDKCallerIdentity
    ) async throws -> String {
        // --- 1. Grant check first.
        try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: caller)

        // --- 2. Validate and bound extension-supplied content.
        try validate(request)

        // --- 3. Non-consuming quota gate pre-check. The client re-checks
        // --- the gate and records the round-trip itself; this check only
        // --- gives the extension a fast, typed answer before any work.
        let gate = SCCloudRateLimiter.shared.checkGate()
        if !gate.allowed {
            throw quotaError(retryAfter: gate.retryAfter)
        }

        // --- 4. The real host call. Only extension-supplied content crosses
        // --- this boundary; endpoint, fingerprint, and headers are supplied
        // --- host-side by SCCloudModelClient.
        do {
            return try await SCCloudModelClient.shared.complete(
                prompt: request.prompt,
                history: request.history.map { (role: $0.role, content: $0.content) },
                systemPrompt: request.systemPrompt,
                modelIdentifier: request.modelIdentifier
            )
        } catch let cloudError as SCCloudError {
            throw mapCloudError(cloudError)
        }
    }

    // MARK: - Validation

    /// Bounds extension-supplied content. Malformed input is
    /// `.invalidArgument`: the caller is told exactly what to fix, and the
    /// host never forwards unbounded payloads.
    private func validate(_ request: SDKCloudModelCompletionRequest) throws {
        if request.prompt.isEmpty {
            throw SDKError(
                code: .invalidArgument,
                message: "The \"prompt\" must be a non-empty string.",
                suggestion: "Send a prompt like {\"prompt\": \"...\"}."
            )
        }
        if request.prompt.utf8.count > Self.maxPromptBytes {
            throw SDKError(
                code: .invalidArgument,
                message: "The prompt is too large (limit \(Self.maxPromptBytes) bytes).",
                suggestion: "Shorten the prompt and try again."
            )
        }
        if request.history.count > Self.maxHistoryEntries {
            throw SDKError(
                code: .invalidArgument,
                message: "The history is too long (limit \(Self.maxHistoryEntries) entries).",
                suggestion: "Trim the conversation history and try again."
            )
        }
        for entry in request.history {
            if entry.role.isEmpty || entry.role.count > Self.maxHistoryRoleLength {
                throw SDKError(
                    code: .invalidArgument,
                    message: "A history entry has an invalid role (1–\(Self.maxHistoryRoleLength) characters).",
                    suggestion: "Use roles like \"user\" or \"assistant\"."
                )
            }
            if entry.content.utf8.count > Self.maxHistoryEntryBytes {
                throw SDKError(
                    code: .invalidArgument,
                    message: "A history entry is too large (limit \(Self.maxHistoryEntryBytes) bytes).",
                    suggestion: "Shorten the history entry and try again."
                )
            }
        }
        if let systemPrompt = request.systemPrompt,
           systemPrompt.utf8.count > Self.maxSystemPromptBytes {
            throw SDKError(
                code: .invalidArgument,
                message: "The system prompt is too large (limit \(Self.maxSystemPromptBytes) bytes).",
                suggestion: "Shorten the system prompt and try again."
            )
        }
        if let modelIdentifier = request.modelIdentifier,
           modelIdentifier.isEmpty || modelIdentifier.count > Self.maxModelIdentifierLength {
            throw SDKError(
                code: .invalidArgument,
                message: "The model identifier is invalid (1–\(Self.maxModelIdentifierLength) characters).",
                suggestion: "Omit \"modelIdentifier\" to use the host default."
            )
        }
    }

    // MARK: - Error mapping

    /// Typed quota denial. Never fabricates a response; never includes
    /// host internals.
    private func quotaError(retryAfter: TimeInterval?) -> SDKError {
        let suggestion: String
        if let retryAfter {
            suggestion = "The daily quota will reset in \(SCCloudRateLimiter.formatDuration(retryAfter))."
        } else {
            suggestion = "The daily quota will reset in 24 hours."
        }
        return SDKError(
            code: .resourceLimitExceeded,
            message: "The SwiftCode Cloud Model daily request quota is exhausted.",
            suggestion: suggestion,
            diagnostics: retryAfter.map { ["retryAfterSeconds": String(Int($0))] }
        )
    }

    /// Projects `SCCloudError` onto the SDK taxonomy. Host-secret details
    /// (endpoint, fingerprint, raw server bodies) are never included:
    /// server messages are sanitized and truncated to 300 characters, and
    /// only the status code — a safe numeric value — travels in diagnostics.
    private func mapCloudError(_ error: SCCloudError) -> SDKError {
        switch error {
        case .rateLimited(let retryAfter):
            return quotaError(retryAfter: retryAfter)
        case .notConfigured:
            return SDKError(
                code: .serviceUnavailable,
                message: "The SwiftCode Cloud Model is not configured on this host.",
                suggestion: "Configure the cloud endpoint on the host to use this feature."
            )
        case .fingerprintUnavailable:
            return SDKError(
                code: .serviceUnavailable,
                message: "The SwiftCode Cloud Model is unavailable: the host could not identify this device.",
                suggestion: "Try again later."
            )
        case .network:
            return SDKError(
                code: .serviceUnavailable,
                message: "The SwiftCode Cloud Model could not be reached over the network.",
                suggestion: "Check the network connection and try again."
            )
        case .server(let statusCode, let message):
            let sanitized = String(
                SDKLogRedaction.sanitizeForUser(message).prefix(300)
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return SDKError(
                code: .serviceUnavailable,
                message: sanitized.isEmpty
                    ? "The SwiftCode Cloud Model returned an error."
                    : "The SwiftCode Cloud Model returned an error: \(sanitized)",
                suggestion: "Try again; if it persists, wait and retry later.",
                diagnostics: ["statusCode": String(statusCode)]
            )
        case .invalidResponse:
            return SDKError(
                code: .serviceUnavailable,
                message: "The SwiftCode Cloud Model returned an unreadable response.",
                suggestion: "Try again."
            )
        case .noModelAvailable:
            return SDKError(
                code: .serviceUnavailable,
                message: "No SwiftCode Cloud Model is available on this host right now.",
                suggestion: "Try again later."
            )
        }
    }
}
