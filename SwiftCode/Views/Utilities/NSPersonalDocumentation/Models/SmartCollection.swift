import Foundation
import SwiftData

@Model
public final class SmartCollection {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var title: String
    public var includedTags: [String]
    public var archetypeFilter: String?

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String,
        includedTags: [String] = [],
        archetypeFilter: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.includedTags = includedTags
        self.archetypeFilter = archetypeFilter
    }
}
