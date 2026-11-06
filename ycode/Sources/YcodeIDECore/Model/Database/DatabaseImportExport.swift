import Foundation
import YcodeHealthStore

/// Import / export — Legacy's `Core/DatabaseExportManager.swift` +
/// `Core/DatabaseImportManager.swift`, ported to the explorer's
/// `SQLiteDatabase`.
///
/// Deviation, recorded and an improvement: Legacy's CSV import
/// split rows on `components(separatedBy: ",")`, which breaks on
/// any quoted field containing a comma. The port parses real CSV
/// (quoted fields, `""` escapes, embedded newlines, CRLF) and
/// infers column types from the values. Empty cells import as
/// NULL. Export covers CSV, JSON and a SQL dump (schema + INSERTs);
/// blobs export as base64 in JSON and `X'...'` hex in SQL.

public enum DatabaseCSVError: Error, Equatable, Sendable {
    case unterminatedQuote
    case emptyInput
}

extension DatabaseCSVError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unterminatedQuote: return "CSV input has an unterminated quoted field."
        case .emptyInput: return "CSV input is empty."
        }
    }
}

/// A real CSV parser: quoted fields, `""` escapes, embedded
/// newlines, CRLF/LF/CR line endings.
public enum DatabaseCSVParser {
    public static func parse(_ input: String) throws -> [[String]] {
        guard !input.isEmpty else { throw DatabaseCSVError.emptyInput }
        var rows: [[String]] = []
        var currentRow: [String] = []
        var current = ""
        var inQuotes = false
        var fieldStarted = false
        let chars = Array(input)
        var i = 0
        func endField() {
            currentRow.append(current)
            current = ""
            fieldStarted = false
        }
        func endRow() {
            endField()
            rows.append(currentRow)
            currentRow = []
        }
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        current.append("\"")
                        i += 2
                    } else {
                        inQuotes = false
                        i += 1
                    }
                } else {
                    current.append(c)
                    i += 1
                }
            } else if c == "\"" && !fieldStarted && current.isEmpty {
                inQuotes = true
                fieldStarted = true
                i += 1
            } else if c == "," {
                endField()
                i += 1
            } else if c == "\r" || c == "\n" {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                endRow()
                i += 1
            } else {
                current.append(c)
                fieldStarted = true
                i += 1
            }
        }
        if inQuotes { throw DatabaseCSVError.unterminatedQuote }
        if !current.isEmpty || !currentRow.isEmpty || fieldStarted {
            endRow()
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    /// Escapes one field for CSV output.
    public static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

@MainActor
public final class DatabaseExportManager {
    private let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    private func tableRows(_ table: String) throws -> (columns: [String], rows: [[SQLiteDatabase.Value]]) {
        try db.queryWithColumns("SELECT * FROM \(DatabaseSQL.quoted(table))")
    }

    private static func jsonValue(_ value: SQLiteDatabase.Value) -> Any {
        switch value {
        case .null: return NSNull()
        case .int(let v): return v
        case .real(let v): return v
        case .text(let v): return v
        case .blob(let bytes): return Data(bytes).base64EncodedString()
        }
    }

    public func exportCSV(table: String) throws -> String {
        let (columns, rows) = try tableRows(table)
        var lines = [columns.map(DatabaseCSVParser.escape).joined(separator: ",")]
        for row in rows {
            lines.append(row.map { value in
                switch value {
                case .null: return ""
                case .int(let v): return String(v)
                case .real(let v): return String(v)
                case .text(let v): return DatabaseCSVParser.escape(v)
                case .blob(let bytes): return DatabaseCSVParser.escape(Data(bytes).base64EncodedString())
                }
            }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// One JSON object per row; blobs are base64 strings.
    public func exportJSON(table: String) throws -> String {
        let (columns, rows) = try tableRows(table)
        let objects: [[String: Any]] = rows.map { row in
            var object: [String: Any] = [:]
            for (index, column) in columns.enumerated() where index < row.count {
                object[column] = Self.jsonValue(row[index])
            }
            return object
        }
        let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// The `CREATE` statements for every table, view, index and
    /// trigger, straight from `sqlite_master`.
    public func exportSchema() throws -> String {
        let rows = try db.query("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name")
        return rows.compactMap { $0.first?.text }.map { $0.hasSuffix(";") ? $0 : $0 + ";" }.joined(separator: "\n")
    }

    /// `INSERT` statements rebuilding one table's rows.
    public func exportSQL(table: String) throws -> String {
        let (columns, rows) = try tableRows(table)
        let columnList = columns.map(DatabaseSQL.quoted).joined(separator: ", ")
        return rows.map { row in
            let values = row.map(DatabaseSQL.literal).joined(separator: ", ")
            return "INSERT INTO \(DatabaseSQL.quoted(table)) (\(columnList)) VALUES (\(values));"
        }.joined(separator: "\n")
    }
}

@MainActor
public final class DatabaseImportManager {
    private let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    private static func sanitizedColumn(_ raw: String, index: Int, used: inout Set<String>) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "column\(index + 1)" }
        name = String(name.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
        if name.first?.isNumber == true { name = "_" + name }
        var candidate = name
        var suffix = 2
        while used.contains(candidate) {
            candidate = "\(name)_\(suffix)"
            suffix += 1
        }
        used.insert(candidate)
        return candidate
    }

    private static func inferredType(for values: [String]) -> String {
        let nonEmpty = values.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return "TEXT" }
        if nonEmpty.allSatisfy({ Int64($0) != nil }) { return "INTEGER" }
        if nonEmpty.allSatisfy({ Double($0) != nil }) { return "REAL" }
        return "TEXT"
    }

    private static func value(for cell: String, type: String) -> SQLiteDatabase.Value {
        guard !cell.isEmpty else { return .null }
        switch type {
        case "INTEGER": return Int64(cell).map(SQLiteDatabase.Value.int) ?? .text(cell)
        case "REAL": return Double(cell).map(SQLiteDatabase.Value.real) ?? .text(cell)
        default: return .text(cell)
        }
    }

    /// Imports CSV into a table, creating it (with types inferred
    /// from the values) when `createTable` is set. The first row is
    /// the header. Returns the number of rows imported. Empty cells
    /// import as NULL.
    @discardableResult
    public func importCSV(_ csv: String, into table: String, createTable: Bool = true) throws -> Int {
        let rows = try DatabaseCSVParser.parse(csv)
        guard let header = rows.first, !header.isEmpty else { throw DatabaseCSVError.emptyInput }
        var used: Set<String> = []
        let columns = header.enumerated().map { Self.sanitizedColumn($0.element, index: $0.offset, used: &used) }
        let dataRows = Array(rows.dropFirst())
        let types = columns.enumerated().map { index, _ in
            Self.inferredType(for: dataRows.map { index < $0.count ? $0[index] : "" })
        }
        return try db.transaction {
            if createTable {
                let definitions = zip(columns, types).map { "\(DatabaseSQL.quoted($0)) \($1)" }.joined(separator: ", ")
                try db.execute("CREATE TABLE IF NOT EXISTS \(DatabaseSQL.quoted(table)) (\(definitions))")
            }
            let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
            let columnList = columns.map(DatabaseSQL.quoted).joined(separator: ", ")
            var imported = 0
            for row in dataRows {
                let values = columns.enumerated().map { index, _ in
                    Self.value(for: index < row.count ? row[index] : "", type: types[index])
                }
                _ = try db.query("INSERT INTO \(DatabaseSQL.quoted(table)) (\(columnList)) VALUES (\(placeholders))", values)
                imported += 1
            }
            return imported
        }
    }

    /// Imports a JSON array of objects into a table, creating it
    /// when `createTable` is set. Columns are the union of the
    /// objects' keys, in first-seen order. Returns the number of
    /// rows imported.
    @discardableResult
    public func importJSON(_ json: String, into table: String, createTable: Bool = true) throws -> Int {
        guard let data = json.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DatabaseCSVError.emptyInput
        }
        var columns: [String] = []
        var seen: Set<String> = []
        for object in array {
            for key in object.keys where seen.insert(key).inserted {
                columns.append(key)
            }
        }
        guard !columns.isEmpty else { throw DatabaseCSVError.emptyInput }
        let types: [String] = columns.map { column in
            let values = array.compactMap { $0[column] }
            if values.allSatisfy({ $0 is String }) { return "TEXT" }
            if values.allSatisfy({ $0 is NSNumber }) {
                let numbers = values.compactMap { $0 as? NSNumber }
                if numbers.allSatisfy({ $0.doubleValue.truncatingRemainder(dividingBy: 1) == 0 }) { return "INTEGER" }
                return "REAL"
            }
            return "TEXT"
        }
        func value(for raw: Any?, type: String) -> SQLiteDatabase.Value {
            guard let raw else { return .null }
            if raw is NSNull { return .null }
            if let number = raw as? NSNumber, type != "TEXT" {
                return type == "INTEGER" ? .int(number.int64Value) : .real(number.doubleValue)
            }
            if let string = raw as? String { return .text(string) }
            return .text(String(describing: raw))
        }
        return try db.transaction {
            if createTable {
                let definitions = zip(columns, types).map { "\(DatabaseSQL.quoted($0)) \($1)" }.joined(separator: ", ")
                try db.execute("CREATE TABLE IF NOT EXISTS \(DatabaseSQL.quoted(table)) (\(definitions))")
            }
            let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
            let columnList = columns.map(DatabaseSQL.quoted).joined(separator: ", ")
            var imported = 0
            for object in array {
                let values = columns.enumerated().map { index, column in
                    value(for: object[column], type: types[index])
                }
                _ = try db.query("INSERT INTO \(DatabaseSQL.quoted(table)) (\(columnList)) VALUES (\(placeholders))", values)
                imported += 1
            }
            return imported
        }
    }
}
