import Foundation

// MARK: - One-shot text completion for MCP tools (gap-closure: LLM wiring)
//
// The MCP tools that need an LLM — `code_refactor`, `code_review`, the
// Agentic `generate_code` / `refactor_code` / `review_code` / `fix_bugs` /
// `generate_unit_tests` / `generate_integration_tests` /
// `generate_documentation` / `generate_comments`, and `intel_autofix` —
// were registered with honest failures because Ycode's MCP host had no
// LLM provider wired for them (Waves 2, 6, 8). This service wires them
// to the real Wave 9 providers through the Assist host's own dispatch
// (`AssistantBackends.provider(_:)` / `providerKind(forModelID:)`, Wave 15
// router rules) — never a parallel client, never a parallel registry.
//
// Behaviour sources (Dylan's own code, direct port authorised under MIT):
//   * Legacy `SwiftCode/Backend/Assist/Tools/AssistRefactorTool.swift` —
//     `code_refactor` prompts an LLM with the file + action and writes
//     back only the modified code (OpenAI + stored key in Legacy).
//   * Legacy `SwiftCode/Backend/Assist/Tools/CodeReview.swift` —
//     `code_review` sends the task context to an LLM and requires a JSON
//     verdict with status `task_ready` or `task_failed`.
//   * Legacy `SwiftCode/Backend/Assist/Tools/AssistAutoFixErrorsTool.swift`
//     — `intel_autofix` runs `lint_project`, then asks an LLM to rewrite
//     the file, and writes back only the fixed code.
//   * Legacy `SwiftCode/Tools/Agentic/GenerateCode.swift`,
//     `RefactorCode.swift`, `ReviewCode.swift`, `FixBugs.swift`,
//     `GenerateUnitTests.swift`, `GenerateIntegrationTests.swift`,
//     `GenerateDocumentation.swift`, `GenerateComments.swift` — the
//     Agentic tools return canned strings in Legacy (a stub, a canned
//     "LGTM!", the input unchanged with a comment); the port sends the
//     same request to the real provider instead of reproducing the fake.
//   * Legacy `SwiftCode/Tools/Agentic/ExplainCode.swift` really calls
//     OpenRouter; `explain_code` is NOT wired here — its Wave 8 static
//     explanation stands (out of scope for this slice).
//
// Provider selection (Wave 15 router, `AssistModelRouting.swift`):
// the provider + model chosen in Settings win. A stored model id routes
// through `AssistantBackends.providerKind(forModelID:)` so prefixed ids
// (`hermes:`, `opencode:`, `swiftcode-cloud:`) can never be misrouted to
// another provider. The SwiftCode Cloud toggle (`useSwiftCodeCloudModel`)
// short-circuits to the cloud model, as the router does. No provider and
// no model is ever hardcoded: Legacy's `code_review` fallback queue
// (hardcoded `gpt-4o`, `claude-3.5-sonnet`, …) is deliberately NOT ported
// — a failed turn fails honestly instead of silently substituting a model
// the user did not choose (router failover across models is a later wave's
// follow-up; see the spec).
//
// Honest failure is the contract: when no provider is usable the service
// throws naming the provider and what is missing (an API key, a running
// server, an endpoint URL, an installed CLI, Apple Intelligence); when a
// provider fails mid-request the error names the provider and the failure;
// when the model returns nothing the error says so. Nothing is ever
// generated from canned text. Callers in YcodeMCP translate these errors
// into `MCPToolError`s that keep the words "unavailable" and "LLM" so the
// existing honest-failure tests keep passing while unconfigured.
//
// There is no network call, no credential access, and no model call in
// `resolve()`: it only reads settings. `complete()` performs exactly one
// `AssistantProvider.send` through the resolved provider.

/// What a one-shot LLM completion returns.
public struct LLMToolCompletion: Sendable, Equatable {
    /// The model's full reply text (text events concatenated).
    public var text: String
    /// The provider that answered.
    public var provider: ProviderKind
    /// The model id sent with the request, when one was configured.
    public var model: String?
    /// True when the provider stopped at the output limit.
    public var truncated: Bool

    public init(text: String, provider: ProviderKind, model: String?, truncated: Bool) {
        self.text = text
        self.provider = provider
        self.model = model
        self.truncated = truncated
    }
}

/// Why a tool LLM call could not produce output. Every description names
/// the LLM provider involved, so MCP callers can surface it verbatim.
public enum LLMToolError: Error, LocalizedError, Equatable {
    /// The configured provider cannot be used now (not signed in, not
    /// running, not installed, no endpoint configured, no models).
    case providerUnavailable(provider: ProviderKind, detail: String)
    /// The provider answered with an error, or the stream failed.
    case providerFailed(provider: ProviderKind, detail: String)
    /// The selected model is barred by the "Only Use Free Models" policy.
    case ineligibleModel(model: String, provider: ProviderKind?)
    /// The provider answered, but with no text at all.
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

/// One-shot text completion for MCP tools, through the Assist host's
/// provider dispatch.
public struct LLMToolCompletionService: Sendable {
    /// The host's back ends (settings + secret store + account).
    public var backends: AssistantBackends
    /// Test / host overrides, by provider kind (the host's
    /// `CodingAssistantServices.providerOverride`, evaluated once per
    /// kind by the MCP accessor). Empty in production.
    public var providerOverrides: [ProviderKind: AssistantProvider]

    public init(backends: AssistantBackends, providerOverrides: [ProviderKind: AssistantProvider] = [:]) {
        self.backends = backends
        self.providerOverrides = providerOverrides
    }

    /// The provider + model a tool call uses (Wave 15 router rules; see
    /// the file header). Order: the SwiftCode Cloud model when the cloud
    /// toggle names one (or the provider itself is SwiftCode Cloud); the
    /// model stored for the configured provider, routed by its id; the
    /// free-text custom model id; otherwise the configured provider with
    /// no model (the provider's default). Throws
    /// `.ineligibleModel` when "Only Use Free Models" bars the selected
    /// model. A provider with no code model is not special-cased here:
    /// these are plain text completions, which every provider serves;
    /// a provider that cannot serve one reports it through
    /// `availability()` / `send(_:)`.
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

    /// The provider for a resolved kind: a test/host override first,
    /// otherwise the host's dispatch (`AssistantBackends.provider(_:)`).
    public func provider(for kind: ProviderKind) -> AssistantProvider {
        providerOverrides[kind] ?? backends.provider(kind)
    }

    /// Sends one text completion through the configured provider and
    /// collects the reply. Checks `availability()` first so a missing
    /// key / server / endpoint / CLI fails with the provider's own
    /// recovery hint instead of a bare transport error. Throws
    /// `LLMToolError` on every failure path; never returns canned text.
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

    /// An error's message plus its recovery suggestion, when it has one.
    nonisolated static func describe(_ error: Error) -> String {
        var detail = error.localizedDescription
        if let assistant = error as? AssistantError,
           let hint = assistant.recoverySuggestion, !hint.isEmpty {
            detail += " \(hint)"
        }
        return detail
    }
}
