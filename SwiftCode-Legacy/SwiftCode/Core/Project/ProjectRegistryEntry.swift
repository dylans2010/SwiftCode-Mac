import Foundation

public struct ProjectRegistryEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let rootURL: URL
    public let kind: ProjectKind
    public var lastOpenedAt: Date
    public var sourceControlEnabled: Bool

    public init(id: UUID = UUID(), name: String, rootURL: URL, kind: ProjectKind, lastOpenedAt: Date = Date(), sourceControlEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.kind = kind
        self.lastOpenedAt = lastOpenedAt
        self.sourceControlEnabled = sourceControlEnabled
    }
}
