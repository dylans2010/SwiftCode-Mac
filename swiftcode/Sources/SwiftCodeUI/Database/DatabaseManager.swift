import Foundation
import os.log
import SwiftCodeCloud
import SwiftCodeHealthStore

/// The SQLite driver for the Database utility: open a file, run
/// SQL, list tables with their columns and row counts.
///
/// Ported from Legacy's
/// `Views/Utilities/Database/Core/DatabaseManager.swift`.
///
/// One deliberate change, and it is the whole point of this port:
/// Legacy drove the C SQLite API directly through the SQLite3
/// Swift module. That module does not exist in this package, and
/// through `SQLiteDatabase` (`SwiftCodeHealthStore`), the shared
/// SQLite client this package already has (the same client
/// `SQLiteExplorerModel` is built on, backed by the `CSQLite`
/// system-library target). The public surface is Legacy's:
/// `executeSQLiteQuery(filePath:sql:)` returns rows as
/// `[String: String]` dictionaries keyed by column name, and
/// `fetchSQLiteTables(filePath:)` returns `DatabaseTable` values.
///
/// Two smaller corrections over Legacy, both noted where they
/// land: table names are quoted in the `PRAGMA` / `COUNT(*)` SQL
/// (Legacy interpolated them raw, so a table with a space or a
/// quote in its name broke the query), and a blob cell renders as
/// `<N bytes>` instead of being forced through `sqlite3_column_text`
/// (Legacy's lossy byte-to-text coercion).
@MainActor
public final class DatabaseManager {
    public static let shared = DatabaseManager()
    private let logger = Logger(subsystem: "com.SwiftCode", category: "DatabaseManager")

    private init() {}

    /// Opens the file at `filePath` (creating its parent directory
    /// and the file itself when missing, exactly as Legacy did) and
    /// runs one SQL statement, returning its rows as dictionaries
    /// keyed by column name. A statement with no result set
    /// (INSERT, UPDATE, CREATE…) returns an empty array. Only the
    /// first statement in `sql` runs.
    public func executeSQLiteQuery(filePath: String, sql: String) throws -> [[String: String]] {
        let db = try openDatabase(filePath: filePath)
        do {
            let (columns, rows) = try db.queryWithColumns(sql)
            return rows.map { row in
                var dict: [String: String] = [:]
                for (index, column) in columns.enumerated() where index < row.count {
                    dict[column] = SQLiteExplorerModel.display(row[index])
                }
                return dict
            }
        } catch {
            throw DatabaseError.queryExecutionFailed(Self.message(of: error), sql: sql)
        }
    }

    /// Every user table in the file (excluding SQLite's own
    /// `sqlite_*` internals), each with its declared columns in
    /// order and its row count — the schema the cache, the
    /// validator, and the sync manager all work from.
    public func fetchSQLiteTables(filePath: String) throws -> [DatabaseTable] {
        let tablesQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
        let rows = try executeSQLiteQuery(filePath: filePath, sql: tablesQuery)

        var tables: [DatabaseTable] = []
        for row in rows {
            guard let tableName = row["name"] else { continue }

            // Columns, in declared order (`PRAGMA table_info`).
            let pragmaQuery = "PRAGMA table_info(\(SQLiteExplorerModel.quoted(tableName)));"
            let columnRows = try executeSQLiteQuery(filePath: filePath, sql: pragmaQuery)

            var columns: [DatabaseColumn] = []
            for colRow in columnRows {
                guard let colName = colRow["name"], let colType = colRow["type"] else { continue }
                let isPK = colRow["pk"] == "1"
                let isNullable = colRow["notnull"] == "0"
                let defaultValue = colRow["dflt_value"] == "NULL" ? nil : colRow["dflt_value"]

                let col = DatabaseColumn(
                    name: colName,
                    type: colType,
                    isPrimaryKey: isPK,
                    isNullable: isNullable,
                    defaultValue: defaultValue
                )
                columns.append(col)
            }

            // Record count.
            let countQuery = "SELECT COUNT(*) as count FROM \(SQLiteExplorerModel.quoted(tableName));"
            let countRows = try? executeSQLiteQuery(filePath: filePath, sql: countQuery)
            let recordCount = Int(countRows?.first?["count"] ?? "0") ?? 0

            let table = DatabaseTable(
                name: tableName,
                columns: columns,
                recordCount: recordCount
            )
            tables.append(table)
        }
        return tables
    }

    // MARK: - Private

    /// Opens (creating when missing) the SQLite file, creating its
    /// parent directory first — Legacy's `executeSQLiteQuery` did
    /// both before `sqlite3_open`.
    private func openDatabase(filePath: String) throws -> SQLiteDatabase {
        let fileURL = URL(fileURLWithPath: filePath)
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        do {
            return try SQLiteDatabase(path: filePath, create: true)
        } catch {
            throw DatabaseError.connectionFailed(Self.message(of: error))
        }
    }

    /// The message inside a `HealthStoreError.sqlite`, without the
    /// Health-store prefix: this manager is a general SQLite
    /// driver, and its errors must not claim to be about a health
    /// store. (Same strip as `SQLiteExplorerModel.message(of:)` —
    /// that helper is private to the model, so it is repeated here.)
    private static func message(of error: Error) -> String {
        if let healthError = error as? HealthStoreError, case .sqlite(let m) = healthError {
            return m
        }
        return error.localizedDescription
    }
}
