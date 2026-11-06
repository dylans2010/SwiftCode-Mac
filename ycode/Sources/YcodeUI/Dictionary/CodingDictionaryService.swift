import Foundation
import YcodeAssistant
import YcodeIDECore
import YcodeSDK

// MARK: - Coding dictionary service
//
// Wave 17, Slice C: the `dictionary.open` window, built whole. A port
// of Legacy's `DictionaryManager`
// (`SwiftCode/Backend/Dictionary/DictionaryManager.swift`, Dylan's
// own code; direct porting authorised under MIT), with one deliberate
// substitution: Legacy called `LLMService.shared.generateResponse`
// (preferred model "AFM 3 Core", falling back to the default model);
// Ycode calls the host's configured text-completion provider through
// the same seam Wave 16 attached for extension turns
// (`AssistantProvider.send(ChatRequest)`), resolved from the host's
// own Coding Assistant settings. The system prompt and the JSON
// schema it demands are Legacy's, verbatim apart from the product
// name, and the brace-scanner JSON extraction is Legacy's.
//
// There is still no bundled term data — Legacy shipped none, and
// none is invented here. Every entry is generated per query, exactly
// as Legacy generated it; without a configured text provider the
// window fails honestly (`.providerNotReady`) instead of showing a
// fabricated entry. Agent providers (Claude Code, Codex,
// Antigravity, ACP agents, Hermes, OpenCode, Meta Assist) are refused
// with `.agentProvider`, reusing the partition
// `SDKAssistHostBackend.textCompletionProviderKinds` as the single
// source of truth, never silently downgraded: those providers run an
// agent on the user's machine, which a one-shot definition lookup
// must not trigger.
//
// History is the only persisted state, as in Legacy: past queries in
// UserDefaults under a Ycode-namespaced key (Legacy used
// `com.swiftcode.dictionary.history`).

/// A dictionary lookup failure. The window shows `errorDescription`;
/// the raw provider text is kept only for the invalid-JSON case, so
/// the user can see what the model actually returned.
public enum CodingDictionaryError: Error, Equatable, Sendable {
    /// The configured provider cannot answer now (with the host's hint
    /// for what the user can do, e.g. start Ollama).
    case providerNotReady(String)
    /// The configured provider runs an agent, not a text completion.
    case agentProvider(ProviderKind)
    /// The provider returned no text at all.
    case emptyResponse
    /// The provider's text held no decodable entry JSON.
    case invalidJSON(String)
    /// The provider request itself failed (network, key, server).
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

/// The host provider + model for one dictionary lookup.
public typealias CodingDictionaryProviderResolution = (provider: any AssistantProvider, modelID: String?)

/// Generates coding-dictionary entries through the host's configured
/// text-completion provider. Main-actor isolated: the window drives
/// it, and `CodingAssistantServices` (which builds providers from
/// host settings + the secret store) is main-actor isolated too. The
/// provider is resolved per lookup from current settings, so a
/// provider change in Settings applies to the next lookup without
/// reopening the window.
@MainActor
public final class CodingDictionaryService {
    /// UserDefaults key for the persisted query history. Ycode's own
    /// namespace; Legacy's key was `com.swiftcode.dictionary.history`.
    public static let historyDefaultsKey = "com.ycode.dictionary.history"

    /// Past queries, newest first. Pinned items sort first.
    public private(set) var history: [DictionaryHistoryItem] = []

    private let userDefaults: UserDefaults
    private let resolveProvider: (() async throws -> CodingDictionaryProviderResolution)?

    /// - Parameters:
    ///   - userDefaults: Where history is persisted. Tests pass a
    ///     throwaway suite; the app passes `.standard`.
    ///   - resolveProvider: How the host provider is found. `nil`
    ///     resolves from the host's Coding Assistant settings; tests
    ///     pass a stub returning a fake provider.
    public init(
        userDefaults: UserDefaults = .standard,
        resolveProvider: (() async throws -> CodingDictionaryProviderResolution)? = nil
    ) {
        self.userDefaults = userDefaults
        self.resolveProvider = resolveProvider
        loadHistory()
    }

    // MARK: - Lookup

    /// Defines `query`, returning the decoded entry. Throws
    /// `CodingDictionaryError` for every honest failure (provider not
    /// ready, agent provider, empty or unparseable response, provider
    /// failure). `CancellationError` propagates unchanged.
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
                // `.activity` (host agent activity) and `.truncated`
                // are dropped: a definition is reply text only.
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

    // MARK: - Provider resolution

    /// Resolves the host's configured text-completion provider, or
    /// throws the honest reason it cannot serve a lookup. Mirrors
    /// `YcodeSDKAssistResolver` (same settings source, same provider
    /// factory); the partition against agent providers is the shared
    /// `SDKAssistHostBackend.textCompletionProviderKinds`.
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

    // MARK: - History

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

    /// Records a query (newest first, deduplicated; pinned items stay
    /// pinned and sort first). Legacy added every search to history
    /// automatically; this keeps that behaviour.
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

    // MARK: - Prompt and extraction (ported from Legacy)

    /// Legacy's system prompt, verbatim apart from the product name
    /// ("Ycode Coding Dictionary" for "SwiftCode Coding Dictionary").
    /// It demands exactly one raw JSON object matching
    /// `CodingDictionaryResult` — no fences, no preamble — and tells
    /// the model to state uncertainty instead of inventing APIs.
    public static func systemPrompt(for query: String) -> String {
        """
        You are the central engine for the Ycode Coding Dictionary.
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

    /// Legacy's brace-block scanner: the JSON object from the first
    /// `{` to the last `}`. This is what lets a model that wraps its
    /// answer in fences or prose still yield a decodable entry.
    public static func extractJSON(from text: String) -> String? {
        guard let firstBrace = text.firstIndex(of: "{"),
              let lastBrace = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[firstBrace...lastBrace])
    }
}
