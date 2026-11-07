import Foundation
import SwiftCodeCloud

@MainActor
enum DatabaseViewSQLite {

    static func explorer(for connection: DatabaseConnection) throws -> SQLiteExplorerModel {
        guard let path = connection.sqliteFilePath, !path.isEmpty else {
            throw SQLiteExplorerError.openFailed("No SQLite file path on this connection.")
        }
        return try SQLiteExplorerModel(path: path)
    }

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

    static func sqlLiteral(_ value: String?) -> String {
        guard let value, value != "NULL" else { return "NULL" }
        return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
