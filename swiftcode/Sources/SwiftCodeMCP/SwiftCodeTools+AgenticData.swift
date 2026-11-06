import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
#if canImport(ApplicationServices)
import ApplicationServices
#endif
#if canImport(AppKit)
import AppKit
#endif

/// The ported Legacy Agentic data / environment / secrets / UI /
/// profiling tool family (Wave 8, slice G).
///
/// Behaviour source: Legacy's `ParseJSONTool` (`ParseJSON.swift`),
/// `ParseYAMLTool` (`ParseYAML.swift`), `ParseXMLTool`
/// (`ParseXML.swift`), `ParseMarkdownTool` (`ParseMarkdown.swift`),
/// `SQLQueryTool` (`SQLQuery.swift`),
/// `DatabaseSchemaInspectorTool` (`DatabaseSchemaInspector.swift`),
/// `DatabaseMigrationTool` (`DatabaseMigrationTool.swift`),
/// `ReadEnvironmentVariablesTool`
/// (`ReadEnvironmentVariables.swift`),
/// `UpdateEnvironmentVariablesTool`
/// (`UpdateEnvironmentVariables.swift`), `ManageSecretsTool`
/// (`ManageSecrets.swift`), `OpenBrowserTool` (`OpenBrowser.swift`),
/// `BrowserAutomationTool` (`BrowserAutomation.swift`),
/// `UIInspectorTool` (`UIInspector.swift`),
/// `AccessibilityInspectorTool` (`AccessibilityInspector.swift`),
/// `PerformanceProfilerTool` (`PerformanceProfiler.swift`),
/// `MemoryProfilerTool` (`MemoryProfiler.swift`),
/// `NetworkInspectorTool` (`NetworkInspector.swift`),
/// `CrashAnalyzerTool` (`CrashAnalyzer.swift`),
/// `SymbolicateCrashLogsTool` (`SymbolicateCrashLogs.swift`) and
/// `TakeScreenshotTool` (`TakeScreenshot.swift`) — Dylan's own
/// code, ported under MIT. See `specs/ide/agentic-data-draft.md`.
///
/// Conventions, following Waves 1–7:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter every SwiftCode tool carries. Legacy's
///   Agentic tools declare no parameter descriptions, so the
///   SwiftCode schema adds short neutral descriptions. Legacy's
///   Agentic tools declare no capability or risk level (the
///   `AgentTool` protocol carries neither), so annotations are
///   assigned by behaviour: reads are `.read`, the three writers
///   are `safeMutation` with `writes: true`, `open_browser` is an
///   external side effect (`openWorld: true`, `writes: true`).
/// * Structured data keeps Legacy's keys where Legacy had any,
///   with typed JSON values the way SwiftCode's other tools do —
///   Legacy's string-only map is not reproduced. Tools whose
///   Legacy result carries no data return a plain text result.
/// * Path resolution: database and crash-log paths use the strict
///   `resolveFileWritingPath` (trim; reject empty, NUL, a leading
///   `~` and any `..`; plain relative paths resolve against the
///   workspace root, never the session directory) for database
///   files, and the session-aware `resolveFileReadingPath` for
///   crash logs (the same resolver Wave 6's `crash_log_parse`
///   uses). No path is ever allowed to escape the workspace.
/// * Approval gating: every writing handler gates BEFORE touching
///   disk or state. `database_migration` goes through
///   `approveFileWritingChange`; `update_environment_variables`,
///   `manage_secrets` (save) and `open_browser` go through
///   `terminalApproveChange` (the Wave 4 shape for non-file
///   operations, whose change path is the workspace root). There
///   is no Autopilot bypass.
/// * Subprocesses are fixed argument vectors, never a shell.
///   `sqlite3`, `ps`, `netstat` / `ss`, `open` / `xdg-open` and
///   `atos` run by absolute path with Legacy-equivalent argv.
/// * Secrets: a secret VALUE never appears in tool output.
///   `manage_secrets` `get` reports only whether a secret exists
///   for the key; `read_environment_variables` reports variable
///   names only, never values. This is a deliberate deviation
///   from Legacy (which dumped `KEY=value` lines and returned the
///   stored secret), following the Wave 6 `secrets_scan`
///   precedent of reporting file:line:label only.
/// * Profilers and inspectors that need a live device, simulator
///   or Xcode session implement the local/static part honestly
///   and fail honestly where live capture is impossible here —
///   no measurement, query result or secret value is ever
///   invented.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `parse_json` keeps Legacy's dictionary-only rule (a JSON
///   document whose top level is not an object fails with
///   "JSON is not a dictionary"); the parsed object is returned
///   as structured data instead of Legacy's `"\(result)"` string.
/// * `parse_yaml`, `parse_xml` and `parse_markdown` were stubs in
///   Legacy (each returned a hardcoded "Parsed … (simulated)"
///   string). The port implements real parsers instead: a YAML
///   subset parser, a Foundation `XMLParser` tree builder, and a
///   structural Markdown block parser. Each documents its limits
///   in the spec; unsupported constructs fail with the exact
///   construct and line instead of pretending to parse.
/// * `sql_query` was a stub in Legacy ("Result of query: …").
///   The port runs the query for real against SQLite via the
///   `sqlite3` CLI (`-json -readonly`), and accepts read-only
///   statements only (`SELECT`, `WITH`, `EXPLAIN`); anything else
///   fails before running. Writes go through
///   `database_migration`, never through this tool.
/// * `database_schema_inspector` and `database_migration` were
///   stubs in Legacy. The port runs them for real via the
///   `sqlite3` CLI: schema from `sqlite_master` plus per-table
///   `PRAGMA table_info` / `PRAGMA foreign_key_list`, migration
///   from the migration file via `.read` with `-bail` (stops at
///   the first failing statement; the file's own transaction
///   handling applies, so a file without `BEGIN` can leave a
///   partial apply behind on error).
/// * `read_environment_variables` returns names only (see
///   "Secrets" above); Legacy returned `KEY=value` lines.
/// * `manage_secrets` `get` reports existence only (see
///   "Secrets" above); Legacy returned the stored value.
///   `save` without a `value` fails in the port (Legacy silently
///   reported "Secret saved" without saving anything). The store
///   is SwiftCode's `SecretStore` (login keychain on macOS, a 0600
///   file under `~/.config/swiftcode/secrets` on Linux).
/// * `open_browser` opens http(s) URLs only. Legacy passed any
///   string to `/usr/bin/open`; the port validates the scheme
///   first and uses `xdg-open` on Linux.
/// * `performance_profiler` and `memory_profiler` were stubs in
///   Legacy. The port takes a single live `ps` snapshot of the
///   named process (CPU %, RSS, VSZ, % memory) — real
///   measurements, but a snapshot, not a time series or a
///   sampling profiler.
/// * `network_inspector` was a stub in Legacy. The port returns
///   a snapshot of the active connection table (`netstat -an`,
///   else `ss -tan`) — it is not packet capture, and says so.
/// * `crash_analyzer` was a stub in Legacy. The port parses the
///   crash log for real, reusing Wave 6's
///   `testingParseCrashLog` (same parser as `crash_log_parse`,
///   different parameter name: `logPath`, not `path`).
/// * `symbolicate_crash_logs` was a stub in Legacy. The port
///   symbolicates for real on macOS via `atos` against the
///   dSYM's DWARF binary, using the load address from the log's
///   Binary Images section. On Linux it fails honestly naming
///   the missing `atos` (Xcode command line tools).
/// * `take_screenshot` is NOT registered here: SwiftCode already has
///   `take_screenshot` (Wave 4, `SwiftCodeTools+Terminal.swift`),
///   which is the served target for the Agentic ID — see the
///   spec. `browser_automation`, `ui_inspector` and
///   `accessibility_inspector` are registered with their full
///   Legacy schemas but always fail, naming the exact missing
///   prerequisite (no browser automation driver, no live target
///   application with accessibility access).
extension SwiftCodeMCPHost {
    var agenticDataTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let external = MCPToolAnnotations(readOnly: false, idempotent: false, openWorld: true)
        return [
            tool("parse_json", "Parse JSON",
                 "Parses a JSON string.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "json": Schema.string("JSON text to parse. The top level must be an object.")],
                                      required: ["json"]),
                 output: Schema.output(["result": Schema.anyObject]),
                 annotations: .read) { h, call in
                try h.agenticDataParseJSON(call)
            },
            tool("parse_yaml", "Parse YAML",
                 "Parses a YAML string.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "yaml": Schema.string("YAML text to parse. A subset is supported: mappings, sequences, scalars, flow collections, block scalars, anchors, aliases and merge keys; tags are rejected.")],
                                      required: ["yaml"]),
                 annotations: .read) { h, call in
                try h.agenticDataParseYAML(call)
            },
            tool("parse_xml", "Parse XML",
                 "Parses an XML string.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "xml": Schema.string("XML text to parse.")],
                                      required: ["xml"]),
                 output: Schema.output(["root": Schema.anyObject]),
                 annotations: .read) { h, call in
                try h.agenticDataParseXML(call)
            },
            tool("parse_markdown", "Parse Markdown",
                 "Parses a Markdown string.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "markdown": Schema.string("Markdown text to parse into structural blocks.")],
                                      required: ["markdown"]),
                 annotations: .read) { h, call in
                try h.agenticDataParseMarkdown(call)
            },
            tool("sql_query", "SQL Query",
                 "Executes an SQL query.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Read-only SQL statement (SELECT, WITH, or EXPLAIN)."),
                                       "databasePath": Schema.string("Workspace-relative path to the SQLite database file.")],
                                      required: ["query", "databasePath"]),
                 output: Schema.output(["rows": Schema.anyArray, "rowCount": Schema.int]),
                 annotations: .read) { h, call in
                try await h.agenticDataSQLQuery(call)
            },
            tool("database_schema_inspector", "Database Schema Inspector",
                 "Inspects the schema of a database.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "databasePath": Schema.string("Workspace-relative path to the SQLite database file.")],
                                      required: ["databasePath"]),
                 output: Schema.output(["tables": Schema.anyArray, "views": Schema.anyArray, "indexes": Schema.anyArray,
                                        "tableCount": Schema.int]),
                 annotations: .read) { h, call in
                try await h.agenticDataDatabaseSchemaInspector(call)
            },
            tool("database_migration", "Database Migration",
                 "Applies a database migration.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "databasePath": Schema.string("Workspace-relative path to the SQLite database file. Created when it does not exist."),
                                       "migrationPath": Schema.string("Workspace-relative path to the SQL migration file to apply.")],
                                      required: ["databasePath", "migrationPath"]),
                 output: Schema.output(["database": Schema.str, "migration": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticDataDatabaseMigration(call)
            },
            tool("read_environment_variables", "Read Environment Variables",
                 "Reads environment variables.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["names": Schema.anyArray, "count": Schema.int]),
                 annotations: .read) { h, call in
                try h.agenticDataReadEnvironmentVariables(call)
            },
            tool("update_environment_variables", "Update Environment Variables",
                 "Updates environment variables.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "variables": ["type": "object", "additionalProperties": ["type": "string"],
                                                     "description": "Variable names mapped to their new string values."]],
                                      required: ["variables"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticDataUpdateEnvironmentVariables(call)
            },
            tool("manage_secrets", "Manage Secrets",
                 "Manages secrets in the keychain.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'save' stores a secret, 'get' reports whether one is stored.", oneOf: ["save", "get"]),
                                       "key": Schema.string("Secret name."),
                                       "value": Schema.string("Secret value for 'save'. Never echoed back in tool output.")],
                                      required: ["action", "key"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticDataManageSecrets(call)
            },
            tool("open_browser", "Open Browser",
                 "Opens a URL in the default browser.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "url": Schema.string("http(s) URL to open in the default browser.")],
                                      required: ["url"]),
                 annotations: external, writes: true) { h, call in
                try await h.agenticDataOpenBrowser(call)
            },
            tool("browser_automation", "Browser Automation",
                 "Evaluates a JavaScript snippet in the front tab of Safari (macOS).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "script": Schema.string("JavaScript to evaluate in Safari's front document. The result is returned as text."),
                                       "url": Schema.string("Optional URL to open in Safari before evaluating the script.")],
                                      required: ["script"]),
                 annotations: external, writes: true) { h, call in
                try await h.agenticDataBrowserAutomation(call)
            },
            tool("ui_inspector", "UI Inspector",
                 "Inspects the UI hierarchy of a running macOS application through the accessibility API.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "app": Schema.string("Bundle identifier or process name of the app to inspect. Default: the frontmost app."),
                                       "maxDepth": Schema.integer("Maximum tree depth to walk. Default: 6, maximum: 10.")]),
                 annotations: .read) { h, call in
                try h.agenticDataUIInspector(call)
            },
            tool("accessibility_inspector", "Accessibility Inspector",
                 "Inspects accessibility properties of a running macOS application through the accessibility API.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "app": Schema.string("Bundle identifier or process name of the app to inspect. Default: the frontmost app."),
                                       "maxDepth": Schema.integer("Maximum tree depth to walk. Default: 6, maximum: 10.")]),
                 annotations: .read) { h, call in
                try h.agenticDataAccessibilityInspector(call)
            },
            tool("performance_profiler", "Performance Profiler",
                 "Profiles the performance of a process.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "pid": Schema.integer("Process ID to profile.", minimum: 1)],
                                      required: ["pid"]),
                 output: Schema.output(["pid": Schema.int, "cpuPercent": ["type": "number"], "rssBytes": Schema.int,
                                        "vszBytes": Schema.int, "command": Schema.str]),
                 annotations: .read) { h, call in
                try await h.agenticDataPerformanceProfiler(call)
            },
            tool("memory_profiler", "Memory Profiler",
                 "Profiles the memory usage of a process.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "pid": Schema.integer("Process ID to profile.", minimum: 1)],
                                      required: ["pid"]),
                 output: Schema.output(["pid": Schema.int, "rssBytes": Schema.int, "vszBytes": Schema.int,
                                        "memPercent": ["type": "number"], "command": Schema.str]),
                 annotations: .read) { h, call in
                try await h.agenticDataMemoryProfiler(call)
            },
            tool("network_inspector", "Network Inspector",
                 "Inspects network traffic.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["connections": Schema.anyArray, "connectionCount": Schema.int, "source": Schema.str]),
                 annotations: .read) { h, call in
                try await h.agenticDataNetworkInspector(call)
            },
            tool("crash_analyzer", "Crash Analyzer",
                 "Analyzes crash logs.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "logPath": Schema.string("Workspace-relative path to the .crash or .ips file.")],
                                      required: ["logPath"]),
                 output: Schema.output(["hasException": Schema.bool, "frameCount": Schema.int]),
                 annotations: .read) { h, call in
                try h.agenticDataCrashAnalyzer(call)
            },
            tool("symbolicate_crash_logs", "Symbolicate Crash Logs",
                 "Symbolicates crash logs.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "logPath": Schema.string("Workspace-relative path to the .crash file."),
                                       "dsymPath": Schema.string("Workspace-relative path to the .dSYM bundle (or the DWARF binary itself).")],
                                      required: ["logPath", "dsymPath"]),
                 output: Schema.output(["symbolicatedFrames": Schema.anyArray, "frameCount": Schema.int]),
                 annotations: .read) { h, call in
                try await h.agenticDataSymbolicateCrashLogs(call)
            },
        ]
    }
}

