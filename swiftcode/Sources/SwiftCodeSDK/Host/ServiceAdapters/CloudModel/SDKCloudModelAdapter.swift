import Foundation
import SwiftCodeAssistant

public actor SDKCloudModelAdapter {
    public static let shared = SDKCloudModelAdapter()

    public static let maxPromptBytes = 65_536
    public static let maxHistoryEntries = 100
    public static let maxHistoryEntryBytes = 16_384
    public static let maxRoleLength = 32
    public static let maxSystemPromptBytes = 16_384
    public static let maxModelIdentifierLength = 256

    private let provider: any AssistantProvider

    public init(provider: any AssistantProvider = SCCloudProvider()) {
        self.provider = provider
    }

    public func complete(caller: SDKCallerIdentity, request: SDKCloudModelCompletionRequest) async throws -> String {
        try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: caller)
        try validate(request)
        let gate = SCCloudRateLimiter.shared.checkGate()
        guard gate.allowed else {
            throw SDKError(
                code: .resourceLimitExceeded,
                message: "The SwiftCode Cloud Model daily limit has been reached.",
                suggestion: gate.retryAfter.map { "Try again in \(SCCloudRateLimiter.formatDuration($0))." }
            )
        }
        let chatRequest = ChatRequest(
            model: request.modelIdentifier,
            instructions: request.systemPrompt ?? "",
            messages: request.history.map { ChatMessage(ChatRole(rawValue: $0.role) ?? .user, $0.content) }
                + [ChatMessage(.user, request.prompt)]
        )
        var text = ""
        do {
            for try await event in provider.send(chatRequest) {
                switch event {
                case .text(let delta):
                    text += delta
                case .finished:
                    break
                case .activity, .truncated:
                    break
                }
            }
        } catch {
            throw mapCloudError(error)
        }
        return text
    }

    private func validate(_ request: SDKCloudModelCompletionRequest) throws {
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.prompt.utf8.count <= Self.maxPromptBytes else {
            throw SDKError(code: .invalidArgument, message: "The prompt is empty or too large.")
        }
        guard request.history.count <= Self.maxHistoryEntries else {
            throw SDKError(code: .invalidArgument, message: "Too many history entries.")
        }
        for entry in request.history {
            guard (1...Self.maxRoleLength).contains(entry.role.count),
                  entry.content.utf8.count <= Self.maxHistoryEntryBytes else {
                throw SDKError(code: .invalidArgument, message: "A history entry is invalid or too large.")
            }
        }
        if let systemPrompt = request.systemPrompt {
            guard systemPrompt.utf8.count <= Self.maxSystemPromptBytes else {
                throw SDKError(code: .invalidArgument, message: "The system prompt is too large.")
            }
        }
        if let modelIdentifier = request.modelIdentifier {
            guard (1...Self.maxModelIdentifierLength).contains(modelIdentifier.count) else {
                throw SDKError(code: .invalidArgument, message: "The model identifier is invalid.")
            }
        }
    }

    private func mapCloudError(_ error: Error) -> SDKError {
        if let assistantError = error as? AssistantError {
            switch assistantError {
            case .usageLimit(let message):
                return SDKError(code: .resourceLimitExceeded, message: "The SwiftCode Cloud Model daily limit has been reached.", diagnostics: ["detail": String(message.prefix(300))])
            case .notSignedIn:
                return SDKError(code: .serviceUnavailable, message: "The SwiftCode Cloud Model is not configured.")
            case .http(let status, _):
                return SDKError(code: .serviceUnavailable, message: "The SwiftCode Cloud Model is unavailable.", diagnostics: ["status": String(status)])
            case .unreachable:
                return SDKError(code: .serviceUnavailable, message: "The SwiftCode Cloud Model is unreachable.")
            default:
                return SDKError(
                    code: .serviceUnavailable,
                    message: "The SwiftCode Cloud Model is unavailable.",
                    diagnostics: ["detail": String(assistantError.localizedDescription.prefix(300))]
                )
            }
        }
        return SDKError(code: .serviceUnavailable, message: "The SwiftCode Cloud Model is unavailable.")
    }
}
