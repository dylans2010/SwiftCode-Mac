import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeMCP

/// The ported Legacy Terminal / system tools (Wave 4), each driven
/// black-box through the server's real write-policy path against a
/// copy of `Samples/AgentSamples/Greeter`.
///
/// Behaviour source: Legacy `UseTermFunction`,
/// `AssistTaskRunnerTool`, `AssistLogCaptureTool`,
/// `AssistEnvironmentInfoTool`, `UseMCP`, `UseExtensionTool`,
/// `AssistComposioTool`, `UseWorkersTool`,
/// `AssistEnvironmentVariableManagerTool`,
/// `AssistClipboardManagerTool`, `AssistProcessMonitorTool`,
/// `AssistDiskSpaceAnalyzerTool`, `AssistSystemNotificationTool`,
/// `AssistSystemTool`, `AssistTakeScreenshotTool`,
/// `AssistTakeScreenrecordTool` and `AssistUseAppTool` (Dylan's own
/// code, ported under MIT).
///
/// Assertions are on the tool RESULT (message + on-disk state),
/// never on internals. Messages quoted verbatim are Legacy's; where
/// the SwiftCode port may legitimately word a failure differently
/// (path-safety wording, the no-shell deviation), the test asserts
/// the behaviour plus a tolerant message match.
///
/// Platform notes: this machine has no Swift toolchain and the
/// tests run on Linux here, so the macOS-only tools
/// (`clipboard_manager_tool`, `system_notification_tool`,
/// `take_screenshot`, `use_app`, and `use_system`'s macOS-only
/// operations) assert their exact "only available on macOS"
/// failure on Linux. Their real macOS behaviour — pasteboard
/// round-trip, notification delivery, screen capture, app control,
/// `log`/`launchctl`/`defaults`/sysctl — stays pending on Dylan's
/// Mac (see the Wave 4 report). `system_notification_tool` is not
/// exercised on macOS at all: it would post a real notification.
@MainActor
@Suite(.serialized) struct SwiftCodeTerminalToolsTests {
    /// The 17 Wave 4 Terminal / system tool IDs, verified live from
    /// the Legacy registry (`AssistToolRegistry.registerAllTools` +
    /// each tool's `id`).
    static let terminalIDs = ["use_terminal", "task_runner", "env_capture_logs", "env_info", "use_mcp",
                              "use_extension", "use_composio", "use_workers", "environment_variable_manager",
                              "clipboard_manager_tool", "process_monitor_tool", "disk_space_analyzer",
                              "system_notification_tool", "use_system", "take_screenshot", "take_screenrecord",
                              "use_app"]