// MARK: - Shared helpers (all `agenticData`-prefixed)

extension SwiftCodeMCPHost {
    /// Test seam for `manage_secrets`: when set, the secret store
    /// used instead of `defaultSecretStore()`. Tests set a
    /// `MemorySecretStore` so no real keychain or config file is
    /// touched; production never sets it.
    static var agenticDataTestSecretStore: SecretStore?

    /// The secret store for `manage_secrets`.
    static func agenticDataSecretStore() -> SecretStore {
        agenticDataTestSecretStore ?? defaultSecretStore()
    }

    /// The `sqlite3` CLI, or `nil` when it is not installed.
    nonisolated static func agenticDataSQLite3Executable() -> String? {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3") ? "/usr/bin/sqlite3" : nil
    }

    /// Runs `sqlite3` with a fixed argument vector (120-second
    /// timeout, via the Wave 5 runner). `nil` when the process
    /// cannot start at all.
    func agenticDataRunSQLite3(_ args: [String]) async -> TerminalFixedRun? {
        await archiveRunFixed("/usr/bin/sqlite3", args)
    }

    /// A `sqlite3` run that must succeed: start failure, timeout
    /// and a non-zero exit all become a tool error naming the
    /// operation. A zero-exit run with empty stdout is a success
    /// with no rows (that is what `sqlite3 -json` prints for an
    /// empty result).
    func agenticDataRequireSQLite3(_ args: [String], what: String) async throws -> String {
        guard Self.agenticDataSQLite3Executable() != nil else {
            throw MCPToolError("\(what) needs the `sqlite3` command-line tool, which is not installed on this system.")
        }
        guard let run = await agenticDataRunSQLite3(args) else {
            throw MCPToolError("Failed to execute sqlite3: could not start /usr/bin/sqlite3")
        }
        if run.timedOut {
            throw MCPToolError("sqlite3 timed out after 120 seconds while \(what).")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("\(what) failed: \(run.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return run.stdout
    }

    /// Parses `sqlite3 -json` output (an array of objects, or
    /// empty output for zero rows) into `AnyJSON`.
    nonisolated static func agenticDataParseSQLiteJSON(_ stdout: String, what: String) throws -> [AnyJSON] {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let parsed: AnyJSON
        do {
            parsed = try AnyJSON.parse(Data(trimmed.utf8))
        } catch {
            throw MCPToolError("Could not parse sqlite3 output while \(what): \(error)")
        }
        guard let rows = parsed.array else {
            throw MCPToolError("Unexpected sqlite3 output while \(what): expected a JSON array.")
        }
        return rows
    }

    /// One live `ps` snapshot of a process.
    struct AgenticDataProcessSample {
        let pid: Int
        let cpuPercent: Double
        let rssBytes: Int
        let vszBytes: Int
        let memPercent: Double
        let command: String
    }

    /// Samples a process with `/bin/ps -o
    /// pid=,%cpu=,rss=,vsz=,%mem=,comm= -p <pid>` (the same
    /// columns on macOS and Linux; `rss`/`vsz` are KiB). Throws
    /// when `ps` is missing, the pid is invalid, or no such
    /// process is visible.
    func agenticDataSampleProcess(pid: Int) async throws -> AgenticDataProcessSample {
        guard pid >= 1 else {
            throw MCPToolError("Invalid pid '\(pid)': expected a process ID of 1 or more.")
        }
        guard FileManager.default.isExecutableFile(atPath: "/bin/ps") else {
            throw MCPToolError("Process profiling needs the `ps` command-line tool, which is not installed on this system.")
        }
        guard let run = await archiveRunFixed("/bin/ps",
                                              ["-o", "pid=,%cpu=,rss=,vsz=,%mem=,comm=", "-p", "\(pid)"]) else {
            throw MCPToolError("Failed to execute ps: could not start /bin/ps")
        }
        if run.timedOut {
            throw MCPToolError("ps timed out after 120 seconds while sampling process \(pid).")
        }
        let line = run.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard run.exitCode == 0, !line.isEmpty else {
            throw MCPToolError("No running process with pid \(pid) was found (or it is not visible to this user).")
        }
        // Five fields, then the command name (which may contain
        // spaces, so the split stops after the fifth field).
        let parts = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        guard parts.count == 6,
              let foundPid = Int(parts[0]), foundPid == pid,
              let cpu = Double(parts[1]), let rssKB = Int(parts[2]), let vszKB = Int(parts[3]),
              let mem = Double(parts[4]) else {
            throw MCPToolError("Could not parse ps output for process \(pid): '\(line)'.")
        }
        return AgenticDataProcessSample(pid: pid, cpuPercent: cpu, rssBytes: rssKB * 1024, vszBytes: vszKB * 1024,
                                        memPercent: mem, command: String(parts[5]))
    }

    /// One row of the active connection table.
    struct AgenticDataConnection {
        let proto: String
        let local: String
        let foreign: String
        let state: String
    }

    /// Parses `netstat -an` output: header lines and UNIX-domain
    /// rows are skipped; TCP rows carry a state, UDP rows do not.
    nonisolated static func agenticDataParseNetstat(_ text: String) -> [AgenticDataConnection] {
        var rows: [AgenticDataConnection] = []
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5, parts[0].hasPrefix("tcp") || parts[0].hasPrefix("udp") else { continue }
            let state = parts.count >= 6 ? parts[5] : ""
            rows.append(AgenticDataConnection(proto: parts[0], local: parts[3], foreign: parts[4], state: state))
        }
        return rows
    }

    /// Parses `ss -tan` output: the header line is skipped; each
    /// row is `State Recv-Q Send-Q Local Peer [Process]`.
    nonisolated static func agenticDataParseSS(_ text: String) -> [AgenticDataConnection] {
        var rows: [AgenticDataConnection] = []
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5, parts[0] != "State" else { continue }
            rows.append(AgenticDataConnection(proto: "tcp", local: parts[3], foreign: parts[4], state: parts[0]))
        }
        return rows
    }
}

