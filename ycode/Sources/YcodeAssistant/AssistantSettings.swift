import Foundation

/// The assistant's settings (no secrets: those are in a `SecretStore`).
public struct AssistantSettings: Codable, Sendable, Equatable {
    public enum OpenAIAuth: String, Codable, Sendable, CaseIterable { case chatGPT, apiKey }

    public var provider: ProviderKind = .ollama
    public var ollamaURL = OllamaProvider.defaultBaseURL
    public var llamaCppURL = ChatCompletionsProvider.defaultBaseURL
    public var openAIURL = OpenAIProvider.defaultBaseURL
    /// OpenRouter's API root (Wave 9).
    public var openRouterURL = OpenRouterProvider.defaultBaseURL
    /// The local OpenCode server's address (Wave 9).
    public var openCodeURL = OpenCodeProvider.defaultBaseURL
    /// The OpenCode agent every session names (Wave 15: Legacy
    /// `OpenCodeConfiguration.agentName`, default `"swiftcode"`).
    /// It must be configured server-side with every permission
    /// denied, so the server returns JSON tool requests for Ycode
    /// to run instead of executing tools itself.
    public var openCodeAgentName = OpenCodeProvider.defaultAgentName
    /// The free-text custom model ID (Wave 15: Legacy
    /// `AssistModelManager.customModelID` / `AppSettings.customModel`).
    /// A bare ID stored here is user-provided by definition; provider
    /// IDs arrive as `provider/model` or via a discovered record.
    public var customModelID = ""
    /// SwiftCode Cloud's base URL (Wave 9). Empty by default: no
    /// endpoint is shipped, and the provider reports unconfigured
    /// until Dylan enters a real one.
    public var scCloudURL = ""
    public var openAIAuth: OpenAIAuth = .chatGPT
    /// The chosen model per provider (raw value → model ID; "" = the
    /// tool's default).
    public var models: [String: String] = [:]
    /// A path per agent tool that replaces the search (raw value → path).
    public var toolPaths: [String: String] = [:]
    /// The most tokens a request may use, whatever the model allows.
    public var contextLimit = 32_768
    public var context = ContextOptions()
    /// The ChatGPT plan notice was shown (the first sign-in disclosure).
    public var shownPlanNotice = false
    /// The ACP agent's command line ("<executable> <arguments…>").
    public var acpCommand = ""
    /// Agent mode: agent tools and ACP agents get Ycode's MCP server and may
    /// change files, each change reviewed as a proposal (off: they only
    /// read and propose, coding-assistant.md §3.4).
    public var agentMode = true
    /// Output limit and sampling for the model servers (Ollama, llama.cpp,
    /// OpenAI); unset values are not sent.
    public var generation = GenerationOptions.assistantDefault
    /// How a request picks its model (Wave 15: Legacy
    /// `AppSettings.assistModelRoutingStrategy`). `.providerDefault`
    /// uses the provider + model chosen in Settings;
    /// `.appModels` considers every eligible model from every
    /// provider when a turn fails over. Legacy's third strategy,
    /// `"rotation"` (Gemini key rotation through the Antigravity SDK
    /// catalog), has no Ycode equivalent and decodes to
    /// `.providerDefault`.
    public var routingStrategy: AssistRoutingStrategy = .providerDefault
    /// "Automatically Switch Models" (Wave 15: Legacy
    /// `assistAutomaticallySwitchModels`, default true). When off,
    /// a turn failure never silently substitutes another model: the
    /// router returns nil and the caller waits on / retries the
    /// selected model.
    public var automaticallySwitchModels = true
    /// "Use Provider Models" (Wave 15: Legacy
    /// `assistUseProviderModels`, default false). When on, selection
    /// and failover may never pick a user-provided (custom) model,
    /// even as a fallback.
    public var useProviderModelsOnly = false
    /// "Only Use Free Models" (Wave 15: Legacy `onlyUseFreeModels`,
    /// default false). When on, a model is eligible only when its ID
    /// contains "free" (see `AssistModelEligibilityPolicy`).
    public var onlyUseFreeModels = false
    /// "Use SwiftCode's Cloud Model" (Wave 15: Legacy
    /// `useSwiftCodeCloudModel`, default false). When on, the cloud
    /// model is eligible under every routing strategy and bypasses
    /// provider credentials entirely.
    public var useSwiftCodeCloudModel = false
    /// The Meta reasoning effort for `turn/start` (Wave 16:
    /// Legacy `AppSettings.metaReasoningEffort`, default
    /// `"high"`). The `/effort` slash command updates it through
    /// the host; the provider reads it at `send` time.
    public var metaReasoningEffort = "high"
    /// "Gemini Key Rotation" (Wave 16: Legacy
    /// `AppSettings.alternativeKeysEnabled`, default false). When
    /// on, a rate-limited Gemini turn rotates to the next stored
    /// alternative key (`GeminiKeyRotationManager`) instead of
    /// failing over to the next model. Off by default: rotation
    /// only happens when Dylan has stored alternative keys and
    /// switched this on.
    public var alternativeKeysEnabled = false

