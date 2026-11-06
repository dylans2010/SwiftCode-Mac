import Foundation
import SwiftData

@MainActor
public final class VersionHistoryManager {
    private let storage: StorageManager
    private let projectID: UUID

    public init(storage: StorageManager, projectID: UUID) {
        self.storage = storage
        self.projectID = projectID
    }

    public func recordSnapshot(for doc: Document) throws {
        let snapshot = DocumentVersion(
            projectID: projectID,
            documentID: doc.id,
            titleSnapshot: doc.title,
            markdownSnapshot: doc.markdownSource
        )
        storage.context.insert(snapshot)
        try storage.context.save()
    }

    public func fetchVersions(for documentID: UUID) throws -> [DocumentVersion] {
        let descriptor = FetchDescriptor<DocumentVersion>()
        let all = try storage.context.fetch(descriptor)
        let filtered = all.filter { version in
            return version.projectID == self.projectID && version.documentID == documentID
        }
        return filtered.sorted { $0.timestamp > $1.timestamp }
    }
}
