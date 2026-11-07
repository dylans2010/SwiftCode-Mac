import Foundation

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

public struct MetaAssistProvider: AssistantProvider {
    public let kind = ProviderKind.metaAssist

    public static let providerID = "meta_assist"
    public static let providerName = "Assist with Meta"
    public static let defaultModelID = "muse-wonder-1.0"
    public static let executableName = "muse"

    public static let notInstalledHint = "The 'muse' CLI executable was not found on your system. Install the Muse Code CLI and sign in once by running `muse` in Terminal."

    public static let notSignedInHint = "Assist with Meta is installed but not signed in. Run `muse` once in Terminal and sign in, then try again."

    public static let modelListTimeout: TimeInterval = 15

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
    public var reasoningEffort: String
    public var turnTimeoutSeconds: TimeInterval
    public var attachment: AgentAttachment?
    public var knownToolIDs: Set<String>
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

    public func executableURL() -> URL? {
        if let found = locator.find(Self.executableName) { return found }
        let extra = (homeDirectory as NSString).appendingPathComponent(".muse/bin/muse")
        return locator.isExecutable(extra) ? URL(fileURLWithPath: extra) : nil
    }

    public func hasCredentials() -> Bool {
        let candidates = [
            (homeDirectory as NSString).appendingPathComponent(".config/muse/auth.json"),
            (homeDirectory as NSString).appendingPathComponent(".muse/auth.json"),
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

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

    public func availability() async -> ProviderAvailability {
        guard executableURL() != nil else { return .notInstalled(hint: Self.notInstalledHint) }
        guard hasCredentials() else { return .signedOut(hint: Self.notSignedInHint) }
        let models = await withTimeout(seconds: Self.modelListTimeout, fallback: Self.fallbackModels) { await self.fetchModels() }
        return .ready(models.map {
            ModelInfo(id: $0.modelId, displayName: "Meta \($0.displayLabel)", contextWindow: $0.contextLimit)
        })
    }

    public func contextWindow(model: String) async -> Int? {
        Self.fallbackModels.first { $0.modelId == model }?.contextLimit
    }

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
