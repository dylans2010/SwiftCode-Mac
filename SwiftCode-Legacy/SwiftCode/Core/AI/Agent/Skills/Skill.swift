import Foundation

public enum SkillSource: String, Codable, Sendable, Hashable {
    case preset
    case uploaded
}

public struct SkillScheme: Codable, Sendable, Hashable {
    public let name: String
    public let summary: String
    public let version: String
    public let author: String
    public let tags: [String]
    public let recommendedTools: [String]
    public let guidance: [String]

    public init(
        name: String = "",
        summary: String = "",
        version: String = "1.0.0",
        author: String = "",
        tags: [String] = [],
        recommendedTools: [String] = [],
        guidance: [String] = []
    ) {
        self.name = name
        self.summary = summary
        self.version = version
        self.author = author
        self.tags = tags
        self.recommendedTools = recommendedTools
        self.guidance = guidance
    }
}

public struct AgentSkillBundle: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let scheme: SkillScheme
    public let markdown: String
    public let source: SkillSource

    public init(id: UUID = UUID(), scheme: SkillScheme, markdown: String, source: SkillSource) {
        self.id = id
        self.scheme = scheme
        self.markdown = markdown
        self.source = source
    }
}

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
