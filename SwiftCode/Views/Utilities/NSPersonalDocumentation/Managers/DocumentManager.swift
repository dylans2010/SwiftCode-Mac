import Foundation
import SwiftData
import Observation

@Observable
@MainActor
public final class DocumentManager {
    private let storage: StorageManager
    private let projectID: UUID

    public init(storage: StorageManager, projectID: UUID) {
        self.storage = storage
        self.projectID = projectID
    }

    public func fetchDocuments(for kind: ModuleKind? = nil) throws -> [Document] {
        let fetchDescriptor = FetchDescriptor<Document>()
        let all = try storage.context.fetch(fetchDescriptor)
        let filtered = all.filter { $0.projectID == projectID }
        if let kind = kind {
            return filtered.filter { $0.moduleKind == kind }
        }
        return filtered
    }

    public func fetchDocument(id: UUID) throws -> Document? {
        let fetchDescriptor = FetchDescriptor<Document>()
        let all = try storage.context.fetch(fetchDescriptor)
        return all.first { $0.id == id && $0.projectID == projectID }
    }

    public func createDocument(title: String, kind: ModuleKind, markdown: String = "") throws -> Document {
        let doc = Document(
            projectID: projectID,
            archetype: kind.archetype.rawValue,
            moduleKind: kind,
            title: title,
            markdownSource: markdown
        )
        storage.context.insert(doc)
        try storage.context.save()
        return doc
    }

    public func updateDocument(_ doc: Document) throws {
        doc.updatedAt = Date()
        try storage.context.save()
    }

    public func deleteDocument(_ doc: Document) throws {
        storage.context.delete(doc)
        try storage.context.save()
    }
}
