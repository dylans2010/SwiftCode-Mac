import Foundation
import os.log
import SwiftCodeCloud
import YcodeHealthStore

@MainActor
public final class DatabaseManager {
    public static let shared = DatabaseManager()
    private let logger = Logger(subsystem: "com.SwiftCode", category: "DatabaseManager")

    private init() {}

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

    public func fetchSQLiteTables(filePath: String) throws -> [DatabaseTable] {
        let tablesQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
        let rows = try executeSQLiteQuery(filePath: filePath, sql: tablesQuery)

        var tables: [DatabaseTable] = []
        for row in rows {
            guard let tableName = row["name"] else { continue }

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

    private static func message(of error: Error) -> String {
        if let healthError = error as? HealthStoreError, case .sqlite(let m) = healthError {
            return m
        }
        return error.localizedDescription
    }
}
