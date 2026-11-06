import Foundation
import SwiftData

@Model
public final class AttachmentRecord {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var relativePath: String
    public var originalFileName: String
    public var mimeType: String
    public var fileSize: Int64
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        relativePath: String,
        originalFileName: String,
        mimeType: String,
        fileSize: Int64,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.relativePath = relativePath
        self.originalFileName = originalFileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.addedAt = addedAt
    }
}
