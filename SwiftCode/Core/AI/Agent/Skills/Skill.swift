import Foundation

public struct Skill: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public var isEnabled: Bool
    public let content: String
    public let metadata: [String: String]
    public let url: URL?
    public let scheme: SkillScheme
    public var swiftCodeAssistCapable: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        isEnabled: Bool = true,
        content: String,
        metadata: [String: String] = [:],
        url: URL? = nil,
        scheme: SkillScheme = SkillScheme(),
        swiftCodeAssistCapable: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isEnabled = isEnabled
        self.content = content
        self.metadata = metadata
        self.url = url
        self.scheme = scheme
        self.swiftCodeAssistCapable = swiftCodeAssistCapable
    }
}
