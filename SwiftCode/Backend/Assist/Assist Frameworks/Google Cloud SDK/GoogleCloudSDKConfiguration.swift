//
//  GoogleCloudSDKConfiguration.swift
//  SwiftCode
//
//  Configuration models for the Google Cloud SDK and Antigravity bridge.
//

import Foundation

public enum GoogleCloudSDKServiceTier: String, Codable, Sendable {
    case standard = "standard"
    case priority = "priority"
}

public struct GoogleCloudSDKConfiguration: Codable, @unchecked Sendable {
    public var model: String
    public var apiKey: String?
    public var oauthToken: String?
    /// Explicit execution mode separating Google Sign-In Antigravity execution
    /// ("antigravity") from direct provider API-key execution ("api_key"),
    /// Vertex AI ("vertex"), or local runtimes ("local").
    public var executionMode: String?
    /// Google Cloud project ID used as the quota project (x-goog-user-project)
    /// for OAuth account authentication. Never fabricated: nil means "not
    /// configured".
    public var userProject: String?
    public var vertex: Bool
    public var project: String?
    public var location: String?
    public var systemInstructions: String?
    public var skillsPaths: [String]
    public var workspaces: [String]
    public var appDataDir: String?
    public var saveDir: String?
    public var enableSubagents: Bool
    public var maxSubagentDepth: Int
    public var allowedSubagents: [String]?
    public var serviceTier: GoogleCloudSDKServiceTier
    public var tools: [[String: Any]]?
    public var provider: String?
    public var baseURL: String?
    public var thinkingLevel: String?
    public var useSavedModels: Bool
    public var toolkit: String
    public var litertModelPath: String?
    public var litertBackend: String?
    public var downloadIfMissing: Bool
    public var enableSpeculativeDecoding: Bool
    /// Active Assist execution mode (e.g. "Plan" vs "Autopilot")
    public var activeExecutionMode: String?

    public init(
        model: String = "gemini-3.8-flash",
        apiKey: String? = nil,
        oauthToken: String? = nil,
        executionMode: String? = nil,
        userProject: String? = nil,
        vertex: Bool = false,
        project: String? = nil,
        location: String? = nil,
        systemInstructions: String? = nil,
        skillsPaths: [String] = [],
        workspaces: [String] = [],
        appDataDir: String? = nil,
        saveDir: String? = nil,
        enableSubagents: Bool = true,
        maxSubagentDepth: Int = 3,
        allowedSubagents: [String]? = nil,
        serviceTier: GoogleCloudSDKServiceTier = .standard,
        tools: [[String: Any]]? = nil,
        provider: String? = nil,
        baseURL: String? = nil,
        thinkingLevel: String? = nil,
        useSavedModels: Bool = false,
        toolkit: String = "System",
        litertModelPath: String? = nil,
        litertBackend: String? = nil,
        downloadIfMissing: Bool = false,
        enableSpeculativeDecoding: Bool = false,
        activeExecutionMode: String? = nil
    ) {
        self.model = model
        self.apiKey = apiKey
        self.oauthToken = oauthToken
        self.executionMode = executionMode
        self.userProject = userProject
        self.vertex = vertex
        self.project = project
        self.location = location
        self.systemInstructions = systemInstructions
        self.skillsPaths = skillsPaths
        self.workspaces = workspaces
        self.appDataDir = appDataDir
        self.saveDir = saveDir
        self.enableSubagents = enableSubagents
        self.maxSubagentDepth = maxSubagentDepth
        self.allowedSubagents = allowedSubagents
        self.serviceTier = serviceTier
        self.tools = tools
        self.provider = provider
        self.baseURL = baseURL
        self.thinkingLevel = thinkingLevel
        self.useSavedModels = useSavedModels
        self.toolkit = toolkit
        self.litertModelPath = litertModelPath
        self.litertBackend = litertBackend
        self.downloadIfMissing = downloadIfMissing
        self.enableSpeculativeDecoding = enableSpeculativeDecoding
        self.activeExecutionMode = activeExecutionMode
    }