// MARK: - Legacy's YAML subset (ported, not a full parser)

/// One non-blank, non-comment line of a YAML document.
struct AgenticDataYAMLLine {
    let indent: Int
    let content: String
    let number: Int
}

/// A YAML subset parser: block mappings and sequences by
/// indentation, plain / single- / double-quoted scalars, `null` /
/// booleans / integers / doubles, flow collections (`[a, b]`,
/// `{k: v}`), block scalars (`|` literal / `>` folded, with
/// chomping and explicit indent indicators), anchors (`&name`),
/// aliases (`*name`), and merge keys (`<<: *name`). Tags,
/// multi-document streams beyond `---` / `...` separators, and
/// tab indentation are rejected with the line number. Duplicate
/// mapping keys are rejected, as in YAML. Full YAML 1.2 needs the
/// Yams dependency (see the Package.swift wiring list); this
/// subset covers the shapes real configs use.
struct AgenticDataYAMLParser {
    var lines: [AgenticDataYAMLLine]
    var rawLines: [String]
    var anchors: [String: AnyJSON] = [:]
    var index: Int = 0

    init(text: String) throws {
        rawLines = text.components(separatedBy: .newlines)
        var parsed: [AgenticDataYAMLLine] = []
        for (offset, rawLine) in rawLines.enumerated() {
            let number = offset + 1
            let leading = rawLine.prefix(while: { $0 == " " || $0 == "\t" })
            if leading.contains("\t") {
                throw MCPToolError("YAML line \(number): tab used for indentation (YAML requires spaces).")
            }
            let indent = rawLine.prefix(while: { $0 == " " }).count
            let stripped = Self.stripComment(String(rawLine.dropFirst(indent)))
            let content = stripped.trimmingCharacters(in: .whitespaces)
            if content.isEmpty { continue }
            if content == "---" || content == "..." { continue }
            parsed.append(AgenticDataYAMLLine(indent: indent, content: content, number: number))
        }
        lines = parsed
    }

