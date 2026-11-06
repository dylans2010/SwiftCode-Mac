import Foundation
import YcodeSubprocess

// MARK: - Antigravity SDK model catalog (Wave 16, Slice D)
//
// Ported from Legacy (Dylan's own code; direct port authorised under
// MIT, spec-first where it costs nothing):
//   * `SwiftCode/Services/AntigravitySDKModelFetcher.swift` —
//     `AntigravitySDKModel`, `seedModels`, `fetchModels`,
//     `parseAgyModelsOutput`, `deriveThinkingLevel`,
//     `deriveContextWindow`, `deriveCategory`,
//     `isAntigravityCatalogModel`, `getModel(byID:)`.
//
// The catalog is the live model list of the Google Antigravity SDK
// (`agy models` on the Antigravity CLI), with Legacy's seed catalog
// as the fallback when the CLI is absent. Models from this catalog
// are NEVER presented as discovered: `createSyntheticCandidate`
// marks them `isSynthetic`, and the discovery service labels them
// "Antigravity catalog" in `statusDescription`.
//
// Adaptations (the host has no Antigravity SDK session):
//   * No SwiftUI: `iconName` / `thinkingColor` are not ported.
//     Callers that need an icon derive it from `thinkingLevel` /
//     `isImageModel` themselves.
//   * No `@Observable` / `@Published`: this is an actor. The host
//     owns one (`shared`); callers `await` its state.
//   * No disk cache: Legacy persisted the fetched list in
//     UserDefaults. Ycode keeps the fetched list in memory only and
//     falls back to the seed catalog on a fresh launch, exactly as
//     Legacy did when its cache was empty. Persisting the cache is
//     follow-up work, not a behaviour change.
//   * No Python fallback: Legacy's `runPythonSDKModelDiscoverySync`
//     ran the vendored Google Cloud SDK's bundled python3
//     (`SwiftCode/Resources/Google Cloud SDK/...`). That vendored
//     tree is EXTERNAL_OR_UNAVAILABLE in the migration inventory
//     and was never copied into Ycode, so there is no bundled
//     runtime to run. Live discovery here is the `agy` binary
//     only; when no `agy` binary is found the seed catalog stands.
//   * `sdkDefaultModelIDs` (Legacy `AssistModelRouter`) lives here
//     as a computed property, because the catalog — not the router
//     — owns the live-vs-seed rule.

// MARK: - Model

/// One model in the Antigravity SDK catalog (Legacy
/// `AntigravitySDKModelFetcher.AntigravitySDKModel`).
public struct AntigravitySDKModel: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public var name: String { displayName }
    /// "Low", "Medium", "High", "Minimal".
    public let thinkingLevel: String
    public let contextWindow: Int
    public let isImageModel: Bool
    /// "Google", "Anthropic", "OpenAI", ...
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

// MARK: - Catalog

/// The Antigravity SDK's model catalog: live-fetched from the `agy`
/// CLI when it exists, otherwise Legacy's seed catalog.
public actor AntigravitySDKCatalog {
    public static let shared = AntigravitySDKCatalog()

    /// The canonical seed catalog (Legacy `seedModels`, verbatim).
    /// These ids are Dylan's own catalog entries, not a Ycode
    /// invention — but they are a *seed*, not a discovery: callers
    /// must present them as catalog models, never as live-listed.
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

    /// Where the `agy` CLI is looked for (Legacy's candidates,
    /// verbatim, in order).
    public nonisolated static let agyBinaryCandidates: [String] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/bin/agy").path,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy").path,
        "/usr/local/bin/agy",
        "/opt/homebrew/bin/agy",
    ]

    /// The live-fetched models; the seed catalog until the first
    /// successful fetch.
    public private(set) var models: [AntigravitySDKModel]
    public private(set) var lastFetchDate: Date?
    public private(set) var fetchError: String?

    public init(models: [AntigravitySDKModel] = seedModels) {
        self.models = models
    }

    public var allModelIDs: [String] { models.map { $0.id } }

    /// The default model ids for SDK-strategy selection (Legacy
    /// `AssistModelRouter.sdkDefaultModelIDs`): the live list when
    /// it is non-empty, otherwise the seed catalog.
    public var sdkDefaultModelIDs: [String] {
        let list = allModelIDs
        if !list.isEmpty { return list }
        return Self.seedModels.map { $0.id }
    }

    public func getModel(byID id: String) -> AntigravitySDKModel? {
        models.first { $0.id == id } ?? Self.seedModels.first { $0.id == id }
    }

    /// Whether `modelID` belongs to the catalog (live-fetched or
    /// seed). Membership is metadata, not authorization: it never
    /// implies a credential exists for the model.
    public func isAntigravityCatalogModel(_ modelID: String) -> Bool {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if models.contains(where: { $0.id.lowercased() == normalized }) { return true }
        return Self.seedModels.contains { $0.id.lowercased() == normalized }
    }

    public func models(forThinkingLevel level: String) -> [AntigravitySDKModel] {
        let normalized = level.lowercased()
        return models.filter { $0.thinkingLevel.lowercased() == normalized }
    }

    /// Fetches the live list from the `agy` CLI. An empty result
    /// keeps the current list (Legacy: "Retaining current
    /// registry"). The seed catalog is never overwritten by a
    /// failed fetch.
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

    // MARK: - `agy models` execution & parsing

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

    /// Parses `agy models` stdout (Legacy
    /// `parseAgyModelsOutput`, verbatim rules): strips ANSI
    /// escapes, braille characters and the "Fetching available
    /// models..." line; the first whitespace-separated token of
    /// each remaining line is the model id, the rest is the
    /// display name. Thinking level, context window and category
    /// are derived from the id/display name.
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

    /// The thinking level implied by a model id / display name
    /// (Legacy `deriveThinkingLevel`, verbatim).
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

    /// The context window implied by a model id (Legacy
    /// `deriveContextWindow`, verbatim).
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

    /// The vendor category implied by a model id (Legacy
    /// `deriveCategory`, verbatim).
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

    // MARK: - Synthetic router candidate

    /// The router candidate for a catalog model id (Legacy
    /// `AssistModelRouter.createSyntheticSDKModel`, adapted to
    /// `AssistCandidateModel`).
    ///
    /// The candidate is marked `isSynthetic` and its
    /// `statusDescription` names the catalog: it was synthesized
    /// from the Antigravity catalog, not discovered from a
    /// provider's list endpoint. `isConfigured` is the caller's
    /// credential verdict for this model — the catalog itself
    /// never claims a credential exists.
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
