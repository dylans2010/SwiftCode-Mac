import Foundation
import SwiftCodeHealthStore

// MARK: - SQLite Explorer model
//
// Wave 17, Slice C: the `db.ExploreView` window, built whole —
// scoped to the job a database browser actually does. Legacy's
// Database Explorer is a twelve-section workspace (dashboard,
// tables & views, schema designer, SQL editor, migrations, backups,
// import/export, templates, AI assistant, performance, logs,
// settings) over its own SQLite managers; this port covers the
// browser's core, which is the whole window at this scope: open a
// SQLite file, list its tables and views, page through rows, inspect
// a table's schema, and run SQL with a results grid. Migrations,
// backups, import/export, and the AI assistant are not in this
// window — the draft records them as follow-up, not as missing
// pieces of a half-built browser.
//
// The SQLite client is NOT reimplemented here: SwiftCode already has
// one, `SQLiteDatabase` in SwiftCodeHealthStore (the Health store's
// connection). This model is a thin browser layer over it — table
// listing, schema, paging, SQL execution, and value formatting —
// and the one method it needed that the client lacked
// (`queryWithColumns`, for column names on arbitrary SQL results)
// was added to the shared client instead of forking it.

/// A SQLite Explorer failure, shown in the window's status line.
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

/// One grid of results: column names plus display strings. A
/// statement that returns no rows (INSERT, UPDATE, CREATE…) carries
/// empty columns/rows and a `message` instead ("OK — N row(s)
/// affected."). Only the first statement in the SQL runs; trailing
/// statements are ignored.
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

/// The browser's model: one open SQLite file. Main-actor isolated
/// because the underlying `SQLiteDatabase` connection is a single
/// non-Sendable handle; the window drives it, and queries run in
/// `Task.detached` only through the window's async wrappers.
@MainActor
public final class SQLiteExplorerModel {
    public let path: String
    private var db: SQLiteDatabase

    /// The shared connection, for the sections panel (same module):
    /// the panel's section models run against the same database the
    /// browser is showing, on the same main-actor connection.
    var database: SQLiteDatabase { db }

    /// Reopens the database file (the old connection closes when
    /// it is replaced). The sections panel calls this after a
    /// restore, which replaces the file under the live connection.
    func reopen() throws {
        db = try SQLiteDatabase(path: path)
    }

    private init(db: SQLiteDatabase) {
        self.db = db
        self.path = db.path
    }

    /// Opens an existing SQLite file (never creates one — a missing
    /// path is an honest `.openFailed`, not a new empty database).
    public convenience init(path: String) throws {
        do {
            try self.init(db: SQLiteDatabase(path: path))
        } catch {
            throw SQLiteExplorerError.openFailed(Self.message(of: error))
        }
    }

    /// An empty in-memory database. Tests use it; the window never
    /// offers it (a browser with nothing to browse is not a window).
    public static func inMemory() throws -> SQLiteExplorerModel {
        do {
            return try SQLiteExplorerModel(db: SQLiteDatabase(path: ":memory:", create: true))
        } catch {
            throw SQLiteExplorerError.openFailed(Self.message(of: error))
        }
    }

    // MARK: - Schema

    /// Tables and views, by name, excluding SQLite's own internals
    /// (`sqlite_*`). Internal tables are hidden deliberately: they
    /// are not user data, and editing them can corrupt the file.
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

    /// A table's columns, in declared order (`PRAGMA table_info`).
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

    /// Row count of a table or view.
    public func rowCount(of table: String) throws -> Int {
        do {
            let rows = try db.query("SELECT COUNT(*) FROM \(Self.quoted(table))")
            return rows.first?.first?.int ?? 0
        } catch {
            throw SQLiteExplorerError.queryFailed(Self.message(of: error))
        }
    }

    // MARK: - Rows and SQL

    /// One page of a table's rows, in rowid order (the table's
    /// natural order). Column names come from the schema, which
    /// matches `SELECT *` column-for-column.
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

    /// Runs the user's SQL. A result set comes back as a grid; a
    /// statement with no result set reports the affected row count.
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

    // MARK: - Formatting

    /// One cell's display string. Blobs show their size, never raw
    /// bytes; NULL is explicit, never blank — a blank cell must mean
    /// an empty string, not a missing value.
    public static func display(_ value: SQLiteDatabase.Value) -> String {
        switch value {
        case .null: return "NULL"
        case .int(let v): return String(v)
        case .real(let v): return String(v)
        case .text(let v): return v
        case .blob(let bytes): return "<\(bytes.count) bytes>"
        }
    }

    /// Quotes an identifier (`"name"`, doubling embedded quotes).
    /// Table names come from the file itself, never from typed SQL,
    /// so quoting is defence in depth, not the only defence.
    public static func quoted(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The message inside a `HealthStoreError.sqlite` (or any other
    /// error's description), without the Health-store prefix: this
    /// model is a general SQLite browser, and its errors must not
    /// claim to be about a health store.
    private static func message(of error: Error) -> String {
        if let healthError = error as? HealthStoreError, case .sqlite(let m) = healthError {
            return m
        }
        return error.localizedDescription
    }
}