    public enum CodingKeys: String, CodingKey {
        case model, apiKey, oauthToken, executionMode, userProject, vertex, project, location, systemInstructions, skillsPaths, workspaces, appDataDir, saveDir, enableSubagents, maxSubagentDepth, allowedSubagents, serviceTier, provider, baseURL, thinkingLevel, useSavedModels, toolkit
        case litertModelPath, litertBackend, downloadIfMissing, enableSpeculativeDecoding, activeExecutionMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        self.oauthToken = try container.decodeIfPresent(String.self, forKey: .oauthToken)
        self.executionMode = try container.decodeIfPresent(String.self, forKey: .executionMode)
        self.userProject = try container.decodeIfPresent(String.self, forKey: .userProject)
        self.vertex = try container.decode(Bool.self, forKey: .vertex)
        self.project = try container.decodeIfPresent(String.self, forKey: .project)
        self.location = try container.decodeIfPresent(String.self, forKey: .location)
        self.systemInstructions = try container.decodeIfPresent(String.self, forKey: .systemInstructions)
        self.activeExecutionMode = try container.decodeIfPresent(String.self, forKey: .activeExecutionMode)
        self.skillsPaths = try container.decode([String].self, forKey: .skillsPaths)
        self.workspaces = try container.decode([String].self, forKey: .workspaces)
        self.appDataDir = try container.decodeIfPresent(String.self, forKey: .appDataDir)
        self.saveDir = try container.decodeIfPresent(String.self, forKey: .saveDir)
        self.enableSubagents = try container.decode(Bool.self, forKey: .enableSubagents)
        self.maxSubagentDepth = try container.decode(Int.self, forKey: .maxSubagentDepth)
        self.allowedSubagents = try container.decodeIfPresent([String].self, forKey: .allowedSubagents)
        self.serviceTier = try container.decode(GoogleCloudSDKServiceTier.self, forKey: .serviceTier)
        self.provider = try container.decodeIfPresent(String.self, forKey: .provider)
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        self.thinkingLevel = try container.decodeIfPresent(String.self, forKey: .thinkingLevel)
        self.useSavedModels = try container.decodeIfPresent(Bool.self, forKey: .useSavedModels) ?? false
        self.toolkit = try container.decodeIfPresent(String.self, forKey: .toolkit) ?? "System"
        self.litertModelPath = try container.decodeIfPresent(String.self, forKey: .litertModelPath)
        self.litertBackend = try container.decodeIfPresent(String.self, forKey: .litertBackend)
        self.downloadIfMissing = try container.decodeIfPresent(Bool.self, forKey: .downloadIfMissing) ?? false
        self.enableSpeculativeDecoding = try container.decodeIfPresent(Bool.self, forKey: .enableSpeculativeDecoding) ?? false
        self.tools = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(apiKey, forKey: .apiKey)
        try container.encodeIfPresent(oauthToken, forKey: .oauthToken)
        try container.encodeIfPresent(executionMode, forKey: .executionMode)
        try container.encodeIfPresent(userProject, forKey: .userProject)
        try container.encode(vertex, forKey: .vertex)
        try container.encodeIfPresent(project, forKey: .project)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(systemInstructions, forKey: .systemInstructions)
        try container.encode(skillsPaths, forKey: .skillsPaths)
        try container.encode(workspaces, forKey: .workspaces)
        try container.encodeIfPresent(appDataDir, forKey: .appDataDir)
        try container.encodeIfPresent(saveDir, forKey: .saveDir)
        try container.encode(enableSubagents, forKey: .enableSubagents)
        try container.encode(maxSubagentDepth, forKey: .maxSubagentDepth)
        try container.encodeIfPresent(allowedSubagents, forKey: .allowedSubagents)
        try container.encode(serviceTier, forKey: .serviceTier)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(baseURL, forKey: .baseURL)
        try container.encodeIfPresent(thinkingLevel, forKey: .thinkingLevel)
        try container.encode(useSavedModels, forKey: .useSavedModels)
        try container.encode(toolkit, forKey: .toolkit)
        try container.encodeIfPresent(litertModelPath, forKey: .litertModelPath)
        try container.encodeIfPresent(litertBackend, forKey: .litertBackend)
        try container.encode(downloadIfMissing, forKey: .downloadIfMissing)
        try container.encode(enableSpeculativeDecoding, forKey: .enableSpeculativeDecoding)
    }