    /// Strips a trailing `#` comment: a `#` at the start of the
    /// line, or preceded by a space or tab, outside quotes.
    static func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        var escaped = false
        var previous: Character? = nil
        for (offset, ch) in line.enumerated() {
            if escaped {
                escaped = false
            } else if inSingle {
                if ch == "'" { inSingle = false }
            } else if inDouble {
                if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inDouble = false
                }
            } else if ch == "'" {
                inSingle = true
            } else if ch == "\"" {
                inDouble = true
            } else if ch == "#" && (offset == 0 || previous == " " || previous == "\t") {
                return String(line.prefix(offset))
            }
            previous = ch
        }
        return line
    }

    mutating func parseDocument() throws -> AnyJSON {
        guard index < lines.count else { return .null }
        return try parseBlock(at: lines[index].indent)
    }

    /// Parses the block starting at `index`, whose lines share
    /// `indent` (a mapping, a sequence, or a lone scalar).
    mutating func parseBlock(at indent: Int) throws -> AnyJSON {
        guard index < lines.count else { return .null }
        let line = lines[index]
        guard line.indent == indent else {
            throw MCPToolError("YAML line \(line.number): unexpected indentation.")
        }
        if line.content == "-" || line.content.hasPrefix("- ") {
            return try parseSequence(at: indent)
        }
        if Self.isMappingLine(line.content) {
            return try parseMapping(at: indent)
        }
        index += 1
        let (anchor, anchorRest) = Self.splitAnchorPrefix(line.content)
        if let header = Self.parseBlockScalarHeader(anchorRest) {
            let text = try collectBlockScalar(header: header, headerLine: line.number, parentIndent: indent)
            let value: AnyJSON = .string(text)
            if let anchor { anchors[anchor] = value }
            return value
        }
        if anchorRest.isEmpty, anchor != nil {
            if index < lines.count, lines[index].indent > indent {
                let value = try parseBlock(at: lines[index].indent)
                if let anchor { anchors[anchor] = value }
                return value
            }
            return .null
        }
        return try scalar(anchorRest, line: line.number)
    }

    mutating func parseSequence(at indent: Int) throws -> AnyJSON {
        var items: [AnyJSON] = []
        while index < lines.count {
            let line = lines[index]
            guard line.indent == indent, line.content == "-" || line.content.hasPrefix("- ") else { break }
            let rest = line.content == "-"
                ? ""
                : String(line.content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                index += 1
                if index < lines.count, lines[index].indent > indent {
                    items.append(try parseBlock(at: lines[index].indent))
                } else {
                    items.append(.null)
                }
            } else if rest == "-" || rest.hasPrefix("- ") {
                // A nested sequence on the same line ("- - a"):
                // rewrite it as a virtual line one level deeper.
                lines[index] = AgenticDataYAMLLine(indent: indent + 2, content: rest, number: line.number)
                items.append(try parseBlock(at: indent + 2))
            } else if Self.isMappingLine(rest) {
                // A mapping starting on the item line ("- name: x"):
                // rewrite it as a virtual mapping line one level
                // deeper; the following deeper lines belong to it.
                lines[index] = AgenticDataYAMLLine(indent: indent + 2, content: rest, number: line.number)
                items.append(try parseMapping(at: indent + 2))
            } else {
                index += 1
                let (anchor, anchorRest) = Self.splitAnchorPrefix(rest)
                if let header = Self.parseBlockScalarHeader(anchorRest) {
                    let text = try collectBlockScalar(header: header, headerLine: line.number, parentIndent: indent)
                    let value: AnyJSON = .string(text)
                    if let anchor { anchors[anchor] = value }
                    items.append(value)
                } else if anchorRest.isEmpty {
                    let value: AnyJSON
                    if index < lines.count, lines[index].indent > indent {
                        value = try parseBlock(at: lines[index].indent)
                    } else {
                        value = .null
                    }
                    if let anchor { anchors[anchor] = value }
                    items.append(value)
                } else {
                    let value = try scalar(anchorRest, line: line.number)
                    if let anchor { anchors[anchor] = value }
                    items.append(value)
                }
            }
        }
        return .array(items)
    }

    mutating func parseMapping(at indent: Int) throws -> AnyJSON {
        var object: [String: AnyJSON] = [:]
        // Merge keys (`<<: *name`) are applied after the loop so
        // explicit keys always win, wherever `<<` appears.
        var pendingMerges: [(value: AnyJSON, line: Int)] = []
        while index < lines.count {
            let line = lines[index]
            guard line.indent == indent, Self.isMappingLine(line.content) else { break }
            let (key, valueText) = Self.splitMapping(line.content)
            guard let key, !key.isEmpty else {
                throw MCPToolError("YAML line \(line.number): empty mapping key.")
            }
            guard object[key] == nil else {
                throw MCPToolError("YAML line \(line.number): duplicate mapping key '\(key)'.")
            }
            index += 1
            if key == "<<" {
                pendingMerges.append((try scalar(valueText, line: line.number), line.number))
                continue
            }
            let (anchor, anchorRest) = Self.splitAnchorPrefix(valueText)
            if let header = Self.parseBlockScalarHeader(anchorRest) {
                let text = try collectBlockScalar(header: header, headerLine: line.number, parentIndent: indent)
                let value: AnyJSON = .string(text)
                if let anchor { anchors[anchor] = value }
                object[key] = value
            } else if anchorRest.isEmpty {
                // `key:` or `key: &name` — the value is the
                // following block (or null).
                let value: AnyJSON
                if index < lines.count, lines[index].indent > indent {
                    value = try parseBlock(at: lines[index].indent)
                } else {
                    value = .null
                }
                if let anchor { anchors[anchor] = value }
                object[key] = value
            } else {
                let value = try scalar(anchorRest, line: line.number)
                if let anchor { anchors[anchor] = value }
                object[key] = value
            }
        }
        for merge in pendingMerges {
            switch merge.value {
            case .object(let dict):
                for (k, v) in dict where object[k] == nil { object[k] = v }
            case .array(let items):
                for item in items {
                    guard case .object(let dict) = item else {
                        throw MCPToolError("YAML line \(merge.line): merge key '<<' must reference a mapping or a sequence of mappings.")
                    }
                    for (k, v) in dict where object[k] == nil { object[k] = v }
                }
            default:
                throw MCPToolError("YAML line \(merge.line): merge key '<<' must reference a mapping or a sequence of mappings.")
            }
        }
        return .object(object)
    }

    /// A mapping line: a top-level colon followed by a space or
    /// the end of the line (so `http://x` and `key:value` are
    /// plain scalars, not mappings).
    static func isMappingLine(_ content: String) -> Bool {
        Self.splitMapping(content).key != nil
    }

    /// Splits `key: value` on the first top-level colon, or
    /// returns `nil` when the line is not a mapping line. The key
    /// may be single- or double-quoted.
    static func splitMapping(_ content: String) -> (key: String?, value: String) {
        var inSingle = false
        var inDouble = false
        var depth = 0
        var cursor = content.startIndex
        while cursor < content.endIndex {
            let ch = content[cursor]
            if inSingle {
                if ch == "'" { inSingle = false }
            } else if inDouble {
                if ch == "\"" { inDouble = false }
            } else if ch == "'" {
                inSingle = true
            } else if ch == "\"" {
                inDouble = true
            } else if ch == "[" || ch == "{" {
                depth += 1
            } else if ch == "]" || ch == "}" {
                depth -= 1
            } else if ch == ":" && depth == 0 {
                let next = content.index(after: cursor)
                if next == content.endIndex || content[next] == " " {
                    let rawKey = String(content[..<cursor]).trimmingCharacters(in: .whitespaces)
                    let key = unquoteKey(rawKey)
                    let value = next == content.endIndex
                        ? "" : String(content[next...]).trimmingCharacters(in: .whitespaces)
                    return (key, value)
                }
            }
            cursor = content.index(after: cursor)
        }
        return (nil, content)
    }

    /// Splits an optional `&name` anchor prefix off a value.
    /// Returns (anchor name, rest). `&` with no name is not an
    /// anchor and is returned untouched.
    static func splitAnchorPrefix(_ text: String) -> (String?, String) {
        guard text.hasPrefix("&") else { return (nil, text) }
        let afterAmp = text.dropFirst()
        let name = afterAmp.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        guard !name.isEmpty else { return (nil, text) }
        let rest = afterAmp.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
        return (String(name), rest)
    }

    /// Parses a block-scalar header (`|`, `>`, with optional
    /// chomping `-`/`+` and an explicit indent indicator).
    /// Returns (literal, chomping, indent indicator), or nil when
    /// the text is not a block-scalar header.
    static func parseBlockScalarHeader(_ text: String) -> (literal: Bool, chomping: Character?, indent: Int?)? {
        var rest = text
        guard rest.first == "|" || rest.first == ">" else { return nil }
        let literal = rest.first == "|"
        rest.removeFirst()
        var chomping: Character?
        var indent: Int?
        for ch in rest {
            if ch == "-" || ch == "+" {
                guard chomping == nil else { return nil }
                chomping = ch
            } else if let digit = ch.wholeNumberValue {
                guard indent == nil else { return nil }
                indent = digit
            } else if ch == " " {
                continue
            } else {
                return nil
            }
        }
        return (literal, chomping, indent)
    }

    /// Collects a block scalar's raw lines following the header at
    /// `headerLine` (1-based), whose parent block sits at
    /// `parentIndent`, and folds them per the header (literal
    /// keeps newlines; folded turns single newlines into spaces,
    /// keeping newlines around blank or more-indented lines).
    /// Chomping: clip (default) keeps one trailing newline, strip
    /// (`-`) keeps none, keep (`+`) keeps them all. Advances
    /// `index` past the consumed lines.
    mutating func collectBlockScalar(header: (literal: Bool, chomping: Character?, indent: Int?),
                                    headerLine: Int, parentIndent: Int) throws -> String {
        var collected: [(indent: Int, text: String, number: Int)] = []
        var n = headerLine + 1
        while n <= rawLines.count {
            let raw = rawLines[n - 1]
            let isBlank = raw.trimmingCharacters(in: .whitespaces).isEmpty
            let indent = raw.prefix(while: { $0 == " " }).count
            if !isBlank && indent <= parentIndent { break }
            collected.append((indent, raw, n))
            n += 1
        }
        let lastNumber = collected.last?.number ?? headerLine
        while index < lines.count && lines[index].number <= lastNumber { index += 1 }
        let contentLines = collected.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let blockIndent: Int
        if let explicit = header.indent {
            blockIndent = parentIndent + explicit
        } else {
            blockIndent = contentLines.first?.indent ?? (parentIndent + 1)
        }
        var stripped: [String] = []
        for entry in collected {
            if entry.text.trimmingCharacters(in: .whitespaces).isEmpty {
                stripped.append("")
            } else {
                stripped.append(String(entry.text.dropFirst(min(blockIndent, entry.indent))))
            }
        }
        var trailingBlanks = 0
        while trailingBlanks < stripped.count && stripped[stripped.count - 1 - trailingBlanks].isEmpty {
            trailingBlanks += 1
        }
        let body = Array(stripped.dropLast(trailingBlanks))
        var result: String
        if header.literal {
            result = body.joined(separator: "\n")
        } else {
            var out = ""
            for (i, line) in body.enumerated() {
                if i > 0 {
                    let prev = body[i - 1]
                    if line.isEmpty || prev.isEmpty || prev.hasPrefix(" ") || line.hasPrefix(" ") {
                        out.append("\n")
                    } else {
                        out.append(" ")
                    }
                }
                out.append(line)
            }
            result = out
        }
        switch header.chomping {
        case "-":
            break
        case "+":
            result += result.isEmpty
                ? String(repeating: "\n", count: trailingBlanks)
                : String(repeating: "\n", count: trailingBlanks + 1)
        default:
            if !result.isEmpty { result += "\n" }
        }
        return result
    }

    static func unquoteKey(_ raw: String) -> String {
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
            return String(raw.dropFirst().dropLast())
        }
        if raw.count >= 2, raw.hasPrefix("'"), raw.hasSuffix("'") {
            return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return raw
    }

    /// One scalar value: `null` / booleans / integers / doubles /
    /// quoted strings / flow collections / plain strings, plus
    /// aliases (`*name`) resolved against the anchors seen so
    /// far. Anything with an unsupported leading indicator fails
    /// (tags, `%` directives, block scalars outside a value
    /// position — those are intercepted by the caller).
    func scalar(_ raw: String, line: Int) throws -> AnyJSON {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text == "~" || text == "null" || text == "Null" || text == "NULL" { return .null }
        if text == "true" || text == "True" || text == "TRUE" { return .bool(true) }
        if text == "false" || text == "False" || text == "FALSE" { return .bool(false) }
        if text.hasPrefix("*") {
            let name = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let anchored = anchors[name] else {
                throw MCPToolError("YAML line \(line): unknown alias '*\(name)'.")
            }
            return anchored
        }
        if let first = text.first, "!|>%@`".contains(first) {
            throw MCPToolError("YAML line \(line): unsupported YAML construct ('\(first)' — tags, directives and block scalars outside a value position are not supported by this subset parser).")
        }
        if text.hasPrefix("\"") {
            guard text.count >= 2, text.hasSuffix("\"") else {
                throw MCPToolError("YAML line \(line): unterminated double-quoted string.")
            }
            return .string(Self.unescapeDoubleQuoted(String(text.dropFirst().dropLast())))
        }
        if text.hasPrefix("'") {
            guard text.count >= 2, text.hasSuffix("'") else {
                throw MCPToolError("YAML line \(line): unterminated single-quoted string.")
            }
            return .string(String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'"))
        }
        if text.hasPrefix("[") {
            guard text.hasSuffix("]") else {
                throw MCPToolError("YAML line \(line): unterminated flow sequence.")
            }
            let items = try Self.splitFlow(String(text.dropFirst().dropLast())).map { try scalar($0, line: line) }
            return .array(items)
        }
        if text.hasPrefix("{") {
            guard text.hasSuffix("}") else {
                throw MCPToolError("YAML line \(line): unterminated flow mapping.")
            }
            var object: [String: AnyJSON] = [:]
            for item in Self.splitFlow(String(text.dropFirst().dropLast())) {
                let (key, value) = Self.splitMapping(item)
                guard let key, !key.isEmpty else {
                    throw MCPToolError("YAML line \(line): flow mapping entry '\(item)' has no key.")
                }
                object[key] = try scalar(value, line: line)
            }
            return .object(object)
        }
        if let int = Int(text) { return .int(int) }
        if let double = Double(text), text.contains(".") || text.contains("e") || text.contains("E") {
            return .double(double)
        }
        return .string(text)
    }

    /// Splits a flow collection's inside on top-level commas
    /// (quote- and bracket-aware).
    static func splitFlow(_ text: String) -> [String] {
        var items: [String] = []
        var depth = 0
        var inSingle = false
        var inDouble = false
        var current = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let ch = text[cursor]
            if inSingle {
                current.append(ch)
                if ch == "'" { inSingle = false }
            } else if inDouble {
                current.append(ch)
                if ch == "\\" {
                    let next = text.index(after: cursor)
                    if next < text.endIndex {
                        current.append(text[next])
                        cursor = next
                    }
                } else if ch == "\"" {
                    inDouble = false
                }
            } else if ch == "'" {
                inSingle = true
                current.append(ch)
            } else if ch == "\"" {
                inDouble = true
                current.append(ch)
            } else if ch == "[" || ch == "{" {
                depth += 1
                current.append(ch)
            } else if ch == "]" || ch == "}" {
                depth -= 1
                current.append(ch)
            } else if ch == "," && depth == 0 {
                items.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
            cursor = text.index(after: cursor)
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        // A trailing comma adds no item ("[a,]" is ["a"]); an
        // empty slot before a comma does ("[,]" is [null, null]).
        if !last.isEmpty || items.last?.isEmpty == true { items.append(last) }
        return items
    }

    /// The escapes a double-quoted YAML scalar understands.
    /// Unknown escapes keep the escaped character itself.
    static func unescapeDoubleQuoted(_ text: String) -> String {
        var out = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let ch = text[cursor]
            if ch == "\\" {
                let next = text.index(after: cursor)
                guard next < text.endIndex else { break }
                switch text[next] {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "0": out.append("\0")
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                case "/": out.append("/")
                default: out.append(text[next])
                }
                cursor = text.index(after: next)
            } else {
                out.append(ch)
                cursor = text.index(after: cursor)
            }
        }
        return out
    }
}

// MARK: - Markdown structure (subset, not a renderer)

