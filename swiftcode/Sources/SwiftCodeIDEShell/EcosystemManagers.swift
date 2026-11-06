// EcosystemManagers.swift
//
// Ported from Legacy `SwiftCode/Views/Utilities/NSPersonalDocumentation/Managers/EcosystemManagers.swift`
// (SwiftCode-Mac migration). REDESIGNED, not verbatim: Legacy persisted through
// SwiftData (`StorageManager` / `ModelContext`, `@Model WhiteboardRecord` /
// `CodeSnippetRecord` / `ProjectSnapshotRecord`, `DocumentManager`, `Document`,
// `ModuleKind`, `LLMService`) — none of those types exists in production, and
// production deliberately replaced that whole layer with the JSON-backed
// `PersonalDocStore` (`PersonalDocWhiteboard` / `PersonalDocSnippet` /
// `PersonalDocSnapshot` / `PersonalDocDocument`, same fields, same behaviour;
// see `PersonalDocumentationModel.swift`). These managers are therefore thin
// adapters over one `PersonalDocStore` instead of a second persistence system.
//
// Rename mapping (also documented in `PersonalDocCommandPalette.swift`):
//   WhiteboardRecord -> PersonalDocWhiteboard, CodeSnippetRecord -> PersonalDocSnippet,
//   ProjectSnapshotRecord -> PersonalDocSnapshot, ModuleKind -> PersonalDocModuleKind,
//   Document -> PersonalDocDocument, StorageManager/DocumentManager -> PersonalDocStore,
//   LLMService -> PersonalDocTextProvider (via the store; see below).
//
// Signature changes vs Legacy (no callers in production, verified by grep):
//   - Managers take `init(store: PersonalDocStore)`; the store owns the project.
//   - `SnapshotManager.createSnapshot(title:description:)` snapshots the store's
//     own collections (Legacy took the collections as parameters).
//   - `SnapshotManager.restoreSnapshot(_:)` takes only the snapshot (Legacy took
//     three managers); the store restores its own collections.
//   - `IntelligenceManager` methods no longer take a documents array (the store
//     owns the documents); `runIntelligenceAudit()` delegates to
//     `store.analyze(kind: .knowledgeGaps)`.
//   - `EcosystemTimelineManager.fetchTimeline()` returns the store's real timeline
//     mapped to `TimelineItem`. Legacy's three hardcoded rows (a fake git commit,
//     a fake build success, a fake AI report) are NOT carried over — the store
//     timeline is real data; see `PersonalDocStore.fetchTimeline()`.
//   - `IntelligenceManager` text generation goes through the store's
//     `textProvider` when one is wired; with none set it falls back to
//     `PersonalDocLocalAnalyzer` / a locally assembled document, never to a
//     claim that an LLM wrote it.
//
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
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
        // No text provider wired: honest local description computed from the
        // snippet itself, never presented as LLM output.
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
    public let category: String // "document", "git", "build", "whiteboard", "snippet", "ai"
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
        // Real timeline from the store (documents, whiteboards, snippets, AI
        // insights). Legacy appended three hardcoded rows here (a fake git
        // commit, a fake build success, a fake AI report); those are gone —
        // the store timeline is real data.
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
        // No text provider wired: extractive local summary of the same
        // documents, labelled as local.
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
        // No text provider wired: return the source itself inside an honestly
        // labelled local document instead of claiming an LLM wrote it.
        return """
        # Documentation (\(sourceKind))
        _Assembled locally — no text provider is configured, so no LLM-generated prose is included._

        ## Source
        \(source)
        """
    }
}
