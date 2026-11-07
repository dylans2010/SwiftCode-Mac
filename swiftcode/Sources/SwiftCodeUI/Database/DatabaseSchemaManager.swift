import Foundation
import SwiftCodeCloud

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
