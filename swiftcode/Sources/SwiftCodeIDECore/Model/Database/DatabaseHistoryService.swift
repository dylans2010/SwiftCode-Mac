// Ported from Legacy `SwiftCode/Views/Utilities/Database/Services/DatabaseHistoryService.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: QueryHistoryItem, SavedQueryItem.

import Foundation

public struct QueryHistoryItem: Identifiable, Codable, Hashable {
    public let id: UUID
    public var sql: String
    public var timestamp: Date
    public var executionTimeMs: Double
    public var rowsAffected: Int
    public var status: String // "SUCCESS" or "ERROR"
    public var errorMessage: String?

    public init(id: UUID = UUID(), sql: String, timestamp: Date = Date(), executionTimeMs: Double, rowsAffected: Int, status: String, errorMessage: String? = nil) {
        self.id = id
        self.sql = sql
        self.timestamp = timestamp
        self.executionTimeMs = executionTimeMs
        self.rowsAffected = rowsAffected
        self.status = status
        self.errorMessage = errorMessage
    }
}

public struct SavedQueryItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var sql: String
    public var category: String
    public var tags: [String]
    public var isFavorite: Bool
    public var timestamp: Date

    public init(id: UUID = UUID(), title: String, sql: String, category: String = "General", tags: [String] = [], isFavorite: Bool = false, timestamp: Date = Date()) {
        self.id = id
        self.title = title
        self.sql = sql
        self.category = category
        self.tags = tags
        self.isFavorite = isFavorite
        self.timestamp = timestamp
    }
}