    public init() {}

    public func model(for p: ProviderKind) -> String? { models[p.rawValue] }
    public mutating func setModel(_ m: String?, for p: ProviderKind) { models[p.rawValue] = m }

    public init(from decoder: Decoder) throws {
        // Missing keys keep their defaults (settings saved by older builds).
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AssistantSettings()
        provider = (try? c.decode(ProviderKind.self, forKey: .provider)) ?? d.provider
        ollamaURL = (try? c.decode(String.self, forKey: .ollamaURL)) ?? d.ollamaURL
        llamaCppURL = (try? c.decode(String.self, forKey: .llamaCppURL)) ?? d.llamaCppURL
        openAIURL = (try? c.decode(String.self, forKey: .openAIURL)) ?? d.openAIURL
        openRouterURL = (try? c.decode(String.self, forKey: .openRouterURL)) ?? d.openRouterURL
        openCodeURL = (try? c.decode(String.self, forKey: .openCodeURL)) ?? d.openCodeURL
        openCodeAgentName = (try? c.decode(String.self, forKey: .openCodeAgentName)) ?? d.openCodeAgentName
        customModelID = (try? c.decode(String.self, forKey: .customModelID)) ?? d.customModelID
        scCloudURL = (try? c.decode(String.self, forKey: .scCloudURL)) ?? d.scCloudURL
        openAIAuth = (try? c.decode(OpenAIAuth.self, forKey: .openAIAuth)) ?? d.openAIAuth
        models = (try? c.decode([String: String].self, forKey: .models)) ?? [:]
        toolPaths = (try? c.decode([String: String].self, forKey: .toolPaths)) ?? [:]
        contextLimit = (try? c.decode(Int.self, forKey: .contextLimit)) ?? d.contextLimit
        context = (try? c.decode(ContextOptions.self, forKey: .context)) ?? d.context
        shownPlanNotice = (try? c.decode(Bool.self, forKey: .shownPlanNotice)) ?? false
        acpCommand = (try? c.decode(String.self, forKey: .acpCommand)) ?? ""
        agentMode = (try? c.decode(Bool.self, forKey: .agentMode)) ?? d.agentMode
        generation = (try? c.decode(GenerationOptions.self, forKey: .generation)) ?? d.generation
        routingStrategy = (try? c.decode(AssistRoutingStrategy.self, forKey: .routingStrategy)) ?? d.routingStrategy
        automaticallySwitchModels = (try? c.decode(Bool.self, forKey: .automaticallySwitchModels)) ?? d.automaticallySwitchModels
        useProviderModelsOnly = (try? c.decode(Bool.self, forKey: .useProviderModelsOnly)) ?? d.useProviderModelsOnly
        onlyUseFreeModels = (try? c.decode(Bool.self, forKey: .onlyUseFreeModels)) ?? d.onlyUseFreeModels
        useSwiftCodeCloudModel = (try? c.decode(Bool.self, forKey: .useSwiftCodeCloudModel)) ?? d.useSwiftCodeCloudModel
        metaReasoningEffort = (try? c.decode(String.self, forKey: .metaReasoningEffort)) ?? d.metaReasoningEffort
        alternativeKeysEnabled = (try? c.decode(Bool.self, forKey: .alternativeKeysEnabled)) ?? d.alternativeKeysEnabled
    }
}

/// Makes providers from settings and finds which back ends can be used.
public struct AssistantBackends: Sendable {
    public var settings: AssistantSettings
    public var store: SecretStore
    public var account: OpenAIAccount?
    public var locator: CLIToolLocator

    public init(settings: AssistantSettings, store: SecretStore, account: OpenAIAccount?, locator: CLIToolLocator = CLIToolLocator()) {
        self.settings = settings
        self.store = store
        self.account = account
        self.locator = locator
    }

