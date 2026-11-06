import Foundation
import Observation

/// The Codex API-key client facade (ported from Legacy's `CodexManager`).
///
/// Keys come from the secret store, never from the code: the user's own
/// key (`codex.user-api-key`) is tried first, then the app-owned key
/// (`codex.app-api-key`). Legacy read the same two keys from its
/// `KeychainService`; the accounts here are the `SecretStore` equivalents
/// (there is no `SecretAccount` constant for Codex — these account strings
/// are owned by this file). No key is embedded anywhere.
///
/// Usage modes: with a user key the mode is unlimited; with the app-owned
/// key it is restricted to 200 requests and 200,000 tokens per session.
/// The default model is `gpt-5-codex` (UserDefaults `codex.model`
/// overrides it).
///
/// `streamResponse` replays the already-received `lastResponse` one
/// character at a time as a typewriter effect — Legacy's behaviour, kept
/// honestly labelled: it is not a live stream from the API.
@Observable
@MainActor
public final class CodexManager {
    public static let shared = CodexManager()

    public static let userKeyAccount = "codex.user-api-key"
    public static let appKeyAccount = "codex.app-api-key"
    public static let modelDefaultsKey = "codex.model"
    public static let defaultModel = "gpt-5-codex"

    public private(set) var activeSession = CodexSession()
    public private(set) var isRequestInFlight = false
    public private(set) var streamedText = ""
    public private(set) var usageMode: CodexUsageMode = .restrictedAppControlled

    private let service: CodexService
    private let tracker: CodexUsageTracker
    private let store: SecretStore
    private var activeTask: Task<Void, Never>?
    private let appOwnedRequestLimit = 200
    private let appOwnedTokenLimit = 200_000

    public init(service: CodexService = CodexService(), tracker: CodexUsageTracker = .shared, store: SecretStore = defaultSecretStore()) {
        self.service = service
        self.tracker = tracker
        self.store = store
        refreshUsageMode()
    }

    public var userHasCustomAPIKey: Bool {
        !(store.readString(Self.userKeyAccount) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var activeAPIKey: String? {
        let userKey = store.readString(Self.userKeyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !userKey.isEmpty { return userKey }

        let appKey = store.readString(Self.appKeyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return appKey.isEmpty ? nil : appKey
    }

    public var hasValidConfiguration: Bool {
        activeAPIKey != nil
    }

    public func refreshUsageMode() {
        if userHasCustomAPIKey {
            usageMode = .unlimitedUserControlled
        } else {
            usageMode = .restrictedAppControlled
        }
    }

    public func validateUserAPIKey(_ apiKey: String) async -> Bool {
        await service.validateAPIKey(apiKey, model: currentModel)
    }

    public var currentModel: String {
        let saved = UserDefaults.standard.string(forKey: Self.modelDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? Self.defaultModel : saved
    }

    public func sendPrompt(_ prompt: String) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return "" }
        guard !isRequestInFlight else { throw CodexManagerError.requestInFlight }
        guard let apiKey = activeAPIKey else { throw CodexAPIError.invalidKey }

        refreshUsageMode()
        try enforceRestrictionsIfNeeded(prompt: trimmedPrompt)

        isRequestInFlight = true
        streamedText = ""
        activeSession.lastErrorMessage = nil
        activeSession.messages.append(.user(trimmedPrompt))
        activeSession.updatedAt = Date()
        defer { isRequestInFlight = false }

        do {
            let response = try await service.send(prompt: trimmedPrompt, session: activeSession, apiKey: apiKey, model: currentModel, taskType: inferTaskType(from: trimmedPrompt))
            let text = response.completionText.trimmingCharacters(in: .whitespacesAndNewlines)
            activeSession.messages.append(.assistant(text))
            activeSession.lastResponse = text
            activeSession.updatedAt = Date()
            tracker.record(prompt: trimmedPrompt, response: text, tokenUsage: response.tokenUsage, mode: usageMode)
            return text
        } catch {
            activeSession.lastErrorMessage = CodexErrorHandler.userFacingMessage(for: error)
            throw error
        }
    }

    /// Replays `lastResponse` as a typewriter effect (see the class doc:
    /// this is not a live API stream).
    public func streamResponse(handler: @escaping (String) -> Void) {
        activeTask?.cancel()
        let text = activeSession.lastResponse
        activeTask = Task { @MainActor in
            streamedText = ""
            for character in text {
                if Task.isCancelled { return }
                streamedText.append(character)
                handler(streamedText)
                try? await Task.sleep(nanoseconds: 15_000_000)
            }
        }
    }

    public func cancelRequest() {
        activeTask?.cancel()
        activeTask = nil
        isRequestInFlight = false
    }

    public func resetSession() {
        cancelRequest()
        activeSession = CodexSession()
        streamedText = ""
        tracker.recordSessionReset()
    }

    private func enforceRestrictionsIfNeeded(prompt: String) throws {
        guard usageMode == .restrictedAppControlled else { return }
        if tracker.requestCount >= appOwnedRequestLimit {
            throw CodexAPIError.rateLimited
        }
        let estimatedPromptTokens = max(1, Int((Double(prompt.count) / 4.0).rounded(.up)))
        if tracker.estimatedTotalTokens + estimatedPromptTokens > appOwnedTokenLimit {
            throw CodexAPIError.rateLimited
        }
    }

    private func inferTaskType(from prompt: String) -> CodexTaskType {
        let lower = prompt.lowercased()
        if lower.contains("debug") || lower.contains("error") || lower.contains("fix") { return .debugging }
        if lower.contains("refactor") || lower.contains("cleanup") || lower.contains("rename") { return .refactoring }
        if lower.contains("generate") || lower.contains("create") || lower.contains("write") { return .codeGeneration }
        return .general
    }
}
