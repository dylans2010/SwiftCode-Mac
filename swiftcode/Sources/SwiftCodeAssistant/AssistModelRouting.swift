import Foundation

// MARK: - SDK provider paths / router / selection (Wave 15)
//
// Ported from Legacy (Dylan's own code; direct port authorised under
// MIT, spec-first where it costs nothing):
//   * `SwiftCode/Backend/Assist/AssistModels.swift` —
//     `AgentModelContextBudget`, `AssistModelEligibilityPolicy`.
//   * `SwiftCode/Backend/Assist/AgentModelAdapter.swift` —
//     `ModelCapabilities`, `ModelSpecification`,
//     `specification(for:)`, `contextBudget(for:)`,
//     `normalizePrompt`.
//   * `SwiftCode/Backend/Assist/AssistProviderConfiguration.swift` —
//     `OpenCodeModelID`, `OpenCodeConfiguration`
//     (`swiftcodeAgentDefinition` verbatim).
//   * `SwiftCode/Backend/Assist/HermesProvider.swift` — `HermesModelID`.
//   * `SwiftCode/Backend/Assist/AssistModelRouter.swift` — selection,
//     ranking, eligibility, failure classification, quarantine,
//     failover, continuation prompts.
//   * `SwiftCode/Backend/Assist/AssistModelManager.swift` — the
//     custom-model ID is `AssistantSettings.customModelID`; the
//     singleton itself (ObservableObject, OfflineFallbackManager
//     health) is not ported.
//   * `SwiftCode/Backend/Assist/AssistModelEligibilityPolicy.swift` —
//     a forwarding file; the policy lives here.
//
// This wires into SwiftCode's existing Assist host dispatch —
// `AssistantBackends.provider(_:)` / `providerKind(forModelID:)` —
// and never builds a second dispatcher, a parallel registry, a
// transplanted session loop, or Autopilot. It does not send a
// request itself: it picks the provider + model, and the host's
// `AssistantProvider.send` does the work. There is no LLM call,
// no network call, and no credential access in this file.
//
// Deliberate adaptations (the host has no Antigravity SDK):
//   * Legacy's provider enum (`AssistModelProvider`: openAI,
//     anthropic, gemini, mistral, meta, kimi, openRouter, openCode,
//     hermes, codex) is replaced by SwiftCode's `ProviderKind`.
//     Vendors SwiftCode has no direct provider for (Anthropic, Gemini,
//     Mistral, Kimi, DeepSeek, the Meta vendor API) map to
//     `.openRouter`, the host that can serve those models — the
//     same fallback Legacy's own `llmProvider` mapping used for
//     meta/kimi (`.openRouter`). `codex` maps to `.codex`,
//     `ollama`/`lmstudio` to `.ollama`, Apple/Foundation to
//     `.foundationModels`.
//   * Legacy's routing strategies `"default"` / `"rotation"` /
//     `"app_models"` were Antigravity-SDK strategies: the first two
//     restricted selection to the SDK's live model catalog. SwiftCode
//     now has that catalog (`AntigravitySDKCatalog`, Wave 16),
//     so `selectModelForSDK` restricts `"default"` / `"rotation"`
//     to it again; the plain router paths (`resolveDefaultModel`,
//     `eligibleCandidates`) still take the discovered set, and
//     `"rotation"` (and any unknown value) still decodes to
//     `.providerDefault` here because key rotation is a failover
//     behaviour, not a selection strategy (see
//     `handleTurnFailureWithKeyRotation`).
//   * `buildSDKConfiguration(for:)` (Legacy) is ported as
//     `SDKSessionConfiguration` + `AssistModelRouter.
//     selectModelForSDK` in `AssistSDKModelSelection.swift`:
//     the SwiftCode equivalent is `ChatRequest` + the chosen
//     `ProviderKind`, with the SDK session's model, thinking
//     level and execution mode carried in the configuration.
//     There is no `GoogleCloudSDKConfiguration` and no
//     Antigravity SDK session in SwiftCode, so the fields that only
//     a live SDK session consumes (vertex/project/location,
//     skills paths, workspaces, LiteRT) are not carried over.
//   * Gemini key rotation (`AlternativeKeyManager`) is ported
//     as `GeminiKeyRotationManager` in `GeminiKeyRotation.swift`,
//     and the failover branch that rotates a key before failing
//     over to the next model is `AssistModelRouter.
//     handleTurnFailureWithKeyRotation` (see
//     `AssistSDKModelSelection.swift`). The plain
//     `handleTurnFailure` below still fails over to the next
//     model, as before, when no rotation manager is supplied.
//     Google OAuth (`GoogleAccountAuthService`) is NOT ported
//     here: the router takes an `isGoogleOAuthAuthenticated`
//     flag from the host instead of owning the session.
//   * Failure classification is text-only. Legacy also matched
//     `NSURLErrorDomain` codes; this portable target does not
//     import FoundationNetworking, and the text checks
//     ("timed out", "network", "cannot connect") cover the same
//     cases.
//   * Legacy's `AssistModelRouter` was a `@MainActor` singleton
//     (`AssistModelRouter.shared`) with `@Observable` state for
//     SwiftUI. Here it is an actor: callers create one (the host
//     owns it) and the pure rules are `static`, so tests can call
//     them without an instance.

// MARK: - Model capabilities

/// What a model can do (Legacy `AgentModelAdapter.ModelCapabilities`).
public struct ModelCapabilities: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let toolCalling = ModelCapabilities(rawValue: 1 << 0)
    public static let streaming = ModelCapabilities(rawValue: 1 << 1)
    public static let structuredOutput = ModelCapabilities(rawValue: 1 << 2)
    public static let reasoning = ModelCapabilities(rawValue: 1 << 3)
    public static let vision = ModelCapabilities(rawValue: 1 << 4)
    public static let largeContext = ModelCapabilities(rawValue: 1 << 5)
    public static let parallelToolCalls = ModelCapabilities(rawValue: 1 << 6)
    public static let codeGeneration = ModelCapabilities(rawValue: 1 << 7)
    public static let systemInstructions = ModelCapabilities(rawValue: 1 << 8)
    public static let subagents = ModelCapabilities(rawValue: 1 << 9)
    public static let backgroundExecution = ModelCapabilities(rawValue: 1 << 10)

    public static let longContext: ModelCapabilities = .largeContext

    public static let standardCloud: ModelCapabilities = [
        .toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions, .subagents
    ]

    public static let advancedReasoning: ModelCapabilities = [
        .toolCalling, .streaming, .structuredOutput, .reasoning, .largeContext, .parallelToolCalls, .codeGeneration, .systemInstructions, .subagents
    ]

    public static let localFoundation: ModelCapabilities = [
        .codeGeneration, .structuredOutput
    ]
}

