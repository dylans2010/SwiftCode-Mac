import Foundation
import SwiftCodeAssistant
import SwiftCodeBuild
import SwiftCodeIDECore

/// The ported Legacy test-running / coverage tool family (Wave 6,
/// slice A).
///
/// Behaviour source: Legacy's `AssistTestRunSingleTool`,
/// `AssistXctestDiscoveryTool`, `AssistTestLogParseTool`,
/// `AssistTestFlakyDetectTool`, `AssistTestCoverageReportTool`,
/// `AssistTestCoverageReporterTool`, `AssistTestDataFactoryTool`,
/// `AssistTestSnapshotManageTool`, `AssistTestTargetAddTool`,
/// `AssistUITestScaffoldTool`, `AssistInterfaceSimulatorTool`,
/// `AssistPreflightChecksTool`, `AssistPerformanceBenchmarkTool`,
/// `AssistCompilerDiagnosticsEngine`, `AssistCrashLogParseTool` and
/// `AssistRuntimeDiagnosticsEngine` (Dylan's own code, ported under
/// MIT). Pure parsing/generation lives in
/// `SwiftCodeTools+TestingSupport.swift`.
///
/// Conventions, following Waves 1–5:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter every SwiftCode tool carries. Legacy's
///   parameter-name aliases are NOT supported: SwiftCode's argument
///   validation rejects unknown arguments before the handler runs.
///   The one tool-name alias in this slice, `test_coverage` →
///   `test_coverage_reporter` (Legacy's `AssistToolRegistry` alias
///   table), lives in `MCPServer.toolAliases`, which the coordinator
///   owns — it is not added here.
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers, booleans, doubles) the way SwiftCode's other tools do —
///   Legacy's string-only map is not reproduced. Tools whose Legacy
///   result carries no data return a plain text result instead.
/// * Paths resolve through the session resolvers
///   (`resolveFileReadingPath`, `fileReadingRelativePath`) and never
///   escape the workspace, with two deliberate, read-only
///   exceptions documented in `specs/ide/assist-testing-running.md`:
///   `test_coverage_reporter` searches the user's own DerivedData
///   for `.xccovreport` files (its Legacy default) and accepts an
///   explicit absolute report path as-is; `preflight_checks` reads
///   the DerivedData directory and the system tool paths.
/// * Approval gating: the four writing tools (`test_data_factory`,
///   `test_snapshot_manage`, `test_target_add`, `ui_test_scaffold`)
///   are `writes: true` with `safeMutation` annotations. Text writes
///   go through `commit()`; snapshot deletions go through an
///   explicit `MCPChange` + `approve()` per file, stopping at the
///   first refusal. `test_snapshot_manage`'s `list` action writes
///   nothing but is still `writes: true`, because the flag is static
///   per tool — so in `readOnly` mode even a list call is refused
///   in `run()`, exactly as the approval model specifies for
///   dry-run tools. There is no Autopilot bypass.
/// * Test execution reuses SwiftCode's own test-runner seam — the
///   session's discovery (`discoverTests` /
///   `testsDiscovered`) and `runTests(only:)`, the same path the
///   `test` tool uses — never a second runner and never a shell.
///   `test_run_single` and `test_coverage_report` therefore run
///   through swiftcodebuild / SwiftPM, not Apple's `xcodebuild`, and
///   work on SwiftPM packages as well as Xcode projects. Test
///   execution itself always runs the real command and reports its
///   actual output — no result is ever invented.
/// * `performance_benchmark` runs its allow-listed command with
///   the fixed-argv runner from `SwiftCodeTools+TerminalSupport.swift`
///   (`terminalRunFixed`, off the main actor), never a shell.
///   `test_coverage_reporter` runs the real `xcrun xccov` the same
///   way.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `test_run_single`: no `/usr/bin/xcodebuild` is spawned and no
///   `-only-testing:` argument is built. The test is found through
///   the session's discovery (same matching as the `test` tool:
///   identifier, runner identifier, bare name, suite, `Suite/name()`)
///   and run with `runTests(only:)`. A testId that discovery cannot
///   find fails with the `test` tool's "no test … was found"
///   message instead of xcodebuild failing on it. `scheme` /
///   `destination` go through `applyScheme`, so `destination` is a
///   SwiftCode destination name/id/specifier (Legacy's default
///   `platform=macOS` is the specifier of the "My Mac" destination
///   and matches as-is); the shell-character guards are still
///   checked first with Legacy's messages. The result has no
///   `exitCode` key — SwiftCode's runner reports per-test outcomes, not
///   a process exit code — and the output tail is the session build
///   log's tail rather than xcodebuild's stdout tail.
/// * `test_coverage_report`: coverage comes from the session's
///   latest coverage rows (`latestCoverage`, gathered by
///   `runTests` when the scheme's Test action enables it), not from
///   parsing `xcodebuild` stdout for `%` lines, and there is no
///   `build/TestResults.xcresult` result bundle — SwiftCode's runner
///   writes its own reports, and no xcresult path is exposed. When
///   the scheme does not gather coverage the tool says so plainly
///   instead of reporting a coverage number. The `coverage` data
///   key is the overall percent as a string (`"82.5"`, `""` when
///   nothing was gathered), as in Legacy.
/// * `compiler_diagnostics_engine`: the build runs through the
///   session (`s.build(.build)` — swiftcodebuild / SwiftPM), not a
///   directly spawned `xcodebuild`, so there is no 300 s timeout
///   and no macOS-only gate (SwiftCode builds on Linux too). The
///   `project` argument must name the already-open workspace;
///   anything else fails and tells the caller to open it with
///   `workspace_open` first. Diagnostics are the build's issues by
///   severity, capped at 200 lines each, and the call still
///   succeeds when the build fails — success means "diagnostics
///   were collected", as in Legacy — with `buildFailed` and an
///   `exitCode` derived from the build status (0 when it
///   succeeded, 1 otherwise).
/// * `xctest_discovery`: inventory comes from the session's
///   discovery, filtered to XCTest (`kind == .xctest`), grouped by
///   suite — so swift-testing `@Test` functions are not counted
///   (Legacy only saw XCTestCase subclasses either), and a test
///   class with no test methods does not appear (Legacy's line
///   scan listed it with 0). Objective-C XCTest classes are found
///   too, through the same discovery the `test` tool uses.
/// * `test_data_factory` / `ui_test_scaffold`: Legacy's `overwrite`
///   parameter is a string (`"true"`/`"false"`) in the schema and
///   stays one here; a boolean `true` is also accepted by the
///   handler when argument validation lets it through.
/// * `test_snapshot_manage`: Legacy's `confirm` stays a string;
///   only the exact value `"true"` (case-insensitive) cleans.
/// * `test_coverage_reporter`: an explicit `reportPath` that is
///   absolute is used as-is (Legacy behaviour); a relative one
///   resolves against the workspace root. The DerivedData search
///   is Legacy's (newest `.xccovreport`/`.xccovarchive` by
///   modification date). Finding nothing is a success with
///   Legacy's message, not a failure.
/// * `interface_simulator`: Legacy's counting quirks are kept
///   verbatim — any line carrying `.accessibilityIdentifier(` or
///   `.accessibilityLabel(` counts toward the button total, and
///   `.accessibilityHidden(` lines count toward the image total —
///   because the audit's score is defined by that counting.
/// * `test_target_add`: the pbxproj edit is computed in memory
///   first and only written after every insert succeeds, so a
///   missing anchor writes nothing (Legacy created the test file
///   before checking anchors in an earlier shape; the checked-in
///   Legacy code checks anchors first, and this port preserves the
///   no-partial-write outcome either way). The random-ID generator
///   fails cleanly instead of indexing out of range if it cannot
///   produce 12 unique IDs.
/// * `test_log_parse` / `test_flaky_detect` /
///   `interface_simulator` / `crash_log_parse` /
///   `runtime_diagnostics_engine`: a path the session resolver
///   refuses fails with Legacy's own message for that tool
///   (`logPath must be inside the workspace…`, `Cannot read crash
///   log at: …`, …) rather than the resolver's message. A `..`
///   that stays inside the workspace resolves (the session
///   resolver's rule) where Legacy's per-tool resolvers rejected
///   any `..` as text.
/// * `runtime_diagnostics_engine`: Legacy's filesystem read threw
///   its underlying error; this port reports `Cannot read log at:
///   <logPath>` for any resolve/read failure.
/// * `performance_benchmark`: Legacy waited unboundedly; this port
///   bounds each run at 300 s through `terminalRunFixed` and fails
///   on timeout. The `exitCodes` data key is a JSON array of
///   integers (Legacy joined them with commas into a string).
extension SwiftCodeMCPHost {
    var testingTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let execution = MCPToolAnnotations(readOnly: false, idempotent: false)
        return [
            tool("test_run_single", "Run Single Test",
                 "Runs one test by ID with xcodebuild test -only-testing and returns pass/fail plus the output tail.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "testId": Schema.string("Required. Test identifier, e.g. MyTests/MyTest/testExample."),
                                       "scheme": Schema.string("Scheme to test. Defaults to the first scheme listed by xcodebuild."),
                                       "destination": Schema.string("xcodebuild destination. Default: platform=macOS.")],
                                      required: ["testId"]),
                 output: Schema.output(["status": Schema.str, "testId": Schema.str, "scheme": Schema.str, "passed": Schema.int,
                                        "failed": Schema.int, "skipped": Schema.int, "tests": Schema.anyArray, "logTail": Schema.anyArray]),
                 annotations: execution) { h, call in
                try await h.testingRunSingleTest(call)
            },
            tool("xctest_discovery", "XCTest Discovery",
                 "Discovers XCTestCase subclasses and their test methods across the workspace — a test inventory without running anything.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["classCount": Schema.int, "testCount": Schema.int])) { h, call in
                try await h.testingDiscoverXctests(call)
            },
            tool("test_log_parse", "Parse Test Log",
                 "Parses a test log for passed/failed test cases, suite summaries, and errors, returning counts plus the failed test list.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "logPath": Schema.string("Required. Workspace-relative path to a test log file.")],
                                      required: ["logPath"]),
                 output: Schema.output(["total": Schema.int, "passed": Schema.int, "failed": Schema.int,
                                        "errorCount": Schema.int, "failedTests": Schema.str])) { h, call in
                try h.testingParseTestLog(call)
            },
            tool("test_flaky_detect", "Flaky Test Detection",
                 "Parses test logs and reports tests that show both pass and fail outcomes across runs.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "logPath": Schema.string("Workspace-relative path to a test log file."),
                                       "logsDir": Schema.string("Workspace-relative path to a directory of test log files. Used when logPath is empty.")]),
                 output: Schema.output(["filesRead": Schema.int, "flakyCount": Schema.int, "flakyTests": Schema.str])) { h, call in
                try h.testingDetectFlaky(call)
            },
            tool("test_coverage_report", "Test Coverage Report",
                 "Runs xcodebuild test with code coverage enabled and reports the coverage summary plus pass/fail.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "scheme": Schema.string("Scheme to test. Defaults to the first scheme listed by xcodebuild."),
                                       "destination": Schema.string("xcodebuild destination. Default: platform=macOS.")]),
                 output: Schema.output(["status": Schema.str, "scheme": Schema.str, "coverage": Schema.str,
                                        "passed": Schema.int, "failed": Schema.int, "skipped": Schema.int]),
                 annotations: execution) { h, call in
                try await h.testingCoverageReport(call)
            },
            tool("test_coverage_reporter", "Test Coverage Reporter",
                 "Extracts line and target test coverage metrics from build and test artifacts via xccov.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "reportPath": Schema.string("Optional explicit path to an .xccovreport file.")])) { h, call in
                try await h.testingCoverageReporter(call)
            },
            tool("test_data_factory", "Test Data Factory",
                 "Writes a test fixture file: a JSON object with sample values per field type, or a Swift struct with a static sample.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "name": Schema.string("Required. Valid Swift identifier used for the fixture type and file name."),
                                       "kind": Schema.string("json or swift. Default: json."),
                                       "fields": Schema.string("Optional comma list, e.g. id:Int,name:String,isActive:Bool. Defaults to id:Int,name:String."),
                                       "path": Schema.string("Optional workspace-relative directory or file path. Default: TestData/."),
                                       "overwrite": Schema.string("Must be 'true' to replace an existing file. Default: 'false'.")],
                                      required: ["name"]),
                 output: Schema.output(["path": Schema.str, "kind": Schema.str, "name": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.testingDataFactory(call)
            },
            tool("test_snapshot_manage", "Manage Test Snapshots",
                 "Lists snapshot test reference images under __Snapshots__ directories, or deletes unreferenced snapshot files when confirm is true.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("list or clean. Default: list."),
                                       "confirm": Schema.string("Must be 'true' for clean. Any other value refuses to delete.")]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.testingSnapshotManage(call)
            },
            tool("test_target_add", "Add Test Target",
                 "Creates a test directory with a real XCTest file and inserts a PBXNativeTarget block into the project pbxproj.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "targetName": Schema.string("Required. Valid identifier for the new test target."),
                                       "type": Schema.string("unit or ui. Default: unit.")],
                                      required: ["targetName"]),
                 output: Schema.output(["targetName": Schema.str, "type": Schema.str, "targetID": Schema.str, "testFile": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.testingAddTestTarget(call)
            },
            tool("ui_test_scaffold", "UI Test Scaffold",
                 "Creates a real XCTest UI test file with setUp, launch, a launch-state assertion, and tearDown.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "testName": Schema.string("Required. Valid Swift identifier used for the test class and file name."),
                                       "targetApp": Schema.string("Optional bundle identifier of the app under test. When empty, XCUIApplication() is used."),
                                       "path": Schema.string("Workspace-relative directory for the new test file. Default: UITests/."),
                                       "overwrite": Schema.string("Must be 'true' to replace an existing file. Default: 'false'.")],
                                      required: ["testName"]),
                 output: Schema.output(["path": Schema.str, "testName": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.testingScaffoldUITest(call)
            },
            tool("interface_simulator", "Interface Simulator & Accessibility Auditor",
                 "Inspects SwiftUI View files, audits accessibility traits, accessibility identifiers, touch targets, and hierarchy structure.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "viewPath": Schema.string("Workspace-relative path to a SwiftUI View file.")],
                                      required: ["viewPath"])) { h, call in
                try h.testingAuditInterface(call)
            },
            tool("preflight_checks", "Preflight Checks",
                 "Runs environment preflight checks before a build/task: workspace writable, Xcode tools present, DerivedData reachable, free disk space.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["checkCount": Schema.int, "failureCount": Schema.int])) { h, call in
                try h.testingPreflightChecks(call)
            },
            tool("performance_benchmark", "Performance Benchmark",
                 "Runs an allow-listed command N times via Process and reports average, minimum, and maximum wall time plus exit codes.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "command": Schema.string("Required. Executable path, one of /usr/bin/time, /usr/bin/xcodebuild, /usr/bin/swift, /bin/ls, /usr/bin/du. May include arguments after the executable."),
                                       "arguments": Schema.string("Optional extra arguments, space-separated. Combined with any arguments in command."),
                                       "iterations": Schema.string("Run count. Default: 3. Maximum: 10.")],
                                      required: ["command"]),
                 // No output schema: the seconds are doubles and this
                 // file's Schema helper has no number type.
                 annotations: execution) { h, call in
                try await h.testingBenchmark(call)
            },
            tool("compiler_diagnostics_engine", "Compiler Diagnostics Engine",
                 "Runs xcodebuild and parses warnings/errors into structured diagnostics.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "project": Schema.string("Workspace-relative path to the .xcodeproj/.xcworkspace to diagnose. Defaults to the project found in the workspace root."),
                                       "scheme": Schema.string("Build scheme. Defaults to the project's first listed scheme.")]),
                 output: Schema.output(["error_count": Schema.int, "warning_count": Schema.int, "errors": Schema.str,
                                        "warnings": Schema.str, "exitCode": Schema.int, "buildFailed": Schema.bool]),
                 annotations: execution) { h, call in
                try await h.testingCompilerDiagnostics(call)
            },
            tool("crash_log_parse", "Crash Log Parse",
                 "Parses .crash/.ips crash logs: exception type, termination reason, faulting thread, and top blamed frames.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the .crash or .ips file.")],
                                      required: ["path"]),
                 output: Schema.output(["hasException": Schema.bool, "frameCount": Schema.int])) { h, call in
                try h.testingParseCrashLog(call)
            },
            tool("runtime_diagnostics_engine", "Runtime Diagnostics Engine",
                 "Analyzes runtime logs for crashes/anomalies and suggests concrete fixes.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "logPath": Schema.string("Workspace-relative path of the log file to analyze.")],
                                      required: ["logPath"]),
                 output: Schema.output(["crash_count": Schema.int, "thread_anomaly_count": Schema.int,
                                        "suggestions": Schema.str, "crashes": Schema.str])) { h, call in
                try h.testingRuntimeDiagnostics(call)
            },
        ]
    }
}

