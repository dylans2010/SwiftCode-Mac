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
    public var useSavedModels: Bool

    public init(
        model: String = "gemini-3.8-flash",
        apiKey: String? = nil,
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
        useSavedModels: Bool = false
    ) {
        self.model = model
        self.apiKey = apiKey
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
        self.useSavedModels = useSavedModels
    }

    public enum CodingKeys: String, CodingKey {
        case model, apiKey, vertex, project, location, systemInstructions, skillsPaths, workspaces, appDataDir, saveDir, enableSubagents, maxSubagentDepth, allowedSubagents, serviceTier, provider, baseURL, useSavedModels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        self.vertex = try container.decode(Bool.self, forKey: .vertex)
        self.project = try container.decodeIfPresent(String.self, forKey: .project)
        self.location = try container.decodeIfPresent(String.self, forKey: .location)
        self.systemInstructions = try container.decodeIfPresent(String.self, forKey: .systemInstructions)
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
        self.useSavedModels = try container.decodeIfPresent(Bool.self, forKey: .useSavedModels) ?? false
        self.tools = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(apiKey, forKey: .apiKey)
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
        try container.encode(useSavedModels, forKey: .useSavedModels)
    }

    /// Automatically resolves environment configuration from SwiftCode project, tools, and preferences.
    @MainActor
    public static func resolveDefault(for workspaceURL: URL? = nil) -> GoogleCloudSDKConfiguration {
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
        var effectiveInstructions: String? = nil

        // Load SwiftCode system prompt AgentSystemAsset.md
        if let systemPrompt = try? AssistManager.shared.getSystemPrompt() {
            effectiveInstructions = systemPrompt
        }

        let targetURL = workspaceURL ?? ProjectSessionStore.shared.activeProject?.directoryURL

        if let rootURL = targetURL {
            let rootPath = rootURL.path
            workspaces.append(rootPath)

            // Discover repository AGENTS.md / Agent.md and append if present
            let candidates = ["AGENTS.md", "Agents.md", "Agent.md"]
            for name in candidates {
                let candidateURL = rootURL.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidateURL.path),
                   let repoAgentsContent = try? String(contentsOf: candidateURL, encoding: .utf8),
                   !repoAgentsContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let existing = effectiveInstructions {
                        effectiveInstructions = existing + "\n\n# REPOSITORY SPECIFIC AGENTS RULES\n" + repoAgentsContent
                    } else {
                        effectiveInstructions = repoAgentsContent
                    }
                    break
                }
            }

            // Discover repository skills
            let repoSkills = rootURL.appendingPathComponent(".agents/skills")
            if FileManager.default.fileExists(atPath: repoSkills.path) {
                skillsPaths.append(repoSkills.path)
            }
        }

        // Add bundled skills if available
        if let bundledResource = Bundle.main.resourceURL?.appendingPathComponent("Google Cloud SDK/skills") {
            if FileManager.default.fileExists(atPath: bundledResource.path) {
                skillsPaths.append(bundledResource.path)
            }
        }

        // Isolate persistent state in Application Support
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let sdkStorage = appSupport.appendingPathComponent("SwiftCode/GoogleCloudSDK", isDirectory: true)
        let appDataDir = sdkStorage.appendingPathComponent("brain", isDirectory: true).path
        let saveDir = sdkStorage.appendingPathComponent("persistence", isDirectory: true).path

        try? fm.createDirectory(atPath: appDataDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: saveDir, withIntermediateDirectories: true)

        // Derive dynamic tool schemas from SwiftCode Tool Registry
        let toolSchemas = AssistManager.shared.registry.getToolSchemas()

        return GoogleCloudSDKConfiguration(
            model: selectedModel,
            apiKey: apiKey,
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
            useSavedModels: isSavedModels
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
            "useSavedModels": useSavedModels
        ]

        if let provider = provider, !provider.isEmpty {
            dict["provider"] = provider
        }
        if let baseURL = baseURL, !baseURL.isEmpty {
            dict["baseURL"] = baseURL
        }
        if let apiKey = apiKey, !apiKey.isEmpty {
            dict["apiKey"] = apiKey
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

        return dict
    }
}