// MARK: - Model specification (name-based catalog)

/// A known model's specification (Legacy `AgentModelAdapter.ModelSpecification`).
public struct ModelSpecification: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let displayName: String
    public let provider: ProviderKind
    public let contextWindowTokens: Int
    public let capabilities: ModelCapabilities
    public let defaultTemperature: Double

    public init(
        id: String,
        displayName: String,
        provider: ProviderKind,
        contextWindowTokens: Int = 128_000,
        capabilities: ModelCapabilities = .standardCloud,
        defaultTemperature: Double = 0.2
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.contextWindowTokens = contextWindowTokens
        self.capabilities = capabilities
        self.defaultTemperature = defaultTemperature
    }
}

/// The canonical registry of known model specifications and
/// capabilities (Legacy `AgentModelAdapter.specification(for:)`).
///
/// Prefix rules run first: a stored `opencode:anthropic/claude-…`
/// id would otherwise match the `claude` branch below and be
/// misreported (and misrouted) as a direct Anthropic model. The
/// `hermes:` and `swiftcode-cloud:` branches are SwiftCode additions:
/// Legacy had no `hermes:` branch (a Hermes id fell through to the
/// OpenRouter default, which its own fail-closed guards then had
/// to catch) and routed cloud ids through a separate short-circuit
/// in the router.
public enum AssistModelSpecification {
    public static func specification(for modelId: String) -> ModelSpecification {
        // OpenCode first (see above). Context is a conservative
        // 128k default: the underlying OpenCode model's true limit
        // varies, and specification() is synchronous so it cannot
        // consult the server's catalog here.
        if let openCode = OpenCodeModelID.parse(modelId) {
            return ModelSpecification(
                id: modelId,
                displayName: openCode.displayName,
                provider: .openCode,
                contextWindowTokens: 128_000,
                capabilities: .standardCloud
            )
        }
        // Hermes: the spec after the prefix is the model Hermes
        // itself runs; the host's Hermes provider owns the run.
        if let hermes = HermesModelID.parse(modelId) {
            return ModelSpecification(
                id: modelId,
                displayName: hermes.spec,
                provider: .hermes,
                contextWindowTokens: 128_000,
                capabilities: .standardCloud
            )
        }
        // SwiftCode Cloud: a direct (non-agentic) chat model.
        if SCCloudProvider.isCloudModelID(modelId) {
            let endpointName = SCCloudProvider.endpointName(forInternalID: modelId)
            return ModelSpecification(
                id: modelId,
                displayName: endpointName ?? SCCloudProvider.displayNameFallback,
                provider: .scCloud,
                contextWindowTokens: 128_000,
                capabilities: [.structuredOutput, .systemInstructions, .codeGeneration, .largeContext]
            )
        }

        let lower = modelId.lowercased()

        if lower.contains("claude") || lower.contains("anthropic") {
            let displayName: String
            if lower.contains("3-7") || lower.contains("3.7") {
                displayName = "Claude 3.7 Sonnet"
            } else if lower.contains("haiku") {
                displayName = "Claude 3.5 Haiku"
            } else if lower.contains("opus") {
                displayName = "Claude 3 Opus"
            } else {
                displayName = "Claude 3.5 Sonnet"
            }
            return ModelSpecification(
                id: modelId,
                displayName: displayName,
                provider: .openRouter,
                contextWindowTokens: 200_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .vision, .largeContext, .codeGeneration, .systemInstructions, .subagents]
            )
        } else if lower.contains("gpt") || lower.contains("o1") || lower.contains("o3") || lower.contains("chatgpt") || lower.contains("openai") {
            let displayName: String
            if lower.contains("o3-mini") {
                displayName = "o3-mini"
            } else if lower.contains("o1") {
                displayName = "o1"
            } else if lower.contains("gpt-4o-mini") {
                displayName = "GPT-4o Mini"
            } else {
                displayName = "GPT-4o"
            }
            return ModelSpecification(
                id: modelId,
                displayName: displayName,
                provider: .openAI,
                contextWindowTokens: 128_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .vision, .largeContext, .parallelToolCalls, .codeGeneration, .systemInstructions, .subagents]
            )
        } else if lower.contains("gemini") {
            let displayName = lower.contains("flash") ? "Gemini 3.8 Flash" : "Gemini 3.8 Pro"
            return ModelSpecification(
                id: modelId,
                displayName: displayName,
                provider: .openRouter,
                contextWindowTokens: 1_000_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions, .subagents]
            )
        } else if lower.contains("mistral") || lower.contains("codestral") || lower.contains("pixtral") {
            let displayName = lower.contains("codestral") ? "Codestral" : "Mistral Large"
            return ModelSpecification(
                id: modelId,
                displayName: displayName,
                provider: .openRouter,
                contextWindowTokens: 128_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions, .subagents]
            )
        } else if lower.contains("deepseek") {
            return ModelSpecification(
                id: modelId,
                displayName: "DeepSeek V3",
                provider: .openRouter,
                contextWindowTokens: 64_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions, .subagents]
            )
        } else if lower.contains("codex") {
            return ModelSpecification(
                id: modelId,
                displayName: "Codex Local Bridge",
                provider: .codex,
                contextWindowTokens: 32_000,
                capabilities: [.codeGeneration, .structuredOutput]
            )
        } else if lower.contains("ollama") || lower.contains("lmstudio") {
            return ModelSpecification(
                id: modelId,
                displayName: modelId,
                provider: .ollama,
                contextWindowTokens: 32_000,
                capabilities: [.toolCalling, .streaming, .codeGeneration, .systemInstructions]
            )
        } else if lower.contains("afm 3 core") || lower.contains("afm-3-core") || lower.contains("apple") || lower.contains("foundation") {
            // NOTE: Legacy disagrees with itself here. This branch
            // (the adapter) says 8,192; the router's Apple Foundation
            // synthetic model says 16,000. Both values are preserved
            // in their own paths (`syntheticFoundationModel` uses
            // 16,000); a Mac check should settle which is real.
            return ModelSpecification(
                id: modelId,
                displayName: "Apple Foundation Models",
                provider: .foundationModels,
                contextWindowTokens: 8_192,
                capabilities: .localFoundation
            )
        }

        return ModelSpecification(
            id: modelId,
            displayName: modelId,
            provider: .openRouter,
            contextWindowTokens: 128_000,
            capabilities: .standardCloud
        )
    }

    /// The context budget for a model id (Legacy `contextBudget(for:)`).
    public static func contextBudget(for modelId: String) -> AgentModelContextBudget {
        let spec = specification(for: modelId)
        return AgentModelContextBudget(
            modelId: modelId,
            contextWindowTokens: spec.contextWindowTokens
        )
    }

    /// Normalizes outgoing prompt structure based on model
    /// capabilities (Legacy `normalizePrompt`). Models without
    /// native system instructions get the system prompt merged
    /// into the user instruction block instead.
    public static func normalizePrompt(systemPrompt: String, userInstructions: String, for modelId: String) -> String {
        let spec = specification(for: modelId)
        if spec.capabilities.contains(.systemInstructions) {
            return "\(systemPrompt)\n\n# TASK EXECUTION INSTRUCTIONS\n\(userInstructions)"
        } else {
            return "SYSTEM DIRECTIVES:\n\(systemPrompt)\n\nUSER REQUEST:\n\(userInstructions)"
        }
    }
}

