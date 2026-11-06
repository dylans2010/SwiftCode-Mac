// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/On Device Intelligence/OnDeviceSession.swift
//   (Legacy commit d51a8f0d)
//
// `AIMessage` (minimal, local): Legacy's session history is `[AIMessage]`,
// but the destination has no `AIMessage` type — Legacy's full definition
// lives in `SwiftCode/Core/AI/AIMessage.swift`, which is outside this
// fragment's scope. Rather than invent a dependency, this file defines
// the smallest message type this family actually uses: id, role,
// content, model used, timestamp, with Legacy's `init(role:content:)`
// signature. Legacy's `attachments` (`[AIMessageAttachment]`) are NOT
// carried over — nothing in this family reads them — so if the full
// Core/AI `AIMessage` is ported later, this minimal type must be removed
// and the session must adopt it instead of redeclaring the name.

import Foundation

public struct AIMessage: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let role: Role
    public var content: String
    public let modelUsed: String?
    public let timestamp: Date

    public enum Role: String, Sendable, Codable {
        case user
        case assistant
        case system
    }

    public init(role: Role, content: String, modelUsed: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.modelUsed = modelUsed
        self.timestamp = Date()
    }
}

public struct OnDeviceSession: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var createdAt: Date
    public var lastUpdated: Date
    public var history: [AIMessage]
    public var cachedSummary: String?

    public init(id: UUID = UUID(), createdAt: Date = Date(), lastUpdated: Date = Date(), history: [AIMessage] = [], cachedSummary: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.history = history
        self.cachedSummary = cachedSummary
    }
}