    /// Opens a copy of Greeter and installs the ported terminal
    /// tools on the server (same shape as Wave 2's `opened`; the
    /// coordinator wires `terminalTools` into `installTools()`).
    /// Defaults to `.allow`: most terminal tools are `writes: true`
    /// (execution risk), so the read-only policy refuses them
    /// before they run.
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        // Filter-first (Wave 2 shape): `installTools()` may already
        // wire `terminalTools`, so a plain `+=` would register them
        // twice.
        let ported = Set(host.terminalTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.terminalTools
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

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.terminalTools
        #expect(tools.map(\.name) == Self.terminalIDs)
        let expectedTitles: [String: String] = [
            "use_terminal": "Use Terminal", "task_runner": "Run Task", "env_capture_logs": "Capture Logs",
            "env_info": "Environment Info", "use_mcp": "Execute MCP Tool", "use_extension": "Use Extension",
            "use_composio": "Execute Composio Tool", "use_workers": "Create and Coordinate Assist Workers",
            "environment_variable_manager": "Environment Variable Manager", "clipboard_manager_tool": "Clipboard Manager",
            "process_monitor_tool": "Process Monitor", "disk_space_analyzer": "Disk Space Analyzer",
            "system_notification_tool": "Post macOS System Notification", "use_system": "System Diagnostics",
            "take_screenshot": "take_screenshot", "take_screenrecord": "take_screenrecord", "use_app": "use_app",
        ]
        let expectedRequired: [String: [String]] = [
            "use_terminal": ["command"], "task_runner": ["task_id"], "env_capture_logs": [], "env_info": [],
            "use_mcp": ["serverName", "toolName", "arguments"], "use_extension": ["action"],
            "use_composio": ["toolSlug", "arguments"], "use_workers": ["workers"],
            "environment_variable_manager": ["action"], "clipboard_manager_tool": ["action"],
            "process_monitor_tool": [], "disk_space_analyzer": [], "system_notification_tool": [],
            "use_system": ["operation"], "take_screenshot": [], "take_screenrecord": ["app_identifier"],
            "use_app": ["app_identifier", "action"],
        ]
        let expectedOutputs: [String: [String]] = [
            "use_terminal": ["command", "duration", "exitCode", "stderr", "stderrTruncated", "stdout", "stdoutTruncated", "workingDirectory"],
            "task_runner": ["output"], "env_capture_logs": [],
            "env_info": ["cpu_count", "locale", "os", "physical_memory_bytes", "timezone", "workspace_root"],
            "use_mcp": [], "use_extension": [], "use_composio": [], "use_workers": [],
            "environment_variable_manager": [], "clipboard_manager_tool": [], "process_monitor_tool": [],
            "disk_space_analyzer": [], "system_notification_tool": [], "use_system": [],
            "take_screenshot": ["artifact_id", "base64", "capture_mode", "display_id", "format", "height", "path", "size_bytes", "width"],
            "take_screenrecord": [], "use_app": [],
        ]
        // Legacy risk → annotations (catalogue §1.3, extended the
        // way Wave 3 extended it for `.execution`).
        let readOnlyIDs: Set<String> = ["env_capture_logs", "env_info", "process_monitor_tool", "disk_space_analyzer",
                                        "system_notification_tool", "take_screenrecord"]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name])
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            let outputKeys = tool.outputSchema?["properties"]?.object?.keys.sorted() ?? []
            #expect(outputKeys == expectedOutputs[tool.name], "\(tool.name) output keys: \(outputKeys)")
            if readOnlyIDs.contains(tool.name) {
                #expect(tool.annotations.readOnly && tool.annotations.idempotent && !tool.writes,
                        "\(tool.name) must be a read-only tool")
            } else {
                #expect(!tool.annotations.readOnly && tool.writes, "\(tool.name) must be a gated write/execution tool")
            }
        }
        // The host serves them once installed (the coordinator wires
        // `terminalTools` into `installTools()`; filter-first so they
        // are not registered twice).
        let installed = Set(host.terminalTools.map(\.name))
        host.server.tools = host.server.tools.filter { !installed.contains($0.name) } + host.terminalTools
        let served = host.server.tools.map(\.name)
        for id in Self.terminalIDs { #expect(served.contains(id), "\(id) is not installed on the server") }
    }

    // MARK: - `use_terminal`

    @Test func useTerminalRunsPlainCommandAsArgv() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_terminal", ["command": .string("echo hello")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["exitCode"] == .int(0))
        #expect(r.structured?["stdout"]?.string?.contains("hello") == true)
        #expect(r.structured?["workingDirectory"]?.string == sample.url.path)
        #expect(r.structured?["command"]?.string == "echo hello")
        #expect(r.resultText.contains("Terminal command executed successfully (exit code 0"))
    }

    @Test func useTerminalRejectsShellSyntax() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        for command in ["echo hi | cat", "echo hi > out.txt", "echo $HOME", "echo a && echo b", "echo *.swift"] {
            let r = try await host.server.callTool("use_terminal", ["command": .string(command)])
            #expect(r.isToolError, "\(command) must be rejected, got: \(r.resultText)")
            #expect(r.resultText.contains("without a shell"), "\(command): \(r.resultText)")
        }
    }

    @Test func useTerminalReportsExitCodeAndEmptyCommand() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let failed = try await host.server.callTool("use_terminal", ["command": .string("false")])
        #expect(failed.isToolError)
        #expect(failed.structured?["exitCode"] == .int(1))
        #expect(failed.resultText.contains("exit code 1"))
        let empty = try await host.server.callTool("use_terminal", ["command": .string("")])
        #expect(empty.isToolError && empty.resultText.contains("Command cannot be empty"))
        let missing = try await host.server.callTool("use_terminal", ["command": .string("no-such-program-xyz")])
        #expect(missing.isToolError && missing.resultText.contains("was not found"))
    }

    @Test func useTerminalValidatesWorkingDirectory() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let bad = try await host.server.callTool("use_terminal", ["command": .string("echo hi"), "workingDirectory": .string("Nope")])
        #expect(bad.isToolError && bad.resultText.contains("workingDirectory"))
        let ok = try await host.server.callTool("use_terminal", ["command": .string("pwd"), "workingDirectory": .string("Sources")])
        #expect(!ok.isToolError, "\(ok.resultText)")
        #expect(ok.structured?["stdout"]?.string?.contains("Sources") == true)
    }

    @Test func useTerminalIsRefusedByReadOnlyPolicy() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .readOnly)
        let r = try await host.server.callTool("use_terminal", ["command": .string("echo hello")])
        #expect(r.isToolError, "a writes:true execution tool must not run under the read-only policy")
    }

    // MARK: - `task_runner`

    @Test func taskRunnerRunsTheFourRegisteredTasks() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let indexed = try await host.server.callTool("task_runner", ["task_id": .string("project_indexing")])
        #expect(!indexed.isToolError, "\(indexed.resultText)")
        #expect(indexed.structured?["output"]?.string?.hasPrefix("Indexed project at Greeter. Found ") == true)
        let deps = try await host.server.callTool("task_runner", ["task_id": .string("dependency_analysis")])
        #expect(deps.structured?["output"]?.string == "Dependency scan complete. SPM: true, CocoaPods: false, Carthage: false")
        let lint = try await host.server.callTool("task_runner", ["task_id": .string("lint_project")])
        #expect(!lint.isToolError, "\(lint.resultText)")
        #expect(lint.structured?["output"]?.string?.hasPrefix("Lint completed.") == true)
        let tests = try await host.server.callTool("task_runner", ["task_id": .string("project_test")])
        #expect(tests.structured?["output"]?.string == "Discovered 1 XCTest file(s). Sample: GreeterTests.swift")
    }

    @Test func taskRunnerRejectsUnknownTask() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("task_runner", ["task_id": .string("nope")])
        #expect(r.isToolError && r.resultText.contains("Task 'nope' failed: Task 'nope' not found in registry."))
    }

    // MARK: - `env_info`, `disk_space_analyzer`, `process_monitor_tool`

    @Test func envInfoReportsTypedEnvironment() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("env_info")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["workspace_root"]?.string == sample.url.path)
        #expect((r.structured?["cpu_count"]?.int ?? 0) > 0)
        #expect((r.structured?["physical_memory_bytes"]?.int ?? 0) > 0)
        #expect(r.structured?["os"]?.string?.isEmpty == false)
        #expect(r.structured?["locale"]?.string?.isEmpty == false)
        #expect(r.structured?["timezone"]?.string?.isEmpty == false)
    }

    @Test func diskSpaceAnalyzerReportsWorkspaceAndDerivedData() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("disk_space_analyzer")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("### Disk Space Analysis:"))
        #expect(r.resultText.contains("Xcode DerivedData Cache"))
        #expect(r.resultText.contains("Target Scope"))
    }

    @Test func processMonitorReportsProcessesOrNone() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("process_monitor_tool")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("Active Developer Processes") || r.resultText.contains("No active processes matching"))
        let filtered = try await host.server.callTool("process_monitor_tool", ["filter": .string("definitely-no-such-process-xyz")])
        #expect(!filtered.isToolError && filtered.resultText.contains("No active processes matching"))
    }

    // MARK: - `environment_variable_manager`

    @Test func environmentVariableManagerListsGetsAndSets() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, ".env", "API_URL=https://example.invalid\n# a comment\nEMPTY=\n")
        let host = try await opened(sample)
        let list = try await host.server.callTool("environment_variable_manager", ["action": .string("list_keys")])
        #expect(!list.isToolError, "\(list.resultText)")
        #expect(list.resultText.contains("Found 2 environment keys in `.env`"))
        #expect(list.resultText.contains("- `API_URL`") && list.resultText.contains("- `EMPTY`"))
        let get = try await host.server.callTool("environment_variable_manager", ["action": .string("get"), "key": .string("API_URL")])
        #expect(get.firstText == "API_URL=https://example.invalid")
        let missing = try await host.server.callTool("environment_variable_manager", ["action": .string("get"), "key": .string("NOPE")])
        #expect(missing.isToolError && missing.resultText.contains("Key 'NOPE' not found in .env."))
        let set = try await host.server.callTool("environment_variable_manager",
                                                 ["action": .string("set"), "key": .string("API_URL"), "value": .string("https://other.invalid")])
        #expect(!set.isToolError, "\(set.resultText)")
        #expect(set.resultText.contains("Successfully set `API_URL` in `.env`."))
        #expect(sample.read(".env").contains("API_URL=https://other.invalid"))
        #expect(!sample.read(".env").contains("example.invalid"))
        let add = try await host.server.callTool("environment_variable_manager",
                                                 ["action": .string("set"), "key": .string("NEW_KEY"), "value": .string("v1")])
        #expect(!add.isToolError, "\(add.resultText)")
        #expect(sample.read(".env").contains("NEW_KEY=v1"))
        let unknown = try await host.server.callTool("environment_variable_manager", ["action": .string("delete")])
        #expect(unknown.isToolError && unknown.resultText.contains("Unsupported action 'delete'"))
    }

    @Test func environmentVariableManagerSetOnMissingFileKeepsLegacyLeadingNewline() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let set = try await host.server.callTool("environment_variable_manager",
                                                 ["action": .string("set"), "key": .string("FOO"), "value": .string("bar")])
        #expect(!set.isToolError, "\(set.resultText)")
        // Legacy's exact line logic: an empty file splits to one
        // empty line, so the new line is appended after it.
        #expect(sample.read(".env") == "\nFOO=bar")
        let missing = try await host.server.callTool("environment_variable_manager",
                                                     ["action": .string("list_keys"), "envFilePath": .string("nope.env")])
        #expect(!missing.isToolError && missing.resultText.contains("No nope.env file found in workspace."))
    }

    // MARK: - macOS-only tools

    @Test func clipboardManagerIsMacOSOnlyHere() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