// MARK: - Context budget

/// A model's context budget (Legacy `AgentModelContextBudget`).
public struct AgentModelContextBudget: Sendable, Equatable {
    public let modelId: String
    public let contextWindowTokens: Int
    public let reservedOutputTokens: Int
    public let maxInputTokens: Int
    public let utilizationRatio: Double

    public init(modelId: String, contextWindowTokens: Int, reservedOutputTokens: Int = 4096) {
        self.modelId = modelId
        self.contextWindowTokens = contextWindowTokens
        self.reservedOutputTokens = reservedOutputTokens
        self.maxInputTokens = max(1024, contextWindowTokens - reservedOutputTokens)
        self.utilizationRatio = Double(reservedOutputTokens) / Double(contextWindowTokens)
    }

    public func fitsContext(estimatedTokens: Int) -> Bool {
        estimatedTokens <= maxInputTokens
    }

    public func estimatedTokenCount(for text: String) -> Int {
        text.count / 4
    }
}

// MARK: - Free-only eligibility policy

/// Errors for the free-only policy (Legacy `AssistModelEligibilityError`).
public enum AssistModelEligibilityError: LocalizedError, Equatable {
    case ineligibleModel(modelID: String, provider: String?)
    case noEligibleFreeModelAvailable(provider: String?)

    public var errorDescription: String? {
        switch self {
        case .ineligibleModel(let modelID, let provider):
            let provStr = provider.map { " on provider '\($0)'" } ?? ""
            return "Model '\(modelID)'\(provStr) is ineligible under the 'Only Use Free Models' policy. The model ID must contain 'free' (case-insensitive)."
        case .noEligibleFreeModelAvailable(let provider):
            let provStr = provider.map { " for provider '\($0)'" } ?? ""
            return "No eligible free model is available\(provStr). Please disable 'Only Use Free Models' or select a provider that offers free models."
        }
    }
}

/// The "Only Use Free Models" policy (Legacy `AssistModelEligibilityPolicy`).
public struct AssistModelEligibilityPolicy {
    /// A model is eligible in free-only mode ONLY when its actual
    /// model ID contains the literal substring "free"
    /// (case-insensitive). Display names, marketing titles, or
    /// price tags alone NEVER override this rule.
    public static func isEligible(modelID: String, onlyUseFreeModels: Bool) -> Bool {
        guard onlyUseFreeModels else { return true }
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.localizedCaseInsensitiveContains("free")
    }

    /// Validates model eligibility at runtime before execution.
    public static func validateExecutionEligibility(modelID: String, provider: String? = nil, onlyUseFreeModels: Bool) throws {
        guard onlyUseFreeModels else { return }
        if !isEligible(modelID: modelID, onlyUseFreeModels: true) {
            throw AssistModelEligibilityError.ineligibleModel(modelID: modelID, provider: provider)
        }
    }

    /// Filters an array of model identifiers according to the policy.
    public static func filterEligibleModelIDs(_ modelIDs: [String], onlyUseFreeModels: Bool) -> [String] {
        guard onlyUseFreeModels else { return modelIDs }
        return modelIDs.filter { isEligible(modelID: $0, onlyUseFreeModels: true) }
    }

    /// Filters an arbitrary collection of models by their identifier.
    public static func filterEligible<T>(_ models: [T], onlyUseFreeModels: Bool, idKeyPath: KeyPath<T, String>) -> [T] {
        guard onlyUseFreeModels else { return models }
        return models.filter { isEligible(modelID: $0[keyPath: idKeyPath], onlyUseFreeModels: true) }
    }

    /// Filters models using a closure to extract the model ID.
    public static func filterEligible<T>(_ models: [T], onlyUseFreeModels: Bool, idExtractor: (T) -> String) -> [T] {
        guard onlyUseFreeModels else { return models }
        return models.filter { isEligible(modelID: idExtractor($0), onlyUseFreeModels: true) }
    }
}

// MARK: - Stored model identifiers

/// A model selected through the OpenCode provider (Legacy `OpenCodeModelID`).
///
/// Stored in `selectedAssistModelID` as `opencode:<providerID>/<modelID>`
/// (for example `opencode:anthropic/claude-sonnet-4-5`). The prefix is
/// deliberate: bare `provider/model` identifiers already route to
/// OpenRouter, so an unprefixed OpenCode model would be silently sent
/// to the wrong provider. Nothing here ever strips the prefix and
/// re-routes the model elsewhere.
public struct OpenCodeModelID: Equatable, Sendable {
    public let providerID: String
    public let modelID: String

    public var storedID: String { "opencode:\(providerID)/\(modelID)" }
    public var displayName: String { "\(providerID)/\(modelID)" }

    public init(providerID: String, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }

    /// Parses a stored `opencode:` model identifier. Returns nil for
    /// any other provider's identifier, including bare OpenRouter
    /// `a/b` ids.
    public static func parse(_ storedID: String) -> OpenCodeModelID? {
        guard storedID.hasPrefix("opencode:") else { return nil }
        let remainder = String(storedID.dropFirst("opencode:".count))
        guard let slash = remainder.firstIndex(of: "/") else { return nil }
        let providerID = String(remainder[..<slash])
        let modelID = String(remainder[remainder.index(after: slash)...])
        guard !providerID.isEmpty, !modelID.isEmpty else { return nil }
        return OpenCodeModelID(providerID: providerID, modelID: modelID)
    }

    public static func isOpenCodeModelID(_ storedID: String) -> Bool {
        parse(storedID) != nil
    }
}