extension SwiftCodeMCPHost {
    /// Splits Markdown into structural blocks: ATX headings,
    /// fenced code blocks, lists (flat — nested items are
    /// separate items), blockquotes, horizontal rules and
    /// paragraphs. Links and images are collected separately.
    /// Tables, reference-style links, HTML blocks and nested
    /// emphasis are not parsed: their lines become paragraphs.
    nonisolated static func agenticDataParseMarkdown(_ text: String) -> (blocks: [AnyJSON], headings: [String], links: [AnyJSON]) {
        var blocks: [AnyJSON] = []
        var headings: [String] = []
        var links: [AnyJSON] = []
        let lines = text.components(separatedBy: .newlines)
        var index = 0

        func collectLinks(from text: String) {
            // One pass: `!` before the bracket marks an image.
            let pattern = #"(!?)\[([^\]]+)\]\(([^)]+)\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let textRange = Range(match.range(at: 2), in: text),
                      let urlRange = Range(match.range(at: 3), in: text) else { continue }
                let isImage = match.range(at: 1).length > 0
                links.append(.object(["kind": .string(isImage ? "image" : "link"),
                                      "text": .string(String(text[textRange])),
                                      "url": .string(String(text[urlRange]).trimmingCharacters(in: .whitespaces))]))
            }
        }

        func headingLevel(of line: String) -> (level: Int, text: String)? {
            var level = 0
            for ch in line {
                if ch == "#" { level += 1 } else { break }
            }
            guard level >= 1, level <= 6 else { return nil }
            let rest = line.dropFirst(level)
            guard rest.hasPrefix(" ") || rest.isEmpty else { return nil }
            let heading = rest.trimmingCharacters(in: .whitespaces)
            guard !heading.isEmpty else { return nil }
            return (level, heading)
        }

        func isListItem(_ line: String) -> (ordered: Bool, text: String)? {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
                return (false, String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
            // Ordered: digits, a dot, a space.
            var digits = ""
            for ch in trimmed {
                if ch.isNumber { digits.append(ch) } else { break }
            }
            if !digits.isEmpty, trimmed.dropFirst(digits.count).hasPrefix(". ") {
                return (true, String(trimmed.dropFirst(digits.count + 2)).trimmingCharacters(in: .whitespaces))
            }
            return nil
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1 // the closing fence (or past the end)
                blocks.append(.object(["type": .string("code"), "language": .string(language),
                                       "text": .string(code.joined(separator: "\n"))]))
                continue
            }
            if let heading = headingLevel(of: trimmed) {
                headings.append(heading.text)
                collectLinks(from: heading.text)
                blocks.append(.object(["type": .string("heading"), "level": .int(heading.level),
                                       "text": .string(heading.text)]))
                index += 1
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.object(["type": .string("rule")]))
                index += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while index < lines.count {
                    let q = lines[index].trimmingCharacters(in: .whitespaces)
                    guard q.hasPrefix(">") else { break }
                    quote.append(String(q.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                let text = quote.joined(separator: "\n")
                collectLinks(from: text)
                blocks.append(.object(["type": .string("quote"), "text": .string(text)]))
                continue
            }
            if let item = isListItem(line) {
                var items: [String] = []
                let ordered = item.ordered
                while index < lines.count, let next = isListItem(lines[index]), next.ordered == ordered {
                    items.append(next.text)
                    collectLinks(from: next.text)
                    index += 1
                }
                // A list that changes marker kind mid-run is one
                // block per kind; the outer loop picks the rest up.
                blocks.append(.object(["type": .string("list"), "ordered": .bool(ordered),
                                       "items": .strings(items)]))
                continue
            }
            // A paragraph: consecutive lines that start no other
            // block (soft line breaks join with a space, as
            // Markdown renders them).
            var paragraph: [String] = []
            while index < lines.count {
                let p = lines[index].trimmingCharacters(in: .whitespaces)
                if p.isEmpty || p.hasPrefix("```") || headingLevel(of: p) != nil || isListItem(lines[index]) != nil
                    || p.hasPrefix(">") || p == "---" || p == "***" || p == "___" {
                    break
                }
                paragraph.append(p)
                index += 1
            }
            let text = paragraph.joined(separator: " ")
            collectLinks(from: text)
            blocks.append(.object(["type": .string("paragraph"), "text": .string(text)]))
        }
        return (blocks, headings, links)
    }
}

// MARK: - XML tree (Foundation XMLParser)

/// One XML element: its tag, attributes, element children and
/// the character data directly inside it.
final class AgenticDataXMLNode {
    let tag: String
    let attributes: [String: String]
    var children: [AgenticDataXMLNode] = []
    var text = ""

    init(tag: String, attributes: [String: String]) {
        self.tag = tag
        self.attributes = attributes
    }

    var json: AnyJSON {
        var object: [String: AnyJSON] = ["tag": .string(tag), "attributes": .object(attributes.mapValues { .string($0) })]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { object["text"] = .string(trimmed) }
        if !children.isEmpty { object["children"] = .array(children.map(\.json)) }
        return .object(object)
    }
}

final class AgenticDataXMLTreeBuilder: NSObject, XMLParserDelegate {
    private var stack: [AgenticDataXMLNode] = []
    private(set) var root: AgenticDataXMLNode?
    private(set) var parseError: Error?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        stack.append(AgenticDataXMLNode(tag: elementName, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard let node = stack.popLast() else { return }
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            root = node
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

// MARK: - Crash-log images (for symbolicate)

extension SwiftCodeMCPHost {
    /// `(name, loadAddress, arch)` for each image in a `.crash`
    /// log's Binary Images section (`0x… - 0x…  Name  arch
    /// <uuid>  /path`). `.ips` (JSON) logs have no such section.
    nonisolated static func agenticDataCrashImages(_ text: String) -> [(name: String, loadAddress: String, arch: String)] {
        var images: [(name: String, loadAddress: String, arch: String)] = []
        var inImages = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Binary Images:") {
                inImages = true
                continue
            }
            guard inImages else { continue }
            if trimmed.isEmpty { break }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5, parts[0].hasPrefix("0x"), parts[1] == "-", parts[2].hasPrefix("0x") else { continue }
            images.append((name: parts[3], loadAddress: parts[0], arch: parts[4]))
        }
        return images
    }

    /// Frame lines (`N  ImageName  0x…  …`) anywhere in the log,
    /// as `(image, address)` pairs in order, duplicates removed.
    nonisolated static func agenticDataCrashFrames(_ text: String) -> [(image: String, address: String)] {
        var frames: [(image: String, address: String)] = []
        var seen = Set<String>()
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3, parts[0].allSatisfy(\.isNumber), parts[2].hasPrefix("0x") else { continue }
            let key = "\(parts[1]) \(parts[2])"
            guard seen.insert(key).inserted else { continue }
            frames.append((image: parts[1], address: parts[2]))
        }
        return frames
    }
}

// MARK: - Handlers: parsers

extension SwiftCodeMCPHost {
    /// `parse_json`: Legacy's dictionary-only rule is kept; the
    /// parsed object is returned as structured data.
    func agenticDataParseJSON(_ call: MCPToolCall) throws -> MCPToolResult {
        _ = try session(for: call)
        let raw = try fileReadingRequiredString(call, "json")
        let parsed: AnyJSON
        do {
            parsed = try AnyJSON.parse(Data(raw.utf8))
        } catch {
            throw MCPToolError("\(error)")
        }
        guard let object = parsed.object else {
            throw MCPToolError("JSON is not a dictionary")
        }
        return .structured(["result": parsed],
                           summary: "Parsed JSON object with \(object.count) top-level key\(object.count == 1 ? "" : "s").")
    }

    /// `parse_yaml`: the subset parser above. Legacy returned a
    /// hardcoded string; this parses for real or fails naming
    /// the unsupported construct and line.
    func agenticDataParseYAML(_ call: MCPToolCall) throws -> MCPToolResult {
        _ = try session(for: call)
        let raw = try fileReadingRequiredString(call, "yaml")
        var parser = try AgenticDataYAMLParser(text: raw)
        let parsed = try parser.parseDocument()
        let keys: [String] = parsed.object.map { $0.keys.sorted() } ?? []
        var summary = "Parsed YAML"
        if parsed.object != nil {
            summary += " object with \(keys.count) top-level key\(keys.count == 1 ? "" : "s")"
        } else if let array = parsed.array {
            summary += " sequence with \(array.count) item\(array.count == 1 ? "" : "s")"
        } else if parsed.isNull {
            summary += ": empty document"
        } else {
            summary += " scalar"
        }
        summary += " (subset parser)."
        return .structured(["parsed": parsed, "topLevelKeys": .strings(keys)], summary: summary)
    }

    /// `parse_xml`: a Foundation `XMLParser` tree builder.
    /// Legacy returned a hardcoded string.
    func agenticDataParseXML(_ call: MCPToolCall) throws -> MCPToolResult {
        _ = try session(for: call)
        let raw = try fileReadingRequiredString(call, "xml")
        guard let data = raw.data(using: .utf8) else {
            throw MCPToolError("Invalid XML: not UTF-8 text.")
        }
        let builder = AgenticDataXMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse() else {
            let detail = builder.parseError.map { "\($0)" } ?? "unknown parse error"
            throw MCPToolError("Invalid XML: \(detail)")
        }
        guard let root = builder.root else {
            throw MCPToolError("Invalid XML: document has no root element.")
        }
        return .structured(["root": root.json],
                           summary: "Parsed XML document with root element <\(root.tag)>.")
    }

