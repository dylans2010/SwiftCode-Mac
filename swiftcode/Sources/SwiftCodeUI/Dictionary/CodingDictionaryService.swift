import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore
import SwiftCodeSDK

public enum CodingDictionaryError: Error, Equatable, Sendable {
    case providerNotReady(String)
    case agentProvider(ProviderKind)
    case emptyResponse
    case invalidJSON(String)
    case providerFailure(String)
}

extension CodingDictionaryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .providerNotReady(let hint):
            return "The dictionary provider is not ready. \(hint)"
        case .agentProvider(let kind):
            return "The configured provider (\(kind.displayName)) runs an agent on this machine and cannot answer dictionary lookups. Choose a text-completion provider in Settings ▸ Coding Assistant."
        case .emptyResponse:
            return "The provider returned an empty response. Please try again with a different query."
        case .invalidJSON:
            return "Failed to parse the dictionary response. The response did not match the required JSON schema."
        case .providerFailure(let message):
            return "An error occurred calling the provider: \(message)"
        }
    }
}

public typealias CodingDictionaryProviderResolution = (provider: any AssistantProvider, modelID: String?)

@MainActor
public final class CodingDictionaryService {
    public static let historyDefaultsKey = "com.swiftcode.dictionary.history"

    public private(set) var history: [DictionaryHistoryItem] = []

    private let userDefaults: UserDefaults
    private let resolveProvider: (() async throws -> CodingDictionaryProviderResolution)?

    public init(
        userDefaults: UserDefaults = .standard,
        resolveProvider: (() async throws -> CodingDictionaryProviderResolution)? = nil
    ) {
        self.userDefaults = userDefaults
        self.resolveProvider = resolveProvider
        loadHistory()
    }

