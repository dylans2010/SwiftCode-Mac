import Foundation
import Testing
import SwiftCodeAssistant
import SwiftCodeIDECore
@testable import SwiftCodeMCP

/// The ported Legacy Agentic data / environment / secrets / UI /
/// profiling tools (Wave 8, slice G) against
/// `Samples/AgentSamples/Greeter` (a copy). Static checks only —
/// no Swift toolchain runs in this environment; the tests below
/// are written to the same shape as the other SwiftCodeMCP suites and
/// run on Dylan's Mac / CI.
///
/// Fixture facts: `Greeter.swift` is 14 lines plus a trailing
/// newline. The SQLite fixtures are built with the `sqlite3` CLI
/// (present on macOS and on the Linux test host); a test that
/// needs it returns early when the CLI is absent, since the tool
/// itself then fails honestly naming the missing CLI.
@MainActor
@Suite(.serialized) struct SwiftCodeAgenticDataTests {
    static let agenticDataIDs = ["parse_json", "parse_yaml", "parse_xml", "parse_markdown", "sql_query",
                                 "database_schema_inspector", "database_migration", "read_environment_variables",
                                 "update_environment_variables", "manage_secrets", "open_browser", "browser_automation",
                                 "ui_inspector", "accessibility_inspector", "performance_profiler", "memory_profiler",
                                 "network_inspector", "crash_analyzer", "symbolicate_crash_logs"]

    /// Opens a copy of Greeter and installs the ported Agentic
    /// data tools on the server (same shape as Wave 3's
    /// `opened`; the coordinator wires `agenticDataTools` into
    /// `installTools()`).
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        // Filter-first (Wave 2 shape): `installTools()` already
        // wires `agenticDataTools`, so a plain `+=` would
        // register them twice.
        let ported = Set(host.agenticDataTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticDataTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    /// Writes a fixture file directly (not through a tool under test).
    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    var sqlite3Available: Bool { FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3") }

    /// Runs the `sqlite3` CLI once to build a fixture database.
    func runSQLite3(_ dbPath: String, _ sql: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [dbPath, sql]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0, "sqlite3 fixture setup failed for \(sql)")
    }

    /// Builds the shared SQLite fixture: a `users` table, a
    /// `posts` table with a foreign key to it, a view and an
    /// index. Returns the workspace-relative database path.
    func makeDatabaseFixture(_ sample: TempSample) throws -> String {
        let dbPath = sample.path("data/test.db")
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: dbPath).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try runSQLite3(dbPath, "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT NOT NULL);")
        try runSQLite3(dbPath, "INSERT INTO users VALUES(1, 'ann'), (2, 'bob');")
        try runSQLite3(dbPath, "CREATE TABLE posts(id INTEGER PRIMARY KEY, user_id INTEGER REFERENCES users(id), title TEXT);")
        try runSQLite3(dbPath, "INSERT INTO posts VALUES(1, 1, 'hello');")
        try runSQLite3(dbPath, "CREATE VIEW user_names AS SELECT id, name FROM users;")
        try runSQLite3(dbPath, "CREATE INDEX idx_users_name ON users(name);")
        return "data/test.db"
    }

    func requiredParams(of tools: [MCPTool], _ name: String) -> [String] {
        tools.first { $0.name == name }?.inputSchema["required"]?.array?.compactMap(\.string) ?? []
    }

