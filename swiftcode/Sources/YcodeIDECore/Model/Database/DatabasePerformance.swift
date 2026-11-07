import Foundation
import YcodeHealthStore

public struct DatabaseTableStats: Sendable, Equatable {
    public var name: String
    public var rowCount: Int
    public var indexCount: Int

    public init(name: String, rowCount: Int, indexCount: Int) {
        self.name = name
        self.rowCount = rowCount
        self.indexCount = indexCount
    }
}

public struct DatabasePerformanceReport: Sendable, Equatable {
    public var pageCount: Int
    public var pageSize: Int
    public var freelistCount: Int
    public var journalMode: String
    public var cacheSizeKiB: Int
    public var databaseSizeBytes: Int64
    public var integrity: String
    public var tables: [DatabaseTableStats]
    public var totalRows: Int

    public init(pageCount: Int, pageSize: Int, freelistCount: Int, journalMode: String,
                cacheSizeKiB: Int, databaseSizeBytes: Int64, integrity: String,
                tables: [DatabaseTableStats], totalRows: Int) {
        self.pageCount = pageCount
        self.pageSize = pageSize
        self.freelistCount = freelistCount
        self.journalMode = journalMode
        self.cacheSizeKiB = cacheSizeKiB
        self.databaseSizeBytes = databaseSizeBytes
        self.integrity = integrity
        self.tables = tables
        self.totalRows = totalRows
    }
}

@MainActor
public final class DatabasePerformanceAnalyzer {
    private let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    private func pragmaInt(_ name: String) throws -> Int {
        let rows = try db.query("PRAGMA \(name)")
        return rows.first?.first?.int ?? 0
    }

    private func pragmaText(_ name: String) throws -> String {
        let rows = try db.query("PRAGMA \(name)")
        return rows.first?.first?.text ?? ""
    }

    public func userTables() throws -> [String] {
        let rows = try db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        return rows.compactMap { $0.first?.text }
    }

    public func tableStats() throws -> [DatabaseTableStats] {
        try userTables().map { table in
            let count = try db.query("SELECT COUNT(*) FROM \(DatabaseSQL.quoted(table))").first?.first?.int ?? 0
            let indexes = try db.query("SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND tbl_name = ?", [.text(table)]).first?.first?.int ?? 0
            return DatabaseTableStats(name: table, rowCount: count, indexCount: indexes)
        }
    }

    public func report() throws -> DatabasePerformanceReport {
        let tables = try tableStats()
        let integrityRows = try db.query("PRAGMA integrity_check")
        let integrity = integrityRows.first?.first?.text ?? ""
        let size: Int64
        if db.path == ":memory:" {
            size = 0
        } else {
            size = (try? FileManager.default.attributesOfItem(atPath: db.path)[.size] as? Int64) ?? 0
        }
        return DatabasePerformanceReport(
            pageCount: try pragmaInt("page_count"),
            pageSize: try pragmaInt("page_size"),
            freelistCount: try pragmaInt("freelist_count"),
            journalMode: try pragmaText("journal_mode"),
            cacheSizeKiB: try pragmaInt("cache_size"),
            databaseSizeBytes: size,
            integrity: integrity,
            tables: tables,
            totalRows: tables.reduce(0) { $0 + $1.rowCount }
        )
    }

    public func explain(_ sql: String) throws -> [String] {
        let (columns, rows) = try db.queryWithColumns("EXPLAIN QUERY PLAN \(sql)")
        guard let detailIndex = columns.firstIndex(of: "detail") else { return [] }
        return rows.compactMap { row in detailIndex < row.count ? row[detailIndex].text : nil }
    }

    public func unindexedForeignKeys() throws -> [(table: String, column: String)] {
        var missing: [(table: String, column: String)] = []
        for table in try userTables() {
            let indexedColumns = Set(try {
                var columns: [String] = []
                let indexes = try db.query("PRAGMA index_list(\(DatabaseSQL.quoted(table)))")
                for indexRow in indexes {
                    guard indexRow.count > 1, let indexName = indexRow[1].text else { continue }
                    let info = try db.query("PRAGMA index_info(\(DatabaseSQL.quoted(indexName)))")
                    for infoRow in info where infoRow.count > 2 {
                        if let column = infoRow[2].text { columns.append(column) }
                    }
                }
                return columns
            }())
            let foreignKeys = try db.query("PRAGMA foreign_key_list(\(DatabaseSQL.quoted(table)))")
            for fkRow in foreignKeys where fkRow.count > 3 {
                if let column = fkRow[3].text, !indexedColumns.contains(column) {
                    missing.append((table: table, column: column))
                }
            }
        }
        return missing
    }

    public func vacuum() throws {
        try db.execute("VACUUM")
        try db.execute("ANALYZE")
    }
}
