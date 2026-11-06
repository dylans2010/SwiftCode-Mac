import Foundation
import YcodeHealthStore

/// Shared SQL text helpers for the SQLite Explorer's section models
/// (`ycode/Sources/YcodeIDECore/Model/Database/`). The browser model
/// in YcodeUI has its own `quoted`; this one lives in IDECore so the
/// section models do not depend on the UI target.

enum DatabaseSQL {
    /// Quotes an identifier (`"name"`, doubling embedded quotes).
    static func quoted(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A value as a SQL literal (single quotes doubled; blobs as
    /// `X'...'` hex). Only used for generated SQL dumps — real
    /// inserts go through bound parameters.
    static func literal(_ value: SQLiteDatabase.Value) -> String {
        switch value {
        case .null: return "NULL"
        case .int(let v): return String(v)
        case .real(let v): return String(v)
        case .text(let v): return "'" + v.replacingOccurrences(of: "'", with: "''") + "'"
        case .blob(let bytes): return "X'" + bytes.map { String(format: "%02x", $0) }.joined() + "'"
        }
    }

    /// Maps a provider-generic declared type (Legacy's templates use
    /// `UUID`, `VARCHAR(255)`, `TIMESTAMP`) to the SQLite type the
    /// explorer actually creates. SQLite types pass through
    /// unchanged; unknown types fall back to `TEXT` rather than
    /// failing the whole template.
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
