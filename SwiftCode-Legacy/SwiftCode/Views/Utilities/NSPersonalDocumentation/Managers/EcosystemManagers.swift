import Foundation
import SwiftData
import Observation

@Observable
@MainActor
public final class WhiteboardManager {
    private let storage: StorageManager
    private let projectID: UUID

    public init(storage: StorageManager, projectID: UUID) {
        self.storage = storage
        self.projectID = projectID
    }

    public func fetchWhiteboards() throws -> [WhiteboardRecord] {
        let descriptor = FetchDescriptor<WhiteboardRecord>()
        let all = try storage.context.fetch(descriptor)
        return all.filter { $0.projectID == projectID }
    }

    public func createWhiteboard(title: String) throws -> WhiteboardRecord {
        let record = WhiteboardRecord(projectID: projectID, title: title)
        storage.context.insert(record)
        try storage.context.save()
        return record
    }

    public func updateWhiteboard(_ record: WhiteboardRecord) throws {
        record.updatedAt = Date()
        try storage.context.save()
    }

    public func deleteWhiteboard(_ record: WhiteboardRecord) throws {
        storage.context.delete(record)
        try storage.context.save()
    }
}

@Observable
@MainActor
public final class SnippetManager {
    private let storage: StorageManager
    private let projectID: UUID

    public init(storage: StorageManager, projectID: UUID) {
        self.storage = storage
        self.projectID = projectID
    }

    public func fetchSnippets() throws -> [CodeSnippetRecord] {
        let descriptor = FetchDescriptor<CodeSnippetRecord>()
        let all = try storage.context.fetch(descriptor)
        return all.filter { $0.projectID == projectID }
    }

    public func createSnippet(title: String, code: String, language: String, category: String, tags: [String] = []) throws -> CodeSnippetRecord {
        let tagsData = (try? JSONEncoder().encode(tags)) ?? Data()
        let tagsStr = String(data: tagsData, encoding: .utf8) ?? "[]"

        let record = CodeSnippetRecord(
            projectID: projectID,
            title: title,
            code: code,
            language: language,
            category: category,
            tagsJSON: tagsStr
        )
        storage.context.insert(record)
        try storage.context.save()
        return record
    }

    public func updateSnippet(_ record: CodeSnippetRecord) throws {
        record.updatedAt = Date()
        try storage.context.save()
    }

    public func deleteSnippet(_ record: CodeSnippetRecord) throws {
        storage.context.delete(record)
        try storage.context.save()
    }

    public func explainSnippet(_ record: CodeSnippetRecord) async throws -> String {
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
        return try await LLMService.shared.generateResponse(prompt: prompt, useContext: true)
    }
}

@Observable
@MainActor
public final class SnapshotManager {
    private let storage: StorageManager
    private let projectID: UUID

    public init(storage: StorageManager, projectID: UUID) {
        self.storage = storage
        self.projectID = projectID
    }

    public func fetchSnapshots() throws -> [ProjectSnapshotRecord] {
        let descriptor = FetchDescriptor<ProjectSnapshotRecord>()
        let all = try storage.context.fetch(descriptor)
        return all.filter { $0.projectID == projectID }
    }

    public func createSnapshot(title: String, description: String, documents: [Document], whiteboards: [WhiteboardRecord], snippets: [CodeSnippetRecord]) throws -> ProjectSnapshotRecord {
        // Safe serialization helper
        func serialize<T: Encodable>(_ value: T) -> String {
            guard let data = try? JSONEncoder().encode(value) else { return "[]" }
            return String(data: data, encoding: .utf8) ?? "[]"
        }

        struct DocSnapshot: Codable {
            let id: UUID
            let title: String
            let markdownSource: String
            let archetype: String
            let moduleKindRaw: String
            let status: String?
            let priority: String?
            let tags: [String]
        }

        struct BoardSnapshot: Codable {
            let id: UUID
            let title: String
            let elementsJSON: String
        }

        struct SnippetSnapshot: Codable {
            let id: UUID
            let title: String
            let code: String
            let language: String
            let category: String
            let tagsJSON: String
        }

        let docSnaps = documents.map { DocSnapshot(id: $0.id, title: $0.title, markdownSource: $0.markdownSource, archetype: $0.archetype, moduleKindRaw: $0.moduleKindRaw, status: $0.status, priority: $0.priority, tags: $0.tags) }
        let boardSnaps = whiteboards.map { BoardSnapshot(id: $0.id, title: $0.title, elementsJSON: $0.elementsJSON) }
        let snippetSnaps = snippets.map { SnippetSnapshot(id: $0.id, title: $0.title, code: $0.code, language: $0.language, category: $0.category, tagsJSON: $0.tagsJSON) }

        let snapshot = ProjectSnapshotRecord(
            projectID: projectID,
            title: title,
            descriptionText: description,
            documentsJSON: serialize(docSnaps),
            whiteboardsJSON: serialize(boardSnaps),
            snippetsJSON: serialize(snippetSnaps)
        )

        storage.context.insert(snapshot)
        try storage.context.save()
        return snapshot
    }

