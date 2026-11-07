import Foundation
import SwiftData

@Model
public final class WhiteboardRecord {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var title: String
    public var elementsJSON: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String,
        elementsJSON: String = "[]",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.elementsJSON = elementsJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class CodeSnippetRecord {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var title: String
    public var code: String
    public var language: String
    public var category: String
    public var tagsJSON: String
    public var isFavorite: Bool
    public var versionHistoryJSON: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String,
        code: String = "",
        language: String = "Swift",
        category: String = "Utility",
        tagsJSON: String = "[]",
        isFavorite: Bool = false,
        versionHistoryJSON: String = "[]",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.code = code
        self.language = language
        self.category = category
        self.tagsJSON = tagsJSON
        self.isFavorite = isFavorite
        self.versionHistoryJSON = versionHistoryJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class ProjectSnapshotRecord {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var title: String
    public var descriptionText: String
    public var documentsJSON: String
    public var whiteboardsJSON: String
    public var snippetsJSON: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String,
        descriptionText: String = "",
        documentsJSON: String = "[]",
        whiteboardsJSON: String = "[]",
        snippetsJSON: String = "[]",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.descriptionText = descriptionText
        self.documentsJSON = documentsJSON
        self.whiteboardsJSON = whiteboardsJSON
        self.snippetsJSON = snippetsJSON
        self.createdAt = createdAt
    }
}
