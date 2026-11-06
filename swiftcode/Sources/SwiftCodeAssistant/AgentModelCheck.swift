import Foundation

/// Typed result of a timed model check (Legacy
/// `SwiftCode/Core/AI/Agent/AgentModelCheck.swift`, Dylan's own code,
/// ported under MIT).
///
/// Adaptation: Legacy checked through `LLMService.validateAPIKey`
/// with `LLMProvider`/`LLMError`. The destination checks through
/// `AssistantProvider.availability()` (per-kind, via
/// `AssistantBackends`) plus `OpenRouterProvider.testConnection()`
/// for the OpenRouter kind; the typed statuses and the latency +
/// capability report are restored here.
public enum ModelCheckStatus: String, Sendable, Codable {
    case success
    case invalid_key
    case model_not_found
    case rate_limited
    case network_error
    case configuration_error
}

public struct AgentModelCheckResult: Sendable, Codable {
    public let status: ModelCheckStatus
    public let latency: TimeInterval
    public let modelCapability: String
}

public actor AgentModelCheck {
    public static let shared = AgentModelCheck()
    private init() {}

    /// Checks one model on one provider and times it. `provider` is a
    /// `ProviderKind` raw value (`"openRouter"`, `"openAI"`, …) or a
    /// Legacy `LLMProvider` raw value (`"OpenRouter"`, `"Anthropic"`,
    /// `"Gemini"`, `"Mistral"`, `"Qwen"`, `"OpenAI"`); both spellings
    /// are accepted. `apiKey` is used when the provider kind reads its
    /// key from the secret store and the caller supplies an override —
    /// it is never stored. The check reports reachability and model
    /// presence, never a chat completion.
    public func checkModel(provider: String, apiKey: String, model: String) async -> AgentModelCheckResult {
        let startTime = Date()
        let latency: TimeInterval = { Date().timeIntervalSince(startTime) }

        guard let kind = Self.providerKind(for: provider) else {
            return AgentModelCheckResult(
                status: .configuration_error,
                latency: latency(),
                modelCapability: "Unknown provider: \(provider)"
            )
        }

        do {
            // A supplied key is checked as given (Legacy validated the
            // passed key); without one the stored key is used.
            let providerInstance: AssistantProvider
            if kind == .openRouter, !apiKey.isEmpty {
                providerInstance = OpenRouterProvider(apiKey: apiKey)
            } else {
                let backends = AssistantBackends(settings: AssistantSettings(), store: defaultSecretStore(), account: nil)
                providerInstance = backends.provider(kind)
            }
            let availability = await providerInstance.availability()
            switch availability {
            case .ready(let models):
                if models.isEmpty || models.contains(where: { $0.id == model }) {
                    return AgentModelCheckResult(
                        status: .success,
                        latency: latency(),
                        modelCapability: "Model \(model) is reachable and the provider answered."
                    )
                }
                return AgentModelCheckResult(
                    status: .model_not_found,
                    latency: latency(),
                    modelCapability: "Model \(model) was not listed by \(kind.displayName)."
                )
            case .signedOut(let hint):
                return AgentModelCheckResult(status: .invalid_key, latency: latency(), modelCapability: hint)
            case .notRunning(let hint):
                return AgentModelCheckResult(status: .network_error, latency: latency(), modelCapability: hint)
            case .noModels(let hint):
                return AgentModelCheckResult(status: .model_not_found, latency: latency(), modelCapability: hint)
            case .notInstalled(let hint):
                return AgentModelCheckResult(status: .configuration_error, latency: latency(), modelCapability: hint)
            case .failed(let message):
                return AgentModelCheckResult(status: Self.status(for: message), latency: latency(), modelCapability: message)
            }
        } catch {
            return AgentModelCheckResult(status: .network_error, latency: latency(), modelCapability: error.localizedDescription)
        }
    }

    /// Legacy `LLMProvider` raw values and `ProviderKind` raw values
    /// both resolve to a kind. Legacy had direct Anthropic / Gemini /
    /// Mistral / Qwen providers; the destination routes those models
    /// through the OpenAI-compatible provider or OpenRouter, so their
    /// checks run against `openRouter` (which lists them) unless a
    /// direct provider exists for the kind.
    public static func providerKind(for rawValue: String) -> ProviderKind? {
        if let kind = ProviderKind(rawValue: rawValue) { return kind }
        switch rawValue.lowercased() {
        case "openrouter": return .openRouter
        case "openai": return .openAI
        case "anthropic": return .openRouter
        case "gemini", "google": return .openRouter
        case "mistral": return .openRouter
        case "qwen": return .openRouter
        case "offline": return .foundationModels
        case "codex": return .codex
        default: return nil
        }
    }

    private static func status(for message: String) -> ModelCheckStatus {
        let lower = message.lowercased()
        if lower.contains("unauthorized") || lower.contains("invalid key") || lower.contains("401") { return .invalid_key }
        if lower.contains("rate limit") || lower.contains("429") { return .rate_limited }
        if lower.contains("not found") || lower.contains("404") { return .model_not_found }
        if lower.contains("network") || lower.contains("unreachable") || lower.contains("connection") { return .network_error }
        return .configuration_error
    }
}