/// A model selected through the Hermes provider (Legacy `HermesModelID`).
///
/// Stored as `hermes:<spec>` where the spec is a bare model name or
/// a `provider:model` override.
public struct HermesModelID: Equatable, Sendable {
    /// The Hermes model spec after the `hermes:` prefix.
    public let spec: String

    public var storedID: String { "hermes:\(spec)" }

    /// The Hermes provider override, when the spec carries one
    /// (`provider:model`). Nil for a bare model name: Hermes then
    /// uses its configured default provider and SwiftCode must not
    /// invent one.
    public var provider: String? {
        guard let colon = spec.firstIndex(of: ":") else { return nil }
        let value = String(spec[..<colon])
        return value.isEmpty ? nil : value
    }

    /// The model name Hermes receives via --model: the part after the
    /// provider prefix, or the whole spec for a bare model name.
    public var model: String {
        guard let colon = spec.firstIndex(of: ":") else { return spec }
        return String(spec[spec.index(after: colon)...])
    }

    public init(spec: String) {
        self.spec = spec
    }

    /// Parses a stored `hermes:` model identifier. Returns nil for
    /// any other provider's identifier, for an empty spec, and for a
    /// spec whose model part is empty (`hermes:openrouter:`).
    public static func parse(_ storedID: String) -> HermesModelID? {
        guard storedID.hasPrefix("hermes:") else { return nil }
        let spec = String(storedID.dropFirst("hermes:".count))
        guard !spec.isEmpty else { return nil }
        let parsed = HermesModelID(spec: spec)
        guard !parsed.model.isEmpty else { return nil }
        return parsed
    }

    public static func isHermesModelID(_ storedID: String) -> Bool {
        parse(storedID) != nil
    }
}

// MARK: - OpenCode server configuration

/// Persisted OpenCode connection settings (Legacy `OpenCodeConfiguration`).
///
/// Provider model credentials (Anthropic, OpenAI, OpenRouter keys, …)
/// live in OpenCode's own configuration and are never stored, logged,
/// or sent by SwiftCode: SwiftCode only ever talks to the local server, on
/// loopback by default.
///
/// Storage deviation: Legacy read/wrote this from UserDefaults
/// (`opencode.serverURL`, `opencode.agentName`,
/// `opencode.managedServerEnabled`). SwiftCode persists provider
/// configuration in its settings store (`AssistantSettings`, JSON
/// under `SwiftCode.codingAssistant`), so this type bridges to and from
/// `AssistantSettings` instead of touching UserDefaults. The Legacy
/// key names are recorded here only so a future reader can find
/// them: `opencode.serverURL`, `opencode.agentName`,
/// `opencode.managedServerEnabled`.
public struct OpenCodeConfiguration: Equatable, Sendable {
    public static let defaultServerURL = URL(string: "http://127.0.0.1:4096")!
    public static let defaultAgentName = "swiftcode"

    public var serverURL: URL
    /// The OpenCode agent every SwiftCode session names. Must be
    /// configured server-side with all permissions denied (see
    /// `swiftcodeAgentDefinition`); otherwise the server would
    /// execute its own tools instead of returning JSON tool
    /// requests for SwiftCode's dispatcher.
    public var agentName: String
    /// Retained for compatibility with previously saved settings.
    /// The server is now managed automatically for loopback URLs
    /// regardless of this flag: a missing server is started, and a
    /// missing binary is located or installed, without the user
    /// toggling anything.
    public var managedServerEnabled: Bool

    public init(
        serverURL: URL = defaultServerURL,
        agentName: String = defaultAgentName,
        managedServerEnabled: Bool = false
    ) {
        self.serverURL = serverURL
        self.agentName = agentName
        self.managedServerEnabled = managedServerEnabled
    }

    /// Reads the configuration from SwiftCode's settings store.
    public init(settings: AssistantSettings) {
        let url = URL(string: settings.openCodeURL)
        self.init(
            serverURL: url ?? Self.defaultServerURL,
            agentName: settings.openCodeAgentName,
            managedServerEnabled: false
        )
    }

    /// Writes the configuration back into SwiftCode's settings store.
    public func apply(to settings: inout AssistantSettings) {
        settings.openCodeURL = serverURL.absoluteString
        settings.openCodeAgentName = agentName
    }

    /// Port extracted from the server URL, for managed-server startup.
    public var port: Int {
        serverURL.port ?? (serverURL.scheme == "https" ? 443 : 80)
    }

    /// Managed startup is only ever attempted for a loopback server,
    /// so a misconfigured URL cannot make SwiftCode bind or launch a
    /// server that listens on a LAN interface.
    public var isLoopback: Bool {
        guard let host = serverURL.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    /// Agent definition the user installs server-side so OpenCode
    /// acts as a pure model behind SwiftCode's tool loop. Install as
    /// `.opencode/agent/swiftcode.md` in the project (or
    /// `~/.config/opencode/agent/swiftcode.md` globally), or express
    /// the same permissions in `opencode.json` under
    /// `agent.swiftcode`.
    public static let swiftcodeAgentDefinition = """
        ---
        description: SwiftCode Assist model agent. Returns JSON tool requests for SwiftCode to execute; never runs tools itself.
        mode: primary
        permission:
          "*": deny
        ---

        You are the model behind SwiftCode Assist. You do not execute tools.
        Follow the system prompt SwiftCode sends with every request exactly,
        and respond only in the JSON format it specifies (`toolId`/`input`/
        `explanation`, or `finalResponse`). Never read, write, or execute
        anything on the host yourself: SwiftCode validates and runs every
        tool call through its own dispatcher and permission system and
        returns the real result to you on the next turn.
        """
}

// MARK: - Routing strategy

/// How a request picks its model (Legacy
/// `AppSettings.assistModelRoutingStrategy`: `"default"` /
/// `"rotation"` / `"app_models"`).
///
/// Legacy's `"default"` and `"rotation"` restricted selection to
/// the Antigravity SDK's live model catalog (`"rotation"`
/// additionally rotated Gemini API keys). SwiftCode has no Antigravity
/// SDK catalog and no key-rotation system, so both collapse to
/// the discovered set here; `"rotation"` (and any unknown value)
/// decodes to `.providerDefault`. The strategy is still persisted
/// because the distinction matters again if a catalog ever exists.
public enum AssistRoutingStrategy: String, Codable, Sendable, CaseIterable {
    /// Use the provider + model chosen in Settings
    /// (Legacy `"default"`).
    case providerDefault = "default"
    /// Consider every eligible model from every provider
    /// (Legacy `"app_models"`).
    case appModels = "app_models"

    public var displayName: String {
        switch self {
        case .providerDefault: "Provider default"
        case .appModels: "App model catalog"
        }
    }

