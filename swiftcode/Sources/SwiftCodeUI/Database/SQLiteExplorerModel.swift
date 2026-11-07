import Foundation
import SwiftCodeHealthStore

public enum SQLiteExplorerError: Error, Equatable, Sendable {
    case openFailed(String)
    case queryFailed(String)
}

extension SQLiteExplorerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "Could not open the database: \(message)"
        case .queryFailed(let message): return message
        }
    }
}

public struct SQLiteExplorerTable: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case table, view }
    public let name: String
    public let kind: Kind
    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }
}

public struct SQLiteExplorerColumn: Equatable, Sendable {
    public let name: String
    public let type: String
    public let notNull: Bool
    public let primaryKey: Bool
    public init(name: String, type: String, notNull: Bool, primaryKey: Bool) {
        self.name = name
        self.type = type
        self.notNull = notNull
        self.primaryKey = primaryKey
    }
}

public struct SQLiteExplorerResult: Equatable, Sendable {
    public let columns: [String]
    public let rows: [[String]]
    public let message: String?
    public init(columns: [String], rows: [[String]], message: String? = nil) {
        self.columns = columns
        self.rows = rows
        self.message = message
    }
}

@MainActor
public final class SQLiteExplorerModel {
    public let path: String
    private var db: SQLiteDatabase

    var database: SQLiteDatabase { db }

    func reopen() throws {
        db = try SQLiteDatabase(path: path)
    }

    private init(db: SQLiteDatabase) {
        self.db = db
        self.path = db.path
    }

    public convenience init(path: String) throws {
        do {
            try self.init(db: SQLiteDatabase(path: path))
        } catch {
            throw SQLiteExplorerError.openFailed(Self.message(of: error))
        }
    }

    public static func inMemory() throws -> SQLiteExplorerModel {
        do {
            return try SQLiteExplorerModel(db: SQLiteDatabase(path: ":memory:", create: true))
        } catch {
            throw SQLiteExplorerError.openFailed(Self.message(of: error))
        }
    }

    public func tables() throws -> [SQLiteExplorerTable] {
        do {
            let rows = try db.query(
                "SELECT type, name FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
            return rows.compactMap { row in
                guard row.count >= 2,
                      let kindText = row[0].text,
                      let name = row[1].text,
                      let kind = SQLiteExplorerTable.Kind(rawValue: kindText) else { return nil }
                return SQLiteExplorerTable(name: name, kind: kind)
            }
        } catch {
            throw SQLiteExplorerError.queryFailed(Self.message(of: error))
        }
    }

    public func columns(of table: String) throws -> [SQLiteExplorerColumn] {
        do {
            let rows = try db.query("PRAGMA table_info(\(Self.quoted(table)))")
            return rows.compactMap { row in
                guard row.count >= 6,
                      let name = row[1].text,
                      let type = row[2].text,
                      let notNull = row[3].int,
                      let pk = row[5].int else { return nil }
                return SQLiteExplorerColumn(name: name, type: type, notNull: notNull != 0, primaryKey: pk != 0)
            }
        } catch {
            throw SQLiteExplorerError.queryFailed(Self.message(of: error))
        }
    }

    public func rowCount(of table: String) throws -> Int {
        do {
            let rows = try db.query("SELECT COUNT(*) FROM \(Self.quoted(table))")
            return rows.first?.first?.int ?? 0
        } catch {
            throw SQLiteExplorerError.queryFailed(Self.message(of: error))
        }
    }

    public func rows(of table: String, limit: Int, offset: Int) throws -> SQLiteExplorerResult {
        do {
            let columns = try columns(of: table).map(\.name)
            let raw = try db.query(
                "SELECT * FROM \(Self.quoted(table)) LIMIT ? OFFSET ?",
                [.int(Int64(limit)), .int(Int64(offset))]
            )
            return SQLiteExplorerResult(columns: columns, rows: raw.map { $0.map(Self.display) })
        } catch let error as SQLiteExplorerError {
            throw error
        } catch {
            throw SQLiteExplorerError.queryFailed(Self.message(of: error))
        }
    }

    public func run(sql: String) throws -> SQLiteExplorerResult {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SQLiteExplorerError.queryFailed("Enter a SQL statement to run.")
        }
        do {
            let (columns, raw) = try db.queryWithColumns(trimmed)
            if columns.isEmpty {
                return SQLiteExplorerResult(
                    columns: [], rows: [],
                    message: "OK — \(db.changes) row(s) affected."
                )
            }
            return SQLiteExplorerResult(
                columns: columns, rows: raw.map { $0.map(Self.display) },
                message: "\(raw.count) row(s)."
            )
        } catch {
            throw SQLiteExplorerError.queryFailed(Self.message(of: error))
        }
    }

    public static func display(_ value: SQLiteDatabase.Value) -> String {
        switch value {
        case .null: return "NULL"
        case .int(let v): return String(v)
        case .real(let v): return String(v)
        case .text(let v): return v
        case .blob(let bytes): return "<\(bytes.count) bytes>"
        }
    }

    public static func quoted(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func message(of error: Error) -> String {
        if let healthError = error as? HealthStoreError, case .sqlite(let m) = healthError {
            return m
        }
        return error.localizedDescription
    }
}
