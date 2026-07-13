import Foundation
import SwiftData

@Model
public final class WikiPage {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var title: String
    public var markdownSource: String
    public var lastUpdated: Date
    public var isStale: Bool

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String,
        markdownSource: String = "",
        lastUpdated: Date = Date(),
        isStale: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.markdownSource = markdownSource
        self.lastUpdated = lastUpdated
        self.isStale = isStale
    }
}
