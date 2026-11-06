// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Core/AI/AIMessage.swift
//   (Legacy main ab03f681)
//
// Destination: SwiftCodeAssistant/Models/AIMessage.swift. Verbatim apart from the
// header and the `public` access level (Legacy's types were already public).
//
// Wiring hook — LAND TOGETHER, or the target will not compile:
// `SwiftCodeAssistant/OnDeviceIntelligence/OnDeviceSession.swift` currently
// declares a MINIMAL `AIMessage` (id, role, content, modelUsed, timestamp —
// no attachments) with a header comment stating exactly this: "if the full
// Core/AI `AIMessage` is ported later, this minimal type must be removed
// and the session must adopt it instead of redeclaring the name."
// Landing this file requires deleting that minimal declaration from
// OnDeviceSession.swift; `OnDeviceSession.history` (`[AIMessage]`) then
// adopts this full type, gaining the `attachments` field and the
// `init(role:content:modelUsed:attachments:)` initialiser. Nothing else
// in the target declares `AIMessage` or `AIMessageAttachment`.

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
