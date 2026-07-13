import Foundation
import SwiftData

@MainActor
public final class RelationshipManager {
    private let storage: StorageManager
    private let projectID: UUID

    public init(storage: StorageManager, projectID: UUID) {
        self.storage = storage
        self.projectID = projectID
    }

    public func fetchRelationships(for sourceDocumentID: UUID) throws -> [Relationship] {
        let descriptor = FetchDescriptor<Relationship>()
        let all = try storage.context.fetch(descriptor)
        return all.filter { $0.projectID == projectID && $0.sourceDocumentID == sourceDocumentID }
    }

    public func addLink(sourceID: UUID, targetType: String, targetIdentifier: String, targetName: String) throws {
        let rel = Relationship(
            projectID: projectID,
            sourceDocumentID: sourceID,
            targetType: targetType,
            targetIdentifier: targetIdentifier,
            targetName: targetName
        )
        storage.context.insert(rel)
        try storage.context.save()
    }

    public func removeLink(_ rel: Relationship) throws {
        storage.context.delete(rel)
        try storage.context.save()
    }
}
