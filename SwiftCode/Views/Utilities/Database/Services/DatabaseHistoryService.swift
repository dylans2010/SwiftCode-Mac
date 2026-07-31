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

@MainActor
public final class DatabaseHistoryService {
    public static let shared = DatabaseHistoryService()

    private var history: [QueryHistoryItem] = []

    private init() {
        loadHistory()
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
}
