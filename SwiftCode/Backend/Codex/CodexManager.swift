import Foundation
import SwiftUI

@MainActor
final class CodexManager: ObservableObject {
    static let shared = CodexManager()

    @Published private(set) var activeSession = CodexSession()
    @Published private(set) var isRequestInFlight = false
    @Published private(set) var streamedText = ""
    @Published private(set) var usageMode: CodexUsageMode = .restrictedAppControlled

    private let service = CodexService()
    private let tracker = CodexUsageTracker.shared
    private var activeTask: Task<Void, Never>?
    private let appOwnedRequestLimit = 200
    private let appOwnedTokenLimit = 200_000

    private init() {
        refreshUsageMode()
    }

    var userHasCustomAPIKey: Bool {
        !(KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var activeAPIKey: String? {
        let userKey = KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !userKey.isEmpty { return userKey }

        let appKey = KeychainService.shared.get(forKey: KeychainService.codexAppAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return appKey.isEmpty ? nil : appKey
    }

    var hasValidConfiguration: Bool {
        activeAPIKey != nil
    }

    func refreshUsageMode() {
        if userHasCustomAPIKey {
            usageMode = .unlimitedUserControlled
        } else {
            usageMode = .restrictedAppControlled
        }
    }

    func validateUserAPIKey(_ apiKey: String) async -> Bool {
        await service.validateAPIKey(apiKey, model: currentModel)
    }

    var currentModel: String {
        let saved = UserDefaults.standard.string(forKey: "codex.model")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? "gpt-5-codex" : saved
    }

    func sendPrompt(_ prompt: String) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return "" }
        guard !isRequestInFlight else { throw CodexManagerError.requestInFlight }
        guard let apiKey = activeAPIKey else { throw LLMError.invalidKey }

        refreshUsageMode()
        try enforceRestrictionsIfNeeded(prompt: trimmedPrompt)

        isRequestInFlight = true
        streamedText = ""
        activeSession.lastErrorMessage = nil
        activeSession.messages.append(AIMessage(role: "user", content: trimmedPrompt))
        activeSession.updatedAt = Date()
        defer { isRequestInFlight = false }

        do {
            let response = try await service.send(prompt: trimmedPrompt, session: activeSession, apiKey: apiKey, model: currentModel, taskType: inferTaskType(from: trimmedPrompt))
            let text = response.completionText.trimmingCharacters(in: .whitespacesAndNewlines)
            activeSession.messages.append(AIMessage(role: "assistant", content: text))
            activeSession.lastResponse = text
            activeSession.updatedAt = Date()
            tracker.record(prompt: trimmedPrompt, response: text, tokenUsage: response.tokenUsage, mode: usageMode)
            return text
        } catch {
            activeSession.lastErrorMessage = CodexErrorHandler.userFacingMessage(for: error)
            throw error
        }
    }

    func streamResponse(handler: @escaping (String) -> Void) {
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

    func cancelRequest() {
        activeTask?.cancel()
        activeTask = nil
        isRequestInFlight = false
    }

    func resetSession() {
        cancelRequest()
        activeSession = CodexSession()
        streamedText = ""
        tracker.recordSessionReset()
    }

    private func enforceRestrictionsIfNeeded(prompt: String) throws {
        guard usageMode == .restrictedAppControlled else { return }
        if tracker.requestCount >= appOwnedRequestLimit {
            throw LLMError.rateLimited
        }
        let estimatedPromptTokens = max(1, Int((Double(prompt.count) / 4.0).rounded(.up)))
        if tracker.estimatedTotalTokens + estimatedPromptTokens > appOwnedTokenLimit {
            throw LLMError.rateLimited
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
