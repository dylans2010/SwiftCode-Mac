import Foundation

// MARK: - Assist provider configuration (OpenCode + OpenRouter)
//
// Architecture decision (see Docs/Assist-OpenCode-OpenRouter-Providers.md):
// SwiftCode Assist owns the agent loop. Both providers below are *model*
// providers behind that loop, not replacement agents:
//
// * OpenRouter is reached over its OpenAI-compatible
//   https://openrouter.ai/api/v1/chat/completions endpoint through the
//   existing LLMService / OpenRouterClient path. The @openrouter/agent
//   TypeScript SDK was deliberately NOT adopted: it would need a Node/Bun
//   runtime inside a native macOS app and would own the tool-calling loop.
//   Assist's loop already validates tool calls against the registry,
//   enforces phase/permission metadata, executes through the real tools,
//   and feeds results back to the model — that loop is preserved verbatim.
//
// * OpenCode is reached over the OpenCode server's own HTTP API
//   (https://opencode.ai/docs/sdk/) with a native Swift client
//   (OpenCodeClient). The @opencode-ai/sdk TypeScript SDK was NOT adopted
//   for the same reason: it cannot be imported into Swift, and bundling a
//   JS runtime just to speak HTTP would add signing, notarization,
//   startup-time, and lifecycle costs for no capability gain. The server
//   API is plain HTTP + SSE, so Swift speaks it directly.
//
// OpenCode tool-ownership guard: Assist's loop only works if the model
// returns a JSON tool request for SwiftCode to validate and execute. An
// OpenCode server running its default agent would instead execute its own
// tools, bypassing SwiftCode's dispatcher and permissions. OpenCode
// sessions from SwiftCode therefore always name the `swiftcode` agent,
// which the user must configure with every permission denied (see
// OpenCodeConfiguration.swiftcodeAgentDefinition). OpenCodeClient
// additionally fails a run closed if it observes a tool part on the event
// stream, rather than silently surfacing provider-executed tool results
// as if SwiftCode had run them.

// MARK: - OpenCode model identifiers

/// A model selected through the OpenCode provider.
///
/// Stored in `selectedAssistModelID` as `opencode:<providerID>/<modelID>`
/// (for example `opencode:anthropic/claude-sonnet-4-5`). The prefix is
/// deliberate: bare `provider/model` identifiers already route to
/// OpenRouter in LLMService, so an unprefixed OpenCode model would be
/// silently sent to the wrong provider. Nothing in this file ever strips
/// the prefix and re-routes the model elsewhere.
public struct OpenCodeModelID: Equatable, Sendable {
    public let providerID: String
    public let modelID: String

    public var storedID: String { "opencode:\(providerID)/\(modelID)" }
    public var displayName: String { "\(providerID)/\(modelID)" }

    public init(providerID: String, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }

    /// Parses a stored `opencode:` model identifier. Returns nil for any
    /// other provider's identifier, including bare OpenRouter `a/b` ids.
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

/// One model advertised by an OpenCode server (`GET /config/providers`).
public struct OpenCodeModel: Identifiable, Equatable, Sendable {
    public var id: String { storedID }
    public let providerID: String
    public let modelID: String

    public var storedID: String { "opencode:\(providerID)/\(modelID)" }
    public var displayName: String { "\(providerID)/\(modelID)" }

    public init(providerID: String, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }
}

// MARK: - OpenCode server configuration

/// Persisted OpenCode connection settings. Provider model credentials
/// (Anthropic, OpenAI, OpenRouter keys, …) live in OpenCode's own
/// configuration and are never stored, logged, or sent by SwiftCode:
/// SwiftCode only ever talks to the local server, on loopback by default.
public struct OpenCodeConfiguration: Equatable, Sendable {
    public static let defaultServerURL = URL(string: "http://127.0.0.1:4096")!
    public static let defaultAgentName = "swiftcode"

    public var serverURL: URL
    /// The OpenCode agent every SwiftCode session names. Must be
    /// configured server-side with all permissions denied (see
    /// `swiftcodeAgentDefinition`); otherwise the server would execute
    /// its own tools instead of returning JSON tool requests for
    /// SwiftCode's dispatcher.
    public var agentName: String
    /// Opt-in only, off by default. When on, SwiftCode may start
    /// `opencode serve` bound to 127.0.0.1 if the health check fails and
    /// the binary is on PATH. When off (the default), SwiftCode only
    /// connects to a server the user already runs.
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

    private static let serverURLKey = "opencode.serverURL"
    private static let agentNameKey = "opencode.agentName"
    private static let managedServerKey = "opencode.managedServerEnabled"

    public static func load() -> OpenCodeConfiguration {
        var config = OpenCodeConfiguration()
        if let raw = UserDefaults.standard.string(forKey: serverURLKey),
           let url = URL(string: raw),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           url.host != nil {
            config.serverURL = url
        }
        if let name = UserDefaults.standard.string(forKey: agentNameKey),
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.agentName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        config.managedServerEnabled = UserDefaults.standard.bool(forKey: managedServerKey)
        return config
    }

    public func save() {
        UserDefaults.standard.set(serverURL.absoluteString, forKey: Self.serverURLKey)
        UserDefaults.standard.set(agentName, forKey: Self.agentNameKey)
        UserDefaults.standard.set(managedServerEnabled, forKey: Self.managedServerKey)
    }

    /// Port extracted from the server URL, for managed-server startup.
    public var port: Int {
        serverURL.port ?? (serverURL.scheme == "https" ? 443 : 80)
    }

    /// Managed startup is only ever attempted for a loopback server, so a
    /// misconfigured URL cannot make SwiftCode bind or launch a server
    /// that listens on a LAN interface.
    public var isLoopback: Bool {
        guard let host = serverURL.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    /// Agent definition the user installs server-side so OpenCode acts as
    /// a pure model behind SwiftCode's tool loop. Install as
    /// `.opencode/agent/swiftcode.md` in the project (or
    /// `~/.config/opencode/agent/swiftcode.md` globally), or express the
    /// same permissions in `opencode.json` under `agent.swiftcode`.
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

// MARK: - Provider selection

/// The provider a stored model identifier belongs to. OpenCode is
/// recognised only by its `opencode:` prefix; every other identifier
/// keeps the routing it already had, so existing selections are
/// unaffected by this file.
public enum AssistProviderSelection {
    @MainActor
    public static func provider(for storedModelID: String) -> AssistModelProvider {
        if HermesModelID.isHermesModelID(storedModelID) {
            return .hermes
        }
        if OpenCodeModelID.isOpenCodeModelID(storedModelID) {
            return .openCode
        }
        return AgentModelAdapter.shared.specification(for: storedModelID).provider
    }

    /// The persisted provider picker in Assist Settings
    /// (`assist.selectedProvider`, the existing key already read by
    /// AssistAgent/AssistManager/TasksAIPlanner). Kept in sync with the
    /// selected model by the Settings view; the model identifier remains
    /// the routing source of truth for a running session.
    public static var persistedProvider: AssistModelProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: "assist.selectedProvider")
            return raw.flatMap { AssistModelProvider(rawValue: $0) } ?? .openRouter
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "assist.selectedProvider")
        }
    }
}
