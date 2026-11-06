import Foundation
import SwiftData

@Model
public final class Template {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID?
    public var moduleKindRaw: String
    public var title: String
    public var descriptionText: String
    public var markdownSource: String

    public var moduleKind: ModuleKind {
        get { ModuleKind(rawValue: moduleKindRaw) ?? .personalDocumentation }
        set { moduleKindRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        projectID: UUID? = nil,
        moduleKind: ModuleKind,
        title: String,
        descriptionText: String = "",
        markdownSource: String = ""
    ) {
        self.id = id
        self.projectID = projectID
        self.moduleKindRaw = moduleKind.rawValue
        self.title = title
        self.descriptionText = descriptionText
        self.markdownSource = markdownSource
    }
}
