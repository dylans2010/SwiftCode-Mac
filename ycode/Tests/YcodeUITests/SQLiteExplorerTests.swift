import XCTest
@testable import YcodeUI

// NOTE: No Swift toolchain exists in this environment, so these tests
// have NOT been compiled or run — statically verified only. On Dylan's
// Mac: run with `swift test --filter SQLiteExplorerTests`.
//
// Wave 17, Slice C: tests for the SQLite Explorer model
// (`SQLiteExplorerModel`). Every test runs against an in-memory
// database — no file, no window, no provider is involved. The model
// is a thin layer over Ycode's existing `SQLiteDatabase`, so these
// tests pin the browser behaviour (listing, schema, paging, SQL,
// display strings, errors), not the SQLite engine itself.

@MainActor
final class SQLiteExplorerTests: XCTestCase {

    private func makeDB() throws -> SQLiteExplorerModel {
        let model = try SQLiteExplorerModel.inMemory()
        _ = try model.run(sql: """
            CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                score REAL,
                data BLOB
            )
            """)
        _ = try model.run(sql: "CREATE VIEW adults AS SELECT * FROM users WHERE id >= 18")
        _ = try model.run(sql: "INSERT INTO users (id, name, score, data) VALUES (1, 'Ada', 9.5, x'0102')")
        _ = try model.run(sql: "INSERT INTO users (id, name, score, data) VALUES (2, 'Grace', NULL, NULL)")
        _ = try model.run(sql: "INSERT INTO users (id, name, score, data) VALUES (3, 'Linus', 7.25, NULL)")
        return model
    }

    func testTablesListsTablesAndViews() throws {
        let model = try makeDB()
        let tables = try model.tables()
        XCTAssertEqual(tables.map(\.name), ["adults", "users"])
        XCTAssertEqual(tables.first(where: { $0.name == "users" })?.kind, .table)
        XCTAssertEqual(tables.first(where: { $0.name == "adults" })?.kind, .view)
        XCTAssertFalse(tables.contains { $0.name.hasPrefix("sqlite_") })
    }

    func testEmptyDatabaseHasNoTables() throws {
        let model = try SQLiteExplorerModel.inMemory()
        XCTAssertEqual(try model.tables(), [])
    }

    func testColumnsDescribeSchema() throws {
        let model = try makeDB()
        let columns = try model.columns(of: "users")
        XCTAssertEqual(columns.map(\.name), ["id", "name", "score", "data"])
        XCTAssertEqual(columns[0].type, "INTEGER")
        XCTAssertTrue(columns[0].primaryKey)
        XCTAssertEqual(columns[1].type, "TEXT")
        XCTAssertTrue(columns[1].notNull)
        XCTAssertFalse(columns[2].notNull)
    }

    func testRowCountAndPaging() throws {
        let model = try SQLiteExplorerModel.inMemory()
        _ = try model.run(sql: "CREATE TABLE n (v INTEGER)")
        for i in 0..<250 {
            _ = try model.run(sql: "INSERT INTO n (v) VALUES (\(i))")
        }
        XCTAssertEqual(try model.rowCount(of: "n"), 250)
        let first = try model.rows(of: "n", limit: 100, offset: 0)
        XCTAssertEqual(first.columns, ["v"])
        XCTAssertEqual(first.rows.count, 100)
        XCTAssertEqual(first.rows.first, ["0"])
        XCTAssertEqual(first.rows.last, ["99"])
        let last = try model.rows(of: "n", limit: 100, offset: 200)
        XCTAssertEqual(last.rows.count, 50)
        XCTAssertEqual(last.rows.first, ["200"])
        XCTAssertEqual(last.rows.last, ["249"])
    }

    func testRunSelectReturnsColumnsAndRows() throws {
        let model = try makeDB()
        let result = try model.run(sql: "SELECT id, name, score, data FROM users ORDER BY id")
        XCTAssertEqual(result.columns, ["id", "name", "score", "data"])
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(result.rows[0], ["1", "Ada", "9.5", "<2 bytes>"])
        XCTAssertEqual(result.rows[1], ["2", "Grace", "NULL", "NULL"])
        XCTAssertEqual(result.rows[2][2], "7.25")
        XCTAssertEqual(result.message, "3 row(s).")
    }

    func testRunInsertReportsAffectedRows() throws {
        let model = try makeDB()
        let result = try model.run(sql: "INSERT INTO users (id, name) VALUES (4, 'Edsger')")
        XCTAssertTrue(result.columns.isEmpty)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.message, "OK — 1 row(s) affected.")
        XCTAssertEqual(try model.rowCount(of: "users"), 4)
    }

    func testRunBadSQLThrows() throws {
        let model = try makeDB()
        XCTAssertThrowsError(try model.run(sql: "SELEC oops FROM nowhere")) { error in
            guard case SQLiteExplorerError.queryFailed = error else {
                XCTFail("Expected .queryFailed, got \(error)")
                return
            }
        }
    }

    func testRunEmptySQLThrows() throws {
        let model = try makeDB()
        XCTAssertThrowsError(try model.run(sql: "   ")) { error in
            XCTAssertEqual(error as? SQLiteExplorerError, .queryFailed("Enter a SQL statement to run."))
        }
    }

    func testOpenMissingFileThrows() {
        let path = NSTemporaryDirectory() + "ycode-test-missing-\(UUID().uuidString).sqlite"
        XCTAssertThrowsError(try SQLiteExplorerModel(path: path)) { error in
            guard case SQLiteExplorerError.openFailed = error else {
                XCTFail("Expected .openFailed, got \(error)")
                return
            }
        }
    }

    func testDisplayFormatsValues() {
        XCTAssertEqual(SQLiteExplorerModel.display(.null), "NULL")
        XCTAssertEqual(SQLiteExplorerModel.display(.int(42)), "42")
        XCTAssertEqual(SQLiteExplorerModel.display(.real(9.5)), "9.5")
        XCTAssertEqual(SQLiteExplorerModel.display(.text("Ada")), "Ada")
        XCTAssertEqual(SQLiteExplorerModel.display(.text("")), "")
        XCTAssertEqual(SQLiteExplorerModel.display(.blob([1, 2, 3])), "<3 bytes>")
        XCTAssertEqual(SQLiteExplorerModel.display(.blob([])), "<0 bytes>")
    }

    func testQuotedEscapesQuotes() {
        XCTAssertEqual(SQLiteExplorerModel.quoted("users"), "\"users\"")
        XCTAssertEqual(SQLiteExplorerModel.quoted("we\"ird"), "\"we\"\"ird\"")
    }
}
