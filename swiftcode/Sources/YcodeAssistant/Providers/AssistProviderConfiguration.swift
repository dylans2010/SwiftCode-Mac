import Foundation

public struct OpenCodeModelID: Equatable, Sendable {
    public let providerID: String
    public let modelID: String

    public var storedID: String { "opencode:\(providerID)/\(modelID)" }
    public var displayName: String { "\(providerID)/\(modelID)" }

    public init(providerID: String, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }

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

public struct OpenCodeConfiguration: Equatable, Sendable {
    public static let defaultServerURL = URL(string: "http://127.0.0.1:4096")!
    public static let defaultAgentName = "swiftcode"

    public var serverURL: URL
    public var agentName: String
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

    public var port: Int {
        serverURL.port ?? (serverURL.scheme == "https" ? 443 : 80)
    }

    public var isLoopback: Bool {
        guard let host = serverURL.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

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

public enum AssistProviderSelection {
    @MainActor
    public static func provider(for storedModelID: String) -> AssistModelProvider {
        if HermesModelID.isHermesModelID(storedModelID) {
            return .hermes
        }
        if OpenCodeModelID.isOpenCodeModelID(storedModelID) {
            return .openCode
        }
        switch AgentModelAdapter.shared.specification(for: storedModelID).provider {
        case .openCode: return .openCode
        case .hermes: return .hermes
        case .openRouter: return .openRouter
        case .openAI: return .openAI
        case .anthropic: return .anthropic
        case .codex: return .codex
        case .ollama: return .openAI
        case .foundationModels, .scCloud: return .openRouter
        case .llamaCpp, .claudeCode, .antigravity, .acpAgent, .metaAssist, .gemini, .mistral: return .openRouter
        @unknown default: return .openRouter
        }
    }

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
