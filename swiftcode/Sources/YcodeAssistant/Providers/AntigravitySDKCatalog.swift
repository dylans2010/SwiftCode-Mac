import Foundation
import YcodeSubprocess

public struct AntigravitySDKModel: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public var name: String { displayName }
    public let thinkingLevel: String
    public let contextWindow: Int
    public let isImageModel: Bool
    public let category: String

    public init(
        id: String,
        displayName: String,
        thinkingLevel: String,
        contextWindow: Int = 1_048_576,
        isImageModel: Bool = false,
        category: String = "Google"
    ) {
        self.id = id
        self.displayName = displayName
        self.thinkingLevel = thinkingLevel
        self.contextWindow = contextWindow
        self.isImageModel = isImageModel
        self.category = category
    }
}

public actor AntigravitySDKCatalog {
    public static let shared = AntigravitySDKCatalog()

    public nonisolated static let seedModels: [AntigravitySDKModel] = [
        AntigravitySDKModel(id: "gemini-3.8-flash-high", displayName: "Gemini 3.8 Flash (High)", thinkingLevel: "High", contextWindow: 1_048_576, category: "Google"),
        AntigravitySDKModel(id: "gemini-3.8-flash-medium", displayName: "Gemini 3.8 Flash (Medium)", thinkingLevel: "Medium", contextWindow: 1_048_576, category: "Google"),
        AntigravitySDKModel(id: "gemini-3.8-flash-low", displayName: "Gemini 3.8 Flash (Low)", thinkingLevel: "Low", contextWindow: 1_048_576, category: "Google"),
        AntigravitySDKModel(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6 (Thinking)", thinkingLevel: "High", contextWindow: 200_000, category: "Anthropic"),
        AntigravitySDKModel(id: "claude-opus-4-6-thinking", displayName: "Claude Opus 4.6 (Thinking)", thinkingLevel: "High", contextWindow: 200_000, category: "Anthropic"),
        AntigravitySDKModel(id: "gpt-oss-120b-medium", displayName: "GPT-OSS 120B (Medium)", thinkingLevel: "Medium", contextWindow: 128_000, category: "OpenAI"),
        AntigravitySDKModel(id: "gemini-3.8-flash", displayName: "Gemini 3.8 Flash", thinkingLevel: "High", contextWindow: 1_048_576, category: "Google"),
        AntigravitySDKModel(id: "gemini-3.1-pro", displayName: "Gemini 3.1 Pro", thinkingLevel: "High", contextWindow: 2_097_152, category: "Google"),
        AntigravitySDKModel(id: "gemini-3-flash", displayName: "Gemini 3 Flash", thinkingLevel: "Medium", contextWindow: 1_048_576, category: "Google"),
    ]

    public nonisolated static let agyBinaryCandidates: [String] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/bin/agy").path,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy").path,
        "/usr/local/bin/agy",
        "/opt/homebrew/bin/agy",
    ]

    public private(set) var models: [AntigravitySDKModel]
    public private(set) var lastFetchDate: Date?
    public private(set) var fetchError: String?

    public init(models: [AntigravitySDKModel] = seedModels) {
        self.models = models
    }

    public var allModelIDs: [String] { models.map { $0.id } }

    public var sdkDefaultModelIDs: [String] {
        let list = allModelIDs
        if !list.isEmpty { return list }
        return Self.seedModels.map { $0.id }
    }

    public func getModel(byID id: String) -> AntigravitySDKModel? {
        models.first { $0.id == id } ?? Self.seedModels.first { $0.id == id }
    }

    public func isAntigravityCatalogModel(_ modelID: String) -> Bool {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if models.contains(where: { $0.id.lowercased() == normalized }) { return true }
        return Self.seedModels.contains { $0.id.lowercased() == normalized }
    }

    public func models(forThinkingLevel level: String) -> [AntigravitySDKModel] {
        let normalized = level.lowercased()
        return models.filter { $0.thinkingLevel.lowercased() == normalized }
    }

    @discardableResult
    public func fetchModels() async -> [AntigravitySDKModel] {
        let fetched = await Task.detached(priority: .userInitiated) {
            for binaryPath in Self.agyBinaryCandidates {
                guard FileManager.default.isExecutableFile(atPath: binaryPath) else { continue }
                if let parsed = Self.runAgyProcess(binaryPath: binaryPath), !parsed.isEmpty {
                    return parsed
                }
            }
            return [AntigravitySDKModel]()
        }.value
        if !fetched.isEmpty {
            models = fetched
            lastFetchDate = Date()
            fetchError = nil
        } else if models.isEmpty {
            fetchError = "The Antigravity CLI returned no models; retaining the current catalog."
        }
        return models
    }

    public func updateModels(_ newModels: [AntigravitySDKModel]) {
        models = newModels
        lastFetchDate = Date()
    }

    private nonisolated static func runAgyProcess(binaryPath: String) -> [AntigravitySDKModel]? {
        guard let out = try? Subprocess.run(binaryPath, ["models"], environment: [
            "PAGER": "cat",
            "NO_COLOR": "1",
            "TERM": "dumb",
        ]) else { return nil }
        guard out.status == 0, let output = String(data: out.stdout, encoding: .utf8) else { return nil }
        let parsed = parseAgyModelsOutput(output)
        return parsed.isEmpty ? nil : parsed
    }

    public nonisolated static func parseAgyModelsOutput(_ output: String) -> [AntigravitySDKModel] {
        var result: [AntigravitySDKModel] = []

        var noAnsi = output
        if let regex = try? NSRegularExpression(pattern: "\\x1B\\[[0-9;?]*[a-zA-Z]") {
            noAnsi = regex.stringByReplacingMatches(in: output, range: NSRange(location: 0, length: output.utf16.count), withTemplate: "")
        }
        let cleaned = noAnsi
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "Fetching available models...", with: "")
        for line in cleaned.components(separatedBy: .newlines) {
            let sanitized = line.unicodeScalars.filter { scalar in
                !(0x2800...0x28FF).contains(scalar.value)
            }.map { String($0) }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sanitized.isEmpty, !sanitized.contains("Fetching") else { continue }
            let components = sanitized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let modelId = components.first, !modelId.isEmpty else { continue }
            let displayName = components.count > 1 ? components.dropFirst().joined(separator: " ") : modelId
            result.append(AntigravitySDKModel(
                id: modelId,
                displayName: displayName,
                thinkingLevel: deriveThinkingLevel(modelID: modelId, displayName: displayName),
                contextWindow: deriveContextWindow(modelID: modelId),
                isImageModel: modelId.contains("image") || displayName.lowercased().contains("image"),
                category: deriveCategory(modelID: modelId)
            ))
        }
        return result
    }

    public nonisolated static func deriveThinkingLevel(modelID: String, displayName: String) -> String {
        let lower = (modelID + " " + displayName).lowercased()
        if lower.contains("high") || lower.contains("extra_high") || lower.contains("deep") {
            return "High"
        } else if lower.contains("low") || lower.contains("fast") {
            return "Low"
        } else if lower.contains("minimal") {
            return "Minimal"
        } else if lower.contains("thinking") {
            return "High"
        } else {
            return "Medium"
        }
    }

    public nonisolated static func deriveContextWindow(modelID: String) -> Int {
        let lower = modelID.lowercased()
        if lower.contains("2.5-pro") || lower.contains("3.1-pro") {
            return 2_097_152
        } else if lower.contains("flash") {
            return 1_048_576
        } else if lower.contains("claude") {
            return 200_000
        } else if lower.contains("gpt") {
            return 128_000
        } else {
            return 1_048_576
        }
    }

    public nonisolated static func deriveCategory(modelID: String) -> String {
        let lower = modelID.lowercased()
        if lower.contains("claude") || lower.hasPrefix("anthropic/") {
            return "Anthropic"
        } else if lower.contains("gpt") || lower.hasPrefix("openai/") {
            return "OpenAI"
        } else if lower.hasPrefix("ollama/") || lower.contains("ollama") {
            return "Ollama"
        } else if lower.hasPrefix("local/") || lower.contains("local") {
            return "Local"
        } else if let slashIdx = lower.firstIndex(of: "/") {
            let provider = String(lower[..<slashIdx])
            return provider.capitalized
        } else if lower.contains("gemini") {
            return "Google"
        } else {
            return "Google"
        }
    }

    public func createSyntheticCandidate(modelID: String, isConfigured: Bool) -> AssistCandidateModel {
        if let sdkModel = getModel(byID: modelID) {
            return AssistCandidateModel(
                id: sdkModel.id,
                displayName: sdkModel.displayName,
                provider: AssistModelSpecification.specification(for: sdkModel.id).provider,
                modelIdentifier: sdkModel.id,
                capabilities: [.streaming, .toolCalling, .vision, .structuredOutput, .subagents],
                contextWindow: sdkModel.contextWindow,
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsAgenticUse: true,
                supportsSubagents: !sdkModel.isImageModel,
                supportsVision: true,
                supportsStructuredOutput: true,
                priority: 1,
                isConfigured: isConfigured,
                hasCredentials: isConfigured,
                source: .provider,
                statusDescription: "\(sdkModel.thinkingLevel) Thinking · Antigravity catalog (synthetic)",
                isSynthetic: true
            )
        }
        let level = Self.deriveThinkingLevel(modelID: modelID, displayName: modelID)
        let contextWindow = Self.deriveContextWindow(modelID: modelID)
        let formattedName = modelID
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
        return AssistCandidateModel(
            id: modelID,
            displayName: "\(formattedName) (\(level))",
            provider: AssistModelSpecification.specification(for: modelID).provider,
            modelIdentifier: modelID,
            capabilities: [.streaming, .toolCalling, .vision, .structuredOutput, .subagents],
            contextWindow: contextWindow,
            supportsStreaming: true,
            supportsToolCalling: true,
            supportsAgenticUse: true,
            supportsSubagents: !modelID.contains("image"),
            supportsVision: true,
            supportsStructuredOutput: true,
            priority: 5,
            isConfigured: isConfigured,
            hasCredentials: isConfigured,
            source: .provider,
            statusDescription: "\(level) Thinking · Antigravity catalog (synthetic)",
            isSynthetic: true
        )
    }
}
