import Foundation
import os
import SwiftUI

private let logger = Logger(subsystem: "com.swiftcode.app", category: "Dictionary")

public struct DictionaryHistoryItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let query: String
    public let date: Date
    public var isPinned: Bool

    public init(id: UUID = UUID(), query: String, date: Date = Date(), isPinned: Bool = false) {
        self.id = id
        self.query = query
        self.date = date
        self.isPinned = isPinned
    }
}

public enum DictionaryErrorState: Identifiable, Equatable {
    public var id: String {
        switch self {
        case .invalidJSON: return "invalidJSON"
        case .networkFailure(let desc): return "networkFailure:\(desc)"
        case .modelUnavailable: return "modelUnavailable"
        case .timeout: return "timeout"
        case .emptyResponse: return "emptyResponse"
        }
    }

    case invalidJSON(rawText: String)
    case networkFailure(String)
    case modelUnavailable
    case timeout
    case emptyResponse
}

@Observable
@MainActor
public final class DictionaryManager: Sendable {
    public static let shared = DictionaryManager()

    public private(set) var history: [DictionaryHistoryItem] = []
    public var currentResult: CodingDictionaryResult? = nil
    public var isLoading: Bool = false
    public var errorState: DictionaryErrorState? = nil

    private var activeTask: Task<Void, Never>? = nil
    private var lastQuery: String = ""

    private let historyDefaultsKey = "com.swiftcode.dictionary.history"

    private init() {
        loadHistory()
    }

    // MARK: - History Operations

    public func loadHistory() {
        logger.log("Loading search history from UserDefaults.")
        if let data = UserDefaults.standard.data(forKey: historyDefaultsKey),
           let decoded = try? JSONDecoder().decode([DictionaryHistoryItem].self, from: data) {
            self.history = decoded
            logger.log("Loaded \(decoded.count) history items.")
        } else {
            logger.log("No existing history found.")
        }
    }

    public func saveHistory() {
        logger.log("Saving search history to UserDefaults.")
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyDefaultsKey)
            logger.log("Saved \(self.history.count) history items.")
        } else {
            logger.error("Failed to encode history items.")
        }
    }

    public func addToHistory(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Remove duplicate queries from history to keep it clean
        history.removeAll { $0.query.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }

        let newItem = DictionaryHistoryItem(query: trimmed)
        history.insert(newItem, at: 0)
        saveHistory()
    }

    public func togglePin(id: UUID) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index].isPinned.toggle()
            // Keep pinned items sorted or structured if desired, or just preserve current list
            saveHistory()
        }
    }

    public func deleteHistoryItem(id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    // MARK: - Search Execution

    public func cancelSearch() {
        if activeTask != nil {
            logger.log("Cancelling active search task.")
            activeTask?.cancel()
            activeTask = nil
            isLoading = false
        }
    }

    public func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Prevent duplicate concurrent requests for the exact same query
        if isLoading && lastQuery == trimmed {
            logger.log("Ignoring duplicate request for '\(trimmed)'")
            return
        }

        // Cancel existing active tasks
        cancelSearch()

        isLoading = true
        errorState = nil
        lastQuery = trimmed

        // Automatically add to history
        addToHistory(query: trimmed)

        activeTask = Task {
            logger.log("Starting dictionary search for query: '\(trimmed)'")

            let systemPrompt = """
            You are the central engine for the SwiftCode Coding Dictionary.
            Your sole task is to analyze the user's query and return a highly detailed, professional, and comprehensive dictionary entry in structured JSON format.

            JSON SCHEMA:
            {
              "version": "1.0",
              "confidence": 95,
              "query": "\(trimmed)",
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

            let fullPrompt = "User Query: \(trimmed)"

            do {
                // Combine system prompt with instructions for a comprehensive context
                let promptToSend = "\(systemPrompt)\n\n\(fullPrompt)"

                var responseText = ""
                let usePreferredModel = true // Flag to toggle AFM 3 Core trial

                if usePreferredModel {
                    logger.log("Attempting dictionary search with preferred model 'AFM 3 Core'")
                    do {
                        responseText = try await LLMService.shared.generateResponse(
                            prompt: promptToSend,
                            useContext: false,
                            modelOverride: "AFM 3 Core"
                        )
                    } catch {
                        logger.warning("Preferred model 'AFM 3 Core' failed or is unavailable: \(error.localizedDescription). Falling back to default model.")
                        try Task.checkCancellation()
                        responseText = try await LLMService.shared.generateResponse(
                            prompt: promptToSend,
                            useContext: false,
                            modelOverride: nil
                        )
                    }
                } else {
                    responseText = try await LLMService.shared.generateResponse(
                        prompt: promptToSend,
                        useContext: false,
                        modelOverride: nil
                    )
                }

                try Task.checkCancellation()

                let cleanedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedResponse.isEmpty else {
                    logger.error("Received an empty response from LLMService.")
                    self.errorState = .emptyResponse
                    self.isLoading = false
                    return
                }

                // Parse using robust brace block scanner
                guard let extractedJSON = self.extractJSON(from: cleanedResponse) else {
                    logger.error("Could not find valid JSON block boundaries in response.")
                    self.errorState = .invalidJSON(rawText: cleanedResponse)
                    self.isLoading = false
                    return
                }

                guard let jsonData = extractedJSON.data(using: .utf8) else {
                    logger.error("Failed to convert extracted JSON to data.")
                    self.errorState = .invalidJSON(rawText: extractedJSON)
                    self.isLoading = false
                    return
                }

                do {
                    let decodedResult = try JSONDecoder().decode(CodingDictionaryResult.self, from: jsonData)
                    self.currentResult = decodedResult
                    self.errorState = nil
                } catch {
                    logger.error("JSON parsing/decoding failed: \(error.localizedDescription)")
                    self.errorState = .invalidJSON(rawText: extractedJSON)
                }

            } catch is CancellationError {
                logger.log("Dictionary search task was cancelled successfully.")
            } catch {
                logger.error("Network or model failure: \(error.localizedDescription)")
                self.errorState = .networkFailure(error.localizedDescription)
            }

            self.isLoading = false
        }
    }

    private func extractJSON(from text: String) -> String? {
        guard let firstBrace = text.firstIndex(of: "{"),
              let lastBrace = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[firstBrace...lastBrace])
    }
}
