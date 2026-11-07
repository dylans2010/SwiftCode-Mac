import Foundation
import Observation

@Observable
@MainActor
public final class WhiteboardManager {
    private let store: PersonalDocStore

    public init(store: PersonalDocStore) {
        self.store = store
    }

    public func fetchWhiteboards() throws -> [PersonalDocWhiteboard] {
        store.fetchWhiteboards()
    }

    public func createWhiteboard(title: String) throws -> PersonalDocWhiteboard {
        store.createWhiteboard(title: title)
    }

    public func updateWhiteboard(_ record: PersonalDocWhiteboard) throws {
        store.updateWhiteboard(record)
    }

    public func deleteWhiteboard(_ record: PersonalDocWhiteboard) throws {
        store.deleteWhiteboard(record)
    }
}

@Observable
@MainActor
public final class SnippetManager {
    private let store: PersonalDocStore

    public init(store: PersonalDocStore) {
        self.store = store
    }

    public func fetchSnippets() throws -> [PersonalDocSnippet] {
        store.fetchSnippets()
    }

    public func createSnippet(title: String, code: String, language: String, category: String, tags: [String] = []) throws -> PersonalDocSnippet {
        store.createSnippet(title: title, code: code, language: language, category: category, tags: tags)
    }

    public func updateSnippet(_ record: PersonalDocSnippet) throws {
        store.updateSnippet(record)
    }

    public func deleteSnippet(_ record: PersonalDocSnippet) throws {
        store.deleteSnippet(record)
    }

    public func explainSnippet(_ record: PersonalDocSnippet) async throws -> String {
        let prompt = """
        You are an expert software developer and compiler engineer. Explain the following \(record.language) snippet:

        ```\(record.language.lowercased())
        \(record.code)
        ```

        Provide:
        1. High-level purpose of the code.
        2. Detailed step-by-step breakdown.
        3. Potential optimizations or safety advice.
        """
        if let provider = store.textProvider {
            return try await provider.generate(prompt: prompt)
        }
        let lines = record.code.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let preview = nonEmpty.prefix(5).joined(separator: "\n")
        return """
        Snippet "\(record.title)" (\(record.language), \(record.category), \(lines.count) lines, \
        \(nonEmpty.count) non-empty). No text provider is configured, so this is a local \
        description, not an LLM explanation.
        First lines:
        \(preview)
        """
    }
}

@Observable
@MainActor
public final class SnapshotManager {
    private let store: PersonalDocStore

    public init(store: PersonalDocStore) {
        self.store = store
    }

    public func fetchSnapshots() throws -> [PersonalDocSnapshot] {
        store.fetchSnapshots()
    }

    public func createSnapshot(title: String, description: String) throws -> PersonalDocSnapshot {
        store.createSnapshot(title: title, description: description)
    }

    public func restoreSnapshot(_ snapshot: PersonalDocSnapshot) throws {
        store.restoreSnapshot(snapshot)
    }

    public func duplicateSnapshot(_ snapshot: PersonalDocSnapshot, title: String? = nil) throws -> PersonalDocSnapshot {
        store.duplicateSnapshot(snapshot, title: title)
    }

    public func updateSnapshot(_ snapshot: PersonalDocSnapshot) throws {
        store.updateSnapshot(snapshot)
    }

    public func deleteSnapshot(_ snapshot: PersonalDocSnapshot) throws {
        store.deleteSnapshot(snapshot)
    }
}

public struct TimelineItem: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let category: String
    public let date: Date
    public let author: String
    public let tags: [String]
}

@Observable
@MainActor
public final class EcosystemTimelineManager {
    private let store: PersonalDocStore

    public init(store: PersonalDocStore) {
        self.store = store
    }

    public func fetchTimeline() throws -> [TimelineItem] {
        store.fetchTimeline().map { item in
            TimelineItem(
                id: item.id,
                title: item.title,
                detail: item.detail,
                category: item.category,
                date: item.date,
                author: "Local Developer",
                tags: item.tags
            )
        }
    }
}

@Observable
@MainActor
public final class IntelligenceManager {
    private let store: PersonalDocStore

    public init(store: PersonalDocStore) {
        self.store = store
    }

    public func runIntelligenceAudit() async throws -> String {
        try await store.analyze(kind: .knowledgeGaps)
    }

    public func askProjectMemory(question: String) async throws -> String {
        let documents = store.fetchDocuments()
        if let provider = store.textProvider {
            let contentPayload = documents.map { "=== \($0.title) (\($0.moduleKind.rawValue)) ===\n\($0.markdownSource)" }.joined(separator: "\n\n")
            let prompt = """
            You are the Project Memory Oracle for SwiftCode. Your goal is to answer developer questions strictly using the documentation history, plans, and architectural decisions provided.

            === SEARCHABLE PROJECT HISTORY ===
            \(contentPayload)

            === DEVELOPER QUESTION ===
            \(question)

            Answer professionally, highlighting any relevant files, decisions, or commits mentioned in the documents. If the context doesn't contain the answer, say so, but formulate an expert deduction based on what is documented.
            """
            return try await provider.generate(prompt: prompt)
        }
        return "No text provider is configured, so this is a local summary, not an LLM answer.\n" +
            PersonalDocLocalAnalyzer.summarize(documents: documents)
    }

    public func generateAutomaticDocumentation(from source: String, sourceKind: String) async throws -> String {
        if let provider = store.textProvider {
            let prompt = """
            You are an elite AI technical writer. Generate highly professional markdown documentation from the following source payload.

            Source Payload Type: \(sourceKind)
            === SOURCE PAYLOAD ===
            \(source)

            Requirements:
            1. Clean, hierarchical Markdown headings.
            2. Professional architectural terminology.
            3. Clear feature summary, structural details, and API design tables where relevant.
            4. Bulleted highlights.
            """
            return try await provider.generate(prompt: prompt)
        }
        return """
        # Documentation (\(sourceKind))
        _Assembled locally — no text provider is configured, so no LLM-generated prose is included._

        ## Source
        \(source)
        """
    }
}
