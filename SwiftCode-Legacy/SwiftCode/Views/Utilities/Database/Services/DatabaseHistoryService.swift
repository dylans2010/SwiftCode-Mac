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

@MainActor
public final class DatabaseHistoryService {
    public static let shared = DatabaseHistoryService()

    private var history: [QueryHistoryItem] = []
    private var savedQueries: [SavedQueryItem] = []

    private init() {
        loadHistory()
        loadSavedQueries()
        if savedQueries.isEmpty {
            seedDefaultSavedQueries()
        }
    }

    public func fetchHistory() -> [QueryHistoryItem] {
        return history
    }

    public func addHistoryItem(_ item: QueryHistoryItem) {
        history.insert(item, at: 0)
        saveHistory()
    }

    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    // MARK: - Saved Queries Management
    public func fetchSavedQueries() -> [SavedQueryItem] {
        return savedQueries
    }

    public func saveQuery(title: String, sql: String, category: String = "General", tags: [String] = [], isFavorite: Bool = false) {
        let newItem = SavedQueryItem(title: title, sql: sql, category: category, tags: tags, isFavorite: isFavorite)
        savedQueries.insert(newItem, at: 0)
        saveSavedQueries()
    }

    public func deleteSavedQuery(id: UUID) {
        savedQueries.removeAll { $0.id == id }
        saveSavedQueries()
    }

    public func toggleSavedQueryFavorite(id: UUID) {
        if let idx = savedQueries.firstIndex(where: { $0.id == id }) {
            savedQueries[idx].isFavorite.toggle()
            saveSavedQueries()
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.database.queryHistory"),
           let decoded = try? JSONDecoder().decode([QueryHistoryItem].self, from: data) {
            self.history = decoded
        }
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: "com.swiftcode.database.queryHistory")
        }
    }

    private func loadSavedQueries() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.database.savedQueries"),
           let decoded = try? JSONDecoder().decode([SavedQueryItem].self, from: data) {
            self.savedQueries = decoded
        }
    }

    private func saveSavedQueries() {
        if let encoded = try? JSONEncoder().encode(savedQueries) {
            UserDefaults.standard.set(encoded, forKey: "com.swiftcode.database.savedQueries")
        }
    }

    private func seedDefaultSavedQueries() {
        savedQueries = [
            SavedQueryItem(
                title: "Fetch All Tables",
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
                category: "Utility",
                tags: ["System", "SQLite"],
                isFavorite: true
            ),
            SavedQueryItem(
                title: "Verify Database Integrity",
                sql: "PRAGMA integrity_check;",
                category: "Diagnostics",
                tags: ["Admin", "Check"],
                isFavorite: false
            ),
            SavedQueryItem(
                title: "Show Active Connections Info",
                sql: "PRAGMA database_list;",
                category: "Diagnostics",
                tags: ["Admin", "System"],
                isFavorite: false
            )
        ]
        saveSavedQueries()
    }
}
