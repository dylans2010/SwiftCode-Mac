import Foundation

public struct LLMToolCompletion: Sendable, Equatable {
    public var text: String
    public var provider: ProviderKind
    public var model: String?
    public var truncated: Bool

    public init(text: String, provider: ProviderKind, model: String?, truncated: Bool) {
        self.text = text
        self.provider = provider
        self.model = model
        self.truncated = truncated
    }
}

public enum LLMToolError: Error, LocalizedError, Equatable {
    case providerUnavailable(provider: ProviderKind, detail: String)
    case providerFailed(provider: ProviderKind, detail: String)
    case ineligibleModel(model: String, provider: ProviderKind?)
    case emptyResponse(provider: ProviderKind, model: String?)

    public var errorDescription: String? {
        switch self {
        case .providerUnavailable(let provider, let detail):
            return "no LLM provider is usable: \(provider.displayName) — \(detail)"
        case .providerFailed(let provider, let detail):
            return "the \(provider.displayName) LLM provider failed: \(detail)"
        case .ineligibleModel(let model, let provider):
            let providerText = provider.map { " on provider '\($0.displayName)'" } ?? ""
            return "the LLM model '\(model)'\(providerText) is ineligible under the 'Only Use Free Models' policy. The model ID must contain 'free' (case-insensitive)."
        case .emptyResponse(let provider, let model):
            let modelText = model.map { " (model '\($0)')" } ?? ""
            return "the \(provider.displayName) LLM provider returned an empty response\(modelText)."
        }
    }
}

public struct LLMToolCompletionService: Sendable {
    public var backends: AssistantBackends
    public var providerOverrides: [ProviderKind: AssistantProvider]

    public init(backends: AssistantBackends, providerOverrides: [ProviderKind: AssistantProvider] = [:]) {
        self.backends = backends
        self.providerOverrides = providerOverrides
    }

    public func resolve() throws -> (kind: ProviderKind, model: String?) {
        let settings = backends.settings
        let kind: ProviderKind
        let model: String?
        if settings.provider == .scCloud {
            kind = .scCloud
            let stored = settings.model(for: .scCloud)
            model = (stored?.isEmpty == false) ? stored : nil
        } else if settings.useSwiftCodeCloudModel,
                  let cloudModel = settings.model(for: .scCloud),
                  !cloudModel.isEmpty {
            kind = .scCloud
            model = cloudModel
        } else if let stored = settings.model(for: settings.provider), !stored.isEmpty {
            kind = backends.providerKind(forModelID: stored)
            model = stored
        } else if !settings.customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let custom = settings.customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            kind = backends.providerKind(forModelID: custom)
            model = custom
        } else {
            kind = settings.provider
            model = nil
        }
        if let model, settings.onlyUseFreeModels,
           !AssistModelEligibilityPolicy.isEligible(modelID: model, onlyUseFreeModels: true) {
            throw LLMToolError.ineligibleModel(model: model, provider: kind)
        }
        return (kind, model)
    }

    public func provider(for kind: ProviderKind) -> AssistantProvider {
        providerOverrides[kind] ?? backends.provider(kind)
    }

    public func complete(systemPrompt: String, userText: String) async throws -> LLMToolCompletion {
        let resolved = try resolve()
        let provider = provider(for: resolved.kind)
        let availability = await provider.availability()
        guard availability.isReady else {
            throw LLMToolError.providerUnavailable(
                provider: resolved.kind,
                detail: availability.hint ?? "The provider is not ready.")
        }
        let request = ChatRequest(
            model: resolved.model,
            instructions: systemPrompt,
            messages: [ChatMessage(.user, userText)],
            generation: .assistantDefault)
        var text = ""
        var truncated = false
        do {
            for try await event in provider.send(request) {
                switch event {
                case .text(let delta): text += delta
                case .truncated: truncated = true
                case .activity, .finished: break
                }
            }
        } catch {
            throw LLMToolError.providerFailed(
                provider: resolved.kind, detail: Self.describe(error))
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMToolError.emptyResponse(provider: resolved.kind, model: resolved.model)
        }
        return LLMToolCompletion(text: text, provider: resolved.kind, model: resolved.model, truncated: truncated)
    }

    nonisolated static func describe(_ error: Error) -> String {
        var detail = error.localizedDescription
        if let assistant = error as? AssistantError,
           let hint = assistant.recoverySuggestion, !hint.isEmpty {
            detail += " \(hint)"
        }
        return detail
    }
}