extension SwiftCodeMCPHost {
    // MARK: - Running tests (session seam)

    func testingRunSingleTest(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let testId = call.arguments["testId"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !testId.isEmpty else {
            throw MCPToolError("Missing required parameter: testId")
        }
        guard Self.testingIsValidTestId(testId) else {
            throw MCPToolError("testId '\(testId)' is not valid. Expected a form like MyTests/MyTest/testExample with no spaces or shell characters.")
        }
        let destination = call.string("destination") ?? "platform=macOS"
        if Self.testingHasUnsafeShellCharacters(destination) {
            throw MCPToolError("destination contains characters that are not allowed.")
        }
        let scheme = call.string("scheme")
        if let s = scheme, Self.testingHasUnsafeShellCharacters(s) {
            throw MCPToolError("scheme contains characters that are not allowed.")
        }
        let s = try session(for: call)
        try applyScheme(scheme, destination: destination, to: s)
        delegate?.mcpHostSaveAll()
        // Same discovery + matching as the `test` tool: identifier,
        // runner identifier, bare name, suite, `Suite/name()`.
        s.discoverTests()
        await s.testsDiscovered()
        let only = s.tests.filter { t in
            t.identifier == testId || s.runnerIdentifier(t) == testId || t.name == testId || t.suite == testId
                || "\(t.suite ?? "")/\(t.name)()" == testId
        }
        guard !only.isEmpty else {
            let known = s.tests.prefix(40).map(\.identifier).joined(separator: ", ")
            throw MCPToolError("no test \"\(testId)\" was found in the sources\(known.isEmpty ? "" : "; tests: " + known)")
        }
        let outcomes = await reportingActivity(call.progress) { await s.runTests(only: only) }
        let root = Self.folder(of: s.model).path
        let passed = outcomes.filter { $0.status == .passed }.count
        let failed = outcomes.filter { $0.status == .failed }.count
        let skipped = outcomes.filter { $0.status == .skipped }.count
        let lastReportOK = s.reports.first?.succeeded ?? (failed == 0)
        let status = failed > 0 || !lastReportOK ? "Failed" : "Passed"
        let schemeName = s.scheme ?? s.model.displayName
        var summary = "Single test \(testId) — \(status) (\(s.model.displayName) / \(schemeName))"
        for o in outcomes where o.status == .failed {
            summary += "\n✗ \(o.suite.map { "\($0)/" } ?? "")\(o.name)"
            for f in o.failures.prefix(3) { summary += "\n    " + f.description }
        }
        if outcomes.isEmpty && status == "Failed" {
            summary += "\nNo test ran." + "\nLast log lines:\n" + s.buildLog.suffix(20).joined(separator: "\n")
        }
        let tests: [AnyJSON] = outcomes.map { o in
            ["suite": .optional(o.suite), "name": .string(o.name), "status": .string(o.status.rawValue),
             "seconds": o.duration.map { .double($0) } ?? .null, "failures": .array(o.failures.map { Self.issueJSON($0, relativeTo: root) })]
        }
        return MCPToolResult(content: [.textBlock(summary)],
                             structured: ["status": .string(status), "testId": .string(testId), "scheme": .string(schemeName),
                                          "passed": .int(passed), "failed": .int(failed), "skipped": .int(skipped),
                                          "tests": .array(tests), "logTail": .strings(Array(s.buildLog.suffix(30)))])
    }

    func testingDiscoverXctests(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        s.discoverTests()
        await s.testsDiscovered()
        let root = Self.folder(of: s.model).path
        // One entry per XCTestCase subclass: its file (first seen)
        // and its test-method count. swift-testing `@Test`
        // functions are not XCTest and are not counted.
        var byClass: [String: (file: String, count: Int)] = [:]
        for t in s.tests where t.kind == .xctest {
            let suite = t.suite ?? t.name
            if var entry = byClass[suite] {
                entry.count += 1
                byClass[suite] = entry
            } else {
                byClass[suite] = (file: t.file, count: 1)
            }
        }
        if byClass.isEmpty {
            return .structured(["classCount": .int(0), "testCount": .int(0)],
                               summary: "No XCTestCase subclasses found in the workspace.")
        }
        let totalTests = byClass.values.reduce(0) { $0 + $1.count }
        var lines = ["XCTest inventory: \(byClass.count) test classes, \(totalTests) test methods:"]
        for name in byClass.keys.sorted() {
            let entry = byClass[name]!
            lines.append("- \(name) — \(Self.relativePath(entry.file, root: root)) (\(entry.count) tests)")
        }
        return .structured(["classCount": .int(byClass.count), "testCount": .int(totalTests)],
                           summary: lines.joined(separator: "\n"))
    }

    func testingCoverageReport(_ call: MCPToolCall) async throws -> MCPToolResult {
        let destination = call.string("destination") ?? "platform=macOS"
        if Self.testingHasUnsafeShellCharacters(destination) {
            throw MCPToolError("destination contains characters that are not allowed.")
        }
        let scheme = call.string("scheme")
        if let s = scheme, Self.testingHasUnsafeShellCharacters(s) {
            throw MCPToolError("scheme contains characters that are not allowed.")
        }
        let s = try session(for: call)
        try applyScheme(scheme, destination: destination, to: s)
        delegate?.mcpHostSaveAll()
        let outcomes = await reportingActivity(call.progress) { await s.runTests() }
        let passed = outcomes.filter { $0.status == .passed }.count
        let failed = outcomes.filter { $0.status == .failed }.count
        let skipped = outcomes.filter { $0.status == .skipped }.count
        let lastReportOK = s.reports.first?.succeeded ?? (failed == 0)
        let status = failed > 0 || !lastReportOK ? "Failed" : "Passed"
        let schemeName = s.scheme ?? s.model.displayName
        let coverage = s.latestCoverage
        let coverageValue: String
        let coverageText: String
        if coverage.isEmpty {
            coverageValue = ""
            coverageText = "No coverage data was gathered for this run. Enable code coverage in the scheme's Test action and run again."
        } else {
            let executable = coverage.reduce(0) { $0 + $1.executableLines }
            let covered = coverage.reduce(0) { $0 + $1.coveredLines }
            let percent = executable == 0 ? 0 : Double(covered) / Double(executable) * 100
            coverageValue = String(format: "%.1f", percent)
            var lines = ["Coverage: \(CoverageModel.percent(executable == 0 ? 0 : Double(covered) / Double(executable))) (\(covered) of \(executable) lines)"]
            for target in coverage {
                lines.append("- \(target.name): \(CoverageModel.percent(target.fraction)) (\(target.coveredLines) of \(target.executableLines) lines)")
            }
            coverageText = lines.joined(separator: "\n")
        }
        var output = "Test Coverage — \(s.model.displayName) / \(schemeName): \(status)\n\(coverageText)"
        output += "\nExecuted \(passed + failed + skipped) test(s): \(passed) passed, \(failed) failed, \(skipped) skipped."
        return .structured(["status": .string(status), "scheme": .string(schemeName), "coverage": .string(coverageValue),
                            "passed": .int(passed), "failed": .int(failed), "skipped": .int(skipped)],
                           summary: output)
    }

    func testingCompilerDiagnostics(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        if let project = call.string("project") {
            let url = try resolveFileReadingPath(project, in: s)
            let modelURL = s.model.url.standardizedFileURL
            let folder = Self.folder(of: s.model)
            guard url.standardizedFileURL.path == modelURL.path || url.standardizedFileURL.path == folder.path else {
                throw MCPToolError("project \"\(project)\" is not the open workspace; open it with workspace_open first.")
            }
        }
        try applyScheme(call.string("scheme"), destination: nil, to: s)
        delegate?.mcpHostSaveAll()
        let result = await reportingActivity(call.progress) { await s.build(.build) }
        let errors = result.issues.filter { $0.severity == .error }
        let warnings = result.issues.filter { $0.severity == .warning }
        let exitCode = result.status == .succeeded ? 0 : 1
        let buildFailed = result.status != .succeeded
        // Success means "diagnostics were collected", not "the build
        // passed": the build failure is explicit in the output and
        // in the data.
        let headline = result.status == .succeeded
            ? "Compiler diagnostics collected (build succeeded)."
            : "Compiler diagnostics collected (build FAILED, exit code \(exitCode))."
        return .structured(["error_count": .int(errors.count), "warning_count": .int(warnings.count),
                            "errors": .string(errors.prefix(200).map(\.description).joined(separator: "\n")),
                            "warnings": .string(warnings.prefix(200).map(\.description).joined(separator: "\n")),
                            "exitCode": .int(exitCode), "buildFailed": .bool(buildFailed)],
                           summary: headline)
    }

    // MARK: - Log parsing (pure reads)

    func testingParseTestLog(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let logPath = call.arguments["logPath"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !logPath.isEmpty else {
            throw MCPToolError("Missing required parameter: logPath")
        }
        let url: URL
        do {
            url = try resolveFileReadingPath(logPath, in: s)
        } catch {
            throw MCPToolError("logPath must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("Log file not found at '\(logPath)'.")
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw MCPToolError("Could not read log file at '\(logPath)' as UTF-8 text.")
        }
        let parsed = Self.testingParseTestLogLines(content)
        let total = parsed.passed + parsed.failed
        var output = "Test log '\(logPath)': \(total) test case(s), \(parsed.passed) passed, \(parsed.failed) failed, \(parsed.errorLines.count) error line(s)."
        if !parsed.failedTests.isEmpty {
            output += "\nFailed tests:\n" + parsed.failedTests.map { "- \($0)" }.joined(separator: "\n")
        }
        if !parsed.suiteLines.isEmpty {
            output += "\nSuite summaries:\n" + parsed.suiteLines.prefix(10).joined(separator: "\n")
        }
        if !parsed.errorLines.isEmpty {
            output += "\nErrors:\n" + parsed.errorLines.prefix(10).joined(separator: "\n")
        }
        return .structured(["total": .int(total), "passed": .int(parsed.passed), "failed": .int(parsed.failed),
                            "errorCount": .int(parsed.errorLines.count), "failedTests": .string(parsed.failedTests.joined(separator: ","))],
                           summary: output)
    }

    func testingDetectFlaky(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let logPath = call.arguments["logPath"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let logsDir = call.arguments["logsDir"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var logURLs: [URL] = []
        if !logPath.isEmpty {
            let resolved: URL
            do {
                resolved = try resolveFileReadingPath(logPath, in: s)
            } catch {
                throw MCPToolError("logPath must be inside the workspace and must not contain '..'.")
            }
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                throw MCPToolError("Log file not found at '\(logPath)'.")
            }
            logURLs = [resolved]
        } else if !logsDir.isEmpty {
            let resolvedDir: URL
            do {
                resolvedDir = try resolveFileReadingPath(logsDir, in: s)
            } catch {
                throw MCPToolError("logsDir must be inside the workspace and must not contain '..'.")
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolvedDir.path, isDirectory: &isDir), isDir.boolValue else {
                throw MCPToolError("Logs directory not found at '\(logsDir)'.")
            }
            guard let contents = try? FileManager.default.contentsOfDirectory(at: resolvedDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                throw MCPToolError("Could not list logs directory at '\(logsDir)'.")
            }
            logURLs = contents.filter { ["log", "txt"].contains($0.pathExtension.lowercased()) }.sorted { $0.path < $1.path }
            if logURLs.isEmpty {
                throw MCPToolError("No .log or .txt files found in '\(logsDir)'.")
            }
        } else {
            throw MCPToolError("Provide logPath or logsDir.")
        }
        var passCounts: [String: Int] = [:]
        var failCounts: [String: Int] = [:]
        var filesRead = 0
        for url in logURLs {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            filesRead += 1
            for outcome in Self.testingParseTestOutcomes(from: content) {
                if outcome.passed {
                    passCounts[outcome.test, default: 0] += 1
                } else {
                    failCounts[outcome.test, default: 0] += 1
                }
            }
        }
        let flaky = Set(passCounts.keys).intersection(Set(failCounts.keys)).sorted()
        let distinctCount = Set(passCounts.keys).union(Set(failCounts.keys)).count
        var output = "Flaky test scan across \(filesRead) log file(s): \(distinctCount) distinct tests observed, \(flaky.count) flaky."
        if flaky.isEmpty {
            output += "\nNo test showed both a pass and a fail."
        } else {
            for test in flaky {
                output += "\n- \(test): \(passCounts[test] ?? 0) pass, \(failCounts[test] ?? 0) fail"
            }
        }
        return .structured(["filesRead": .int(filesRead), "flakyCount": .int(flaky.count),
                            "flakyTests": .string(flaky.joined(separator: ","))],
                           summary: output)
    }

    func testingParseCrashLog(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: path")
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
        var lines = ["Crash log summary for \(raw):"]
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

    func testingRuntimeDiagnostics(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let logPath = call.arguments["logPath"]?.string else { throw MCPToolError("Missing logPath") }
        let log: String
        do {
            let url = try resolveFileReadingPath(logPath, in: s)
            log = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Cannot read log at: \(logPath)")
        }
        let lines = log.components(separatedBy: .newlines)
        let crashes = lines.filter { $0.localizedCaseInsensitiveContains("fatal error") || $0.localizedCaseInsensitiveContains("crash") }
        let threads = lines.filter { $0.localizedCaseInsensitiveContains("thread") && $0.localizedCaseInsensitiveContains("queue") }
        var suggestions: [String] = []
        if !crashes.isEmpty { suggestions.append("Add guards around nil-sensitive code paths and inspect crashing stack frame symbols.") }
        if !threads.isEmpty { suggestions.append("Validate actor/queue confinement for shared mutable state to avoid race conditions.") }
        if suggestions.isEmpty { suggestions.append("No critical anomalies detected; enable verbose logging for deeper tracing.") }
        return .structured(["crash_count": .int(crashes.count), "thread_anomaly_count": .int(threads.count),
                            "suggestions": .string(suggestions.joined(separator: "\n")),
                            "crashes": .string(crashes.prefix(100).joined(separator: "\n"))],
                           summary: "Runtime diagnostics complete.")
    }

    func testingAuditInterface(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let viewPath = call.arguments["viewPath"]?.string else {
            throw MCPToolError("Missing required parameter: viewPath")
        }
        let content: String
        do {
            let url = try resolveFileReadingPath(viewPath, in: s)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw MCPToolError("File does not exist: \(viewPath)")
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw MCPToolError("Cannot read file: \(viewPath)")
            }
            content = text
        } catch let error as MCPToolError {
            throw error
        } catch {
            throw MCPToolError("File does not exist: \(viewPath)")
        }
        guard content.contains(": View") || content.contains("some View") else {
            throw MCPToolError("File does not appear to contain a SwiftUI View implementation: \(viewPath)")
        }
        let lines = content.components(separatedBy: .newlines)
        var buttonCount = 0
        var buttonsWithA11y = 0
        var imageCount = 0
        var imagesWithA11y = 0
        var textCount = 0
        var listCount = 0
        var navigationTitleFound = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("//") { continue }
            if trimmed.contains("Button(") || trimmed.contains("Button {") { buttonCount += 1 }
            if trimmed.contains(".accessibilityIdentifier(") || trimmed.contains(".accessibilityLabel(") {
                buttonsWithA11y += 1
            }
            if trimmed.contains("Image(") || trimmed.contains("Image(systemName:") { imageCount += 1 }
            if trimmed.contains(".accessibilityHidden(") { imagesWithA11y += 1 }
            if trimmed.contains("Text(") { textCount += 1 }
            if trimmed.contains("List {") || trimmed.contains("List(") { listCount += 1 }
            if trimmed.contains(".navigationTitle(") { navigationTitleFound = true }
        }
        let a11yScore = buttonCount > 0 ? Int((Double(buttonsWithA11y) / Double(buttonCount)) * 100.0) : 100
        var report = """
        SwiftUI Interface & Accessibility Audit for '\(viewPath)':
        - Elements Detected:
          * Buttons: \(buttonCount) (\(buttonsWithA11y) have accessibility tags or labels)
          * Images: \(imageCount)
          * Text Labels: \(textCount)
          * Lists/ScrollViews: \(listCount)
          * Navigation Title Configured: \(navigationTitleFound ? "Yes" : "No")
        - Accessibility Identifier Coverage: \(a11yScore)%
        """
        if a11yScore < 60 {
            report += "\n\nRecommendations:\n- Add `.accessibilityIdentifier(...)` to interactive buttons for automated UI testing.\n- Add `.accessibilityLabel(...)` to icon-only buttons."
        } else {
            report += "\n\nInterface compliance check passed with high accessibility readiness."
        }
        return .text(report)
    }

    func testingPreflightChecks(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let fm = FileManager.default
        let root = Self.folder(of: s.model)
        var checks: [(String, Bool, String)] = []
        let writable = fm.isWritableFile(atPath: root.path)
        checks.append(("Workspace writable", writable, root.path))
        let xcodebuild = fm.isExecutableFile(atPath: "/usr/bin/xcodebuild")
        checks.append(("xcodebuild available", xcodebuild, "/usr/bin/xcodebuild"))
        let swift = fm.isExecutableFile(atPath: "/usr/bin/swift")
        checks.append(("swift available", swift, "/usr/bin/swift"))
        let codesign = fm.isExecutableFile(atPath: "/usr/bin/codesign")
        checks.append(("codesign available", codesign, "/usr/bin/codesign"))
        let dd = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        var ddIsDir: ObjCBool = false
        let ddOk = fm.fileExists(atPath: dd.path, isDirectory: &ddIsDir)
        checks.append(("DerivedData reachable", ddOk, dd.path))
        var diskGB = -1.0
        var diskOk = false
        if let attrs = try? fm.attributesOfFileSystem(forPath: root.path),
           let free = attrs[.systemFreeSize] as? NSNumber {
            diskGB = free.doubleValue / 1_073_741_824.0
            diskOk = diskGB >= 5.0
        }
        checks.append(("Free disk ≥ 5 GB", diskOk, diskGB < 0 ? "unknown" : String(format: "%.1f GB free", diskGB)))
        let temp = root.appendingPathComponent(".assist_temp")
        var tempIsDir: ObjCBool = false
        let tempExists = fm.fileExists(atPath: temp.path, isDirectory: &tempIsDir)
        let tempOk = (tempExists && tempIsDir.boolValue && fm.isWritableFile(atPath: temp.path)) || (!tempExists && writable)
        checks.append(("Artifact storage writable", tempOk, tempExists ? temp.path : temp.path + " (will be created on demand)"))
        var lines = ["Preflight checks:"]
        for (name, ok, detail) in checks {
            lines.append("- [\(ok ? "PASS" : "FAIL")] \(name) — \(detail)")
        }
        let failures = checks.filter { !$0.1 }.count
        return .structured(["checkCount": .int(checks.count), "failureCount": .int(failures)],
                           summary: lines.joined(separator: "\n") + "\nResult: \(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")")
    }

    // MARK: - Execution (fixed argv, never a shell)

    func testingBenchmark(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let commandRaw = call.arguments["command"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !commandRaw.isEmpty else {
            throw MCPToolError("Missing required parameter: command")
        }
        let allowed: Set<String> = ["/usr/bin/time", "/usr/bin/xcodebuild", "/usr/bin/swift", "/bin/ls", "/usr/bin/du"]
        var tokens = commandRaw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let executable = tokens.first else {
            throw MCPToolError("command is empty.")
        }
        guard allowed.contains(executable) else {
            throw MCPToolError("command '\(executable)' is not in the allow-list. Allowed: /usr/bin/time, /usr/bin/xcodebuild, /usr/bin/swift, /bin/ls, /usr/bin/du.")
        }
        tokens.removeFirst()
        var extraArguments: [String] = []
        if let argsString = call.arguments["arguments"]?.string {
            extraArguments = argsString.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        } else if let argsArray = call.arguments["arguments"]?.array {
            extraArguments = argsArray.compactMap { $0.string }
        }
        let allArguments = tokens + extraArguments
        for arg in allArguments where Self.testingHasUnsafeShellCharacters(arg) {
            throw MCPToolError("Argument '\(arg)' contains characters that are not allowed.")
        }
        guard FileManager.default.fileExists(atPath: executable) else {
            throw MCPToolError("Executable not found at '\(executable)'.")
        }
        let iterationsRaw = call.arguments["iterations"]?.string ?? (call.arguments["iterations"]?.int).map { String($0) } ?? "3"
        guard let requested = Int(iterationsRaw.trimmingCharacters(in: .whitespacesAndNewlines)), requested >= 1 else {
            throw MCPToolError("iterations must be an integer of at least 1.")
        }
        let iterations = min(requested, 10)
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var durations: [Double] = []
        var exitCodes: [Int32] = []
        var lastOutput = ""
        for _ in 0..<iterations {
            let start = Date()
            let run = (await Task.detached {
                Self.terminalRunFixed(executable, allArguments, workingDirectory: root, timeout: 300)
            }.value)
            guard let run else {
                throw MCPToolError("Benchmark run failed: could not start '\(executable)'.")
            }
            if run.timedOut {
                throw MCPToolError("Benchmark run timed out after 300s.")
            }
            durations.append(Date().timeIntervalSince(start))
            exitCodes.append(run.exitCode)
            lastOutput = (run.stdout + "\n" + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let minValue = durations.min(), let maxValue = durations.max(), !durations.isEmpty else {
            throw MCPToolError("No benchmark runs completed.")
        }
        let average = durations.reduce(0, +) / Double(durations.count)
        let output = "Benchmark '\(executable) \(allArguments.joined(separator: " "))' over \(iterations) run(s): avg \(String(format: "%.3f", average))s, min \(String(format: "%.3f", minValue))s, max \(String(format: "%.3f", maxValue))s. Exit codes: \(exitCodes.map { String($0) }.joined(separator: ", ")).\nLast run output tail:\n\(String(lastOutput.suffix(1000)))"
        return .structured(["executable": .string(executable), "iterations": .int(iterations),
                            "averageSeconds": .double(average), "minSeconds": .double(minValue), "maxSeconds": .double(maxValue),
                            "exitCodes": .array(exitCodes.map { AnyJSON.int(Int($0)) })],
                           summary: output)
    }

    func testingCoverageReporter(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let derivedData = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        var coverageURL: URL?
        if let explicit = call.arguments["reportPath"]?.string, !explicit.isEmpty {
            // Legacy uses an absolute path as-is; a relative path
            // resolves against the workspace root.
            coverageURL = explicit.hasPrefix("/")
                ? URL(fileURLWithPath: explicit)
                : Self.folder(of: s.model).appendingPathComponent(explicit)
        } else {
            // Most recent .xccovreport or .xccovarchive in
            // DerivedData, by modification date.
            if let enumerator = FileManager.default.enumerator(at: derivedData, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
                var candidates: [(url: URL, date: Date)] = []
                while let item = enumerator.nextObject() as? URL {
                    if item.pathExtension == "xccovreport" || item.pathExtension == "xccovarchive" {
                        let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        candidates.append((url: item, date: date))
                    }
                }
                coverageURL = candidates.sorted(by: { $0.date > $1.date }).first?.url
            }
        }
        guard let targetReport = coverageURL, FileManager.default.fileExists(atPath: targetReport.path) else {
            return .text("No active .xccovreport or coverage archive found in DerivedData. Ensure 'Code Coverage' is enabled in your Xcode Scheme test settings.")
        }
        let reportPath = targetReport.path
        let run = (await Task.detached {
            Self.terminalRunFixed("/usr/bin/xcrun", ["xccov", "view", "--report", reportPath], timeout: 60)
        }.value)
        guard let run else {
            throw MCPToolError("Failed to execute xccov: /usr/bin/xcrun is not available on this machine.")
        }
        let output = (run.stdout + "\n" + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            return .text("Coverage report found at \(targetReport.lastPathComponent), but yielded no text metrics.")
        }
        let lines = output.components(separatedBy: .newlines)
        let snippet = lines.prefix(40).joined(separator: "\n")
        return .text("### Test Coverage Report (\(targetReport.lastPathComponent)):\n\n```\n\(snippet)\n```")
    }

    // MARK: - Writes (approval-gated)

    func testingDataFactory(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let name = call.arguments["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw MCPToolError("Missing required parameter: name")
        }
        guard Self.testingIsValidSwiftIdentifier(name) else {
            throw MCPToolError("name '\(name)' is not a valid Swift identifier. Use letters, digits, and underscores, starting with a letter or underscore.")
        }
        let kind = (call.arguments["kind"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "json"
        guard kind == "json" || kind == "swift" else {
            throw MCPToolError("kind must be 'json' or 'swift'.")
        }
        let fieldsRaw = (call.arguments["fields"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "id:Int,name:String"
        let fields: [(name: String, type: String)]
        do {
            fields = try Self.testingParseFixtureFields(fieldsRaw)
        } catch {
            throw MCPToolError((error as? MCPToolError)?.message ?? error.localizedDescription)
        }
        let pathRaw = (call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "TestData/"
        let overwrite = call.arguments["overwrite"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            || call.arguments["overwrite"]?.bool == true
        guard let fileURL = testingResolveFixtureURL(pathRaw, name: name, kind: kind, in: s) else {
            throw MCPToolError("path must be inside the workspace and must not contain '..'.")
        }
        if FileManager.default.fileExists(atPath: fileURL.path) && !overwrite {
            throw MCPToolError("File already exists at '\(fileReadingRelativePath(of: fileURL, in: s))'. Pass overwrite='true' to replace it.")
        }
        let content = kind == "json" ? Self.testingBuildJSONFixture(fields: fields) : Self.testingBuildSwiftFixture(name: name, fields: fields)
        let rel = fileReadingRelativePath(of: fileURL, in: s)
        try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: rel, original: text(of: fileURL), proposed: content,
                                   summary: "Create test fixture \(rel)"), call: call, session: s)
        return .structured(["path": .string(rel), "kind": .string(kind), "name": .string(name)],
                           summary: "Created test fixture at \(rel)")
    }

    func testingScaffoldUITest(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let testName = call.arguments["testName"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !testName.isEmpty else {
            throw MCPToolError("Missing required parameter: testName")
        }
        guard Self.testingIsValidSwiftIdentifier(testName) else {
            throw MCPToolError("testName '\(testName)' is not a valid Swift identifier. Use letters, digits, and underscores, starting with a letter or underscore.")
        }
        let targetApp = call.arguments["targetApp"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dirRaw = (call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "UITests/"
        let dirURL: URL
        do {
            dirURL = try resolveFileReadingPath(dirRaw, in: s)
        } catch {
            throw MCPToolError("path must be inside the workspace and must not contain '..'.")
        }
        let overwrite = call.arguments["overwrite"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            || call.arguments["overwrite"]?.bool == true
        let fileURL = dirURL.appendingPathComponent("\(testName).swift")
        if FileManager.default.fileExists(atPath: fileURL.path) && !overwrite {
            throw MCPToolError("File already exists at '\(fileReadingRelativePath(of: fileURL, in: s))'. Pass overwrite='true' to replace it.")
        }
        let content = Self.testingBuildUITestContent(testName: testName, targetApp: targetApp)
        let rel = fileReadingRelativePath(of: fileURL, in: s)
        try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: rel, original: text(of: fileURL), proposed: content,
                                   summary: "Create UI test \(rel)"), call: call, session: s)
        return .structured(["path": .string(rel), "testName": .string(testName)],
                           summary: "Created UI test file at \(rel)")
    }

    func testingSnapshotManage(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let action = (call.arguments["action"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "list"
        guard action == "list" || action == "clean" else {
            throw MCPToolError("action must be 'list' or 'clean'.")
        }
        let snapshotFiles = Self.testingFindSnapshotFiles(in: root)
        if action == "list" {
            if snapshotFiles.isEmpty {
                return .structured(["count": .int(0), "files": .string("")],
                                   summary: "No snapshot files found under any __Snapshots__ directory in the workspace.")
            }
            var output = "Snapshot references: \(snapshotFiles.count) file(s) under __Snapshots__ directories."
            for file in snapshotFiles {
                output += "\n- \(fileReadingRelativePath(of: file, in: s))"
            }
            return .structured(["count": .int(snapshotFiles.count),
                                "files": .string(snapshotFiles.map { fileReadingRelativePath(of: $0, in: s) }.joined(separator: ","))],
                               summary: output)
        }
        let confirm = call.arguments["confirm"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard confirm == "true" else {
            throw MCPToolError("clean requires confirm='true'. No files were deleted.")
        }
        if snapshotFiles.isEmpty {
            return .structured(["deletedCount": .int(0), "keptCount": .int(0), "deleted": .string("")],
                               summary: "No snapshot files found. Nothing to clean.")
        }
        let sourceText = Self.testingCollectSwiftSourceText(in: root)
        var deleted: [String] = []
        var kept: [String] = []
        for file in snapshotFiles {
            let rel = fileReadingRelativePath(of: file, in: s)
            if Self.testingSnapshotIsReferenced(file, in: sourceText) {
                kept.append(rel)
            } else {
                // One approval per deletion, before touching disk;
                // the first refusal stops the clean.
                try await approveFileWritingChange(tool: call.name, path: file, relativePath: rel, original: nil,
                                                   summary: "Delete unreferenced snapshot \(rel)", call: call)
                do {
                    try FileManager.default.removeItem(at: file)
                    deleted.append(rel)
                    noteFileWritingChanged(file, in: s)
                } catch {
                    kept.append(rel + " (delete failed: \(error.localizedDescription))")
                }
            }
        }
        var output = "Snapshot clean: deleted \(deleted.count) unreferenced file(s), kept \(kept.count)."
        if !deleted.isEmpty {
            output += "\nDeleted:\n" + deleted.map { "- \($0)" }.joined(separator: "\n")
        }
        if !kept.isEmpty {
            output += "\nKept:\n" + kept.map { "- \($0)" }.joined(separator: "\n")
        }
        return .structured(["deletedCount": .int(deleted.count), "keptCount": .int(kept.count),
                            "deleted": .string(deleted.joined(separator: ","))],
                           summary: output)
    }

    func testingAddTestTarget(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let targetName = call.arguments["targetName"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !targetName.isEmpty else {
            throw MCPToolError("Missing required parameter: targetName")
        }
        guard Self.testingIsValidSwiftIdentifier(targetName) else {
            throw MCPToolError("targetName '\(targetName)' is not a valid identifier. Use letters, digits, and underscores, starting with a letter or underscore.")
        }
        let type = (call.arguments["type"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "unit"
        guard type == "unit" || type == "ui" else {
            throw MCPToolError("type must be 'unit' or 'ui'.")
        }
        guard let projectURL = testingFindXcodeproj(in: root) else {
            throw MCPToolError("No .xcodeproj found in the workspace root. Open a project first.")
        }
        let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            throw MCPToolError("project.pbxproj not found in '\(projectURL.lastPathComponent)'.")
        }
        guard let pbxproj = try? String(contentsOf: pbxprojURL, encoding: .utf8) else {
            throw MCPToolError("Could not read project.pbxproj as UTF-8 text.")
        }
        if pbxproj.contains("name = \(targetName);") || pbxproj.contains("/* \(targetName) */") {
            throw MCPToolError("A target named '\(targetName)' already exists in project.pbxproj.")
        }
        let testDir = root.appendingPathComponent(targetName)
        if FileManager.default.fileExists(atPath: testDir.path) {
            throw MCPToolError("Directory '\(targetName)' already exists in the workspace. Choose a different targetName.")
        }
        for anchor in ["/* Begin PBXNativeTarget section */",
                       "/* Begin PBXFileReference section */",
                       "/* Begin PBXSourcesBuildPhase section */",
                       "/* Begin PBXFrameworksBuildPhase section */",
                       "/* Begin XCBuildConfigurationList section */",
                       "/* Begin XCBuildConfiguration section */",
                       "targets = ("] {
            guard pbxproj.contains(anchor) else {
                throw MCPToolError("project.pbxproj is missing required anchor '\(anchor)'. No changes were written.")
            }
        }
        guard let ids = Self.testingMakePbxprojIDs(existing: pbxproj, count: 12) else {
            throw MCPToolError("Failed to generate unique pbxproj identifiers. No changes were written.")
        }
        // Compute the whole pbxproj edit in memory first: a missing
        // anchor must write nothing, including the test file.
        guard let modified = Self.testingInsertTestTarget(into: pbxproj, targetName: targetName, type: type, ids: ids) else {
            throw MCPToolError("Failed to insert the new target blocks into project.pbxproj. No changes were kept.")
        }
        let targetID = ids[0]
        let testFileURL = testDir.appendingPathComponent("\(targetName)Tests.swift")
        let testRel = fileReadingRelativePath(of: testFileURL, in: s)
        try await commit(MCPChange(tool: call.name, path: testFileURL.path, relativePath: testRel, original: nil,
                                   proposed: Self.testingBuildTestTargetContent(targetName: targetName, type: type),
                                   summary: "Create \(testRel)"), call: call, session: s)
        let pbxprojRel = fileReadingRelativePath(of: pbxprojURL, in: s)
        try await commit(MCPChange(tool: call.name, path: pbxprojURL.path, relativePath: pbxprojRel, original: pbxproj, proposed: modified,
                                   summary: "Add test target \(targetName) to \(pbxprojRel)"), call: call, session: s)
        guard let verify = try? String(contentsOf: pbxprojURL, encoding: .utf8),
              verify.contains("name = \(targetName);"),
              verify.contains(targetID) else {
            throw MCPToolError("Verification failed: target '\(targetName)' was not found in project.pbxproj after writing.")
        }
        return .structured(["targetName": .string(targetName), "type": .string(type), "targetID": .string(targetID),
                            "testFile": .string("\(targetName)/\(targetName)Tests.swift")],
                           summary: "Added test target '\(targetName)' (\(type)) with test file \(targetName)/\(targetName)Tests.swift and PBXNativeTarget entry in project.pbxproj.")
    }
}
