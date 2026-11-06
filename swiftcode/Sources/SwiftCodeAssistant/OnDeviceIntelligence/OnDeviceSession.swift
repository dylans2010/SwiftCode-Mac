// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/On Device Intelligence/OnDeviceSession.swift
//   (Legacy commit d51a8f0d)
//
// `AIMessage` (full type) now lives in `SwiftCodeAssistant/AIMessage.swift`
// (ported from Legacy `SwiftCode/Core/AI/AIMessage.swift` in the A5
// migration batch); this file's former minimal local `AIMessage`
// declaration was removed at that landing and `OnDeviceSession.history`
// adopts the full type (gaining `attachments`).

import Foundation

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