#if os(macOS)
        let r = try await host.server.callTool("clipboard_manager_tool", ["action": .string("read")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("Clipboard is currently empty.") || r.resultText.contains("Current Clipboard Content"))
#else
        let r = try await host.server.callTool("clipboard_manager_tool", ["action": .string("read")])
        #expect(r.isToolError && r.resultText.contains("only available on macOS"))
#endif
    }

#if !os(macOS)
    @Test func systemNotificationIsMacOSOnlyHere() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("system_notification_tool", ["title": .string("Hi"), "message": .string("Done")])
        #expect(r.isToolError && r.resultText.contains("only available on macOS"))
    }

    @Test func takeScreenshotIsMacOSOnlyHere() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("take_screenshot")
        #expect(r.isToolError && r.resultText.contains("only available on macOS"))
    }

    @Test func useAppIsMacOSOnlyHere() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_app", ["app_identifier": .string("Finder"), "action": .string("list_applications")])
        #expect(r.isToolError && r.resultText.contains("only available on macOS"))
    }
#else
    @Test func useAppListsRunningApplications() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_app", ["app_identifier": .string("Finder"), "action": .string("list_applications")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("Discovered ") && r.resultText.contains(" application(s):"))
        let noConfirm = try await host.server.callTool("use_app", ["app_identifier": .string("Finder"), "action": .string("close_application")])
        #expect(noConfirm.isToolError && noConfirm.resultText.contains("Pass 'confirm: true' to authorize."))
        let click = try await host.server.callTool("use_app", ["app_identifier": .string("Finder"), "action": .string("click")])
        #expect(click.isToolError && click.resultText.contains("Accessibility"))
    }
