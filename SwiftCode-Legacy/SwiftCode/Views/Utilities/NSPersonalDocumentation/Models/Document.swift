import Foundation
import SwiftData

@Model
public final class Document {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var archetype: String
    public var moduleKindRaw: String
    public var title: String
    public var markdownSource: String
    public var attachments: [UUID]
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var pinned: Bool
    public var archived: Bool

    // Structured fields (Archetype B properties)
    public var status: String?
    public var priority: String?
    public var severity: String?
    public var reproSteps: String?
    public var stackTrace: String?
    public var targetQuarter: String?
    public var dependencyIDs: [UUID]

    public var moduleKind: ModuleKind {
        get { ModuleKind(rawValue: moduleKindRaw) ?? .personalDocumentation }
        set { moduleKindRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        archetype: String,
        moduleKind: ModuleKind,
        title: String,
        markdownSource: String = "",
        attachments: [UUID] = [],
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pinned: Bool = false,
        archived: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.archetype = archetype
        self.moduleKindRaw = moduleKind.rawValue
        self.title = title
        self.markdownSource = markdownSource
        self.attachments = attachments
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.archived = archived
        self.dependencyIDs = []
    }
}
