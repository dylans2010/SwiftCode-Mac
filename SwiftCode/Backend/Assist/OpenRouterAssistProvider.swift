import Foundation
import os

private let openRouterAssistLogger = Logger(subsystem: "com.swiftcode.app", category: "OpenRouterAssistProvider")

// MARK: - OpenRouter Assist provider (formalised)
//
// OpenRouter was already reachable in this codebase through three
// overlapping paths (LLMService's OpenAI-compatible chat completions,
// OpenRouterClient, OpenRouterService). This type is the single Assist
// entry point for provider-level concerns that none of those paths
// owned: an explicit connection test, and a real-model validation that
// never substitutes another model.
//
// What it deliberately does NOT do:
// * It does not adopt the @openrouter/agent TypeScript SDK. That SDK
//   owns the tool-calling loop; Assist already owns its loop (the
//   session asks for a JSON tool request, validates it against the
//   registry, enforces phase/permission metadata, executes the real
//   tool, and returns the result). A model that lacks *native* function
//   calling still works through that JSON protocol, so native tool
//   support is reported, never used as a silent substitution gate.
// * It never invents a model catalog. `fetchModels` delegates to
//   OpenRouterClient, which reads the live /models endpoint.

public enum OpenRouterAssistError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case insufficientCredits
    case modelNotFound(String)
    case notAnOpenRouterModel(String)
    case apiError(status: Int, detail: String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No OpenRouter API key found. Add one in Assist Settings (API Keys), then test the connection again."
        case .invalidAPIKey:
            return "OpenRouter rejected the API key (401). Check the saved key in Assist Settings and try again."
        case .rateLimited:
            return "OpenRouter rate-limited this request (429). Wait briefly and try again; the selected model was not changed."
        case .insufficientCredits:
            return "OpenRouter reports insufficient credits (402) for this account. Add credits on openrouter.ai; the selected model was not changed."
        case .modelNotFound(let id):
            return "Model “\(id)” was not found on OpenRouter. Pick a model from the discovered list in Assist Settings."
        case .notAnOpenRouterModel(let id):
            return "“\(id)” is not an OpenRouter model identifier (expected provider/model, e.g. anthropic/claude-sonnet-4-5)."
        case .apiError(let status, let detail):
            return "OpenRouter request failed (status \(status)): \(detail)"
        case .networkError(let detail):
            return "Could not reach OpenRouter: \(detail)"
        }
    }
}

/// Whether a discovered OpenRouter model advertises native function
/// calling (`supported_parameters` containing `tools`). `.unknown`
/// means the catalog entry carried no such field — Assist's JSON tool
/// protocol does not depend on it, so unknown is not a failure.
public enum OpenRouterToolCallingSupport: Equatable, Sendable {
    case supports
    case doesNotSupport
    case unknown
}

@MainActor
public enum OpenRouterAssistProvider {
    private static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!

    /// Tests the saved credential against the live /models endpoint.
    /// Returns a human-readable success summary; throws a specific
    /// OpenRouterAssistError otherwise. Never logs or returns the key.
    public static func testConnection() async throws -> String {
        let key = OpenRouterClient.resolveOpenRouterAPIKey()
        guard !key.isEmpty else { throw OpenRouterAssistError.missingAPIKey }
        let (data, status) = try await fetchModelsRaw(apiKey: key)
        switch status {
        case 200:
            let count = modelCount(in: data)
            openRouterAssistLogger.log("OpenRouter connection test succeeded: \(count) models listed.")
            return "Connected to OpenRouter (\(count) models available)."
        case 401:
            throw OpenRouterAssistError.invalidAPIKey
        case 402:
            throw OpenRouterAssistError.insufficientCredits
        case 429:
            throw OpenRouterAssistError.rateLimited
        default:
            throw OpenRouterAssistError.apiError(status: status, detail: errorDetail(in: data))
        }
    }

    /// Validates that a model identifier actually exists on OpenRouter
    /// and reports its native tool-calling support. Throws
    /// `.modelNotFound` instead of falling back to another model.
    public static func validateModel(_ modelID: String) async throws -> OpenRouterToolCallingSupport {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("/") else {
            throw OpenRouterAssistError.notAnOpenRouterModel(trimmed)
        }
        let key = OpenRouterClient.resolveOpenRouterAPIKey()
        guard !key.isEmpty else { throw OpenRouterAssistError.missingAPIKey }
        let (data, status) = try await fetchModelsRaw(apiKey: key)
        guard status == 200 else {
            switch status {
            case 401: throw OpenRouterAssistError.invalidAPIKey
            case 402: throw OpenRouterAssistError.insufficientCredits
            case 429: throw OpenRouterAssistError.rateLimited
            default: throw OpenRouterAssistError.apiError(status: status, detail: errorDetail(in: data))
            }
        }
        guard let entry = modelEntry(for: trimmed, in: data) else {
            throw OpenRouterAssistError.modelNotFound(trimmed)
        }
        guard let supported = entry["supported_parameters"] as? [String] else {
            return .unknown
        }
        return supported.contains("tools") ? .supports : .doesNotSupport
    }

    /// Live discovered models, via the existing OpenRouterClient cache
    /// (which reads /models). Kept here so Settings has one call site.
    public static func fetchModels() async throws -> [OpenRouterModel] {
        try await OpenRouterClient.shared.fetchModels()
    }

    // MARK: - Raw /models plumbing (JSONSerialization, no new model type)

    private static func fetchModelsRaw(apiKey: String) async throws -> (Data, Int) {
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return (data, status)
        } catch {
            throw OpenRouterAssistError.networkError(error.localizedDescription)
        }
    }

    private static func modelEntries(in data: Data) -> [[String: Any]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else {
            return []
        }
        return entries
    }

    private static func modelCount(in data: Data) -> Int {
        modelEntries(in: data).count
    }

    private static func modelEntry(for modelID: String, in data: Data) -> [String: Any]? {
        modelEntries(in: data).first { ($0["id"] as? String) == modelID }
    }

    private static func errorDetail(in data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return String(message.prefix(300))
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.isEmpty ? "empty response" : String(raw.prefix(300))
    }
}
