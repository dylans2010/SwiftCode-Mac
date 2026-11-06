import Foundation

// MARK: - "Assist with Meta" provider (Wave 15)
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
// this UI): there is no Meta vendor provider in Ycode, and none
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
//
// What is NOT ported, and why `send` fails honestly: the MSP
// bridge itself (`MuseCodeMSPBridge`, the `initialize` /
// `model/list` / turn JSON-RPC session), the lifecycle manager
// (`MetaAssistLifecycleManager`), the slash-command manager, the
// "other models" bridge (`MuseOtherModelsBridge`), and the turn
// executor (`executeTurn` with its streaming text/thinking
// deltas, tool normalization, and turn tracker). Those are a
// whole JSON-RPC host session, not a provider adapter, and
// belong to a later wave. Until then this provider reports its
// models honestly when the CLI is installed and signed in, and
// `send` throws a named error instead of faking a reply or
// silently routing the turn to another provider.
// `normalizeToolName` is likewise not ported: it resolved names
// against Legacy's `AssistManager` tool registry, which Ycode
// does not have (Ycode's tools live behind MCP).

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

/// "Assist with Meta", behind Ycode's `AssistantProvider`
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

    /// What `send` reports: the one missing piece, named.
    public static let bridgeUnavailableMessage =
        "Assist with Meta needs the Muse Code MSP bridge, which is not ported yet. " +
        "The `muse` CLI is installed, but Ycode cannot drive its model-list/turn protocol without the bridge " +
        "(Legacy `MuseCodeMSPBridge`). No reply was fabricated and the turn was not sent to another provider."

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

    public init(
        locator: CLIToolLocator = CLIToolLocator(),
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.locator = locator
        self.homeDirectory = homeDirectory
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

    /// Binary absent → `.notInstalled`. Binary present but no
    /// credentials → `.signedOut` ("Authentication Required" in
    /// Legacy's discovery status). Installed and signed in →
    /// `.ready` with the fallback catalog (Legacy's
    /// `discoverModels`: live list when the bridge answers,
    /// fallback otherwise — the bridge never answers here, so
    /// the fallback is what is shown, labelled as such by the
    /// provider's documentation, not by the model list).
    public func availability() async -> ProviderAvailability {
        guard executableURL() != nil else { return .notInstalled(hint: Self.notInstalledHint) }
        guard hasCredentials() else {
            return .signedOut(hint: "Assist with Meta is installed but not signed in. Run `muse` once in Terminal and sign in, then try again.")
        }
        return .ready(Self.fallbackModels.map {
            ModelInfo(id: $0.modelId, displayName: "Meta \($0.displayLabel)", contextWindow: $0.contextLimit)
        })
    }

    /// The context window of a catalog model, when it is known.
    public func contextWindow(model: String) async -> Int? {
        Self.fallbackModels.first { $0.modelId == model }?.contextLimit
    }

    /// Fails honestly: the MSP bridge that would carry a turn is
    /// not ported (see the file header). Never fabricates a reply
    /// and never reroutes the turn to another provider.
    public func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        eventStream { _ in
            throw AssistantError.unsupported(Self.bridgeUnavailableMessage)
        }
    }
}