    /// Lenient decode: `"rotation"` and any unknown value become
    /// `.providerDefault` instead of failing the whole settings
    /// decode.
    public static func lenient(_ raw: String?) -> AssistRoutingStrategy {
        guard let raw else { return .providerDefault }
        return AssistRoutingStrategy(rawValue: raw) ?? .providerDefault
    }
}

// MARK: - Candidate model

/// Where a candidate model came from (Legacy `AssistModelSource`,
/// collapsed to what the router actually decides on).
public enum AssistModelSource: String, Codable, Sendable {
    /// A model fetched from a provider's own list.
    case provider
    /// A user-provided (custom) model.
    case custom
    /// A SwiftCode Cloud model (provider-hosted, not user-provided,
    /// even though Legacy recorded it as `.custom`).
    case cloud
    /// An Apple Foundation Models on-device model.
    case foundation
}

/// One model the router may pick (Legacy `AssistAvailableModel`,
/// reduced to the fields the selection rules read).
///
/// `hasCredentials` is supplied by the caller (the host knows
/// whether a key / sign-in / binary exists for the provider);
/// the router never touches the secret store itself.
public struct AssistCandidateModel: Sendable, Equatable {
    /// The stored model id (what Settings and the router compare).
    public var id: String
    /// The provider-side model identifier.
    public var modelIdentifier: String
    public var displayName: String
    public var provider: ProviderKind
    public var capabilities: ModelCapabilities
    public var contextWindow: Int
    public var supportsStreaming: Bool
    public var supportsToolCalling: Bool
    public var supportsAgenticUse: Bool
    public var supportsSubagents: Bool
    public var supportsVision: Bool
    public var supportsStructuredOutput: Bool
    /// Lower wins (Legacy `priority`).
    public var priority: Int
    public var isConfigured: Bool
    public var hasCredentials: Bool
    public var source: AssistModelSource
    public var statusDescription: String
    /// The endpoint this model talks to, when it is not the
    /// provider's default (Legacy set one for Mistral and Codex).
    public var endpointURL: String?
    /// True when this candidate was synthesized from a catalog
    /// (the Antigravity SDK catalog) rather than discovered from
    /// a provider's list endpoint. Synthetic candidates must
    /// never be presented as discovered models.
    public var isSynthetic: Bool

    public init(
        id: String,
        displayName: String? = nil,
        provider: ProviderKind,
        modelIdentifier: String? = nil,
        capabilities: ModelCapabilities = .standardCloud,
        contextWindow: Int = 128_000,
        supportsStreaming: Bool = true,
        supportsToolCalling: Bool = true,
        supportsAgenticUse: Bool = true,
        supportsSubagents: Bool = false,
        supportsVision: Bool = false,
        supportsStructuredOutput: Bool = true,
        priority: Int = 10,
        isConfigured: Bool = true,
        hasCredentials: Bool = true,
        source: AssistModelSource = .provider,
        statusDescription: String = "",
        endpointURL: String? = nil,
        isSynthetic: Bool = false
    ) {
        self.id = id
        self.modelIdentifier = modelIdentifier ?? id
        self.displayName = displayName ?? id
        self.provider = provider
        self.capabilities = capabilities
        self.contextWindow = contextWindow
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsAgenticUse = supportsAgenticUse
        self.supportsSubagents = supportsSubagents
        self.supportsVision = supportsVision
        self.supportsStructuredOutput = supportsStructuredOutput
        self.priority = priority
        self.isConfigured = isConfigured
        self.hasCredentials = hasCredentials
        self.source = source
        self.statusDescription = statusDescription
        self.endpointURL = endpointURL
        self.isSynthetic = isSynthetic
    }

    /// A candidate built from the name-based specification
    /// (Legacy `resolveDefaultModel`'s spec-synthesis branch).
    public static func fromSpecification(id: String) -> AssistCandidateModel {
        let spec = AssistModelSpecification.specification(for: id)
        let endpointURL: String?
        switch spec.provider {
        case .openRouter where id.lowercased().contains("mistral"):
            endpointURL = "https://api.mistral.ai/v1"
        case .codex:
            endpointURL = "http://localhost:3003/v1"
        default:
            endpointURL = nil
        }
        return AssistCandidateModel(
            id: id,
            displayName: spec.displayName,
            provider: spec.provider,
            modelIdentifier: id,
            capabilities: spec.capabilities,
            contextWindow: spec.contextWindowTokens,
            supportsStreaming: spec.capabilities.contains(.streaming),
            supportsToolCalling: spec.capabilities.contains(.toolCalling),
            supportsAgenticUse: spec.capabilities.contains(.toolCalling),
            supportsSubagents: spec.capabilities.contains(.subagents),
            supportsVision: spec.capabilities.contains(.vision),
            supportsStructuredOutput: spec.capabilities.contains(.structuredOutput),
            priority: 10,
            endpointURL: endpointURL
        )
    }
}

// MARK: - Failure classification

/// Why a turn failed, for quarantine and failover
/// (Legacy `AssistModelRouter.ModelRoutingFailureClass`).
public enum ModelRoutingFailureClass: String, Sendable {
    case rateLimited = "Rate Limited"
    case quotaExhausted = "Quota Exhausted"
    case authenticationFailed = "Authentication Failure"
    case modelUnavailable = "Model Unavailable"
    case providerUnavailable = "Provider Unavailable"
    case networkFailure = "Network Failure"
    case timeout = "Timeout"
    case unsupportedCapability = "Unsupported Capability"
    case malformedResponse = "Malformed Response"
    case internalAntigravityFailure = "Internal Antigravity Failure"
}

/// One failover (Legacy `AssistModelRouter.ModelFailoverEvent`).
public struct ModelFailoverEvent: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let failedModelID: String
    public let failedProviderID: String
    public let newModelID: String
    public let newProviderID: String
    public let failureClass: ModelRoutingFailureClass
    public let reason: String

    public init(
        failedModelID: String,
        failedProviderID: String,
        newModelID: String,
        newProviderID: String,
        failureClass: ModelRoutingFailureClass,
        reason: String
    ) {
        self.failedModelID = failedModelID
        self.failedProviderID = failedProviderID
        self.newModelID = newModelID
        self.newProviderID = newProviderID
        self.failureClass = failureClass
        self.reason = reason
    }
}

// MARK: - Router

