import Foundation

public struct DatabaseQueryHistoryItem: Identifiable, Codable, Hashable {
    public let id: UUID
    public var sql: String
    public var timestamp: Date
    public var executionTimeMs: Double
    public var rowsAffected: Int
    public var status: String
    public var errorMessage: String?

    public init(id: UUID = UUID(), sql: String, timestamp: Date = Date(), executionTimeMs: Double,
                rowsAffected: Int, status: String, errorMessage: String? = nil) {
        self.id = id
        self.sql = sql
        self.timestamp = timestamp
        self.executionTimeMs = executionTimeMs
        self.rowsAffected = rowsAffected
        self.status = status
        self.errorMessage = errorMessage
    }
}

public struct DatabaseSavedQueryItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var sql: String
    public var category: String
    public var tags: [String]
    public var isFavorite: Bool
    public var timestamp: Date

    public init(id: UUID = UUID(), title: String, sql: String, category: String = "General",
                tags: [String] = [], isFavorite: Bool = false, timestamp: Date = Date()) {
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

    public static let historyKey = "com.swiftcode.database.queryHistory"
    public static let savedQueriesKey = "com.swiftcode.database.savedQueries"

    private let userDefaults: UserDefaults
    private var history: [DatabaseQueryHistoryItem] = []
    private var savedQueries: [DatabaseSavedQueryItem] = []

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadHistory()
        loadSavedQueries()
        if savedQueries.isEmpty {
            seedDefaultSavedQueries()
        }
    }

    public func fetchHistory() -> [DatabaseQueryHistoryItem] { history }

    public func record(sql: String, executionTimeMs: Double, rowsAffected: Int,
                       status: String, errorMessage: String? = nil) {
        addHistoryItem(DatabaseQueryHistoryItem(sql: sql, executionTimeMs: executionTimeMs,
                                                rowsAffected: rowsAffected, status: status,
                                                errorMessage: errorMessage))
    }

    public func addHistoryItem(_ item: DatabaseQueryHistoryItem) {
        history.insert(item, at: 0)
        saveHistory()
    }

    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    public func fetchSavedQueries() -> [DatabaseSavedQueryItem] { savedQueries }

    public func saveQuery(title: String, sql: String, category: String = "General",
                          tags: [String] = [], isFavorite: Bool = false) {
        let newItem = DatabaseSavedQueryItem(title: title, sql: sql, category: category, tags: tags, isFavorite: isFavorite)
        savedQueries.insert(newItem, at: 0)
        saveSavedQueries()
    }

    public func deleteSavedQuery(id: UUID) {
        savedQueries.removeAll { $0.id == id }
        saveSavedQueries()
    }

    public func toggleSavedQueryFavorite(id: UUID) {
        if let index = savedQueries.firstIndex(where: { $0.id == id }) {
            savedQueries[index].isFavorite.toggle()
            saveSavedQueries()
        }
    }

    private func loadHistory() {
        if let data = userDefaults.data(forKey: Self.historyKey),
           let decoded = try? JSONDecoder().decode([DatabaseQueryHistoryItem].self, from: data) {
            history = decoded
        }
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            userDefaults.set(encoded, forKey: Self.historyKey)
        }
    }

    private func loadSavedQueries() {
        if let data = userDefaults.data(forKey: Self.savedQueriesKey),
           let decoded = try? JSONDecoder().decode([DatabaseSavedQueryItem].self, from: data) {
            savedQueries = decoded
        }
    }

    private func saveSavedQueries() {
        if let encoded = try? JSONEncoder().encode(savedQueries) {
            userDefaults.set(encoded, forKey: Self.savedQueriesKey)
        }
    }

    private func seedDefaultSavedQueries() {
        savedQueries = [
            DatabaseSavedQueryItem(
                title: "Fetch All Tables",
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
                category: "Utility", tags: ["System", "SQLite"], isFavorite: true
            ),
            DatabaseSavedQueryItem(
                title: "Verify Database Integrity",
                sql: "PRAGMA integrity_check;",
                category: "Diagnostics", tags: ["Admin", "Check"], isFavorite: false
            ),
            DatabaseSavedQueryItem(
                title: "Show Active Connections Info",
                sql: "PRAGMA database_list;",
                category: "Diagnostics", tags: ["Admin", "System"], isFavorite: false
            ),
        ]
        saveSavedQueries()
    }
}
