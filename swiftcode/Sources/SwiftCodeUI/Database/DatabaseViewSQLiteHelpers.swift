import Foundation
import SwiftCodeCloud

/// Internal bridge between Legacy's Database views and the
/// destination's real SQLite backend (`SQLiteExplorerModel`).
///
/// Legacy's views drove `DatabaseManager.shared`, which returned
/// rows as `[String: String]` dictionaries and tables as
/// `DatabaseTable` values. The destination keeps that manager (its
/// port is staged alongside these views, built on the same
/// `SQLiteDatabase` client), but these views drive SQLite through
/// `SQLiteExplorerModel` directly, as specified for this family:
/// one open model per connection, `run(sql:)` for execution, and
/// `tables()` / `columns(of:)` / `rowCount(of:)` for schema. This
/// enum is only the shape conversion — dictionary rows from
/// `SQLiteExplorerResult`, `DatabaseTable` values with their
/// declared defaults and row counts — plus the small quoting/
/// literal helpers the views share. Nothing here invents data:
/// every value comes back from the file on disk.
///
/// All entry points are `@MainActor`: `SQLiteExplorerModel` is a
/// main-actor class over a single non-Sendable connection.
@MainActor
enum DatabaseViewSQLite {

    /// Opens the active connection's SQLite file. The file must
    /// already exist — a missing path is an honest open failure,
    /// never a new empty database (that is
    /// `explorerCreatingFileIfNeeded(for:)`'s job, used only by
    /// the connection test, which is allowed to create a file).
    static func explorer(for connection: DatabaseConnection) throws -> SQLiteExplorerModel {
        guard let path = connection.sqliteFilePath, !path.isEmpty else {
            throw SQLiteExplorerError.openFailed("No SQLite file path on this connection.")
        }
        return try SQLiteExplorerModel(path: path)
    }

    /// Opens the connection's SQLite file, creating an empty file
    /// (and its parent directory) when it does not exist yet. A
    /// zero-length file is a valid empty SQLite database, so the
    /// open that follows succeeds; the caller reports the creation
    /// honestly instead of pretending the file was already there.
    static func explorerCreatingFileIfNeeded(for connection: DatabaseConnection) throws -> SQLiteExplorerModel {
        guard let path = connection.sqliteFilePath, !path.isEmpty else {
            throw SQLiteExplorerError.openFailed("No SQLite file path on this connection.")
        }
        if !FileManager.default.fileExists(atPath: path) {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = FileManager.default.createFile(atPath: path, contents: nil)
        }
        return try SQLiteExplorerModel(path: path)
    }

    /// Every user table and view in the open database, each with
    /// its declared columns (in order, with defaults, exactly as
    /// Legacy's `fetchSQLiteTables` returned them) and its row
    /// count. `SQLiteExplorerModel.columns(of:)` does not carry
    /// `dflt_value`, so columns come from `PRAGMA table_info`
    /// via `run(sql:)`; when that fails the plain column list is
    /// the fallback, never invented defaults.
    static func fetchTables(_ explorer: SQLiteExplorerModel) throws -> [DatabaseTable] {
        try explorer.tables().map { entry in
            var columns: [DatabaseColumn] = []
            if let pragma = try? explorer.run(
                sql: "PRAGMA table_info(\(SQLiteExplorerModel.quoted(entry.name)))"
            ) {
                columns = pragma.rows.compactMap { cells in
                    var dict: [String: String] = [:]
                    for (index, name) in pragma.columns.enumerated() where index < cells.count {
                        dict[name] = cells[index]
                    }
                    guard let name = dict["name"], let type = dict["type"] else { return nil }
                    let defaultValue = dict["dflt_value"] == "NULL" ? nil : dict["dflt_value"]
                    return DatabaseColumn(
                        name: name,
                        type: type,
                        isPrimaryKey: dict["pk"] == "1",
                        isNullable: dict["notnull"] == "0",
                        defaultValue: defaultValue
                    )
                }
            }
            if columns.isEmpty {
                columns = (try? explorer.columns(of: entry.name))?.map { column in
                    DatabaseColumn(
                        name: column.name,
                        type: column.type,
                        isPrimaryKey: column.primaryKey,
                        isNullable: !column.notNull
                    )
                } ?? []
            }
            let recordCount = (try? explorer.rowCount(of: entry.name)) ?? 0
            return DatabaseTable(
                name: entry.name,
                columns: columns,
                isView: entry.kind == .view,
                recordCount: recordCount
            )
        }
    }

    /// Runs one SQL statement and returns its rows as dictionaries
    /// keyed by column name (Legacy's `executeSQLiteQuery` shape).
    /// A statement with no result set returns an empty array.
    static func runDictionaries(_ explorer: SQLiteExplorerModel, sql: String) throws -> [[String: String]] {
        let result = try explorer.run(sql: sql)
        return result.rows.map { row in
            var dict: [String: String] = [:]
            for (index, column) in result.columns.enumerated() where index < row.count {
                dict[column] = row[index]
            }
            return dict
        }
    }

    /// A SQL literal for a cell value as displayed by
    /// `SQLiteExplorerModel.display`: `nil` and the display string
    /// `"NULL"` both become SQL `NULL`; anything else is a quoted
    /// string with embedded quotes doubled.
    static func sqlLiteral(_ value: String?) -> String {
        guard let value, value != "NULL" else { return "NULL" }
        return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
