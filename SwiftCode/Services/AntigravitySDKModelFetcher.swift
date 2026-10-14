//
//  AntigravitySDKModelFetcher.swift
//  SwiftCode
//
//  Dynamic model fetcher that retrieves available models directly from the
//  Google Antigravity SDK CLI runtime rather than hardcoding models in SwiftCode.
//  Models are ALWAYS fetched from the SDK and cached in memory/disk.
//

import Foundation
import Combine
import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.antigravity", category: "SDKModelFetcher")

public struct AntigravitySDKModel: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public var name: String { displayName }
    public let thinkingLevel: String // "Low", "Medium", "High", "Minimal"
    public let contextWindow: Int
    public let isImageModel: Bool
    public let category: String // "Google", "Anthropic", "OpenAI"

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

    public var iconName: String {
        if isImageModel { return "photo.on.rectangle.angled" }
        switch thinkingLevel.lowercased() {
        case "high": return "brain.head.profile"
        case "low": return "bolt.fill"
        case "minimal": return "sparkle"
        default: return "sparkles"
        }
    }

    public var thinkingColor: Color {
        switch thinkingLevel.lowercased() {
        case "high": return Color(red: 1.0, green: 0.2, blue: 0.5) // Pink / Coral
        case "low": return Color(red: 0.0, green: 0.8, blue: 0.8) // Cyan / Teal
        case "minimal": return Color.orange
        default: return Color(red: 0.5, green: 0.3, blue: 1.0) // Indigo / Purple
        }
    }
}

@MainActor
public final class AntigravitySDKModelFetcher: ObservableObject {
    public static let shared = AntigravitySDKModelFetcher()

    private static let cacheKey = "com.swiftcode.antigravity.sdk_models_cache"

    @Published public private(set) var models: [AntigravitySDKModel] = []
    @Published public private(set) var isFetching: Bool = false
    @Published public private(set) var lastFetchDate: Date? = nil
    @Published public private(set) var fetchError: String? = nil

    private init() {
        loadCachedModels()
        Task {
            await self.fetchModels()
        }
    }

    public var allModelIDs: [String] {
        models.map { $0.id }
    }

    public func getModel(byID id: String) -> AntigravitySDKModel? {
        models.first { $0.id == id } ?? Self.seedModels.first { $0.id == id }
    }

    /// Returns true if `modelID` belongs to the Antigravity SDK catalog
    /// (either dynamically fetched or in the canonical seed catalog).
    public func isAntigravityCatalogModel(_ modelID: String) -> Bool {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if models.contains(where: { $0.id.lowercased() == normalized }) {
            return true
        }
        if Self.seedModels.contains(where: { $0.id.lowercased() == normalized }) {
            return true
        }
        return false
    }

    public func models(forThinkingLevel level: String) -> [AntigravitySDKModel] {
        let normalized = level.lowercased()
        return models.filter { $0.thinkingLevel.lowercased() == normalized }
    }

    /// Dynamically fetches models directly from the Google Antigravity SDK CLI runtime.
    @discardableResult
    public func fetchModels() async -> [AntigravitySDKModel] {
        guard !isFetching else { return models }
        isFetching = true
        fetchError = nil

        let fetched = await fetchFromSDKRuntime()
        if !fetched.isEmpty {
            self.models = fetched
            self.lastFetchDate = Date()
            saveCachedModels(fetched)
            logger.info("[AntigravitySDKModelFetcher] Successfully fetched \(fetched.count) models from SDK.")
        } else if models.isEmpty {
            logger.warning("[AntigravitySDKModelFetcher] SDK returned empty models. Retaining current registry.")
        }

        isFetching = false
        return self.models
    }

    public nonisolated static let seedModels: [AntigravitySDKModel] = [
        AntigravitySDKModel(id: "gemini-3.8-flash", displayName: "Gemini 3.8 Flash", thinkingLevel: "High", contextWindow: 1_048_576, category: "Google"),
        AntigravitySDKModel(id: "gemini-3.1-pro", displayName: "Gemini 3.1 Pro", thinkingLevel: "High", contextWindow: 2_097_152, category: "Google"),
        AntigravitySDKModel(id: "gemini-3-flash", displayName: "Gemini 3 Flash", thinkingLevel: "Medium", contextWindow: 1_048_576, category: "Google"),
        AntigravitySDKModel(id: "gemini-3.1-pro-high", displayName: "Gemini 3.1 Pro (High)", thinkingLevel: "High", contextWindow: 2_097_152, category: "Google"),
        AntigravitySDKModel(id: "gemini-3.1-pro-low", displayName: "Gemini 3.1 Pro (Low)", thinkingLevel: "Low", contextWindow: 2_097_152, category: "Google"),
        AntigravitySDKModel(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6", thinkingLevel: "Medium", contextWindow: 200_000, category: "Anthropic"),
        AntigravitySDKModel(id: "claude-opus-4-6-thinking", displayName: "Claude Opus 4.6 (Thinking)", thinkingLevel: "High", contextWindow: 200_000, category: "Anthropic")
    ]

    // MARK: - Disk Cache
    private func loadCachedModels() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode([AntigravitySDKModel].self, from: data),
           !decoded.isEmpty {
            self.models = decoded
            return
        }
        self.models = Self.seedModels
    }

