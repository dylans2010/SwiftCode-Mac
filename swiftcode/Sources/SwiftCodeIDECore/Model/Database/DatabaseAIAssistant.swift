import Foundation
import SwiftCodeHealthStore

public enum DatabaseAIError: Error, Equatable, Sendable {
    case noProvider
}

extension DatabaseAIError: LocalizedError {
    public var errorDescription: String? {
        "No LLM provider is attached to the database AI assistant. Attach one through SwiftCodeAssistant to explain SQL with a model; local schema analysis is available without it."
    }
}

public struct DatabaseAIInsight: Sendable, Equatable {
    public enum Severity: String, Sendable, Equatable { case warning, suggestion, info }
    public var severity: Severity
    public var title: String
    public var detail: String

    public init(severity: Severity, title: String, detail: String) {
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

@MainActor
public final class DatabaseAIAssistant {
    private let db: SQLiteDatabase
    private let performance: DatabasePerformanceAnalyzer

    public var llmProvider: ((String) async throws -> String)?

    public init(db: SQLiteDatabase) {
        self.db = db
        self.performance = DatabasePerformanceAnalyzer(db: db)
    }

    public func explainSQL(_ sql: String) async throws -> String {
        guard let llmProvider else { throw DatabaseAIError.noProvider }
        let prompt = """
            You are a SQLite expert. Explain the following SQL statement in plain language: \
            what it does, which tables it touches, and anything risky or slow about it. \
            SQL: \(sql)
            """
        return try await llmProvider(prompt)
    }

    public func explainSQLLocally(_ sql: String) throws -> String {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? "SQL"
        let plan = try performance.explain(sql)
        var lines = ["[Local analysis — no model involved] \(kind.uppercased()) statement."]
        if plan.isEmpty {
            lines.append("EXPLAIN QUERY PLAN returned no steps.")
        } else {
            lines.append("Query plan:")
            lines += plan.map { "  \($0)" }
        }
        return lines.joined(separator: "\n")
    }

    public func analyzeSchema() throws -> [DatabaseAIInsight] {
        var insights: [DatabaseAIInsight] = []
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        for row in tables {
            guard let table = row.first?.text else { continue }
            let columns = try db.query("PRAGMA table_info(\(DatabaseSQL.quoted(table)))")
            let hasPrimaryKey = columns.contains { $0.count > 5 && ($0[5].int ?? 0) > 0 }
            if !hasPrimaryKey {
                insights.append(DatabaseAIInsight(severity: .warning, title: "Table '\(table)' has no primary key",
                                                  detail: "Rows cannot be addressed individually; add a PRIMARY KEY column."))
            }
            let indexRows = try db.query("PRAGMA index_list(\(DatabaseSQL.quoted(table)))")
            if indexRows.isEmpty {
                insights.append(DatabaseAIInsight(severity: .info, title: "Table '\(table)' has no indexes",
                                                  detail: "Every lookup is a full scan; consider an index on the columns queries filter on."))
            }
        }
        for missing in try performance.unindexedForeignKeys() {
            insights.append(DatabaseAIInsight(severity: .suggestion,
                                              title: "Foreign key '\(missing.table).\(missing.column)' has no index",
                                              detail: "Joins and deletes on this column scan the whole table; add an index on \(missing.table)(\(missing.column))."))
        }
        return insights
    }

    public func suggestIndexes(for sql: String) throws -> [String] {
        let plan = try performance.explain(sql)
        var suggestions: [String] = []
        let whereColumns = Self.whereColumns(in: sql)
        for step in plan where step.contains("SCAN") {
            let table = step.split(separator: " ").dropFirst(2).first.map(String.init) ?? "?"
            if whereColumns.isEmpty {
                suggestions.append("EXPLAIN QUERY PLAN scans '\(table)' fully; consider an index on the columns this query filters on.")
            } else {
                suggestions.append("EXPLAIN QUERY PLAN scans '\(table)' fully; consider an index on \(table)(\(whereColumns.joined(separator: ", "))).")
            }
        }
        return suggestions
    }

    private static func whereColumns(in sql: String) -> [String] {
        guard let whereRange = sql.range(of: "WHERE", options: .caseInsensitive) else { return [] }
        let clause = String(sql[whereRange.upperBound...])
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_]*)\s*=[^=]"#) else { return [] }
        let matches = regex.matches(in: clause, range: NSRange(clause.startIndex..., in: clause))
        var seen: Set<String> = []
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: clause) else { return nil }
            let column = String(clause[range])
            return seen.insert(column).inserted ? column : nil
        }
    }
}
