import Foundation

public enum SkillSource: String, Codable, Sendable {
    case preset
    case uploaded
}

public struct SkillScheme: Codable, Sendable {
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

public struct AgentSkillBundle: Identifiable, Sendable {
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