#endif

    @Test func takeScreenshotRegionNeedsTheOverlay() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("take_screenshot", ["capture_mode": .string("region")])
        #expect(r.isToolError && r.resultText.contains("region-selection overlay"))
    }

    // MARK: - `use_system`

    @Test func useSystemInfoDiskAndProcessList() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let info = try await host.server.callTool("use_system", ["operation": .string("system_info")])
        #expect(!info.isToolError, "\(info.resultText)")
        #expect(info.structured?["operation"] == .string("system_info"))
        #expect((info.structured?["cpuCount"]?.int ?? 0) > 0)
        #expect(info.structured?["hostname"]?.string?.isEmpty == false)
        let disk = try await host.server.callTool("use_system", ["operation": .string("disk_info")])
        #expect(!disk.isToolError, "\(disk.resultText)")
        #expect(disk.structured?["operation"] == .string("disk_info"))
        #expect((disk.structured?["totalBytes"]?.int ?? 0) > 0)
        let procs = try await host.server.callTool("use_system", ["operation": .string("process_list")])
        #expect(!procs.isToolError, "\(procs.resultText)")
        #expect(procs.structured?["operation"] == .string("process_list"))
        #expect(procs.structured?["count"]?.int != nil)
    }

    @Test func useSystemConnectivityRefusedPortIsNotReachable() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // Port 1 on loopback refuses without any external network.
        let r = try await host.server.callTool("use_system", ["operation": .string("connectivity"), "target": .string("127.0.0.1"),
                                                              "parameters": .object(["port": .int(1)])])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["reachable"] == .bool(false))
        #expect(r.structured?["port"] == .int(1))
        #expect(r.resultText.contains("127.0.0.1:1 — not reachable"))
    }

    @Test func useSystemRejectsBadOperationsAndArguments() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let unknown = try await host.server.callTool("use_system", ["operation": .string("explode")])
        #expect(unknown.isToolError && unknown.resultText.contains("Unknown operation 'explode'"))
        let noPort = try await host.server.callTool("use_system", ["operation": .string("connectivity"), "target": .string("example.invalid")])
        #expect(noPort.isToolError && noPort.resultText.contains("Missing or invalid parameters.port"))
        let badPort = try await host.server.callTool("use_system", ["operation": .string("connectivity"), "target": .string("example.invalid"),
                                                                    "parameters": .object(["port": .int(0)])])
        #expect(badPort.isToolError && badPort.resultText.contains("Missing or invalid parameters.port"))
        let badSysctl = try await host.server.callTool("use_system", ["operation": .string("config_read"), "target": .string("kern.evil")])
