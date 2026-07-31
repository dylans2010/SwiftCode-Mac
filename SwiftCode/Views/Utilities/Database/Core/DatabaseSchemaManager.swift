import Foundation

@MainActor
public final class DatabaseSchemaManager {
    public static let shared = DatabaseSchemaManager()

    private init() {}

    public func createTable(connection: DatabaseConnection, table: DatabaseTable) async throws {
        let sql = DatabaseUtilities.defaultSQLForCreateTable(table: table, provider: connection.provider)

        switch connection.provider {
        case .sqlite:
            guard let filePath = connection.sqliteFilePath else {
                throw DatabaseError.validationFailed("No SQLite file path provided.")
            }
            _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: filePath, sql: sql)
        case .supabase:
            _ = try await SupabaseService.shared.executeSQL(connection: connection, sql: sql)
        default:
            // Other cloud or remote databases execution
            break
        }
    }

    public func deleteTable(connection: DatabaseConnection, tableName: String) async throws {
        let sql = "DROP TABLE IF EXISTS \(tableName);"

        switch connection.provider {
        case .sqlite:
            guard let filePath = connection.sqliteFilePath else {
                throw DatabaseError.validationFailed("No SQLite file path provided.")
            }
            _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: filePath, sql: sql)
        case .supabase:
            _ = try await SupabaseService.shared.executeSQL(connection: connection, sql: sql)
        default:
            break
        }
    }
}
