import Foundation
import YcodeHealthStore

enum DatabaseSQL {
    static func quoted(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func literal(_ value: SQLiteDatabase.Value) -> String {
        switch value {
        case .null: return "NULL"
        case .int(let v): return String(v)
        case .real(let v): return String(v)
        case .text(let v): return "'" + v.replacingOccurrences(of: "'", with: "''") + "'"
        case .blob(let bytes): return "X'" + bytes.map { String(format: "%02x", $0) }.joined() + "'"
        }
    }

    static func sqliteType(_ declared: String) -> String {
        let upper = declared.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper == "UUID" || upper.hasPrefix("VARCHAR") || upper.hasPrefix("CHAR")
            || upper == "TIMESTAMP" || upper == "DATETIME" || upper == "DATE" || upper == "TIME" {
            return "TEXT"
        }
        if upper == "BOOLEAN" || upper == "BOOL" { return "INTEGER" }
        if upper == "INTEGER" || upper == "INT" || upper == "BIGINT" || upper == "SMALLINT" { return "INTEGER" }
        if upper == "REAL" || upper == "DOUBLE" || upper == "FLOAT" || upper == "NUMERIC" || upper == "DECIMAL" { return "REAL" }
        if upper == "TEXT" || upper == "BLOB" { return upper }
        return "TEXT"
    }
}