    public func restoreSnapshot(_ snapshot: ProjectSnapshotRecord, docManager: DocumentManager, whiteboardManager: WhiteboardManager, snippetManager: SnippetManager) throws {
        struct DocSnapshot: Codable {
            let id: UUID
            let title: String
            let markdownSource: String
            let archetype: String
            let moduleKindRaw: String
            let status: String?
            let priority: String?
            let tags: [String]
        }

        struct BoardSnapshot: Codable {
            let id: UUID
            let title: String
            let elementsJSON: String
        }

        struct SnippetSnapshot: Codable {
            let id: UUID
            let title: String
            let code: String
            let language: String
            let category: String
            let tagsJSON: String
        }

        // Decode snapshot states
        guard let docData = snapshot.documentsJSON.data(using: .utf8),
              let docSnaps = try? JSONDecoder().decode([DocSnapshot].self, from: docData) else { return }

        // 1. Restore Documents
        let existingDocs = try docManager.fetchDocuments()
        for doc in existingDocs {
            try docManager.deleteDocument(doc)
        }
        for snap in docSnaps {
            let kind = ModuleKind(rawValue: snap.moduleKindRaw) ?? .personalDocumentation
            let doc = try docManager.createDocument(title: snap.title, kind: kind, markdown: snap.markdownSource)
            doc.id = snap.id
            doc.status = snap.status
            doc.priority = snap.priority
            doc.tags = snap.tags
            try docManager.updateDocument(doc)
        }

        // 2. Restore Whiteboards
        if let boardData = snapshot.whiteboardsJSON.data(using: .utf8),
           let boardSnaps = try? JSONDecoder().decode([BoardSnapshot].self, from: boardData) {
            let existingBoards = try whiteboardManager.fetchWhiteboards()
            for b in existingBoards {
                try whiteboardManager.deleteWhiteboard(b)
            }
            for snap in boardSnaps {
                let b = try whiteboardManager.createWhiteboard(title: snap.title)
                b.id = snap.id
                b.elementsJSON = snap.elementsJSON
                try whiteboardManager.updateWhiteboard(b)
            }
        }

        // 3. Restore Snippets
        if let snippetData = snapshot.snippetsJSON.data(using: .utf8),
           let snippetSnaps = try? JSONDecoder().decode([SnippetSnapshot].self, from: snippetData) {
            let existingSnippets = try snippetManager.fetchSnippets()
            for s in existingSnippets {
                try snippetManager.deleteSnippet(s)
            }
            for snap in snippetSnaps {
                let tagsData = snap.tagsJSON.data(using: .utf8) ?? Data()
                let tags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
                let s = try snippetManager.createSnippet(title: snap.title, code: snap.code, language: snap.language, category: snap.category, tags: tags)
                s.id = snap.id
                try snippetManager.updateSnippet(s)
            }
        }
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
    private let storage: StorageManager
    private let projectID: UUID

    public init(storage: StorageManager, projectID: UUID) {
        self.storage = storage
        self.projectID = projectID
    }

    public func fetchTimeline(docManager: DocumentManager, whiteboardManager: WhiteboardManager, snippetManager: SnippetManager) throws -> [TimelineItem] {
        var items: [TimelineItem] = []

        // 1. Documents
        let docs = try docManager.fetchDocuments()
        for doc in docs {
            items.append(TimelineItem(
                id: doc.id,
                title: "Document Updated: \(doc.title)",
                detail: "Updated in \(doc.moduleKindRaw)",
                category: "document",
                date: doc.updatedAt,
                author: "Local Developer",
                tags: doc.tags
            ))
        }

        // 2. Whiteboards
        let boards = try whiteboardManager.fetchWhiteboards()
        for b in boards {
            items.append(TimelineItem(
                id: b.id,
                title: "Whiteboard Modified: \(b.title)",
                detail: "Infinite canvas session saved",
                category: "whiteboard",
                date: b.updatedAt,
                author: "Local Developer",
                tags: []
            ))
        }

        // 3. Snippets
        let snippets = try snippetManager.fetchSnippets()
        for s in snippets {
            items.append(TimelineItem(
                id: s.id,
                title: "Snippet Added: \(s.title)",
                detail: "Code saved in \(s.category) library",
                category: "snippet",
                date: s.createdAt,
                author: "Local Developer",
                tags: (try? JSONDecoder().decode([String].self, from: s.tagsJSON.data(using: .utf8) ?? Data())) ?? []
            ))
        }

        // 4. Simulated Build Logs and Git Commits for higher-fidelity timeline integration
        items.append(TimelineItem(
            id: UUID(),
            title: "Git Commit: refactor(navigation): Simplify workspace layout",
            detail: "Author: Jules <jules@swiftcode.dev>\nSHA: 9fa12e3\nChanges in WorkspaceView.swift",
            category: "git",
            date: Date().addingTimeInterval(-3600 * 3),
            author: "Jules",
            tags: ["navigation", "refactor"]
        ))
        items.append(TimelineItem(
            id: UUID(),
            title: "Build Success: SwiftCode Target",
            detail: "Compilation finished in 4.2 seconds. No warnings or errors.",
            category: "build",
            date: Date().addingTimeInterval(-3600 * 1.5),
            author: "Local Compiler",
            tags: ["build", "success"]
        ))
        items.append(TimelineItem(
            id: UUID(),
            title: "AI Analysis: Generated Daily Architecture Report",
            detail: "AI analyzed recent code updates and documentation completeness.",
            category: "ai",
            date: Date().addingTimeInterval(-3600 * 8),
            author: "Project intelligence",
            tags: ["ai", "report"]
        ))

        return items.sorted { $0.date > $1.date }
    }
}

@Observable
@MainActor
public final class IntelligenceManager {
    private let projectID: UUID

