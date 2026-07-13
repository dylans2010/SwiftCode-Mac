import Foundation
import SwiftData

@Model
public final class DocumentVersion {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var documentID: UUID
    public var titleSnapshot: String
    public var markdownSnapshot: String
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        documentID: UUID,
        titleSnapshot: String,
        markdownSnapshot: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.documentID = documentID
        self.titleSnapshot = titleSnapshot
        self.markdownSnapshot = markdownSnapshot
        self.timestamp = timestamp
    }
}
