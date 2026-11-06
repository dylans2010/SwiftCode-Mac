import Foundation

// MARK: - "Assist with Meta" provider (Wave 15, bridge in Wave 16)
//
// Ported from Legacy (Dylan's own code; direct port authorised
// under MIT):
//   * `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MetaAssistProvider.swift`
//     — "Assist with Meta" powered by the Muse Code SDK. Public UI
//     identity is strictly "Assist with Meta".
//   * `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MuseCodeCLIHelper.swift`
//     — executable discovery (`muse`), installation checks, and the
//     credential files (`~/.config/muse/auth.json`,
//     `~/.muse/auth.json`).
//
// What this is: Meta's Muse Code CLI agent, driven through its MSP
// (model-service-protocol) host — a JSON-RPC bridge process
// (`MuseCodeMSPBridge`) that speaks `initialize` / `model/list` /
// turns. It is NOT Meta's vendor API (`AssistModelProvider.meta`
// in Legacy, endpoint `https://api.meta.ai/v1/chat/completions`,
// marked "// Example" in source and never the provider behind
// this UI): there is no Meta vendor provider in SwiftCode, and none
// is invented here.
//
// What is ported: the provider identity (id `meta_assist`, name
// "Assist with Meta", default model `muse-wonder-1.0`), the
// fallback model catalog (the three models Legacy fell back to
// when the bridge returned no list), availability through the
// `muse` binary + credential files (Legacy's
// `discoverModels` gate: installed AND signed in), and the
// `ProviderKind.metaAssist` case wired into
// `AssistantBackends.provider(_:)` — the existing dispatch.
// Wave 16 adds the MSP bridge itself (`MuseCodeMSPBridge`),
// the lifecycle manager (`MetaAssistLifecycleManager`), the
// slash-command manager (`MetaSlashCommandManager`), the
// "other models" bridge (`MuseOtherModelsBridge`), the turn
// executor (`MetaAssistTurnExecutor.executeTurn` with streaming
// text/thinking deltas, tool normalization, and the turn
// tracker), and `normalizeToolName` (as
// `MetaToolNameNormalizer`, resolved against SwiftCode's MCP tool
// ids — see `MetaAssistTurnExecutor.swift`). `send` now runs a
// real turn through the bridge instead of throwing
// `AssistantError.unsupported`.
//
// What is still NOT ported, and why (see
// specs/ide/sdk-platform.md §23.4 / Wave 16 slice B draft):
// SwiftCode MCP tool execution inside the provider (no `SwiftCodeMCP`
// dependency from this target; the host's tools are observed,
// not run — approval decisions go through the agent-mode
// attachment's permission UI, never Autopilot auto-allow);
// Legacy's SystemIndex prompt assets; the direct-LLM
// `MuseOtherModelsBridge.executeTurn` (no `LLMService` in
// SwiftCode — the proxy path + host router failover replace it);
// the interactive `muse login` flow (a turn without
// credentials fails honestly with a sign-in hint).

/// One Meta model (Legacy `MetaAssistProvider.MetaModelItem`).
public struct MetaModelItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { modelId }
    public let modelId: String
    public let displayLabel: String
    public let releaseDate: String?
    public let description: String?
    public let contextLimit: Int
    public let outputLimit: Int
    public let isDefault: Bool
    public let variants: [String]
    public let defaultReasoningEffort: String?

    public init(
        modelId: String,
        displayLabel: String,
        releaseDate: String? = nil,
        description: String? = nil,
        contextLimit: Int = 1_000_000,
        outputLimit: Int = 128_000,
        isDefault: Bool = false,
        variants: [String] = [],
        defaultReasoningEffort: String? = "high"
    ) {
        self.modelId = modelId
        self.displayLabel = displayLabel
        self.releaseDate = releaseDate
        self.description = description
        self.contextLimit = contextLimit
        self.outputLimit = outputLimit
        self.isDefault = isDefault
        self.variants = variants
        self.defaultReasoningEffort = defaultReasoningEffort
    }
}

/// "Assist with Meta", behind SwiftCode's `AssistantProvider`
/// protocol so the host's dispatch serves it like any other
/// provider. See the file header: availability is real,
/// `send` fails honestly until the MSP bridge is ported.
public struct MetaAssistProvider: AssistantProvider {
    public let kind = ProviderKind.metaAssist

    public static let providerID = "meta_assist"
    public static let providerName = "Assist with Meta"
    public static let defaultModelID = "muse-wonder-1.0"
    public static let executableName = "muse"

    /// What `availability()` reports while the CLI is absent.
    /// Legacy `MuseCodeCLIHelper`'s own wording.
    public static let notInstalledHint = "The 'muse' CLI executable was not found on your system. Install the Muse Code CLI and sign in once by running `muse` in Terminal."

    /// What `send` reports when the CLI is installed but no
    /// credential file exists.
    public static let notSignedInHint = "Assist with Meta is installed but not signed in. Run `muse` once in Terminal and sign in, then try again."

