import Foundation

public actor SDKCloudModelAdapter {

    public static let shared = SDKCloudModelAdapter()

    private init() {}

    private static let maxPromptBytes = 64 * 1024
    private static let maxHistoryEntries = 100
    private static let maxHistoryEntryBytes = 16 * 1024
    private static let maxHistoryRoleLength = 32
    private static let maxSystemPromptBytes = 16 * 1024
    private static let maxModelIdentifierLength = 256

    public func complete(
        request: SDKCloudModelCompletionRequest,
        caller: SDKCallerIdentity
    ) async throws -> String {
        try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: caller)

        try validate(request)

        let gate = SCCloudRateLimiter.shared.checkGate()
        if !gate.allowed {
            throw quotaError(retryAfter: gate.retryAfter)
        }

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