    @discardableResult
    public func define(query: String) async throws -> CodingDictionaryResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CodingDictionaryError.emptyResponse }
        addToHistory(query: trimmed)
        let (provider, modelID) = try await resolveTextProvider()
        let request = ChatRequest(
            model: modelID,
            instructions: Self.systemPrompt(for: trimmed),
            messages: [ChatMessage(.user, "User Query: \(trimmed)")],
            workingDirectory: nil,
            generation: .assistantDefault
        )
        var text = ""
        do {
            for try await event in provider.send(request) {
                if case .text(let delta) = event { text += delta }
                if case .finished = event { break }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CodingDictionaryError.providerFailure(error.localizedDescription)
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CodingDictionaryError.emptyResponse }
        guard let extracted = Self.extractJSON(from: cleaned) else {
            throw CodingDictionaryError.invalidJSON(cleaned)
        }
        guard let jsonData = extracted.data(using: .utf8) else {
            throw CodingDictionaryError.invalidJSON(extracted)
        }
        do {
            return try JSONDecoder().decode(CodingDictionaryResult.self, from: jsonData)
        } catch {
            throw CodingDictionaryError.invalidJSON(extracted)
        }
    }

    private func resolveTextProvider() async throws -> CodingDictionaryProviderResolution {
        let resolution: CodingDictionaryProviderResolution
        if let resolveProvider {
            resolution = try await resolveProvider()
        } else {
            resolution = await MainActor.run {
                let services = CodingAssistantServices.shared
                let prefs = services.preferences ?? .shared
                let settings = prefs.codingAssistant
                let kind = settings.provider
                let provider = services.provider(kind, prefs: prefs)
                return (provider, settings.model(for: kind))
            }
        }
        guard SDKAssistHostBackend.textCompletionProviderKinds.contains(resolution.provider.kind) else {
            throw CodingDictionaryError.agentProvider(resolution.provider.kind)
        }
        let availability = await resolution.provider.availability()
        guard availability.isReady else {
            throw CodingDictionaryError.providerNotReady(
                availability.hint ?? "The configured provider is not ready."
            )
        }
        return resolution
    }

    public func loadHistory() {
        if let data = userDefaults.data(forKey: Self.historyDefaultsKey),
           let decoded = try? JSONDecoder().decode([DictionaryHistoryItem].self, from: data) {
            history = decoded
        } else {
            history = []
        }
    }

    public func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            userDefaults.set(data, forKey: Self.historyDefaultsKey)
        }
    }

    public func addToHistory(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history.removeAll { $0.query == trimmed && !$0.isPinned }
        if history.contains(where: { $0.query == trimmed }) { saveHistory(); return }
        history.insert(DictionaryHistoryItem(query: trimmed), at: 0)
        sortHistory()
        saveHistory()
    }

    public func togglePin(id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].isPinned.toggle()
        sortHistory()
        saveHistory()
    }

    public func deleteHistoryItem(id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private func sortHistory() {
        history.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.date > $1.date
        }
    }

    public static func systemPrompt(for query: String) -> String {
        """
        You are the central engine for the SwiftCode Coding Dictionary.
        Your sole task is to analyze the user's query and return a highly detailed, professional, and comprehensive dictionary entry in structured JSON format.

        JSON SCHEMA:
        {
          "version": "1.0",
          "confidence": 95,
          "query": "\(query)",
          "title": "the main term or title of the entry",
          "subtitle": "a clear 1-line definition/category/context",
          "kind": "Class / Struct / Enum / Protocol / Keyword / Error / Git Command / Design Pattern / Concept etc.",
          "category": "Framework / Language / Architecture / Tooling / Networking etc.",
          "difficulty": "Beginner / Intermediate / Advanced",
          "overview": "Detailed explanation of the concept, what it is, and its primary purpose.",
          "definition": "Formal or standard definition.",
          "summary": "Quick takeaway bullet or summary sentence.",
          "syntax": "Code syntax or command usage pattern.",
          "parameters": [
            { "name": "parameter name", "type": "type of parameter", "description": "description of use" }
          ],
          "returnValue": { "type": "type returned", "description": "meaning of return" },
          "examples": [
            { "title": "Example Name", "code": "full formatted, self-contained code example" }
          ],
          "commonMistakes": [
            { "description": "Mistake description", "explanation": "Why this happens", "fix": "How to fix it" }
          ],
          "bestPractices": ["Rule 1", "Rule 2"],
          "performanceNotes": "Notes on speed, memory, complexity, or overhead.",
          "threadSafety": "Is it thread-safe? How should concurrency be managed?",
          "securityNotes": "Any security implications or vulnerabilities.",
          "availability": ["macOS 15.0+", "iOS 18.0+"],
          "relatedConcepts": ["Concept A", "Concept B"],
          "aliases": ["Alternative Name"],
          "keywords": ["keyword1", "keyword2"],
          "warnings": ["Potential pitfalls to look out for"],
          "notes": ["Extra informational tips"],
          "seeAlso": ["Related API names"],
          "references": ["Official Documentation Link or Resource Name"],
          "appleDocsSummary": "A highly detailed summary of the official Apple developer reference documentation for this term.",
          "swiftVersion": "Swift language version compatibility or introduction version (e.g. 'Swift 6.0' or 'Swift 5.0+').",
          "alternativeAPIs": ["Alternative API name 1", "Alternative API name 2"],
          "codeSnippet": "Primary production-ready coding snippet or template illustrating real-world use.",
          "complexity": "Execution runtime or algorithmic space/time complexity notes (e.g., O(1), O(N)).",
          "memoryConsiderations": "Notes on reference cycles (weak/unowned), ARC constraints, or heap allocation overhead."
        }

        STRICT INSTRUCTION:
        1. Output MUST be ONLY valid, raw JSON.
        2. Do NOT wrap the JSON in markdown code fences (like ```json ... ```).
        3. Do NOT include any intro, outro, preamble, explanation, or conversational text before or after the JSON.
        4. Follow the JSON Schema EXACTLY. All keys must be present.
        5. If optional/unnecessary fields exist for this term (e.g., parameters for a conceptual entry), populate them with empty arrays or empty strings rather than null.
        6. Never hallucinate nonexistent Apple APIs or parameters. Prefer official Apple terminology.
        7. State uncertainty instead of inventing facts. If unsure, lower the 'confidence' score and explain the limitation in notes or warnings.
        8. Write high-quality, practical code examples.
        """
    }

    public static func extractJSON(from text: String) -> String? {
        guard let firstBrace = text.firstIndex(of: "{"),
              let lastBrace = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[firstBrace...lastBrace])
    }
}
