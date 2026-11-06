import Foundation
import SQLite3
import os.log

@MainActor
public final class DatabaseManager {
    public static let shared = DatabaseManager()
    private let logger = Logger(subsystem: "com.SwiftCode", category: "DatabaseManager")

    private init() {}

    public func executeSQLiteQuery(filePath: String, sql: String) throws -> [[String: String]] {
        var db: OpaquePointer?

        let fileURL = URL(fileURLWithPath: filePath)
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }

        if sqlite3_open(filePath, &db) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw DatabaseError.connectionFailed(errMsg)
        }

        defer {
            sqlite3_close(db)
        }

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.queryExecutionFailed(errMsg, sql: sql)
        }

        var result: [[String: String]] = []
        let columnCount = sqlite3_column_count(statement)

        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                let columnText: String
                if let textPtr = sqlite3_column_text(statement, i) {
                    columnText = String(cString: textPtr)
                } else {
                    columnText = "NULL"
                }
                row[columnName] = columnText
            }
            result.append(row)
        }

        sqlite3_finalize(statement)
        return result
    }

    public func fetchSQLiteTables(filePath: String) throws -> [DatabaseTable] {
        let tablesQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
        let rows = try executeSQLiteQuery(filePath: filePath, sql: tablesQuery)

        var tables: [DatabaseTable] = []
        for row in rows {
            guard let tableName = row["name"] else { continue }

            // Fetch Columns info using PRAGMA table_info
            let pragmaQuery = "PRAGMA table_info(\(tableName));"
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

            // Fetch record count
            let countQuery = "SELECT COUNT(*) as count FROM \(tableName);"
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
}