#if os(macOS)
        #expect(badSysctl.isToolError && badSysctl.resultText.contains("is not on the allowlist"))
#else
        #expect(badSysctl.isToolError && badSysctl.resultText.contains("only available on macOS"))
#endif
        let noHost = try await host.server.callTool("use_system", ["operation": .string("connectivity"),
                                                                   "parameters": .object(["port": .int(80)])])
        #expect(noHost.isToolError && noHost.resultText.contains("Missing required target"))
    }

    @Test func useSystemMacOSOnlyOperations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let noConfirm = try await host.server.callTool("use_system", ["operation": .string("user_defaults_write"),
                                                                      "target": .string("com.example.Test"),
                                                                      "parameters": .object(["key": .string("k"), "value": .string("v")])])
        #expect(noConfirm.isToolError && noConfirm.resultText.contains("requires explicit confirmation"))
#if !os(macOS)
        let log = try await host.server.callTool("use_system", ["operation": .string("system_log")])
        #expect(log.isToolError && log.resultText.contains("only available on macOS"))
        let services = try await host.server.callTool("use_system", ["operation": .string("service_status")])
        #expect(services.isToolError && services.resultText.contains("only available on macOS"))
        let config = try await host.server.callTool("use_system", ["operation": .string("config_read"), "target": .string("kern.ostype")])
        #expect(config.isToolError && config.resultText.contains("only available on macOS"))
        let write = try await host.server.callTool("use_system", ["operation": .string("user_defaults_write"),
                                                                  "target": .string("com.example.Test"), "confirm": .bool(true),
                                                                  "parameters": .object(["key": .string("k"), "value": .string("v")])])
        #expect(write.isToolError && write.resultText.contains("only available on macOS"))