    /// `parse_markdown`: the structural block parser above.
    /// Legacy returned a hardcoded string.
    func agenticDataParseMarkdown(_ call: MCPToolCall) throws -> MCPToolResult {
        _ = try session(for: call)
        let raw = try fileReadingRequiredString(call, "markdown")
        let parsed = Self.agenticDataParseMarkdown(raw)
        return .structured(["blocks": .array(parsed.blocks), "headings": .strings(parsed.headings),
                            "links": .array(parsed.links)],
                           summary: "Parsed Markdown: \(parsed.blocks.count) block\(parsed.blocks.count == 1 ? "" : "s"), \(parsed.headings.count) heading\(parsed.headings.count == 1 ? "" : "s"), \(parsed.links.count) link\(parsed.links.count == 1 ? "" : "s") (subset parser).")
    }
}

// MARK: - Handlers: SQLite

extension SwiftCodeMCPHost {
    /// The first SQL keyword, ignoring leading `--` line
    /// comments and `/* */` block comments.
    nonisolated static func agenticDataSQLFirstKeyword(_ query: String) -> String {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        while true {
            if text.hasPrefix("--") {
                guard let newline = text.firstIndex(of: "\n") else { return "" }
                text = String(text[text.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if text.hasPrefix("/*") {
                guard let end = text.range(of: "*/") else { return "" }
                text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                break
            }
        }
        return text.components(separatedBy: .whitespacesAndNewlines).first?.uppercased() ?? ""
    }

    /// `sql_query`: read-only statements only, run for real via
    /// `sqlite3 -json -readonly`. Legacy returned a hardcoded
    /// string and never touched a database.
    func agenticDataSQLQuery(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let query = try fileReadingRequiredString(call, "query")
        let dbRaw = try fileReadingRequiredString(call, "databasePath")
        guard let dbURL = resolveFileWritingPath(dbRaw, in: s) else {
            throw MCPToolError("Database path is outside the workspace: \(dbRaw)")
        }
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw MCPToolError("Database file not found at: \(dbRaw)")
        }
        let first = Self.agenticDataSQLFirstKeyword(query)
        guard ["SELECT", "WITH", "EXPLAIN"].contains(first) else {
            throw MCPToolError("sql_query accepts read-only statements only (SELECT, WITH, EXPLAIN); '\(first)' is not allowed. Use database_migration for writes.")
        }
        let dbRel = fileReadingRelativePath(of: dbURL, in: s)
        let stdout = try await agenticDataRequireSQLite3(["-json", "-readonly", dbURL.path, query],
                                                         what: "Querying \(dbRel)")
        let rows = try Self.agenticDataParseSQLiteJSON(stdout, what: "querying \(dbRel)")
        return .structured(["rows": .array(rows), "rowCount": .int(rows.count)],
                           summary: "Query returned \(rows.count) row\(rows.count == 1 ? "" : "s") from \(dbRel).")
    }

    /// `PRAGMA table_info` for one table, as structured column
    /// objects (name, type, notNull, primaryKey, defaultValue).
    func agenticDataSQLiteTableColumns(dbURL: URL, table: String, dbRel: String) async throws -> [AnyJSON] {
        let quoted = "\"" + table.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let stdout = try await agenticDataRequireSQLite3(["-json", "-readonly", dbURL.path, "PRAGMA table_info(\(quoted))"],
                                                         what: "Reading columns of table \(table) in \(dbRel)")
        let rows = try Self.agenticDataParseSQLiteJSON(stdout, what: "reading columns of table \(table) in \(dbRel)")
        return rows.compactMap { row -> AnyJSON? in
            guard let d = row.object, let name = d["name"]?.string else { return nil }
            return .object(["name": .string(name), "type": .string(d["type"]?.string ?? ""),
                            "notNull": .bool((d["notnull"]?.int ?? 0) != 0),
                            "primaryKey": .bool((d["pk"]?.int ?? 0) != 0),
                            "defaultValue": d["dflt_value"] ?? .null])
        }
    }

    /// `PRAGMA foreign_key_list` for one table.
    func agenticDataSQLiteForeignKeys(dbURL: URL, table: String, dbRel: String) async throws -> [AnyJSON] {
        let quoted = "\"" + table.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let stdout = try await agenticDataRequireSQLite3(["-json", "-readonly", dbURL.path, "PRAGMA foreign_key_list(\(quoted))"],
                                                         what: "Reading foreign keys of table \(table) in \(dbRel)")
        let rows = try Self.agenticDataParseSQLiteJSON(stdout, what: "reading foreign keys of table \(table) in \(dbRel)")
        return rows.compactMap { row -> AnyJSON? in
            guard let d = row.object, let table = d["table"]?.string,
                  let from = d["from"]?.string, let to = d["to"]?.string else { return nil }
            return .object(["table": .string(table), "from": .string(from), "to": .string(to),
                            "onUpdate": .string(d["on_update"]?.string ?? ""),
                            "onDelete": .string(d["on_delete"]?.string ?? "")])
        }
    }

    /// `database_schema_inspector`: `sqlite_master` plus
    /// per-table pragmas, run for real. Legacy returned a
    /// hardcoded string and never opened the database.
    func agenticDataDatabaseSchemaInspector(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let dbRaw = try fileReadingRequiredString(call, "databasePath")
        guard let dbURL = resolveFileWritingPath(dbRaw, in: s) else {
            throw MCPToolError("Database path is outside the workspace: \(dbRaw)")
        }
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw MCPToolError("Database file not found at: \(dbRaw)")
        }
        let dbRel = fileReadingRelativePath(of: dbURL, in: s)
        let master = try await agenticDataRequireSQLite3(
            ["-json", "-readonly", dbURL.path,
             "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"],
            what: "Reading the schema of \(dbRel)")
        let objects = try Self.agenticDataParseSQLiteJSON(master, what: "reading the schema of \(dbRel)")
        var tables: [AnyJSON] = []
        var views: [String] = []
        var indexes: [String] = []
        for object in objects {
            guard let dict = object.object, let type = dict["type"]?.string, let name = dict["name"]?.string else { continue }
            switch type {
            case "table":
                let columns = try await agenticDataSQLiteTableColumns(dbURL: dbURL, table: name, dbRel: dbRel)
                let foreignKeys = try await agenticDataSQLiteForeignKeys(dbURL: dbURL, table: name, dbRel: dbRel)
                tables.append(.object(["name": .string(name), "sql": dict["sql"] ?? .null,
                                       "columns": .array(columns), "foreignKeys": .array(foreignKeys)]))
            case "view":
                views.append(name)
            case "index":
                indexes.append(name)
            default:
                break
            }
        }
        return .structured(["tables": .array(tables), "views": .strings(views), "indexes": .strings(indexes),
                            "tableCount": .int(tables.count)],
                           summary: "Schema for \(dbRel): \(tables.count) table\(tables.count == 1 ? "" : "s"), \(views.count) view\(views.count == 1 ? "" : "s"), \(indexes.count) index\(indexes.count == 1 ? "" : "es").")
    }

    /// `database_migration`: applies the migration file for real
    /// via `sqlite3 -bail <db> ".read <path>"`, approval-gated.
    /// Legacy returned a hardcoded string and applied nothing.
    /// The database file is created when it does not exist.
    func agenticDataDatabaseMigration(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let dbRaw = try fileReadingRequiredString(call, "databasePath")
        let migRaw = try fileReadingRequiredString(call, "migrationPath")
        guard let dbURL = resolveFileWritingPath(dbRaw, in: s) else {
            throw MCPToolError("Database path is outside the workspace: \(dbRaw)")
        }
        guard let migURL = resolveFileWritingPath(migRaw, in: s) else {
            throw MCPToolError("Migration path is outside the workspace: \(migRaw)")
        }
        guard FileManager.default.fileExists(atPath: migURL.path) else {
            throw MCPToolError("Migration file not found at: \(migRaw)")
        }
        let sql: String
        do {
            sql = try String(contentsOf: migURL, encoding: .utf8)
        } catch {
            throw MCPToolError("Failed to read migration file at \(migRaw): \(error.localizedDescription)")
        }
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Migration file is empty: \(migRaw)")
        }
        let dbRel = fileReadingRelativePath(of: dbURL, in: s)
        let migRel = fileReadingRelativePath(of: migURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: dbURL, relativePath: dbRel, original: nil,
                                           summary: "Apply migration \(migRel) to \(dbRel)", call: call)
        // `.read` with the quoted absolute path (spaces in the
        // path survive; the argument is a fixed argv element,
        // never a shell). `-bail` stops at the first failing
        // statement; the file's own transaction handling applies.
        let quoted = "\"" + migURL.path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        _ = try await agenticDataRequireSQLite3(["-bail", dbURL.path, ".read \(quoted)"],
                                                what: "Applying migration \(migRel) to \(dbRel)")
        noteFileWritingChanged(dbURL, in: s)
        return .structured(["database": .string(dbRel), "migration": .string(migRel)],
                           summary: "Migration applied to \(dbRel) from \(migRel).")
    }
}

// MARK: - Handlers: environment and secrets

extension SwiftCodeMCPHost {
    /// `read_environment_variables`: names only, never values.
    /// Legacy dumped `KEY=value` lines; values can be secrets,
    /// so the port reports the sorted names and the count.
    func agenticDataReadEnvironmentVariables(_ call: MCPToolCall) throws -> MCPToolResult {
        _ = try session(for: call)
        let names = ProcessInfo.processInfo.environment.keys.sorted()
        return .structured(["names": .strings(names), "count": .int(names.count)],
                           summary: "Found \(names.count) environment variable\(names.count == 1 ? "" : "s") in the MCP host process (names only; values are never reported).")
    }

    /// `update_environment_variables`: `setenv` in the host
    /// process (so children spawned afterwards inherit the new
    /// values), approval-gated. Legacy did the same `setenv`
    /// loop with no gate.
    func agenticDataUpdateEnvironmentVariables(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let variables = call.arguments["variables"]?.object, !variables.isEmpty else {
            throw MCPToolError("Missing required parameter: variables (an object mapping names to string values)")
        }
        var pairs: [(key: String, value: String)] = []
        for key in variables.keys.sorted() {
            guard !key.isEmpty, !key.contains("="), !key.contains("\0") else {
                throw MCPToolError("Invalid environment variable name '\(key)': names must be non-empty and contain no '='.")
            }
            guard let value = variables[key]?.string else {
                throw MCPToolError("Environment variable '\(key)' must have a string value.")
            }
            pairs.append((key: key, value: value))
        }
        try await terminalApproveChange(tool: call.name,
                                        summary: "Set \(pairs.count) environment variable\(pairs.count == 1 ? "" : "s") in the MCP host process: \(pairs.map { $0.key }.joined(separator: ", "))",
                                        in: s, call: call)
        for pair in pairs {
            setenv(pair.key, pair.value, 1)
        }
        return .text("Environment variables updated (\(pairs.count) variable\(pairs.count == 1 ? "" : "s"): \(pairs.map { $0.key }.joined(separator: ", "))).")
    }

