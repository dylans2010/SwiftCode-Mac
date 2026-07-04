import Foundation

public struct Skill: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public var isEnabled: Bool
    public let content: String
    public let metadata: [String: String]

    public init(id: UUID = UUID(), name: String, description: String, isEnabled: Bool = true, content: String, metadata: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.description = description
        self.isEnabled = isEnabled
        self.content = content
        self.metadata = metadata
    }
}