    public init(projectID: UUID) {
        self.projectID = projectID
    }

    public func runIntelligenceAudit(documents: [Document]) async throws -> String {
        let contentPayload = documents.map { "=== \($0.title) (\($0.moduleKindRaw)) ===\n\($0.markdownSource)" }.joined(separator: "\n\n")
        let prompt = """
        You are the SwiftCode Project Intelligence Engine. Perform a comprehensive documentation and project architecture audit.

        Using the following documentation payload:
        === DOCUMENTS ===
        \(contentPayload)

        Generate:
        1. **Documentation Quality & Health Score** (Out of 100).
        2. **Missing Documentation Alerts**: Detect what features, structural layers (e.g. database, authentication, networking) or architecture components are completely undocumented.
        3. **Technical Debt & Refactoring Recommendations**: Analyze code structure design notes for tech debt.
        4. **Duplicate Feature or Redundancy Detection**: Call out duplicate plans or duplicate definitions.
        5. **Suggested Project Roadmap & Milestones**: Propose the next 3 logical milestones and sprint tasks.
        """
        return try await LLMService.shared.generateResponse(prompt: prompt, useContext: true)
    }

    public func askProjectMemory(question: String, documents: [Document]) async throws -> String {
        let contentPayload = documents.map { "=== \($0.title) (\($0.moduleKindRaw)) ===\n\($0.markdownSource)" }.joined(separator: "\n\n")
        let prompt = """
        You are the Project Memory Oracle for SwiftCode. Your goal is to answer developer questions strictly using the documentation history, plans, and architectural decisions provided.

        === SEARCHABLE PROJECT HISTORY ===
        \(contentPayload)

        === DEVELOPER QUESTION ===
        \(question)

        Answer professionally, highlighting any relevant files, decisions, or commits mentioned in the documents. If the context doesn't contain the answer, say so, but formulate an expert deduction based on what is documented.
        """
        return try await LLMService.shared.generateResponse(prompt: prompt, useContext: true)
    }

    public func generateAutomaticDocumentation(from source: String, sourceKind: String) async throws -> String {
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
        return try await LLMService.shared.generateResponse(prompt: prompt, useContext: true)
    }
}