    /// Automatically resolves environment configuration from SwiftCode project, tools, and preferences.
    @MainActor
    public static func resolveDefault(for workspaceURL: URL? = nil, objective: String = "") -> GoogleCloudSDKConfiguration {
        let isSavedModels = AppSettings.shared.useSavedModels
        let activeModelId = AppSettings.shared.selectedAssistModelID

        var selectedModel = activeModelId
        var provider: String? = nil
        var baseURL: String? = nil
        var enableSubagents = true
        var apiKey: String? = nil

        if let routed = AssistModelRouter.shared.currentRuntimeModel {
            selectedModel = routed.modelIdentifier
            provider = routed.providerID
            baseURL = routed.endpointURL
            apiKey = AssistModelRouter.shared.resolveAPIKey(for: routed.providerID)
            enableSubagents = routed.supportsSubagents
        } else {
            let spec = AgentModelAdapter.shared.specification(for: activeModelId)
            selectedModel = activeModelId
            enableSubagents = spec.capabilities.contains(.subagents)

            switch spec.provider {
            case .anthropic:
                provider = "anthropic"
                apiKey = AssistModelRouter.shared.resolveAPIKey(for: "anthropic")
            case .openAI:
                provider = "openai"
                apiKey = AssistModelRouter.shared.resolveAPIKey(for: "openai")
            case .gemini:
                provider = "google"
                apiKey = AssistModelRouter.shared.resolveAPIKey(for: "google")
            case .mistral:
                provider = "mistral"
                baseURL = "https://api.mistral.ai/v1"
                apiKey = AssistModelRouter.shared.resolveAPIKey(for: "mistral")
            case .codex:
                provider = "codex"
                baseURL = "http://localhost:3003/v1"
                apiKey = AssistModelRouter.shared.resolveAPIKey(for: "codex")
            default:
                provider = spec.provider.rawValue.lowercased()
                apiKey = AssistModelRouter.shared.resolveAPIKey(for: provider ?? "openrouter")
            }
        }

        // Alternative Keys resolution strictly for Gemini/Google when enabled
        if AppSettings.shared.alternativeKeysEnabled, provider == "gemini" || provider == "google" {
            if let altKey = AlternativeKeyManager.shared.getActiveOrNextKey() {
                apiKey = altKey.key
            }
        }

        var workspaces: [String] = []
        var skillsPaths: [String] = []
        var repositoryInstructions: String? = nil

        let targetURL = workspaceURL ?? ProjectSessionStore.shared.activeProject?.directoryURL

        if let rootURL = targetURL {
            let rootPath = rootURL.path
            workspaces.append(rootPath)

            let candidates = ["AGENTS.md", "Agents.md", "Agent.md"]
            for name in candidates {
                let candidateURL = rootURL.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidateURL.path),
                   let repoAgentsContent = try? String(contentsOf: candidateURL, encoding: .utf8),
                   !repoAgentsContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    repositoryInstructions = repoAgentsContent
                    break
                }
            }

