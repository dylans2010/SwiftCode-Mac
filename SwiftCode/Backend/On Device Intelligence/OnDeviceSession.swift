import Foundation

struct OnDeviceSession: Identifiable, Codable, Hashable {
    let id: UUID
    var createdAt: Date
    var lastUpdated: Date
    var history: [AIMessage]
    var cachedSummary: String?

    init(id: UUID = UUID(), createdAt: Date = Date(), lastUpdated: Date = Date(), history: [AIMessage] = [], cachedSummary: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.history = history
        self.cachedSummary = cachedSummary
    }
}
