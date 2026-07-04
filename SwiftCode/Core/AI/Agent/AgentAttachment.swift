import Foundation

public struct AgentAttachment: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let type: AttachmentType

    public enum AttachmentType: String, Codable, Sendable {
        case file
        case image
    }

    public init(id: UUID = UUID(), name: String, url: URL, type: AttachmentType) {
        self.id = id
        self.name = name
        self.url = url
        self.type = type
    }
}
