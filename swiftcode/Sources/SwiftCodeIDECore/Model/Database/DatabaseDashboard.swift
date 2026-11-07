import Foundation
import SwiftCodeHealthStore

public struct DatabaseHealthCheck: Sendable, Equatable {
    public var name: String
    public var passed: Bool
    public var detail: String

    public init(name: String, passed: Bool, detail: String) {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

public struct DatabaseDashboardStats: Sendable, Equatable {
    public var databaseSizeBytes: Int64
    public var pageCount: Int
    public var pageSize: Int
    public var tableCount: Int
    public var indexCount: Int
    public var totalRows: Int
    public var integrity: String
    public var largestTables: [DatabaseTableStats]
    public var healthChecks: [DatabaseHealthCheck]
    public var migrationCount: Int
    public var backupCount: Int

    public init(databaseSizeBytes: Int64, pageCount: Int, pageSize: Int, tableCount: Int,
                indexCount: Int, totalRows: Int, integrity: String, largestTables: [DatabaseTableStats],
                healthChecks: [DatabaseHealthCheck], migrationCount: Int, backupCount: Int) {
        self.databaseSizeBytes = databaseSizeBytes
        self.pageCount = pageCount
        self.pageSize = pageSize
        self.tableCount = tableCount
        self.indexCount = indexCount
        self.totalRows = totalRows
        self.integrity = integrity
        self.largestTables = largestTables
        self.healthChecks = healthChecks
        self.migrationCount = migrationCount
        self.backupCount = backupCount
    }
}

@MainActor
public final class DatabaseDashboard {
    private let db: SQLiteDatabase
    private let performance: DatabasePerformanceAnalyzer

    public init(db: SQLiteDatabase) {
        self.db = db
        self.performance = DatabasePerformanceAnalyzer(db: db)
    }

    public func stats(backupManager: DatabaseBackupManager? = nil) throws -> DatabaseDashboardStats {
        let report = try performance.report()
        let largest = report.tables.sorted { $0.rowCount > $1.rowCount }.prefix(5)
        var checks: [DatabaseHealthCheck] = []
        checks.append(DatabaseHealthCheck(
            name: "Integrity", passed: report.integrity == "ok",
            detail: report.integrity == "ok" ? "integrity_check passed." : report.integrity
        ))
        var tablesWithoutPK: [String] = []
        for table in try performance.userTables() {
            let columns = try db.query("PRAGMA table_info(\(DatabaseSQL.quoted(table)))")
            if !columns.contains(where: { $0.count > 5 && ($0[5].int ?? 0) > 0 }) {
                tablesWithoutPK.append(table)
            }
        }
        checks.append(DatabaseHealthCheck(
            name: "Primary keys", passed: tablesWithoutPK.isEmpty,
            detail: tablesWithoutPK.isEmpty
                ? "Every table has a primary key."
                : "No primary key: \(tablesWithoutPK.joined(separator: ", "))."
        ))
        let unindexed = try performance.unindexedForeignKeys()
        checks.append(DatabaseHealthCheck(
            name: "Foreign-key indexes", passed: unindexed.isEmpty,
            detail: unindexed.isEmpty
                ? "Every foreign-key column is indexed."
                : "Unindexed: \(unindexed.map { "\($0.table).\($0.column)" }.joined(separator: ", "))."
        ))
        var migrationCount = 0
        let trackingExists = try db.query(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
            [.text(DatabaseMigrationManager.trackingTable)]
        ).first?.first?.int ?? 0
        if trackingExists > 0 {
            migrationCount = try db.query("SELECT COUNT(*) FROM \(DatabaseSQL.quoted(DatabaseMigrationManager.trackingTable))").first?.first?.int ?? 0
        }
        return DatabaseDashboardStats(
            databaseSizeBytes: report.databaseSizeBytes,
            pageCount: report.pageCount,
            pageSize: report.pageSize,
            tableCount: report.tables.count,
            indexCount: report.tables.reduce(0) { $0 + $1.indexCount },
            totalRows: report.totalRows,
            integrity: report.integrity,
            largestTables: Array(largest),
            healthChecks: checks,
            migrationCount: migrationCount,
            backupCount: backupManager?.listBackups().count ?? 0
        )
    }
}
