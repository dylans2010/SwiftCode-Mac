import Foundation

public struct AIMessageAttachment: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let mimeType: String
    public let base64Data: String
    public let filename: String?

    public init(id: UUID = UUID(), mimeType: String = "image/png", base64Data: String, filename: String? = nil) {
        self.id = id
        self.mimeType = mimeType
        self.base64Data = base64Data
        self.filename = filename
    }
}

public struct AIMessage: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let role: Role
    public var content: String
    public let modelUsed: String?
    public let timestamp: Date
    public var attachments: [AIMessageAttachment]?

    public enum Role: String, Sendable, Codable {
        case user
        case assistant
        case system
    }

    public init(role: Role, content: String, modelUsed: String? = nil, attachments: [AIMessageAttachment]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.modelUsed = modelUsed
        self.timestamp = Date()
        self.attachments = attachments
    }
}

