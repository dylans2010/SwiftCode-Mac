import Foundation
import Observation

@Observable
@MainActor
public final class MetadataManager {
    private let documentManager: DocumentManager

    public init(documentManager: DocumentManager) {
        self.documentManager = documentManager
    }

    public func fetchAllTags() throws -> [String] {
        let docs = try documentManager.fetchDocuments()
        let tags = Set(docs.flatMap { $0.tags })
        return Array(tags).sorted()
    }

    public func addTag(_ tag: String, to doc: Document) throws {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !doc.tags.contains(trimmed) {
            doc.tags.append(trimmed)
            try documentManager.updateDocument(doc)
        }
    }

    public func removeTag(_ tag: String, from doc: Document) throws {
        if let idx = doc.tags.firstIndex(of: tag) {
            doc.tags.remove(at: idx)
            try documentManager.updateDocument(doc)
        }
    }
}