    /// How long `availability()` waits for the bridge's live
    /// model list before falling back to the catalog (Legacy
    /// had no timeout; the survey calls `availability()` for
    /// every provider, so a hung host must not hang the survey).
    public static let modelListTimeout: TimeInterval = 15

    /// The fallback catalog (Legacy `MetaAssistProvider.fallbackModels`):
    /// the models shown when the bridge returns no list. Values are
    /// Legacy's own (context 1,007,997, output 128,000).
    public static let fallbackModels: [MetaModelItem] = [
        MetaModelItem(
            modelId: "muse-wonder-1.0",
            displayLabel: "muse-wonder-1.0",
            releaseDate: "2026-10-12",
            description: "Meta flagship reasoning and coding model with 1,000,000 token context window.",
            contextLimit: 1_007_997,
            outputLimit: 128_000,
            isDefault: true,
            variants: ["minimal", "low", "medium", "high", "xhigh", "max"],
            defaultReasoningEffort: "high"
        ),
        MetaModelItem(
            modelId: "muse-spark-1.3",
            displayLabel: "muse-spark-1.3",
            releaseDate: "2026-09-02",
            description: "Fast, high-throughput coding model with deep reasoning variants.",
            contextLimit: 1_007_997,
            outputLimit: 128_000,
            isDefault: false,
            variants: ["minimal", "low", "medium", "high", "xhigh", "max"],
            defaultReasoningEffort: "max"
        ),
        MetaModelItem(
            modelId: "muse-spark-1.2",
            displayLabel: "muse-spark-1.2",
            releaseDate: "2026-08-05",
            description: "Optimized lightweight assistant model for responsive code edits.",
            contextLimit: 1_007_997,
            outputLimit: 128_000,
            isDefault: false,
            variants: ["minimal", "low", "medium", "high", "xhigh"],
            defaultReasoningEffort: "high"
        ),
    ]

    private let locator: CLIToolLocator
    private let homeDirectory: String
    /// The reasoning effort for `turn/start` (Legacy
    /// `AppSettings.metaReasoningEffort`, default `"high"`).
    /// Lives in `AssistantSettings.metaReasoningEffort`; the
    /// `/effort` slash command updates it through the host.
    public var reasoningEffort: String
    /// The longest a turn may run before it is cancelled and
    /// the host stopped (Wave 17:
    /// `MetaAssistTurnExecutor.defaultTurnTimeout`). Lives in
    /// `AssistantSettings.metaTurnTimeoutSeconds`; the host
    /// passes it through, never a second default.
    public var turnTimeoutSeconds: TimeInterval
    /// The agent-mode attachment, when the host attached one
    /// (see `AgentAttachable`). Its `requestPermission` decides
    /// the host's approval requests; without it every approval
    /// is denied. The attachment's MCP endpoint is NOT passed
    /// to `muse serve` — no documented CLI mechanism for it
    /// exists (see `MetaAssistTurnExecutor.swift`).
    public var attachment: AgentAttachment?
    /// SwiftCode MCP tool ids, for `normalizeToolName` (see
    /// `MetaToolNameNormalizer`). Injected by the host when it
    /// owns the live catalogue; empty until then, and names
    /// that cannot map are recorded on the turn, not guessed.
    public var knownToolIDs: Set<String>
    /// The other-models proxy URL, when the host started one
    /// (`MuseOtherModelsBridge`); passed as `--base-url`.
    public var proxyBaseURL: String?
    private let bridge: MuseCodeMSPBridge
    private let executor: MetaAssistTurnExecutor

    public init(
        locator: CLIToolLocator = CLIToolLocator(),
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        reasoningEffort: String = "high",
        turnTimeoutSeconds: TimeInterval = MetaAssistTurnExecutor.defaultTurnTimeout,
        attachment: AgentAttachment? = nil,
        knownToolIDs: Set<String> = [],
        proxyBaseURL: String? = nil,
        bridge: MuseCodeMSPBridge = .shared,
        executor: MetaAssistTurnExecutor = .shared
    ) {
        self.locator = locator
        self.homeDirectory = homeDirectory
        self.reasoningEffort = reasoningEffort
        self.turnTimeoutSeconds = turnTimeoutSeconds
        self.attachment = attachment
        self.knownToolIDs = knownToolIDs
        self.proxyBaseURL = proxyBaseURL
        self.bridge = bridge
        self.executor = executor
    }

    /// The `muse` executable, if installed. The locator covers
    /// PATH plus the usual folders; Legacy additionally checked
    /// `~/.muse/bin/muse`, which the locator does not know, so it
    /// is checked here.
    public func executableURL() -> URL? {
        if let found = locator.find(Self.executableName) { return found }
        let extra = (homeDirectory as NSString).appendingPathComponent(".muse/bin/muse")
        return locator.isExecutable(extra) ? URL(fileURLWithPath: extra) : nil
    }

