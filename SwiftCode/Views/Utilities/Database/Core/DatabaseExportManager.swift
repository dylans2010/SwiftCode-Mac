import Foundation

public final class DatabaseExportManager: Sendable {
    public static let shared = DatabaseExportManager()

    private init() {}

    public func exportToCSV(rows: [[String: String]], columns: [String]) -> String {
        var csvString = columns.joined(separator: ",") + "\n"
        for row in rows {
            let line = columns.map { col in
                let val = row[col] ?? ""
                // Escape quotes and commas
                if val.contains(",") || val.contains("\"") || val.contains("\n") {
                    let clean = val.replacingOccurrences(of: "\"", with: "\"\"")
                    return "\"\(clean)\""
                }
                return val
            }
            csvString += line.joined(separator: ",") + "\n"
        }
        return csvString
    }

    public func exportToJSON(rows: [[String: String]]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public func exportSQLSchema(tables: [DatabaseTable], provider: DatabaseProvider) -> String {
        var schemaSql = ""
        for table in tables {
            schemaSql += DatabaseUtilities.defaultSQLForCreateTable(table: table, provider: provider) + "\n\n"
        }
        return schemaSql
    }
}