    @Test func toolsAreRegisteredWithLegacySchemas() {
        let host = SwiftCodeMCPHost()
        let tools = host.agenticDataTools
        #expect(tools.map(\.name) == Self.agenticDataIDs)
        let expectedTitles: [String: String] = [
            "parse_json": "Parse JSON", "parse_yaml": "Parse YAML", "parse_xml": "Parse XML",
            "parse_markdown": "Parse Markdown", "sql_query": "SQL Query",
            "database_schema_inspector": "Database Schema Inspector", "database_migration": "Database Migration",
            "read_environment_variables": "Read Environment Variables",
            "update_environment_variables": "Update Environment Variables", "manage_secrets": "Manage Secrets",
            "open_browser": "Open Browser", "browser_automation": "Browser Automation",
            "ui_inspector": "UI Inspector", "accessibility_inspector": "Accessibility Inspector",
            "performance_profiler": "Performance Profiler", "memory_profiler": "Memory Profiler",
            "network_inspector": "Network Inspector", "crash_analyzer": "Crash Analyzer",
            "symbolicate_crash_logs": "Symbolicate Crash Logs"]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name], "title for \(tool.name)")
        }
        // Verbatim Legacy descriptions.
        let expectedDescriptions: [String: String] = [
            "parse_json": "Parses a JSON string.", "parse_yaml": "Parses a YAML string.",
            "parse_xml": "Parses an XML string.", "parse_markdown": "Parses a Markdown string.",
            "sql_query": "Executes an SQL query.", "database_schema_inspector": "Inspects the schema of a database.",
            "database_migration": "Applies a database migration.",
            "read_environment_variables": "Reads environment variables.",
            "update_environment_variables": "Updates environment variables.",
            "manage_secrets": "Manages secrets in the keychain.",
            "open_browser": "Opens a URL in the default browser.",
            "browser_automation": "Executes a browser automation script.",
            "ui_inspector": "Inspects the UI hierarchy.",
            "accessibility_inspector": "Inspects accessibility properties.",
            "performance_profiler": "Profiles the performance of a process.",
            "memory_profiler": "Profiles the memory usage of a process.",
            "network_inspector": "Inspects network traffic.", "crash_analyzer": "Analyzes crash logs.",
            "symbolicate_crash_logs": "Symbolicates crash logs."]
        for tool in tools {
            #expect(tool.description == expectedDescriptions[tool.name], "description for \(tool.name)")
        }
        #expect(requiredParams(of: tools, "parse_json") == ["json"])
        #expect(requiredParams(of: tools, "sql_query") == ["query", "databasePath"])
        #expect(requiredParams(of: tools, "manage_secrets") == ["action", "key"])
        #expect(requiredParams(of: tools, "read_environment_variables") == [])
        #expect(requiredParams(of: tools, "performance_profiler") == ["pid"])
        // The three writers are write-gated; the reads are not.
        for name in ["database_migration", "update_environment_variables", "manage_secrets", "open_browser",
                     "browser_automation"] {
            #expect(tools.first { $0.name == name }?.writes == true, "\(name) must be writes: true")
        }
        for name in ["parse_json", "sql_query", "database_schema_inspector", "read_environment_variables",
                     "performance_profiler", "network_inspector", "crash_analyzer", "symbolicate_crash_logs"] {
            #expect(tools.first { $0.name == name }?.writes == false, "\(name) must not be writes: true")
        }
    }

    @Test func takeScreenshotIsAlreadyServed() {
        // SwiftCode already has `take_screenshot` (Wave 4); the
        // Agentic ID must not register a second tool.
        let host = SwiftCodeMCPHost()
        #expect(host.server.tools.contains { $0.name == "take_screenshot" })
        #expect(!host.agenticDataTools.contains { $0.name == "take_screenshot" })
    }

    @Test func parseJSONParsesObjectsAndRejectsTheRest() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let ok = try await host.server.callTool("parse_json", ["json": .string("{\"a\": 1, \"b\": \"x\"}")])
        #expect(!ok.isToolError, "\(ok.resultText)")
        #expect(ok.structured?["result"]?["a"] == 1)
        #expect(ok.structured?["result"]?["b"] == "x")
        #expect(ok.firstText.contains("2 top-level keys"))
        let invalid = try await host.server.callTool("parse_json", ["json": .string("{oops")])
        #expect(invalid.isToolError && invalid.firstText.contains("invalid JSON"))
        let array = try await host.server.callTool("parse_json", ["json": .string("[1, 2]")])
        #expect(array.isToolError && array.firstText.contains("JSON is not a dictionary"))
        let missing = try await host.server.callTool("parse_json")
        #expect(missing.isToolError)
    }

    @Test func parseYAMLParsesTheSubsetAndRejectsTheRest() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let yaml = """
        name: Greeter
        count: 3
        enabled: true
        ratio: 1.5
        nothing:
        tags: [a, b, c]
        items:
          - one
          - two
        nested:
          key: value
          list:
            - x: 1
              y: 2
        """
        let ok = try await host.server.callTool("parse_yaml", ["yaml": .string(yaml)])
        #expect(!ok.isToolError, "\(ok.resultText)")
        let parsed = ok.structured?["parsed"]
        #expect(parsed?["name"] == "Greeter")
        #expect(parsed?["count"] == 3)
        #expect(parsed?["enabled"] == true)
        #expect(parsed?["ratio"] == 1.5)
        #expect(parsed?["nothing"]?.isNull == true)
        #expect(parsed?["tags"]?[1] == "b")
        #expect(parsed?["items"]?[0] == "one")
        #expect(parsed?["nested"]?["list"]?[0]?["y"] == 2)
        #expect(ok.structured?["topLevelKeys"]?.array?.compactMap(\.string).contains("nested") == true)
        let tabbed = try await host.server.callTool("parse_yaml", ["yaml": .string("a:\n\tb: 1\n")])
        #expect(tabbed.isToolError && tabbed.firstText.contains("tab used for indentation"))
        let anchored = try await host.server.callTool("parse_yaml", ["yaml": .string("a: &anchor 1\nb: *anchor\n")])
        #expect(anchored.isToolError && anchored.firstText.contains("unsupported YAML construct"))
        let duplicate = try await host.server.callTool("parse_yaml", ["yaml": .string("a: 1\na: 2\n")])
        #expect(duplicate.isToolError && duplicate.firstText.contains("duplicate mapping key"))
        let flowMap = try await host.server.callTool("parse_yaml", ["yaml": .string("point: {x: 1, y: 2}\n")])
        #expect(!flowMap.isToolError, "\(flowMap.resultText)")
        #expect(flowMap.structured?["parsed"]?["point"]?["y"] == 2)
    }

    @Test func parseXMLBuildsATreeAndRejectsMalformedInput() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let xml = "<root version=\"1\"><child name=\"a\">hello</child><child name=\"b\">world</child><empty/></root>"
        let ok = try await host.server.callTool("parse_xml", ["xml": .string(xml)])
        #expect(!ok.isToolError, "\(ok.resultText)")
        let root = ok.structured?["root"]
        #expect(root?["tag"] == "root")
        #expect(root?["attributes"]?["version"] == "1")
        #expect(root?["children"]?[0]?["tag"] == "child")
        #expect(root?["children"]?[0]?["attributes"]?["name"] == "a")
        #expect(root?["children"]?[0]?["text"] == "hello")
        #expect(root?["children"]?[1]?["text"] == "world")
        #expect(root?["children"]?.array?.count == 3)
        #expect(root?["children"]?[2]?["tag"] == "empty")
        #expect(root?["children"]?[2]?["text"] == nil)
        #expect(ok.firstText.contains("root element <root>"))
        let bad = try await host.server.callTool("parse_xml", ["xml": .string("<root><unclosed>")])
        #expect(bad.isToolError && bad.firstText.contains("Invalid XML"))
    }

    @Test func parseMarkdownExtractsStructure() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let markdown = """
        # Title
        Some intro text with a [link](https://example.com).

        ## Section
        - one
        - two

        ```swift
        let x = 1
        ```
        """
        let ok = try await host.server.callTool("parse_markdown", ["markdown": .string(markdown)])
        #expect(!ok.isToolError, "\(ok.resultText)")
        #expect(ok.structured?["headings"]?.array?.compactMap(\.string) == ["Title", "Section"])
        #expect(ok.structured?["blocks"]?.array?.count == 5)
        #expect(ok.structured?["blocks"]?[0]?["type"] == "heading")
        #expect(ok.structured?["blocks"]?[1]?["type"] == "paragraph")
        #expect(ok.structured?["blocks"]?[3]?["type"] == "list")
        #expect(ok.structured?["blocks"]?[3]?["items"]?.array?.compactMap(\.string) == ["one", "two"])
        #expect(ok.structured?["blocks"]?[4]?["type"] == "code")
        #expect(ok.structured?["blocks"]?[4]?["language"] == "swift")
        #expect(ok.structured?["links"]?[0]?["url"] == "https://example.com")
        #expect(ok.structured?["links"]?[0]?["kind"] == "link")
        #expect(ok.firstText.contains("5 blocks"))
    }

    @Test func sqlQueryRunsReadOnlyStatements() async throws {
        guard sqlite3Available else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let db = try makeDatabaseFixture(sample)
        let ok = try await host.server.callTool("sql_query", ["query": .string("SELECT id, name FROM users ORDER BY id"),
                                                              "databasePath": .string(db)])
        #expect(!ok.isToolError, "\(ok.resultText)")
        #expect(ok.structured?["rowCount"] == 2)
        #expect(ok.structured?["rows"]?[0]?["id"] == 1)
        #expect(ok.structured?["rows"]?[0]?["name"] == "ann")
        #expect(ok.structured?["rows"]?[1]?["name"] == "bob")
        let empty = try await host.server.callTool("sql_query", ["query": .string("SELECT * FROM users WHERE id > 99"),
                                                                 "databasePath": .string(db)])
        #expect(!empty.isToolError && empty.structured?["rowCount"] == 0)
        let insert = try await host.server.callTool("sql_query", ["query": .string("INSERT INTO users VALUES(3, 'cy')"),
                                                                  "databasePath": .string(db)])
        #expect(insert.isToolError && insert.firstText.contains("read-only statements only"))
        let missing = try await host.server.callTool("sql_query", ["query": .string("SELECT 1"),
                                                                   "databasePath": .string("data/nope.db")])
        #expect(missing.isToolError && missing.firstText.contains("Database file not found"))
        let bad = try await host.server.callTool("sql_query", ["query": .string("SELEC oops"),
                                                               "databasePath": .string(db)])
        #expect(bad.isToolError && bad.firstText.contains("read-only statements only"))
    }

    @Test func databaseSchemaInspectorListsTablesColumnsAndKeys() async throws {
        guard sqlite3Available else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let db = try makeDatabaseFixture(sample)
        let r = try await host.server.callTool("database_schema_inspector", ["databasePath": .string(db)])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["tableCount"] == 2)
        #expect(r.structured?["views"]?.array?.compactMap(\.string) == ["user_names"])
        #expect(r.structured?["indexes"]?.array?.compactMap(\.string) == ["idx_users_name"])
        let tables = r.structured?["tables"]?.array ?? []
        let users = tables.first { $0["name"]?.string == "users" }
        #expect(users != nil)
        let columns = users?["columns"]?.array ?? []
        #expect(columns.contains { $0["name"]?.string == "id" && $0["primaryKey"] == true })
        #expect(columns.contains { $0["name"]?.string == "name" && $0["notNull"] == true })
        let posts = tables.first { $0["name"]?.string == "posts" }
        let foreignKeys = posts?["foreignKeys"]?.array ?? []
        #expect(foreignKeys.count == 1)
        #expect(foreignKeys[0]["table"] == "users")
        #expect(foreignKeys[0]["from"] == "user_id")
        #expect(foreignKeys[0]["to"] == "id")
        let missing = try await host.server.callTool("database_schema_inspector", ["databasePath": .string("data/nope.db")])
        #expect(missing.isToolError && missing.firstText.contains("Database file not found"))
    }

    @Test func databaseMigrationAppliesAndIsApprovalGated() async throws {
        guard sqlite3Available else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "data/migration.sql", """
        CREATE TABLE migrated(id INTEGER PRIMARY KEY, label TEXT);
        INSERT INTO migrated VALUES(1, 'first');
        """)
        let ok = try await host.server.callTool("database_migration", ["databasePath": .string("data/mig.db"),
                                                                       "migrationPath": .string("data/migration.sql")])
        #expect(!ok.isToolError, "\(ok.resultText)")
        #expect(ok.structured?["database"] == "data/mig.db")
        #expect(ok.structured?["migration"] == "data/migration.sql")
        #expect(ok.firstText.contains("Migration applied"))
        let check = try await host.server.callTool("sql_query", ["query": .string("SELECT label FROM migrated"),
                                                                 "databasePath": .string("data/mig.db")])
        #expect(!check.isToolError && check.structured?["rows"]?[0]?["label"] == "first")
        // A failing statement surfaces the sqlite3 error.
        try writeFixture(sample, "data/bad.sql", "CREATE TABLE x(y);\nBAD STATEMENT HERE;\n")
        let bad = try await host.server.callTool("database_migration", ["databasePath": .string("data/mig2.db"),
                                                                        "migrationPath": .string("data/bad.sql")])
        #expect(bad.isToolError && bad.firstText.contains("Applying migration"))
        // An empty migration file fails before anything runs.
        try writeFixture(sample, "data/empty.sql", "\n")
        let empty = try await host.server.callTool("database_migration", ["databasePath": .string("data/mig3.db"),
                                                                          "migrationPath": .string("data/empty.sql")])
        #expect(empty.isToolError && empty.firstText.contains("Migration file is empty"))
        // A read-only server refuses the migration before the handler runs.
        let readOnlyHost = try await opened(sample)
        let refused = try await readOnlyHost.server.callTool("database_migration",
                                                             ["databasePath": .string("data/mig4.db"),
                                                              "migrationPath": .string("data/migration.sql")])
        #expect(refused.isToolError)
        // A rejected approval fails the migration.
        let rejectingHost = try await opened(sample, policy: .review { _ in false })
        let rejected = try await rejectingHost.server.callTool("database_migration",
                                                               ["databasePath": .string("data/mig5.db"),
                                                                "migrationPath": .string("data/migration.sql")])
        #expect(rejected.isToolError)
    }

    @Test func readEnvironmentVariablesListsNamesOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("read_environment_variables")
        #expect(!r.isToolError, "\(r.resultText)")
        let names = r.structured?["names"]?.array?.compactMap(\.string) ?? []
        #expect(names.contains("PATH"))
        #expect(r.structured?["count"]?.int == names.count)
        // No KEY=value pair may leak: the whole result carries no '='.
        #expect(!r.resultText.contains("="))
        #expect(r.firstText.contains("names only"))
    }

    @Test func updateEnvironmentVariablesSetsProcessVariables() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let key = "SWIFTCODE_AGENTIC_DATA_TEST_VAR"
        let r = try await host.server.callTool("update_environment_variables",
                                               ["variables": .object([key: .string("hello")])])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Environment variables updated"))
        // The new name is visible to a later read; the value is not.
        let read = try await host.server.callTool("read_environment_variables")
        #expect(read.structured?["names"]?.array?.compactMap(\.string).contains(key) == true)
        #expect(!read.resultText.contains("hello"))
        let badValue = try await host.server.callTool("update_environment_variables",
                                                      ["variables": .object([key: .int(3)])])
        #expect(badValue.isToolError)
        let badName = try await host.server.callTool("update_environment_variables",
                                                     ["variables": .object(["bad=name": .string("x")])])
        #expect(badName.isToolError && badName.firstText.contains("Invalid environment variable name"))
    }

    @Test func manageSecretsNeverReturnsValues() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        SwiftCodeMCPHost.agenticDataTestSecretStore = MemorySecretStore()
        defer { SwiftCodeMCPHost.agenticDataTestSecretStore = nil }
        let host = try await opened(sample, policy: .allow)
        let missing = try await host.server.callTool("manage_secrets", ["action": .string("get"),
                                                                        "key": .string("agentic-data-test-key")])
        #expect(!missing.isToolError, "\(missing.resultText)")
        #expect(missing.firstText.contains("No secret stored"))
        let saved = try await host.server.callTool("manage_secrets", ["action": .string("save"),
                                                                      "key": .string("agentic-data-test-key"),
                                                                      "value": .string("s3cr3t-value-must-not-appear")])
        #expect(!saved.isToolError, "\(saved.resultText)")
        #expect(saved.firstText.contains("Secret saved"))
        #expect(!saved.resultText.contains("s3cr3t-value-must-not-appear"))
        let got = try await host.server.callTool("manage_secrets", ["action": .string("get"),
                                                                    "key": .string("agentic-data-test-key")])
        #expect(!got.isToolError, "\(got.resultText)")
        #expect(got.firstText.contains("Secret exists"))
        // The value never appears in any tool output.
        #expect(!got.resultText.contains("s3cr3t-value-must-not-appear"))
        let noValue = try await host.server.callTool("manage_secrets", ["action": .string("save"),
                                                                        "key": .string("agentic-data-test-key")])
        #expect(noValue.isToolError && noValue.firstText.contains("Missing required parameter: value"))
        let unknown = try await host.server.callTool("manage_secrets", ["action": .string("delete"),
                                                                        "key": .string("agentic-data-test-key")])
        // Legacy's answer for an unknown action is the plain
        // "No result" string, not an error.
        #expect(!unknown.isToolError && unknown.firstText.contains("No result"))
    }

    @Test func openBrowserRejectsNonHTTPURLs() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        // `.allow` so the handler runs its validation instead of
        // the read-only policy refusing the write tool first.
        let host = try await opened(sample, policy: .allow)
        let bad = try await host.server.callTool("open_browser", ["url": .string("not a url")])
        #expect(bad.isToolError && bad.firstText.contains("Invalid URL"))
        let ftp = try await host.server.callTool("open_browser", ["url": .string("ftp://example.com/x")])
        #expect(ftp.isToolError && ftp.firstText.contains("only opens http(s) URLs"))
    }

    @Test func honestlyFailingToolsNameTheirPrerequisite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let automation = try await host.server.callTool("browser_automation", ["script": .string("click('#x')")])
        #expect(automation.isToolError && automation.firstText.contains("browser automation driver"))
        let ui = try await host.server.callTool("ui_inspector")
        #expect(ui.isToolError && ui.firstText.contains("live target application"))
        let a11y = try await host.server.callTool("accessibility_inspector")
        #expect(a11y.isToolError && a11y.firstText.contains("accessibility permission"))
    }

    @Test func profilersSnapshotTheCurrentProcess() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let perf = try await host.server.callTool("performance_profiler", ["pid": .int(pid)])
        #expect(!perf.isToolError, "\(perf.resultText)")
        #expect(perf.structured?["pid"] == .int(pid))
        #expect((perf.structured?["rssBytes"]?.int ?? 0) > 0)
        #expect((perf.structured?["vszBytes"]?.int ?? 0) > 0)
        #expect(perf.structured?["command"]?.string != nil)
        #expect(perf.firstText.contains("single ps snapshot"))
        let mem = try await host.server.callTool("memory_profiler", ["pid": .int(pid)])
        #expect(!mem.isToolError, "\(mem.resultText)")
        #expect(mem.structured?["pid"] == .int(pid))
        #expect((mem.structured?["rssBytes"]?.int ?? 0) > 0)
        #expect((mem.structured?["memPercent"]?.double ?? -1) >= 0)
        let gone = try await host.server.callTool("performance_profiler", ["pid": .int(2_147_483_647)])
        #expect(gone.isToolError && gone.firstText.contains("No running process"))
        let badPid = try await host.server.callTool("memory_profiler", ["pid": .int(0)])
        #expect(badPid.isToolError)
    }

    @Test func networkInspectorSnapshotsConnections() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("network_inspector")
        if r.isToolError {
            // Neither lister installed: the honest failure names one.
            #expect(r.firstText.contains("netstat") || r.firstText.contains("ss"))
        } else {
            #expect((r.structured?["connectionCount"]?.int ?? -1) >= 0)
            #expect(r.structured?["source"]?.string == "netstat" || r.structured?["source"]?.string == "ss")
            #expect(r.firstText.contains("connection-table snapshot"))
        }
    }

    @Test func crashAnalyzerParsesCrashLogs() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Logs/crash.crash", """
        Incident Identifier: ABC
        Exception Type: EXC_BAD_ACCESS (SIGSEGV)
        Termination Reason: Namespace SIGNAL, Code 11
        Triggered by Thread: 0
        Thread 0 Crashed:
        0   MyApp  0x0000000100000000 main + 0
        1   MyApp  0x0000000100000010 foo + 16
        2   libsystem  0x00000001a0000000 bar + 4
        Thread 1:
        0   libsystem  0x00000001a0000010 baz + 8
        """)
        let r = try await host.server.callTool("crash_analyzer", ["logPath": .string("Logs/crash.crash")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["hasException"] == true && r.structured?["frameCount"] == 3)
        #expect(r.firstText.contains("Exception Type: EXC_BAD_ACCESS (SIGSEGV)"))
        #expect(r.firstText.contains("Top blamed frames:"))
        try writeFixture(sample, "Logs/crash.ips", "{\"exception\": {\"type\": \"EXC_CRASH\"}, \"termination\": {\"reason\": \"Namespace X\"}}")
        let json = try await host.server.callTool("crash_analyzer", ["logPath": .string("Logs/crash.ips")])
        #expect(!json.isToolError && json.firstText.contains("Exception Type: EXC_CRASH"))
        try writeFixture(sample, "Logs/plain.txt", "hello world\nnothing to see\n")
        let garbage = try await host.server.callTool("crash_analyzer", ["logPath": .string("Logs/plain.txt")])
        #expect(garbage.isToolError && garbage.firstText.contains("No crash metadata recognized"))
        let missing = try await host.server.callTool("crash_analyzer", ["logPath": .string("Logs/nope.crash")])
        #expect(missing.isToolError && missing.firstText.contains("Cannot read crash log at: Logs/nope.crash"))
    }

    @Test func symbolicateCrashLogsFailsHonestlyWithoutADsym() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Logs/crash.crash", """
        Incident Identifier: ABC
        Exception Type: EXC_BAD_ACCESS (SIGSEGV)
        Triggered by Thread: 0
        Thread 0 Crashed:
        0   MyApp  0x0000000100000000 main + 0
        Binary Images:
        0x100000000 - 0x100003fff MyApp arm64  <00000000000000000000000000000000> /path/MyApp
        """)
        let missing = try await host.server.callTool("symbolicate_crash_logs",
                                                     ["logPath": .string("Logs/crash.crash"),
                                                      "dsymPath": .string("Build/MyApp.dSYM")])
        #expect(missing.isToolError && missing.firstText.contains("dSYM not found"))
#if os(Linux)
        // No `atos` on Linux: an existing (but empty) dSYM fails
        // naming the missing prerequisite. The macOS `atos` path
        // is unverified here; see the spec.
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: sample.path("Build/MyApp.dSYM")),
                                                withIntermediateDirectories: true)
        let linux = try await host.server.callTool("symbolicate_crash_logs",
                                                   ["logPath": .string("Logs/crash.crash"),
                                                    "dsymPath": .string("Build/MyApp.dSYM")])
        #expect(linux.isToolError && linux.firstText.contains("atos"))
#endif
    }
}
