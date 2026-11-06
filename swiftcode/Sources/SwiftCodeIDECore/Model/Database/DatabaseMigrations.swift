import Foundation
import SwiftCodeHealthStore

/// Migrations — Legacy's `Core/DatabaseMigrationManager.swift` +
/// `Models/DatabaseMigration.swift`, ported to the explorer's
/// `SQLiteDatabase`.
///
/// Deviation, recorded: Legacy tracked applied migrations in
/// `UserDefaults` (`com.swiftcode.database.migrations`). A registry
/// in UserDefaults drifts the moment the database file is copied,
/// renamed or opened on another machine, so the port tracks them in
/// the database itself, in a `_swiftcode_migrations` table — the
/// standard practice, and the table is a normal user-visible table
/// the browser can inspect. `generate` / `apply` / `rollback` keep
/// Legacy's shape: a migration is a versioned up/down SQL pair.

public struct DatabaseMigration: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { version }
    public var version: Int
    public var name: String
    public var up: String
    public var down: String?

    public init(version: Int, name: String, up: String, down: String? = nil) {
        self.version = version
        self.name = name
        self.up = up
        self.down = down
    }
}

public struct DatabaseAppliedMigration: Sendable, Equatable {
    public var version: Int
    public var name: String
    public var appliedAt: Date
    /// The down SQL recorded when the migration was applied, so a
    /// rollback never needs the original migration set.
    public var downSQL: String?

    public init(version: Int, name: String, appliedAt: Date, downSQL: String? = nil) {
        self.version = version
        self.name = name
        self.appliedAt = appliedAt
        self.downSQL = downSQL
    }
}

public enum DatabaseMigrationError: Error, Equatable, Sendable {
    case alreadyApplied(Int)
    case notApplied(Int)
    case noDownMigration(Int)
}

extension DatabaseMigrationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyApplied(let v): return "Migration \(v) is already applied."
        case .notApplied(let v): return "Migration \(v) has not been applied."
        case .noDownMigration(let v): return "Migration \(v) has no down SQL to roll back with."
        }
    }
}

@MainActor
public final class DatabaseMigrationManager {
    public static let trackingTable = "_swiftcode_migrations"
    private let db: SQLiteDatabase
    private let isoFormatter = ISO8601DateFormatter()

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    /// Creates the tracking table if it does not exist yet. The
    /// `down_sql` column records each migration's down SQL at apply
    /// time, so `rollbackLatest` works from the database alone.
    public func ensureTrackingTable() throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS \(DatabaseSQL.quoted(Self.trackingTable)) (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL,
                down_sql TEXT
            )
            """)
        // Databases tracked before `down_sql` existed gain the column.
        let columns = try db.query("PRAGMA table_info(\(DatabaseSQL.quoted(Self.trackingTable)))")
        if !columns.contains(where: { $0.count > 1 && $0[1].text == "down_sql" }) {
            try db.execute("ALTER TABLE \(DatabaseSQL.quoted(Self.trackingTable)) ADD COLUMN down_sql TEXT")
        }
    }

    /// A new migration versioned one past the highest applied (or
    /// highest known) version — Legacy's `generate`.
    public func generate(name: String, up: String, down: String? = nil, known: [DatabaseMigration] = []) throws -> DatabaseMigration {
        try ensureTrackingTable()
        let appliedVersions = try applied().map(\.version)
        let next = max(appliedVersions.max() ?? 0, known.map(\.version).max() ?? 0) + 1
        return DatabaseMigration(version: next, name: name, up: up, down: down)
    }

    public func applied() throws -> [DatabaseAppliedMigration] {
        try ensureTrackingTable()
        let rows = try db.query("SELECT version, name, applied_at, down_sql FROM \(DatabaseSQL.quoted(Self.trackingTable)) ORDER BY version")
        return rows.compactMap { row in
            guard row.count == 4, let version = row[0].int, let name = row[1].text,
                  let appliedAtText = row[2].text, let appliedAt = isoFormatter.date(from: appliedAtText) else { return nil }
            return DatabaseAppliedMigration(version: version, name: name, appliedAt: appliedAt, downSQL: row[3].text)
        }
    }

    public func isApplied(_ migration: DatabaseMigration) throws -> Bool {
        try applied().contains { $0.version == migration.version }
    }

    /// Migrations in the given set that have not been applied yet.
    public func pending(_ migrations: [DatabaseMigration]) throws -> [DatabaseMigration] {
        let appliedVersions = Set(try applied().map(\.version))
        return migrations.filter { !appliedVersions.contains($0.version) }.sorted { $0.version < $1.version }
    }

    /// Runs the up SQL in a transaction and records the migration.
    /// Throws `.alreadyApplied` instead of running twice.
    public func apply(_ migration: DatabaseMigration) throws {
        try ensureTrackingTable()
        guard try !isApplied(migration) else { throw DatabaseMigrationError.alreadyApplied(migration.version) }
        try db.transaction {
            try db.execute(migration.up)
            _ = try db.query(
                "INSERT INTO \(DatabaseSQL.quoted(Self.trackingTable)) (version, name, applied_at, down_sql) VALUES (?, ?, ?, ?)",
                [.int(Int64(migration.version)), .text(migration.name), .text(isoFormatter.string(from: Date())), migration.down.map(SQLiteDatabase.Value.text) ?? .null]
            )
        }
    }

    /// Runs the down SQL in a transaction and removes the record.
    /// Throws `.notApplied` or `.noDownMigration`.
    public func rollback(_ migration: DatabaseMigration) throws {
        try ensureTrackingTable()
        guard try isApplied(migration) else { throw DatabaseMigrationError.notApplied(migration.version) }
        guard let down = migration.down else { throw DatabaseMigrationError.noDownMigration(migration.version) }
        try db.transaction {
            try db.execute(down)
            _ = try db.query(
                "DELETE FROM \(DatabaseSQL.quoted(Self.trackingTable)) WHERE version = ?",
                [.int(Int64(migration.version))]
            )
        }
    }

    /// Rolls back the most recently applied migration, using the
    /// down SQL recorded at apply time. Returns the rolled-back
    /// migration, or nil when nothing has been applied. Throws
    /// `.noDownMigration` when the latest migration recorded no
    /// down SQL.
    @discardableResult
    public func rollbackLatest() throws -> DatabaseAppliedMigration? {
        guard let latest = try applied().last else { return nil }
        guard let down = latest.downSQL else { throw DatabaseMigrationError.noDownMigration(latest.version) }
        try rollback(DatabaseMigration(version: latest.version, name: latest.name, up: "", down: down))
        return latest
    }
}
