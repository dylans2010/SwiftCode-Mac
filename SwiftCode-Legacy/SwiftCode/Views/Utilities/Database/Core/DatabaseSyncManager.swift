import Foundation

@MainActor
public final class DatabaseSyncManager: ObservableObject {
    public static let shared = DatabaseSyncManager()

    @Published public var syncInProgress = false
    @Published public var lastSyncTimestamp: Date?

    private init() {}

    public func synchronizeSchemas(from source: DatabaseConnection, to destination: DatabaseConnection) async throws {
        syncInProgress = true
        defer { syncInProgress = false }

        // Fetch source tables
        let sourceTables: [DatabaseTable]
        if source.provider == .sqlite {
            guard let filePath = source.sqliteFilePath else { return }
            sourceTables = try DatabaseManager.shared.fetchSQLiteTables(filePath: filePath)
        } else if source.provider == .supabase {
            sourceTables = try await SupabaseService.shared.fetchTables(connection: source)
        } else {
            sourceTables = []
        }

        // Migrate to destination
        for table in sourceTables {
            try await DatabaseSchemaManager.shared.createTable(connection: destination, table: table)
        }

        lastSyncTimestamp = Date()
    }
}
