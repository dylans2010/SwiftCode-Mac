import Foundation
import SwiftData

@Model
public final class Relationship {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var sourceDocumentID: UUID
    public var targetType: String
    public var targetIdentifier: String
    public var targetName: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        sourceDocumentID: UUID,
        targetType: String,
        targetIdentifier: String,
        targetName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.sourceDocumentID = sourceDocumentID
        self.targetType = targetType
        self.targetIdentifier = targetIdentifier
        self.targetName = targetName
        self.createdAt = createdAt
    }
}
