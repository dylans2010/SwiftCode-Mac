import Foundation
import SwiftData

@Model
public final class AIInsight {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var kindRaw: String
    public var generatedAt: Date
    public var sourceDocumentIDs: [UUID]
    public var content: String
    public var isStale: Bool

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        kindRaw: String,
        generatedAt: Date = Date(),
        sourceDocumentIDs: [UUID] = [],
        content: String = "",
        isStale: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.kindRaw = kindRaw
        self.generatedAt = generatedAt
        self.sourceDocumentIDs = sourceDocumentIDs
        self.content = content
        self.isStale = isStale
    }
}