/// Intelligent, fault-tolerant model routing and automatic
/// failover (Legacy `AssistModelRouter`), ported onto SwiftCode's
/// Assist host.
///
/// The host owns one router and feeds it candidates: the models
/// its providers actually discovered (from `AssistantBackends`
/// `survey()` / each provider's `availability()`), plus the
/// cloud models when the cloud toggle is on. The router picks
/// one; the host then sends through
/// `AssistantBackends.provider(forModelID:)` — the existing
/// dispatch, never a second one.
///
/// Not ported from the Legacy router: `selectModelForSDK` and
/// `buildSDKConfiguration` (they return a
/// `GoogleCloudSDKConfiguration` for the Antigravity SDK session,
/// which does not exist in SwiftCode); the Gemini key-rotation branch
/// of failover (no `AlternativeKeyManager` in SwiftCode); and the
/// Antigravity SDK catalog behind the `"default"` / `"rotation"`
/// strategies (see `AssistRoutingStrategy`).
public actor AssistModelRouter {
    /// Default quarantine for a 429 / quota failure (Legacy: 60s).
    public static let rateLimitQuarantine: TimeInterval = 60
    /// Quarantine for an authentication failure (Legacy: 10 min).
    public static let authenticationQuarantine: TimeInterval = 600
    /// Quarantine for a model marked unavailable (Legacy: 2 min).
    public static let unavailableQuarantine: TimeInterval = 120

    public init() {}

    /// Quarantined model ids and their un-quarantine dates.
    public private(set) var quarantinedModels: [String: Date] = [:]
    /// Failure counts by model id (ranking penalty).
    public private(set) var failedAttemptsCount: [String: Int] = [:]
    public private(set) var lastFailoverEvent: ModelFailoverEvent?
    public private(set) var failoverHistory: [ModelFailoverEvent] = []

    // MARK: - Model selection

    /// The model for a request (Legacy `resolveDefaultModel`).
    ///
    /// Order: the SwiftCode Cloud short-circuit (never subject to
    /// provider discovery — the selected cloud id is used as-is);
    /// a discovered match; the Apple Foundation synthetic model;
    /// otherwise a model synthesized from the name-based
    /// specification. Discovery is a metadata refresh, not a
    /// prerequisite: the selected model's provider and
    /// capabilities are already known locally, so a normal turn
    /// is never held behind slow/unreachable model-list endpoints.
    public static func resolveDefaultModel(
        preferredID: String,
        discovered: [AssistCandidateModel],
        useCloudModel: Bool,
        cloudConfigured: Bool = false,
        cloudRemainingToday: Int = SCCloudProvider.dailyRequestLimit,
        cloudModels: [AssistCandidateModel] = []
    ) -> AssistCandidateModel {
        if useCloudModel, SCCloudProvider.isCloudModelID(preferredID) {
            return syntheticCloudModel(
                forCloudModelID: preferredID,
                remainingToday: cloudRemainingToday,
                isConfigured: cloudConfigured,
                firstDiscoveredEndpointName: cloudModels.first?.modelIdentifier
            )
        }
        if let match = discovered.first(where: { $0.id == preferredID || $0.modelIdentifier == preferredID }) {
            return match
        }
        if preferredID.lowercased().contains("afm") {
            return syntheticFoundationModel(id: preferredID)
        }
        return AssistCandidateModel.fromSpecification(id: preferredID)
    }

    /// The first eligible candidate (Legacy `resolveSavedModel`).
    public func resolveSavedModel(from eligible: [AssistCandidateModel]) -> AssistCandidateModel? {
        eligible.first
    }

    /// The next model after excluding failures
    /// (Legacy `selectNextModel`).
    public static func selectNextModel(excluding: Set<String>, from candidates: [AssistCandidateModel]) -> AssistCandidateModel? {
        candidates.first { !excluding.contains($0.id) && !excluding.contains($0.modelIdentifier) }
    }

    /// The eligible candidates (Legacy `eligibleCandidates(from:)`).
    ///
    /// A model is eligible when it supports agentic use and tool
    /// calling, is configured, has credentials, is not
    /// quarantined, and — when "Use Provider Models" is on — is
    /// not user-provided. Cloud models join AFTER the agentic
    /// filter (they are direct chat models, not agentic ones), one
    /// entry per discovered cloud model, or one synthetic entry
    /// when none was discovered.
    public func eligibleCandidates(
        from allModels: [AssistCandidateModel],
        strategy: AssistRoutingStrategy,
        useProviderModelsOnly: Bool,
        useCloudModel: Bool,
        cloudModels: [AssistCandidateModel] = [],
        cloudConfigured: Bool = false,
        cloudRemainingToday: Int = SCCloudProvider.dailyRequestLimit
    ) -> [AssistCandidateModel] {
        // Legacy restricted "default" / "rotation" to the
        // Antigravity SDK catalog. SwiftCode has no such catalog, so
        // the strategy does not narrow the set here; the
        // distinction is preserved in the persisted setting (see
        // `AssistRoutingStrategy`).
        _ = strategy
        let eligible = allModels.filter { model in
            guard model.supportsAgenticUse && model.supportsToolCalling else { return false }
            if useProviderModelsOnly, Self.isUserProvidedModel(model) { return false }
            guard model.isConfigured, model.hasCredentials else { return false }
            if let unquarantine = quarantinedModels[model.id], Date() < unquarantine { return false }
            if let unquarantine = quarantinedModels[model.modelIdentifier], Date() < unquarantine { return false }
            return true
        }

        var ranked = Self.rankModels(eligible)
        if useCloudModel {
            ranked.removeAll { SCCloudProvider.isCloudModelID($0.id) }
            if cloudModels.isEmpty {
                ranked.append(Self.syntheticCloudModel(
                    forCloudModelID: SCCloudProvider.internalIDPrefix,
                    remainingToday: cloudRemainingToday,
                    isConfigured: cloudConfigured
                ))
            } else {
                for info in cloudModels {
                    ranked.append(Self.syntheticCloudModel(
                        forCloudModelID: info.id,
                        remainingToday: cloudRemainingToday,
                        isConfigured: cloudConfigured,
                        firstDiscoveredEndpointName: info.modelIdentifier
                    ))
                }
            }
        }
        return ranked
    }

    /// Synthetic model record for the SwiftCode Cloud Model
    /// (Legacy `createSyntheticCloudModel(forCloudModelID:)`).
    /// Returned whenever the cloud toggle is on and this model is
    /// selected, under any routing strategy. Execution bypasses
    /// any agent SDK session; the providerID only needs to avoid
    /// the credential gate of other providers.
    public static func syntheticCloudModel(
        forCloudModelID cloudModelID: String,
        remainingToday: Int,
        isConfigured: Bool = false,
        firstDiscoveredEndpointName: String? = nil
    ) -> AssistCandidateModel {
        let endpointName = SCCloudProvider.endpointName(forInternalID: cloudModelID)
            ?? firstDiscoveredEndpointName
            ?? ""
        let displayName = endpointName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? SCCloudProvider.displayNameFallback
            : endpointName
        return AssistCandidateModel(
            id: cloudModelID,
            displayName: displayName,
            provider: .scCloud,
            modelIdentifier: endpointName,
            capabilities: [.structuredOutput, .systemInstructions, .codeGeneration, .largeContext],
            contextWindow: 128_000,
            supportsStreaming: false,
            supportsToolCalling: false,
            supportsAgenticUse: false,
            supportsSubagents: false,
            supportsVision: false,
            supportsStructuredOutput: true,
            priority: 1,
            isConfigured: isConfigured,
            hasCredentials: true,
            source: .cloud,
            statusDescription: "SwiftCode Cloud · \(remainingToday)/\(SCCloudProvider.dailyRequestLimit) left today"
        )
    }

    /// Synthetic model record for Apple Foundation Models
    /// (Legacy `resolveDefaultModel`'s AFM branch).
    public static func syntheticFoundationModel(id: String) -> AssistCandidateModel {
        AssistCandidateModel(
            id: id,
            displayName: "Apple \(id) (On-Device)",
            provider: .foundationModels,
            modelIdentifier: id,
            capabilities: .localFoundation,
            contextWindow: 16_000,
            supportsStreaming: true,
            supportsToolCalling: false,
            supportsAgenticUse: false,
            supportsSubagents: false,
            supportsVision: id.contains("Advanced"),
            supportsStructuredOutput: true,
            priority: 90,
            isConfigured: true,
            hasCredentials: true,
            source: .foundation,
            statusDescription: "On-Device Available (Chat Mode Only)"
        )
    }

    /// Ranked best-first (Legacy `rankModels`): the user's
    /// preferred model first, then fewest failures, then
    /// provider/model priority (lower wins), then subagent
    /// capability, then the largest context window.
    public static func rankModels(_ models: [AssistCandidateModel], preferredIdentifier: String? = nil) -> [AssistCandidateModel] {
        rankModels(models: models, preferredIdentifier: preferredIdentifier, failedAttemptsCount: [:])
    }

    /// The same ranking with an explicit failure-count table
    /// (the actor's live counts; the one-argument form ranks
    /// with no failure history).
    public static func rankModels(
        models: [AssistCandidateModel],
        preferredIdentifier: String?,
        failedAttemptsCount: [String: Int]
    ) -> [AssistCandidateModel] {
        models.sorted { lhs, rhs in
            let lhsIsPref = (lhs.id == preferredIdentifier || lhs.modelIdentifier == preferredIdentifier)
            let rhsIsPref = (rhs.id == preferredIdentifier || rhs.modelIdentifier == preferredIdentifier)
            if lhsIsPref != rhsIsPref { return lhsIsPref }

            let lhsFailures = failedAttemptsCount[lhs.id] ?? 0
            let rhsFailures = failedAttemptsCount[rhs.id] ?? 0
            if lhsFailures != rhsFailures { return lhsFailures < rhsFailures }

            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }

            if lhs.supportsSubagents != rhs.supportsSubagents { return lhs.supportsSubagents }

            return lhs.contextWindow > rhs.contextWindow
        }
    }

    /// The actor's live ranking: preferred model first, then
    /// fewest failures (from the live failure counts), then
    /// priority, subagents, context window.
    public func ranked(_ models: [AssistCandidateModel], preferredIdentifier: String? = nil) -> [AssistCandidateModel] {
        Self.rankModels(models: models, preferredIdentifier: preferredIdentifier, failedAttemptsCount: failedAttemptsCount)
    }

    // MARK: - Failure classification & quarantine

    /// Whether the error text is a quota / rate-limit failure
    /// (Legacy `isQuotaOrRateLimit`).
    public static func isQuotaOrRateLimit(errorText: String) -> Bool {
        let desc = errorText.lowercased()
        return desc.contains("429") || desc.contains("resource_exhausted") || desc.contains("quota exceeded")
            || desc.contains("rate limit") || desc.contains("rate_limit") || desc.contains("too many requests")
    }

    /// Whether a model is currently quarantined.
    public func isModelQuarantined(modelIdentifier: String) -> Bool {
        if let unquarantine = quarantinedModels[modelIdentifier], Date() < unquarantine { return true }
        return false
    }

    /// Classifies a turn failure (Legacy `classify(error:)`).
    /// Order matters: quota first, then auth, timeout, network,
    /// model-not-found, provider 5xx, and finally the default.
    /// Note the faithful quirk: `.rateLimited`,
    /// `.unsupportedCapability`, and `.malformedResponse` are
    /// never returned — rate limits classify as
    /// `.quotaExhausted` and anything else unmatched falls
    /// through to `.internalAntigravityFailure`.
    public static func classify(error: Error) -> ModelRoutingFailureClass {
        let desc = error.localizedDescription.lowercased()

        if isQuotaOrRateLimit(errorText: desc) {
            return .quotaExhausted
        }

        if desc.contains("401") || desc.contains("403") || desc.contains("invalid api key")
            || desc.contains("authentication") || desc.contains("unauthorized") {
            return .authenticationFailed
        }

        if desc.contains("timed out") || desc.contains("timeout") {
            return .timeout
        }

        if desc.contains("network") || desc.contains("cannot connect") || desc.contains("connection refused") {
            return .networkFailure
        }

        if desc.contains("model not found") || desc.contains("does not exist") || desc.contains("404") {
            return .modelUnavailable
        }

        if desc.contains("500") || desc.contains("502") || desc.contains("503") || desc.contains("504") || desc.contains("overloaded") {
            return .providerUnavailable
        }

        return .internalAntigravityFailure
    }

    /// Quarantines a model after a rate-limit / quota failure
    /// (Legacy `markRateLimited`, default 60s).
    public func markRateLimited(modelID: String, retryAfter: TimeInterval? = nil) {
        let duration = retryAfter ?? Self.rateLimitQuarantine
        quarantinedModels[modelID] = Date().addingTimeInterval(duration)
    }

    /// Quarantines a model after an authentication failure
    /// (Legacy `markAuthenticationFailed`, 10 minutes, until the
    /// user updates credentials).
    public func markAuthenticationFailed(modelID: String) {
        quarantinedModels[modelID] = Date().addingTimeInterval(Self.authenticationQuarantine)
    }

    /// Records a failure and quarantines the model for 2 minutes
    /// (Legacy `markModelUnavailable`).
    public func markModelUnavailable(modelID: String, reason: String) {
        failedAttemptsCount[modelID, default: 0] += 1
        quarantinedModels[modelID] = Date().addingTimeInterval(Self.unavailableQuarantine)
    }

    /// Clears a model's quarantine and failure count
    /// (Legacy `markModelHealthy` / `markHealthy`).
    public func markModelHealthy(modelID: String) {
        quarantinedModels.removeValue(forKey: modelID)
        failedAttemptsCount.removeValue(forKey: modelID)
    }

    /// Clears every quarantine and failure count
    /// (Legacy `clearAllQuarantines`).
    public func clearAllQuarantines() {
        quarantinedModels.removeAll()
        failedAttemptsCount.removeAll()
    }

    /// The handoff prompt that carries a failed turn's partial
    /// work to the next model (Legacy `buildContinuationPrompt`).
    public static func buildContinuationPrompt(originalPrompt: String, priorTurnOutput: String, failedModelName: String) -> String {
        var handoff = "CONTINUATION DIRECTIVE:\n"
        handoff += "The previous model (\(failedModelName)) encountered an interruption or rate limit and failed.\n"
        if !priorTurnOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handoff += "\nPartial response from previous model:\n\"\"\"\n\(priorTurnOutput)\n\"\"\"\n"
            handoff += "DO NOT repeat or overwrite work that has already been successfully accomplished.\n"
        }
        handoff += "\nOriginal Objective:\n\(originalPrompt)\n"
        handoff += "\nINSTRUCTION: Inspect the repository's current disk state and continue fulfilling the user's objective without repeating already completed work."
        return handoff
    }

    // MARK: - User-provided models

    /// A user-provided model: a Custom Model Setup (source
    /// `.custom`), excluding SwiftCode Cloud models, which are
    /// also provider-hosted, not user-provided (Legacy
    /// `isUserProvidedModel`).
    public static func isUserProvidedModel(_ model: AssistCandidateModel) -> Bool {
        model.source == .custom
    }

    /// Whether the selected model id is a user-provided custom
    /// model (Legacy `isUserProvidedSelectedModelID`). Used as
    /// the send-time gate when "Use Provider Models" is on.
    /// A bare custom-model id stored in `customModelID` is
    /// user-provided by definition; provider ids arrive as
    /// `provider/model` or via a discovered record.
    public static func isUserProvidedSelectedModelID(
        _ selectedID: String,
        discovered: AssistCandidateModel?,
        customModelID: String
    ) -> Bool {
        if let discovered {
            return isUserProvidedModel(discovered)
        }
        let trimmed = selectedID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if SCCloudProvider.isCloudModelID(trimmed) { return false }
        if HermesModelID.isHermesModelID(trimmed) { return false }
        if OpenCodeModelID.isOpenCodeModelID(trimmed) { return false }
        return trimmed == customModelID && !customModelID.isEmpty
    }

    // MARK: - Failover & task state continuity

    /// Handles a failed turn (Legacy `handleTurnFailure`).
    ///
    /// Records the failure (quarantine + failure count), then —
    /// when automatic switching is off — returns nil: the caller
    /// must wait on / retry the selected model and show that
    /// wait, never silently substitute another model. Otherwise
    /// picks the next ranked eligible model, excluding the failed
    /// one (and, for quota/auth failures, every model from the
    /// same provider), records the failover event, and returns the
    /// next model with a continuation prompt that carries the
    /// partial output forward.
    ///
    /// The caller passes the already-eligible ranked candidates
    /// (from `eligibleCandidates`); the router does not re-run
    /// discovery here. The Legacy Gemini key-rotation branch is
    /// `handleTurnFailureWithKeyRotation` (see
    /// `AssistSDKModelSelection.swift`): this plain form fails
    /// over to the next model, and the returned pair carries no
    /// SDK configuration (Legacy returned a
    /// `GoogleCloudSDKConfiguration` for the Antigravity session,
    /// which does not exist in SwiftCode — the SwiftCode equivalent is
    /// `SDKSessionConfiguration`, built by the rotation-aware
    /// form).
    public func handleTurnFailure(
        failedModel: AssistCandidateModel,
        error: Error,
        completedTurnContent: String,
        executedToolsCount: Int,
        objective: String = "",
        automaticallySwitchModels: Bool,
        eligibleCandidates: [AssistCandidateModel]
    ) -> (nextModel: AssistCandidateModel, continuationPrompt: String)? {
        let failureClass = Self.classify(error: error)

        switch failureClass {
        case .rateLimited, .quotaExhausted:
            markRateLimited(modelID: failedModel.id)
            markRateLimited(modelID: failedModel.modelIdentifier)
        case .authenticationFailed:
            markAuthenticationFailed(modelID: failedModel.id)
            markAuthenticationFailed(modelID: failedModel.modelIdentifier)
        default:
            markModelUnavailable(modelID: failedModel.id, reason: error.localizedDescription)
            markModelUnavailable(modelID: failedModel.modelIdentifier, reason: error.localizedDescription)
        }

        guard automaticallySwitchModels else { return nil }

        var excluding = Set<String>()
        excluding.insert(failedModel.id)
        excluding.insert(failedModel.modelIdentifier)

        if failureClass == .quotaExhausted || failureClass == .authenticationFailed {
            for m in eligibleCandidates where m.provider == failedModel.provider {
                excluding.insert(m.id)
                excluding.insert(m.modelIdentifier)
            }
        }

        guard let nextModel = Self.selectNextModel(excluding: excluding, from: eligibleCandidates) else {
            return nil
        }

        let reasonString = error.localizedDescription.isEmpty ? failureClass.rawValue : error.localizedDescription
        let event = ModelFailoverEvent(
            failedModelID: failedModel.modelIdentifier,
            failedProviderID: failedModel.provider.displayName,
            newModelID: nextModel.modelIdentifier,
            newProviderID: nextModel.provider.displayName,
            failureClass: failureClass,
            reason: reasonString
        )
        lastFailoverEvent = event
        failoverHistory.append(event)

        var handoff = "CONTINUATION DIRECTIVE:\n"
        handoff += "The previous model (\(failedModel.displayName)) encountered a \(failureClass.rawValue) and failed.\n"
        if executedToolsCount > 0 {
            handoff += "Previous actions executed \(executedToolsCount) tool calls. All files modified on disk remain intact.\n"
        }
        if !completedTurnContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handoff += "\nPartial response from previous model:\n\"\"\"\n\(completedTurnContent)\n\"\"\"\n"
        }
        handoff += "\nINSTRUCTION: Inspect the repository's current disk state and continue fulfilling the user's objective without repeating already completed work."

        return (nextModel, handoff)
    }
}