    /// Whether the CLI holds credentials (Legacy
    /// `MuseCodeCLIHelper.checkCredentials`): an auth file at
    /// `~/.config/muse/auth.json` or `~/.muse/auth.json`. Only
    /// existence is checked — the file is never read.
    public func hasCredentials() -> Bool {
        let candidates = [
            (homeDirectory as NSString).appendingPathComponent(".config/muse/auth.json"),
            (homeDirectory as NSString).appendingPathComponent(".muse/auth.json"),
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// The live model list from the bridge (`model/list`), or
    /// the fallback catalog when the bridge cannot answer
    /// (Legacy `fetchModels`: live list, fallback otherwise).
    /// Starts the host at `/tmp` when it is not running
    /// (Legacy's workspace root for a bare model fetch).
    public func fetchModels() async -> [MetaModelItem] {
        guard let executable = executableURL() else { return Self.fallbackModels }
        do {
            try await bridge.startHost(executable: executable, workspaceRoot: "/tmp")
            if !(await bridge.isInitialized) {
                _ = try await bridge.sendCommand(method: "initialize", params: ["clientInfo": MetaAssistTurnExecutor.clientInfo])
                try await bridge.sendNotification(method: "initialized", params: [:])
                await bridge.markInitialized()
            }
            let response = try await bridge.sendCommand(method: "model/list", params: [:])
            return MetaAssistTurnExecutor.parseModelList(response) ?? Self.fallbackModels
        } catch {
            return Self.fallbackModels
        }
    }

    /// Binary absent → `.notInstalled`. Binary present but no
    /// credentials → `.signedOut` ("Authentication Required" in
    /// Legacy's discovery status). Installed and signed in →
    /// `.ready` with the live model list when the bridge
    /// answers within the timeout, else the fallback catalog
    /// (Legacy's `discoverModels` gate).
    public func availability() async -> ProviderAvailability {
        guard executableURL() != nil else { return .notInstalled(hint: Self.notInstalledHint) }
        guard hasCredentials() else { return .signedOut(hint: Self.notSignedInHint) }
        let models = await withTimeout(seconds: Self.modelListTimeout, fallback: Self.fallbackModels) { await self.fetchModels() }
        return .ready(models.map {
            ModelInfo(id: $0.modelId, displayName: "Meta \($0.displayLabel)", contextWindow: $0.contextLimit)
        })
    }

    /// The context window of a catalog model, when it is known.
    public func contextWindow(model: String) async -> Int? {
        Self.fallbackModels.first { $0.modelId == model }?.contextLimit
    }

    /// Runs one turn through the MSP bridge
    /// (`MetaAssistTurnExecutor.executeTurn`): text streams as
    /// `.text`, thinking as `.activity("Thinking: …")`, host
    /// tool calls as `.activity`. A missing binary, missing
    /// credentials, or a host failure throws honestly — the turn
    /// is never fabricated and never rerouted to another
    /// provider.
    public func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let provider = self
        return eventStream { out in
            guard let executable = provider.executableURL() else {
                throw AssistantError.failed(Self.notInstalledHint)
            }
            guard provider.hasCredentials() || provider.proxyBaseURL != nil else {
                throw AssistantError.notSignedIn(hint: Self.notSignedInHint)
            }
            let trimmedModel = request.model?.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = (trimmedModel?.isEmpty == false ? trimmedModel : nil) ?? Self.defaultModelID
            let workspaceRoot = request.workingDirectory?.path ?? provider.homeDirectory
            let prompt = request.messages.last?.content ?? request.flattenedPrompt
            let history = Array(request.messages.dropLast())
            do {
                try await provider.executor.executeTurn(
                    prompt: prompt,
                    history: history,
                    instructions: request.instructions,
                    modelID: modelID,
                    reasoningEffort: provider.reasoningEffort,
                    workspaceRoot: workspaceRoot,
                    executable: executable,
                    hasCredentials: provider.hasCredentials(),
                    proxyBaseURL: provider.proxyBaseURL,
                    attachment: provider.attachment,
                    knownToolIDs: provider.knownToolIDs,
                    turnTimeoutSeconds: provider.turnTimeoutSeconds,
                    onEvent: { out.yield($0) }
                )
            } catch let error as MuseCodeCLIError {
                throw AssistantError.failed(error.localizedDescription)
            }
            out.yield(.finished(nil))
        }
    }
}

extension MetaAssistProvider: AgentAttachable {
    public var isAttached: Bool { attachment != nil }

    public func attaching(_ attachment: AgentAttachment) -> AssistantProvider {
        var copy = self
        copy.attachment = attachment
        return copy
    }
}

/// Runs `operation`, or returns `fallback` when it takes
/// longer than `seconds`. Used for the model-list fetch inside
/// `availability()`, so a hung host cannot hang the provider
/// survey. Whichever finishes first wins; the loser is
/// cancelled.
private func withTimeout<T: Sendable>(seconds: TimeInterval, fallback: T, operation: @escaping @Sendable () async -> T) async -> T {
    await withTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return fallback
        }
        let result = await group.next()!
        group.cancelAll()
        return result
    }
}