    public func provider(_ kind: ProviderKind) -> AssistantProvider {
        switch kind {
        case .ollama:
            return OllamaProvider(baseURL: settings.ollamaURL)
        case .llamaCpp:
            return ChatCompletionsProvider(baseURL: settings.llamaCppURL, apiKey: store.readString(SecretAccount.llamaCppKey))
        case .openAI:
            let credential: OpenAIProvider.Credential
            switch settings.openAIAuth {
            case .apiKey: credential = store.readString(SecretAccount.openAIKey).map { .apiKey($0) } ?? .none
            case .chatGPT: credential = account.map { .account($0) } ?? .none
            }
            return OpenAIProvider(baseURL: settings.openAIURL, credential: credential)
        case .claudeCode, .codex, .antigravity:
            let agent = kind.cliAgent!
            return CLIAgentProvider(agent: agent, executable: locator.find(agent.executableName, override: settings.toolPaths[kind.rawValue]))
        case .acpAgent:
            return ACPAgentProvider(command: settings.acpCommand, locator: locator)
        case .openRouter:
            return OpenRouterProvider(baseURL: settings.openRouterURL, apiKey: store.readString(SecretAccount.openRouterKey))
        case .openCode:
            return OpenCodeProvider(baseURL: settings.openCodeURL)
        case .hermes:
            return HermesProvider(locator: locator, secretStore: store)
        case .foundationModels:
            return FoundationModelsProvider()
        case .scCloud:
            // The fingerprint is provisioned (once, then stored) only
            // when an endpoint is actually configured, so merely
            // surveying providers never writes to the keychain.
            let fingerprint: String?
            if settings.scCloudURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fingerprint = nil
            } else if let stored = store.readString(SecretAccount.scCloudFingerprint) {
                fingerprint = stored
            } else {
                let fresh = SCCloudProvider.provisionFingerprint()
                try? store.write(Data(fresh.utf8), for: SecretAccount.scCloudFingerprint)
                fingerprint = fresh
            }
            return SCCloudProvider(baseURL: settings.scCloudURL, fingerprint: fingerprint)
        case .metaAssist:
            return MetaAssistProvider(locator: locator, reasoningEffort: settings.metaReasoningEffort)
        }
    }

    /// The provider a stored model identifier belongs to (Wave 15:
    /// Legacy `AssistProviderConfiguration.AssistProviderSelection`).
    /// Prefixed IDs win first — `hermes:`, `opencode:`,
    /// `swiftcode-cloud:` — so a stored OpenCode model can never be
    /// misreported (and misrouted) as a direct provider model.
    /// Every other identifier keeps the routing the name-based
    /// specification already gives it, so existing selections are
    /// unaffected. The model identifier remains the routing source
    /// of truth for a running session; the persisted provider
    /// picker (`settings.provider`) is kept in sync by Settings.
    public func providerKind(forModelID storedID: String) -> ProviderKind {
        if HermesModelID.isHermesModelID(storedID) { return .hermes }
        if OpenCodeModelID.isOpenCodeModelID(storedID) { return .openCode }
        if SCCloudProvider.isCloudModelID(storedID) { return .scCloud }
        return AssistModelSpecification.specification(for: storedID).provider
    }

    /// The back end for a stored model identifier, through the
    /// existing `provider(_:)` dispatch — no second dispatcher.
    public func provider(forModelID storedID: String) -> AssistantProvider {
        provider(providerKind(forModelID: storedID))
    }

    /// Every back end's availability, checked concurrently.
    public func survey() async -> [ProviderKind: ProviderAvailability] {
        await withTaskGroup(of: (ProviderKind, ProviderAvailability).self) { group in
            for k in ProviderKind.allCases {
                let p = provider(k)
                group.addTask { (k, await p.availability()) }
            }
            var out: [ProviderKind: ProviderAvailability] = [:]
            for await (k, a) in group { out[k] = a }
            return out
        }
    }

    /// The empty state when nothing can be used.
    public static let noBackendText = """
    The coding assistant needs a model. Use one of these:
    • Ollama: install it from ollama.com, then run `ollama pull qwen2.5-coder` in Terminal.
    • llama.cpp: run `llama-server -m <model>.gguf`.
    • OpenAI: sign in with ChatGPT, or enter an API key, in Settings ▸ Coding Assistant.
    • Claude Code, Codex or the Antigravity CLI: install one and sign in to it once in Terminal.
    • An ACP agent: set its command in Settings ▸ Coding Assistant.
    • OpenRouter: enter an API key in Settings ▸ Coding Assistant.
    • OpenCode: run `opencode serve` in Terminal.
    • Hermes: install Hermes and sign in once in Terminal.
    • Foundation Models: use a Mac with Apple Intelligence (macOS 26+).
    • SwiftCode Cloud: enter a real endpoint URL in Settings ▸ Coding Assistant.
    """
}