    /// `manage_secrets`: `save` stores through SwiftCode's
    /// `SecretStore` (keychain on macOS, a 0600 file on Linux);
    /// `get` reports only whether a secret exists for the key —
    /// the value is never returned, never logged, never echoed.
    /// Legacy returned the stored value. An unknown action keeps
    /// Legacy's "No result" answer.
    func agenticDataManageSecrets(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let action = try fileReadingRequiredString(call, "action")
        let key = try fileReadingRequiredString(call, "key")
        let store = Self.agenticDataSecretStore()
        switch action {
        case "save":
            guard let value = call.arguments["value"]?.string, !value.isEmpty else {
                throw MCPToolError("Missing required parameter: value for action 'save'")
            }
            try await terminalApproveChange(tool: call.name,
                                            summary: "Save a secret for key '\(key)' in the secret store",
                                            in: s, call: call)
            do {
                try store.write(Data(value.utf8), for: key)
            } catch {
                throw MCPToolError("Failed to save secret for key '\(key)': \(error.localizedDescription)")
            }
            return .text("Secret saved")
        case "get":
            let stored: Data?
            do {
                stored = try store.read(key)
            } catch {
                throw MCPToolError("Failed to read secret for key '\(key)': \(error.localizedDescription)")
            }
            if stored == nil {
                return .text("No secret stored for key '\(key)'.")
            }
            return .text("Secret exists for key '\(key)'.")
        default:
            return .text("No result")
        }
    }
}

// MARK: - Handlers: browser and inspectors

extension SwiftCodeMCPHost {
    /// `open_browser`: `/usr/bin/open` on macOS, `xdg-open` on
    /// Linux, with a fixed argument vector. Only http(s) URLs:
    /// Legacy passed any string to `open`.
    func agenticDataOpenBrowser(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "url")
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"), url.host != nil else {
            throw MCPToolError("Invalid URL '\(raw)': open_browser only opens http(s) URLs.")
        }
        try await terminalApproveChange(tool: call.name, summary: "Open \(trimmed) in the default browser",
                                        in: s, call: call)
#if os(macOS)
        let opener = "/usr/bin/open"
#else
        let opener = "/usr/bin/xdg-open"
        guard FileManager.default.isExecutableFile(atPath: opener) else {
            throw MCPToolError("open_browser needs `xdg-open`, which is not installed on this system.")
        }
#endif
        guard let run = await archiveRunFixed(opener, [trimmed]) else {
            throw MCPToolError("Failed to execute \(opener): could not start it")
        }
        if run.timedOut {
            throw MCPToolError("Opening the browser timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("Failed to open \(trimmed): \((run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return .text("Opened \(trimmed)")
    }

    /// `browser_automation`: evaluates `script` as JavaScript in
    /// Safari's front document via AppleScript (`osascript`, macOS
    /// only), after the same approval gate `open_browser` uses.
    /// Legacy's `run` was a stub that returned a hardcoded string
    /// and executed nothing; there is still no WebDriver/Playwright
    /// driver here, so Safari JavaScript evaluation is the real
    /// automation path this host can offer. An optional `url` opens
    /// in Safari first. On Linux the tool fails honestly: there is
    /// no Safari to drive.
    func agenticDataBrowserAutomation(_ call: MCPToolCall) async throws -> MCPToolResult {
        let script = try fileReadingRequiredString(call, "script")
        let s = try session(for: call)
        try await terminalApproveChange(tool: call.name, summary: "Run JavaScript in Safari's front tab", in: s, call: call)
        #if os(macOS)
        if let url = call.arguments["url"]?.string, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let run = await archiveRunFixed("/usr/bin/osascript", ["-e", "tell application \"Safari\" to open location \"" + url + "\""]) else {
                throw MCPToolError("Failed to open \(url) in Safari: could not start osascript.")
            }
            guard run.exitCode == 0 else {
                throw MCPToolError("Failed to open \(url) in Safari: \((run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        // Escape the script into one AppleScript string literal.
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Safari\" to do JavaScript \"" + escaped + "\" in front document"
        guard let run = await archiveRunFixed("/usr/bin/osascript", ["-e", source]) else {
            throw MCPToolError("Failed to run JavaScript in Safari: could not start osascript.")
        }
        if run.timedOut {
            throw MCPToolError("Running JavaScript in Safari timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("Safari JavaScript failed: \((run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return .text(run.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        #else
        _ = script
        throw MCPToolError("browser_automation needs Safari on macOS; there is no browser to drive on this system. No script was executed.")
        #endif
    }

    /// `ui_inspector`: walks the accessibility tree of a running
    /// macOS app with `AXUIElement` and returns role/title/value
    /// per node (depth- and node-capped). Legacy returned a hardcoded
    /// string; this reads the live hierarchy. Requires the host to
    /// be trusted for accessibility (`AXIsProcessTrusted()`); when
    /// it is not, the tool fails naming the permission instead of
    /// returning invented UI.
    func agenticDataUIInspector(_ call: MCPToolCall) throws -> MCPToolResult {
        _ = try session(for: call)
        return try agenticDataInspectAccessibility(call, detailed: false)
    }

    /// `accessibility_inspector`: the same live `AXUIElement` walk
    /// as `ui_inspector`, plus the accessibility attributes Legacy
    /// never read (subrole, help, enabled, focused, min/max value).
    func agenticDataAccessibilityInspector(_ call: MCPToolCall) throws -> MCPToolResult {
        _ = try session(for: call)
        return try agenticDataInspectAccessibility(call, detailed: true)
    }

    /// Shared accessibility-tree walk for `ui_inspector` /
    /// `accessibility_inspector`. `detailed` adds the extra
    /// accessibility attributes.
    private func agenticDataInspectAccessibility(_ call: MCPToolCall, detailed: Bool) throws -> MCPToolResult {
        #if canImport(ApplicationServices) && os(macOS)
        guard AXIsProcessTrusted() else {
            throw MCPToolError("Accessibility access is not granted to SwiftCode: enable it in System Settings → Privacy & Security → Accessibility, then retry. No UI was inspected.")
        }
        let maxDepth = min(max(call.arguments["maxDepth"]?.int ?? 6, 1), 10)
        let pid = try agenticDataTargetPID(call)
        let appElement = AXUIElementCreateApplication(pid)
        var lines: [String] = []
        var nodeCount = 0
        agenticDataWalkAX(appElement, depth: 0, maxDepth: maxDepth, detailed: detailed, lines: &lines, nodeCount: &nodeCount)
        if lines.isEmpty {
            throw MCPToolError("No accessible UI elements were found for the target application.")
        }
        let capped = nodeCount >= 500 ? "\n(Stopped at 500 nodes; pass a smaller maxDepth for a narrower tree.)" : ""
        return .text(lines.joined(separator: "\n") + capped)
        #else
        _ = detailed
        throw MCPToolError("UI inspection needs the macOS accessibility API (ApplicationServices), which is not available on this system. No UI was inspected.")
        #endif
    }

    #if canImport(ApplicationServices) && os(macOS)
    /// The pid of the app to inspect: `app` names a bundle
    /// identifier or process name, or the frontmost app when absent.
    private func agenticDataTargetPID(_ call: MCPToolCall) throws -> pid_t {
        #if canImport(AppKit)
        let apps = NSWorkspace.shared.runningApplications
        if let name = call.arguments["app"]?.string, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let app = apps.first(where: { $0.bundleIdentifier == name || $0.localizedName == name }) {
                return app.processIdentifier
            }
            throw MCPToolError("No running application matches '\(name)'.")
        }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            throw MCPToolError("No frontmost application is running to inspect.")
        }
        return frontmost.processIdentifier
        #else
        throw MCPToolError("UI inspection needs AppKit to find the target application, which is not available here.")
        #endif
    }

    /// One node's attribute, or nil when the element does not have it.
    private func agenticDataAXValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    /// Depth-first walk of one accessibility subtree, appending one
    /// indented line per node. Stops at `maxDepth` and at 500 nodes.
    private func agenticDataWalkAX(_ element: AXUIElement, depth: Int, maxDepth: Int, detailed: Bool,
                                   lines: inout [String], nodeCount: inout Int) {
        guard depth <= maxDepth, nodeCount < 500 else { return }
        nodeCount += 1
        let indent = String(repeating: "  ", count: depth)
        var parts: [String] = []
        if let role = agenticDataAXValue(element, kAXRoleAttribute as String) as? String { parts.append(role) }
        if let title = agenticDataAXValue(element, kAXTitleAttribute as String) as? String, !title.isEmpty { parts.append("\"" + title + "\"") }
        if let value = agenticDataAXValue(element, kAXValueAttribute as String) as? String, !value.isEmpty { parts.append("value=\"" + value + "\"") }
        if detailed {
            if let subrole = agenticDataAXValue(element, kAXSubroleAttribute as String) as? String, !subrole.isEmpty { parts.append("subrole=\(subrole)") }
            if let help = agenticDataAXValue(element, kAXHelpAttribute as String) as? String, !help.isEmpty { parts.append("help=\"" + help + "\"") }
            if let enabled = agenticDataAXValue(element, kAXEnabledAttribute as String) as? Bool { parts.append("enabled=\(enabled)") }
            if let focused = agenticDataAXValue(element, kAXFocusedAttribute as String) as? Bool, focused { parts.append("focused") }
        }
        if !parts.isEmpty { lines.append(indent + parts.joined(separator: " ")) }
        guard let children = agenticDataAXValue(element, kAXChildrenAttribute as String) as? [AXUIElement] else { return }
        for child in children {
            agenticDataWalkAX(child, depth: depth + 1, maxDepth: maxDepth, detailed: detailed, lines: &lines, nodeCount: &nodeCount)
            guard nodeCount < 500 else { return }
        }
    }
    #endif
}

// MARK: - Handlers: profilers, network, crashes

extension SwiftCodeMCPHost {
    /// Runs `netstat` or `ss` with a fixed argument vector and
    /// returns stdout; start failure, timeout and a non-zero
    /// exit all become tool errors naming the command.
    func agenticDataRunNetworkLister(_ executable: String, _ args: [String], what: String) async throws -> String {
        guard let run = await archiveRunFixed(executable, args) else {
            throw MCPToolError("Failed to execute \(what): could not start \(executable)")
        }
        if run.timedOut {
            throw MCPToolError("\(what) timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("\(what) failed: \(run.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return run.stdout
    }

    /// `performance_profiler`: a single live `ps` snapshot
    /// (CPU %, RSS, VSZ). Legacy returned a hardcoded string.
    func agenticDataPerformanceProfiler(_ call: MCPToolCall) async throws -> MCPToolResult {
        _ = try session(for: call)
        guard let pid = call.int("pid") else {
            throw MCPToolError("Missing required parameter: pid")
        }
        let sample = try await agenticDataSampleProcess(pid: pid)
        return .structured(["pid": .int(sample.pid), "cpuPercent": .double(sample.cpuPercent),
                            "rssBytes": .int(sample.rssBytes), "vszBytes": .int(sample.vszBytes),
                            "command": .string(sample.command)],
                           summary: "Process \(sample.pid) (\(sample.command)): CPU \(sample.cpuPercent)%, RSS \(sample.rssBytes) bytes, VSZ \(sample.vszBytes) bytes (single ps snapshot, not a time series).")
    }

    /// `memory_profiler`: a single live `ps` snapshot (RSS, VSZ,
    /// % of physical memory). Legacy returned a hardcoded string.
    func agenticDataMemoryProfiler(_ call: MCPToolCall) async throws -> MCPToolResult {
        _ = try session(for: call)
        guard let pid = call.int("pid") else {
            throw MCPToolError("Missing required parameter: pid")
        }
        let sample = try await agenticDataSampleProcess(pid: pid)
        return .structured(["pid": .int(sample.pid), "rssBytes": .int(sample.rssBytes),
                            "vszBytes": .int(sample.vszBytes), "memPercent": .double(sample.memPercent),
                            "command": .string(sample.command)],
                           summary: "Process \(sample.pid) (\(sample.command)): RSS \(sample.rssBytes) bytes (\(sample.memPercent)% of physical memory), VSZ \(sample.vszBytes) bytes (single ps snapshot).")
    }

    /// `network_inspector`: a snapshot of the active connection
    /// table (`netstat -an`, else `ss -tan`). That is the honest
    /// local part — live packet capture is not available in
    /// SwiftCode's MCP host, and the summary says so. Legacy
    /// returned a hardcoded string.
    func agenticDataNetworkInspector(_ call: MCPToolCall) async throws -> MCPToolResult {
        _ = try session(for: call)
        let rows: [AgenticDataConnection]
        let source: String
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/netstat") {
            let stdout = try await agenticDataRunNetworkLister("/usr/bin/netstat", ["-an"], what: "netstat")
            rows = Self.agenticDataParseNetstat(stdout)
            source = "netstat"
        } else if FileManager.default.isExecutableFile(atPath: "/usr/bin/ss") {
            let stdout = try await agenticDataRunNetworkLister("/usr/bin/ss", ["-tan"], what: "ss")
            rows = Self.agenticDataParseSS(stdout)
            source = "ss"
        } else {
            throw MCPToolError("network_inspector needs `netstat` or `ss` to list active connections, and neither is installed on this system.")
        }
        let capped = Array(rows.prefix(200))
        let jsonRows: [AnyJSON] = capped.map {
            .object(["protocol": .string($0.proto), "local": .string($0.local),
                     "foreign": .string($0.foreign), "state": .string($0.state)])
        }
        return .structured(["connections": .array(jsonRows), "connectionCount": .int(jsonRows.count),
                            "source": .string(source)],
                           summary: "Active connections (\(jsonRows.count) shown, via \(source)). This is a connection-table snapshot, not packet capture: live traffic content is not available in SwiftCode's MCP host.")
    }

    /// `crash_analyzer`: parses the crash log for real with
    /// Wave 6's `testingParseCrashLog` — the same parser as
    /// `crash_log_parse`, under the Agentic parameter name
    /// `logPath`. Legacy returned a hardcoded string.
    func agenticDataCrashAnalyzer(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["logPath"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: logPath")
        }
        let text: String
        do {
            let url = try resolveFileReadingPath(raw, in: s)
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Cannot read crash log at: \(raw)")
        }
        let parsed = Self.testingParseCrashLog(text)
        if parsed.exception.isEmpty && parsed.terminationReason.isEmpty && parsed.frames.isEmpty {
            throw MCPToolError("No crash metadata recognized in \(raw). Expected .crash or .ips format.")
        }
        var lines = ["Crash log analysis for \(raw):"]
        if !parsed.exception.isEmpty { lines.append("- \(parsed.exception)") }
        if !parsed.terminationReason.isEmpty { lines.append("- \(parsed.terminationReason)") }
        if !parsed.crashedThread.isEmpty { lines.append("- \(parsed.crashedThread)") }
        if !parsed.frames.isEmpty {
            lines.append("Top blamed frames:")
            lines += parsed.frames.map { "  \($0)" }
        }
        return .structured(["hasException": .bool(!parsed.exception.isEmpty), "frameCount": .int(parsed.frames.count)],
                           summary: lines.joined(separator: "\n"))
    }

    /// `symbolicate_crash_logs`: on macOS, symbolicates the
    /// crashed frames that belong to the dSYM's binary for real
    /// via `atos`, using the load address from the log's Binary
    /// Images section. On Linux it fails honestly naming the
    /// missing `atos`. Legacy returned a hardcoded string and
    /// symbolicated nothing. The macOS path is unverified in
    /// this environment (Linux only); see the spec.
    func agenticDataSymbolicateCrashLogs(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let logRaw = try fileReadingRequiredString(call, "logPath")
        let dsymRaw = try fileReadingRequiredString(call, "dsymPath")
        let logURL = try resolveFileReadingPath(logRaw, in: s)
        let logText: String
        do {
            logText = try String(contentsOf: logURL, encoding: .utf8)
        } catch {
            throw MCPToolError("Cannot read crash log at: \(logRaw)")
        }
        let dsymURL = try resolveFileReadingPath(dsymRaw, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dsymURL.path, isDirectory: &isDir) else {
            throw MCPToolError("dSYM not found at: \(dsymRaw)")
        }
#if os(macOS)
        // Resolve the DWARF binary: a .dSYM bundle holds it at
        // Contents/Resources/DWARF/<name>; a plain file is used
        // as-is.
        let binaryURL: URL
        if isDir.boolValue {
            let dwarf = dsymURL.appendingPathComponent("Contents/Resources/DWARF")
            let candidates = (try? FileManager.default.contentsOfDirectory(at: dwarf, includingPropertiesForKeys: nil)) ?? []
            if candidates.isEmpty {
                throw MCPToolError("No DWARF binary found in dSYM at: \(dsymRaw)")
            } else if candidates.count == 1 {
                binaryURL = candidates[0]
            } else {
                let imageNames = Set(Self.agenticDataCrashImages(logText).map { $0.name })
                if let match = candidates.first(where: { imageNames.contains($0.lastPathComponent) }) {
                    binaryURL = match
                } else {
                    throw MCPToolError("Multiple DWARF binaries in dSYM at \(dsymRaw) (\(candidates.map { $0.lastPathComponent }.joined(separator: ", "))); pass the dSYM for a single binary.")
                }
            }
        } else {
            binaryURL = dsymURL
        }
        let binaryName = binaryURL.lastPathComponent
        let images = Self.agenticDataCrashImages(logText)
        guard !images.isEmpty else {
            throw MCPToolError("No Binary Images section found in \(logRaw); symbolication needs a .crash log with binary images.")
        }
        guard let image = images.first(where: { $0.name == binaryName }) else {
            throw MCPToolError("The dSYM binary '\(binaryName)' has no image in \(logRaw); nothing to symbolicate.")
        }
        let frames = Self.agenticDataCrashFrames(logText).filter { $0.image == binaryName }
        guard !frames.isEmpty else {
            return .text("No frames in \(logRaw) belong to the dSYM binary '\(binaryName)'; nothing was symbolicated.")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/atos") else {
            throw MCPToolError("symbolicate_crash_logs needs `atos` (Xcode command line tools), which is not installed on this system.")
        }
        let addresses = frames.map { $0.address }
        guard let run = await archiveRunFixed("/usr/bin/atos",
                                              ["-o", binaryURL.path, "-arch", image.arch, "-l", image.loadAddress] + addresses) else {
            throw MCPToolError("Failed to execute atos: could not start /usr/bin/atos")
        }
        if run.timedOut {
            throw MCPToolError("atos timed out after 120 seconds while symbolicating \(logRaw).")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("atos failed: \(run.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let symbols = run.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var symbolicated: [AnyJSON] = []
        for (offset, frame) in frames.enumerated() {
            let symbol = offset < symbols.count ? symbols[offset] : frame.address
            symbolicated.append(.object(["address": .string(frame.address), "symbol": .string(symbol)]))
        }
        return .structured(["symbolicatedFrames": .array(symbolicated), "frameCount": .int(symbolicated.count)],
                           summary: "Symbolicated \(symbolicated.count) frame\(symbolicated.count == 1 ? "" : "s") from \(logRaw) using \(dsymRaw).")
#else
        throw MCPToolError("symbolicate_crash_logs needs `atos` (Xcode command line tools), which is not available on Linux; no crash log was symbolicated.")
#endif
    }
}