            let repoSkills = rootURL.appendingPathComponent(".agents/skills")
            if FileManager.default.fileExists(atPath: repoSkills.path) {
                skillsPaths.append(repoSkills.path)
            }
        }

        let systemPrompt = (try? AssistManager.shared.getSystemPrompt()) ?? ""
        let effectiveInstructions = AssistSystemPromptSections.runtimeInstructions(
            from: systemPrompt,
            repositoryInstructions: repositoryInstructions,
            toolkit: AppSettings.shared.assistToolkit,
            objective: objective
        )

        if let bundledResource = Bundle.main.resourceURL?.appendingPathComponent("Google Cloud SDK/skills") {
            if FileManager.default.fileExists(atPath: bundledResource.path) {
                skillsPaths.append(bundledResource.path)
            }
        }

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let sdkStorage = appSupport.appendingPathComponent("SwiftCode/GoogleCloudSDK", isDirectory: true)
        let appDataDir = sdkStorage.appendingPathComponent("brain", isDirectory: true).path
        let saveDir = sdkStorage.appendingPathComponent("persistence", isDirectory: true).path

        try? fm.createDirectory(atPath: appDataDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: saveDir, withIntermediateDirectories: true)

        let toolkit = AppSettings.shared.assistToolkit
        let toolSchemas = toolkit.caseInsensitiveCompare("cloud") == .orderedSame
            ? nil
            : AssistManager.shared.registry.getToolSchemas()

        var oauthToken: String? = nil
        var executionMode: String? = nil
        let googleAuthMode = UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? AppSettings.shared.assistGoogleAuthMode
        let isOAuthMode = googleAuthMode == "google_oauth"
        let isGoogleProvider = provider == "google" || provider == "gemini"
        let isAntigravityCatalogModel = AntigravitySDKModelFetcher.shared.getModel(byID: selectedModel) != nil
            || AntigravitySDKModelFetcher.seedModels.contains(where: { $0.id == selectedModel })

        if isOAuthMode && GoogleAccountAuthService.shared.isAuthenticated && !AppSettings.shared.alternativeKeysEnabled {
            if isGoogleProvider || (isAntigravityCatalogModel && (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                oauthToken = GoogleAccountAuthService.shared.getValidAccessToken()
                apiKey = nil
                executionMode = "antigravity"
            }
        }

        if executionMode == nil {
            if !(apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                executionMode = "api_key"
            } else if ["ollama", "lmstudio", "local", "litert"].contains((provider ?? "").lowercased()) {
                executionMode = "local"
            }
        }

        let userProject: String? = {
            let configured = AppSettings.shared.assistGoogleCloudProject.trimmingCharacters(in: .whitespacesAndNewlines)
            if !configured.isEmpty { return configured }
            if let env = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]?.trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty { return env }
            return nil
        }()

        if oauthToken != nil {
            apiKey = nil
        }

        return GoogleCloudSDKConfiguration(
            model: selectedModel,
            apiKey: apiKey,
            oauthToken: oauthToken,
            executionMode: executionMode,
            userProject: userProject,
            vertex: false,
            project: nil,
            location: nil,
            systemInstructions: effectiveInstructions,
            skillsPaths: skillsPaths,
            workspaces: workspaces,
            appDataDir: appDataDir,
            saveDir: saveDir,
            enableSubagents: enableSubagents,
            maxSubagentDepth: 3,
            allowedSubagents: nil,
            serviceTier: .standard,
            tools: toolSchemas,
            provider: provider,
            baseURL: baseURL,
            useSavedModels: isSavedModels,
            toolkit: toolkit,
            litertModelPath: (provider == "litert" || selectedModel.lowercased().contains(".litertlm")) ? selectedModel : nil,
            litertBackend: (provider == "litert" || selectedModel.lowercased().contains(".litertlm")) ? "gpu" : nil,
            downloadIfMissing: false,
            enableSpeculativeDecoding: false,
            activeExecutionMode: UserDefaults.standard.string(forKey: "com.swiftcode.assist.executionMode") ?? ExecutionMode.autopilot.rawValue
        )
    }

    /// Converts configuration to a JSON-serializable dictionary for IPC.
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "model": model,
            "vertex": vertex,
            "enableSubagents": enableSubagents,
            "maxSubagentDepth": maxSubagentDepth,
            "serviceTier": serviceTier.rawValue,
            "skillsPaths": skillsPaths,
            "workspaces": workspaces,
            "useSavedModels": useSavedModels,
            "toolkit": toolkit,
            "downloadIfMissing": downloadIfMissing,
            "enableSpeculativeDecoding": enableSpeculativeDecoding
        ]

        if let activeExecutionMode = activeExecutionMode {
            dict["activeExecutionMode"] = activeExecutionMode
        }

        let trimmedApiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isAntigravityMode = (executionMode == "antigravity" || provider == "antigravity") && trimmedApiKey.isEmpty
        let isGoogleProvider = provider == "google" || provider == "gemini"
            || (provider == nil && model.lowercased().hasPrefix("gemini-"))

        let accountToken = (isGoogleProvider || isAntigravityMode)
            ? oauthToken?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        if let accountToken, !accountToken.isEmpty {
            dict["oauthToken"] = accountToken
        }

        if (isGoogleProvider || isAntigravityMode),
           let userProject = userProject?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userProject.isEmpty {
            dict["headers"] = ["x-goog-user-project": userProject]
        }

        if let executionMode = executionMode, !executionMode.isEmpty, trimmedApiKey.isEmpty || executionMode == "api_key" {
            dict["executionMode"] = executionMode
        }

        if let provider = provider, !provider.isEmpty {
            dict["provider"] = provider
        }
        if let thinkingLevel = thinkingLevel, !thinkingLevel.isEmpty {
            dict["thinkingLevel"] = thinkingLevel
        }
        if let baseURL = baseURL, !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                dict["baseURL"] = trimmed
            } else if trimmed.hasPrefix("127.0.0.1") || trimmed.hasPrefix("localhost") {
                dict["baseURL"] = "http://\(trimmed)"
            } else {
                dict["baseURL"] = "https://\(trimmed)"
            }
        }
        if (accountToken ?? "").isEmpty, !trimmedApiKey.isEmpty {
            dict["apiKey"] = trimmedApiKey
        }
        if let project = project, !project.isEmpty {
            dict["project"] = project
        }
        if let location = location, !location.isEmpty {
            dict["location"] = location
        }
        if let systemInstructions = systemInstructions, !systemInstructions.isEmpty {
            dict["systemInstructions"] = systemInstructions
        }
        if let appDataDir = appDataDir, !appDataDir.isEmpty {
            dict["appDataDir"] = appDataDir
        }
        if let saveDir = saveDir, !saveDir.isEmpty {
            dict["saveDir"] = saveDir
        }
        if let allowedSubagents = allowedSubagents {
            dict["allowedSubagents"] = allowedSubagents
        }
        if let tools = tools {
            dict["tools"] = tools
        }
        if let litertModelPath = litertModelPath, !litertModelPath.isEmpty {
            dict["litertModelPath"] = litertModelPath
            dict["modelPath"] = litertModelPath
        }
        if let litertBackend = litertBackend, !litertBackend.isEmpty {
            dict["litertBackend"] = litertBackend
        }

        return dict
    }

    /// Session-reuse contract (C-3): a live bridge session may only be reused
    /// when every credential-bearing field matches.
    public func canReuseSession(for newConfig: GoogleCloudSDKConfiguration) -> Bool {
        return model == newConfig.model &&
            provider == newConfig.provider &&
            executionMode == newConfig.executionMode &&
            activeExecutionMode == newConfig.activeExecutionMode &&
            baseURL == newConfig.baseURL &&
            thinkingLevel == newConfig.thinkingLevel &&
            apiKey == newConfig.apiKey &&
            oauthToken == newConfig.oauthToken &&
            userProject == newConfig.userProject &&
            systemInstructions == newConfig.systemInstructions &&
            workspaces == newConfig.workspaces &&
            toolkit == newConfig.toolkit
    }
}