#endif
    }

    // MARK: - Honestly-failing tools

    @Test func envCaptureLogsFailsNamingItsPrerequisites() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("env_capture_logs")
        #expect(r.isToolError && r.resultText.contains("snapshot history"))
    }

    @Test func useMCPListsNothingAndExecutesNothing() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let list = try await host.server.callTool("use_mcp", ["serverName": .string("list"), "toolName": .string("list_tools"),
                                                              "arguments": .string("{}")])
        #expect(!list.isToolError, "\(list.resultText)")
        #expect(list.resultText.contains("No MCP servers are currently configured"))
        let exec = try await host.server.callTool("use_mcp", ["serverName": .string("github"), "toolName": .string("list_repos"),
                                                             "arguments": .string("{}")])
        #expect(exec.isToolError && exec.resultText.contains("external MCP client"))
    }

    @Test func useExtensionFailsNamingItsPrerequisite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let unknown = try await host.server.callTool("use_extension", ["action": .string("explode")])
        #expect(unknown.isToolError && unknown.resultText.contains("Unknown or missing action"))
        // The host is wired in (SwiftCodeExtensions target + SwiftCodeMCP
        // dependency, Slice B): `list` answers from the real store
        // instead of failing.
        let list = try await host.server.callTool("use_extension", ["action": .string("list")])
        #expect(!list.isToolError, "\(list.resultText)")
    }

    @Test func useComposioFailsNamingItsPrerequisite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_composio", ["toolSlug": .string("GITHUB_LIST_REPOSITORIES_FOR_THE_AUTHENTICATED_USER"),
                                                               "arguments": .string("{}")])
        #expect(r.isToolError && r.resultText.contains("Composio service"))
    }

    @Test func useWorkersValidatesThenFailsNamingItsPrerequisite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let empty = try await host.server.callTool("use_workers", ["workers": .array([])])
        #expect(empty.isToolError && empty.resultText.contains("At least one worker assignment is required."))
        let noTask = try await host.server.callTool("use_workers", ["workers": .array([.object(["name": .string("A"), "scope": .string("x")])])])
        #expect(noTask.isToolError && noTask.resultText.contains("missing 'task' description"))
        let badDep = try await host.server.callTool("use_workers", ["workers": .array([
            .object(["name": .string("A"), "scope": .string("x"), "task": .string("do it"), "dependencies": .array([.string("B")])]),
        ])])
        #expect(badDep.isToolError && badDep.resultText.contains("depends on unknown worker 'B'"))
        let valid = try await host.server.callTool("use_workers", ["workers": .array([
            .object(["name": .string("A"), "scope": .string("x"), "task": .string("do it")]),
        ])])
        #expect(valid.isToolError && valid.resultText.contains("worker runtime"))
    }

    @Test func takeScreenrecordValidatesThenFailsNamingItsPrerequisite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("take_screenrecord", [:])
        #expect(missing.isToolError)
        let badDuration = try await host.server.callTool("take_screenrecord", ["app_identifier": .string("com.apple.finder"),
                                                                               "recording_duration": .double(0)])
        #expect(badDuration.isToolError && badDuration.resultText.contains("between 1 and 60 seconds"))
        let valid = try await host.server.callTool("take_screenrecord", ["app_identifier": .string("com.apple.finder")])
        #expect(valid.isToolError && valid.resultText.contains("stream-recording engine"))
    }
}
