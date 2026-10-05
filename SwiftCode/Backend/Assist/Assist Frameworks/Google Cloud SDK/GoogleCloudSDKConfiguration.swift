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

public struct GoogleCloudSDKConfiguration: Codable, Sendable {
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
        serviceTier: GoogleCloudSDKServiceTier = .standard
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
    }

    /// Automatically resolves environment configuration from SwiftCode project and preferences.
    @MainActor
    public static func resolveDefault(for workspaceURL: URL? = nil) -> GoogleCloudSDKConfiguration {
        let selectedModel = UserDefaults.standard.string(forKey: "assist.geminiModel") ?? "gemini-3.8-flash"
        let apiKey = KeychainService.shared.get(forKey: LLMProvider.google.keychainKey)

        var workspaces: [String] = []
        var skillsPaths: [String] = []
        var systemInstructions: String? = nil

        let targetURL = workspaceURL ?? ProjectSessionStore.shared.activeProject?.directoryURL

        if let rootURL = targetURL {
            let rootPath = rootURL.path
            workspaces.append(rootPath)

            // Discover repository AGENTS.md / Agent.md
            let candidates = ["AGENTS.md", "Agents.md", "Agent.md"]
            for name in candidates {
                let candidateURL = rootURL.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidateURL.path),
                   let content = try? String(contentsOf: candidateURL, encoding: .utf8),
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    systemInstructions = content
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

        return GoogleCloudSDKConfiguration(
            model: selectedModel,
            apiKey: apiKey,
            vertex: false,
            project: nil,
            location: nil,
            systemInstructions: systemInstructions,
            skillsPaths: skillsPaths,
            workspaces: workspaces,
            appDataDir: appDataDir,
            saveDir: saveDir,
            enableSubagents: true,
            maxSubagentDepth: 3,
            allowedSubagents: nil,
            serviceTier: .standard
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
        ]

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

        return dict
    }
}
