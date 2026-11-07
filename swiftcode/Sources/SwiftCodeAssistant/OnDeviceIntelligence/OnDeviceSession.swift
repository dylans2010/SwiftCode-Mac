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