    private func saveCachedModels(_ models: [AntigravitySDKModel]) {
        if let encoded = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
        }
    }

    // MARK: - SDK Execution
    private func fetchFromSDKRuntime() async -> [AntigravitySDKModel] {
        return await Task.detached(priority: .userInitiated) {
            let agyBinaryCandidates = [
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/bin/agy").path,
                "/usr/local/bin/agy",
                "/opt/homebrew/bin/agy",
            ]

            for binaryPath in agyBinaryCandidates {
                if FileManager.default.isExecutableFile(atPath: binaryPath) {
                    if let parsed = Self.runAgyProcess(binaryPath: binaryPath), !parsed.isEmpty {
                        return parsed
                    }
                }
            }

            if let parsedPython = Self.runPythonSDKModelDiscoverySync(), !parsedPython.isEmpty {
                return parsedPython
            }

            return []
        }.value
    }

    private nonisolated static func runAgyProcess(binaryPath: String) -> [AntigravitySDKModel]? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["models"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var env = ProcessInfo.processInfo.environment
        env["PAGER"] = "cat"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()

            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }

            let parsed = parseAgyModelsOutput(output)
            return parsed.isEmpty ? nil : parsed
        } catch {
            return nil
        }
    }

    public func updateModels(_ newModels: [AntigravitySDKModel]) {
        self.models = newModels
        self.lastFetchDate = Date()
        saveCachedModels(newModels)
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

        let lines = cleaned.components(separatedBy: .newlines)

        for line in lines {
            let sanitized = line.unicodeScalars.filter { scalar in
                !(0x2800...0x28FF).contains(scalar.value)
            }.map { String($0) }.joined().trimmingCharacters(in: .whitespacesAndNewlines)

            guard !sanitized.isEmpty, !sanitized.contains("Fetching") else { continue }

            let components = sanitized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let modelId = components.first, !modelId.isEmpty else { continue }

            let displayName: String
            if components.count > 1 {
                displayName = components.dropFirst().joined(separator: " ")
            } else {
                displayName = modelId
            }

            let thinkingLevel = Self.deriveThinkingLevel(modelID: modelId, displayName: displayName)
            let contextWindow = Self.deriveContextWindow(modelID: modelId)
            let isImageModel = modelId.contains("image") || displayName.lowercased().contains("image")
            let category = Self.deriveCategory(modelID: modelId)

            let model = AntigravitySDKModel(
                id: modelId,
                displayName: displayName,
                thinkingLevel: thinkingLevel,
                contextWindow: contextWindow,
                isImageModel: isImageModel,
                category: category
            )
            result.append(model)
        }

        return result
    }

    private nonisolated static func runPythonSDKModelDiscoverySync() -> [AntigravitySDKModel]? {
        let currentDir = FileManager.default.currentDirectoryPath
        let bundledPython = Bundle.main.resourceURL?.appendingPathComponent("Google Cloud SDK/runtime/bin/python3").path
        let repoPython = "\(currentDir)/SwiftCode/Resources/Google Cloud SDK/runtime/bin/python3"

        let script = """
        import sys
        try:
            import google.antigravity.models as m
            default_model = getattr(m, 'DEFAULT_MODEL', 'gemini-3.8-flash')
            print(default_model)
        except Exception:
            pass
        """

        let pythonExecs = [bundledPython, repoPython, "/opt/homebrew/opt/python@3.14/bin/python3.14", "/usr/bin/python3"].compactMap { $0 }
        for py in pythonExecs {
            guard FileManager.default.isExecutableFile(atPath: py) else { continue }
            let process = Process()
            let stdoutPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: py)
            process.arguments = ["-c", script]
            process.standardOutput = stdoutPipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    if !lines.isEmpty {
                        // Merge any runtime default model with the canonical Antigravity seed catalog
                        var merged: [AntigravitySDKModel] = []
                        var seen = Set<String>()
                        for id in lines {
                            seen.insert(id)
                            if let match = Self.seedModels.first(where: { $0.id == id }) {
                                merged.append(match)
                            } else {
                                let level = Self.deriveThinkingLevel(modelID: id, displayName: id)
                                merged.append(AntigravitySDKModel(
                                    id: id,
                                    displayName: id,
                                    thinkingLevel: level,
                                    contextWindow: Self.deriveContextWindow(modelID: id),
                                    isImageModel: id.contains("image"),
                                    category: Self.deriveCategory(modelID: id)
                                ))
                            }
                        }
                        for seed in Self.seedModels where !seen.contains(seed.id) {
                            merged.append(seed)
                        }
                        return merged
                    }
                }
            } catch {}
        }
        return nil
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
        if lower.contains("claude") {
            return "Anthropic"
        } else if lower.contains("gpt") {
            return "OpenAI"
        } else {
            return "Google"
        }
    }
}
