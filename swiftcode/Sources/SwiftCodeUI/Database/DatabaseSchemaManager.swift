import Foundation
import SwiftCodeCloud

/// Creates and drops tables on a connection.
///
/// Ported from Legacy's
/// `Views/Utilities/Database/Core/DatabaseSchemaManager.swift`.
///
/// Two deliberate changes over Legacy, both recorded here:
///
/// 1. The `CREATE TABLE` SQL no longer comes from
///    `DatabaseUtilities.defaultSQLForCreateTable` — that helper
///    lives in `Helpers/DatabaseUtilities.swift`, which is outside
///    this family and may or may not be ported. The generator is
///    ported inline as `createTableSQL(table:provider:)`, faithful
///    to Legacy's logic (column definitions, `PRIMARY KEY` /
///    `AUTOINCREMENT` / `SERIAL` / `AUTO_INCREMENT` per provider,
///    `NOT NULL` / `UNIQUE` / `DEFAULT` / `CHECK`, foreign keys
///    for one-to-one and one-to-many relationships), with
///    identifiers quoted where Legacy interpolated them raw.
/// 2. Remote execution goes through the destination's
///    `SupabaseService` value type (`SupabaseService()` — there is
///    no `.shared` on the destination service), and a provider
///    with no driver in this package (PostgreSQL, MySQL, MariaDB)
///    now fails honestly with `.schemaModificationFailed` instead
///    of Legacy's silent no-op.
@MainActor
public final class DatabaseSchemaManager {
    public static let shared = DatabaseSchemaManager()

    private init() {}

    public func createTable(connection: DatabaseConnection, table: DatabaseTable) async throws {
        let sql = Self.createTableSQL(table: table, provider: connection.provider)

        switch connection.provider {
        case .sqlite:
            guard let filePath = connection.sqliteFilePath else {
                throw DatabaseError.validationFailed("No SQLite file path provided.")
            }
            _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: filePath, sql: sql)
        case .supabase:
            _ = try await SupabaseService().executeSQL(connection: connection, sql: sql)
        default:
            throw DatabaseError.schemaModificationFailed(
                "Creating tables on \(connection.provider.rawValue) is not supported: no driver for this provider.")
        }
    }

    public func deleteTable(connection: DatabaseConnection, tableName: String) async throws {
        let sql = "DROP TABLE IF EXISTS \(SQLiteExplorerModel.quoted(tableName));"

        switch connection.provider {
        case .sqlite:
            guard let filePath = connection.sqliteFilePath else {
                throw DatabaseError.validationFailed("No SQLite file path provided.")
            }
            _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: filePath, sql: sql)
        case .supabase:
            _ = try await SupabaseService().executeSQL(connection: connection, sql: sql)
        default:
            throw DatabaseError.schemaModificationFailed(
                "Dropping tables on \(connection.provider.rawValue) is not supported: no driver for this provider.")
        }
    }

    // MARK: - SQL generation

    /// The `CREATE TABLE` statement for a table, in the dialect of
    /// `provider`. Faithful port of Legacy's
    /// `DatabaseUtilities.defaultSQLForCreateTable(table:provider:)`
    /// (`Helpers/DatabaseUtilities.swift`), inlined here because
    /// that helper is outside this family; identifiers are quoted,
    /// where Legacy interpolated table and column names raw.
    static func createTableSQL(table: DatabaseTable, provider: DatabaseProvider) -> String {
        var sql = "CREATE TABLE \(SQLiteExplorerModel.quoted(table.name)) (\n"
        var columnsSql: [String] = []

        for col in table.columns {
            let quotedName = SQLiteExplorerModel.quoted(col.name)
            var colDef = "    \(quotedName) \(col.type)"
            if col.isPrimaryKey {
                if provider == .sqlite && col.isAutoIncrement {
                    colDef += " PRIMARY KEY AUTOINCREMENT"
                } else if provider == .postgresql || provider == .supabase {
                    if col.isAutoIncrement {
                        colDef = "    \(quotedName) SERIAL PRIMARY KEY"
                    } else {
                        colDef += " PRIMARY KEY"
                    }
                } else {
                    colDef += " PRIMARY KEY"
                    if col.isAutoIncrement {
                        colDef += " AUTO_INCREMENT"
                    }
                }
            } else {
                if !col.isNullable {
                    colDef += " NOT NULL"
                }
                if col.isUnique {
                    colDef += " UNIQUE"
                }
                if let df = col.defaultValue {
                    colDef += " DEFAULT \(df)"
                }
                if let chk = col.checkConstraint {
                    colDef += " CHECK (\(chk))"
                }
            }
            columnsSql.append(colDef)
        }

        // Relationships / Foreign Keys
        for rel in table.relationships {
            if rel.type == .oneToMany || rel.type == .oneToOne {
                var fkDef = "    FOREIGN KEY (\(SQLiteExplorerModel.quoted(rel.sourceColumn))) REFERENCES \(SQLiteExplorerModel.quoted(rel.targetTable))(\(SQLiteExplorerModel.quoted(rel.targetColumn)))"
                if rel.onDelete != .noAction {
                    fkDef += " ON DELETE \(rel.onDelete.rawValue)"
                }
                if rel.onUpdate != .noAction {
                    fkDef += " ON UPDATE \(rel.onUpdate.rawValue)"
                }
                columnsSql.append(fkDef)
            }
        }

        sql += columnsSql.joined(separator: ",\n")
        sql += "\n);"
        return sql
    }
}
