import Foundation
import SwiftData

@Model
public final class AnalyticsSnapshot {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var timestamp: Date
    public var eventName: String
    public var metadataString: String?

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        timestamp: Date = Date(),
        eventName: String,
        metadataString: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.timestamp = timestamp
        self.eventName = eventName
        self.metadataString = metadataString
    }
}
