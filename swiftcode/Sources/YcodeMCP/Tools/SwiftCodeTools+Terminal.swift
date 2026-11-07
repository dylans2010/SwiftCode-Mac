#if canImport(AppKit)
import AppKit
#endif
#if canImport(SwiftCodeExtensions)
import SwiftCodeExtensions
#endif
import Foundation
import YcodeAssistant
import YcodeIDECore
import YcodeSubprocess

extension SwiftCodeMCPHost {
    var terminalTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let execution = MCPToolAnnotations(readOnly: false, idempotent: false)
        let external = MCPToolAnnotations(readOnly: false, idempotent: false, openWorld: true)
        let externalRead = MCPToolAnnotations(readOnly: true, idempotent: true, openWorld: true)
        return [
            tool("use_terminal", "Use Terminal",
                 "Executes terminal commands on the user's machine. Commands on the user's allow-list (Assist Settings > Terminal Command Approvals), or any command when Full Access is enabled, run without an approval prompt; all other commands require explicit user approval.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "command": Schema.string("The full shell command to run (e.g., 'git status' or 'swift test')"),
                                       "workingDirectory": Schema.string("The relative path from project root where command should run (optional)"),
                                       "explanation": Schema.string("A concise explanation of why this terminal execution is required (optional)"),
                                       "estimatedImpact": Schema.string("The estimated impact on the repository (optional)"),
                                       "modifiesRepo": Schema.string("Whether the command modifies repository state ('true' or 'false', optional)")],
                                      required: ["command"]),
                 output: Schema.output(["command": Schema.str, "workingDirectory": Schema.str, "stdout": Schema.str,
                                        "stderr": Schema.str, "stdoutTruncated": Schema.bool, "stderrTruncated": Schema.bool,
                                        "exitCode": Schema.int, "duration": Schema.str]),
                 annotations: execution, writes: true) { h, call in
                try await h.useTerminal(call)
            },
            tool("task_runner", "Run Task",
                 "Executes a registered internal Swift task within the sandbox.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "task_id": Schema.string("Identifier of the registered task to execute.")],
                                      required: ["task_id"]),
                 output: Schema.output(["output": Schema.str]),
                 annotations: execution, writes: true) { h, call in
                try await h.runTask(call)
            },
            tool("env_capture_logs", "Capture Logs",
                 "Captures logs from the execution environment.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "memoryKey": Schema.string("Optional memory key whose stored value is included as context. Default: \"\".")]),
                 annotations: .read) { h, call in
                try await h.captureLogsReal(call)
            },
            tool("env_info", "Environment Info",
                 "Provides information about the runtime environment (OS, Swift version, etc.).",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["os": Schema.str, "locale": Schema.str, "timezone": Schema.str,
                                        "cpu_count": Schema.int, "physical_memory_bytes": Schema.int,
                                        "workspace_root": Schema.str])) { h, call in
                try h.environmentInfo(call)
            },
            tool("use_mcp", "Execute MCP Tool",
                 "Enumerate configured MCP servers, discover capabilities, and execute external tools (e.g. GitHub, databases, developer services). Pass toolName: 'list_tools' to discover available tools.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "serverName": Schema.string("The display name of the configured MCP server (or 'list' to enumerate all servers)."),
                                       "toolName": Schema.string("The name of the tool to execute on the selected MCP server (or 'list_tools' to inspect available tools)."),
                                       "arguments": Schema.string("A JSON-serialized object string containing the arguments to pass to the MCP tool (pass '{}' for list_tools).")],
                                      required: ["serverName", "toolName", "arguments"]),
                 annotations: external, writes: true) { h, call in
                try await h.useMCPExternal(call)
            },
            tool("use_extension", "Use Extension",
                 "Interact with installed SwiftCode extensions: list, inspect, activate, and execute VS Code extension commands through the real extension host, and run Xcode-compatible source-editor commands against real workspace files. Actions: list, details, list_commands, list_xcode_commands, activate, deactivate, execute, run_xcode_command, enable, disable, diagnostics. Mutating actions (activate, execute, run_xcode_command, enable, disable) require confirm: true. Extension ids are stable publisher.name ids; Xcode command ids look like com.swiftcode.xcode.sortLines.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("One of: list, details, list_commands, list_xcode_commands, activate, deactivate, execute, run_xcode_command, enable, disable, diagnostics."),
                                       "extensionId": Schema.string("Stable publisher.name id of the extension. Required for every action except list and list_xcode_commands."),
                                       "command": Schema.string("Command id for execute (a VS Code / native contributed command) or run_xcode_command (an Xcode command identifier, e.g. com.swiftcode.xcode.sortLines)."),
                                       "file": Schema.string("Workspace-relative path for run_xcode_command. Absolute paths and paths escaping the workspace are rejected."),
                                       "selection": Schema.object(["startLine": Schema.integer("First line of the selection."),
                                                                 "startColumn": Schema.integer("First column of the selection."),
                                                                 "endLine": Schema.integer("Last line of the selection."),
                                                                 "endColumn": Schema.integer("Last column of the selection.")],
                                                                required: []),
                                       "args": Schema.anyObject,
                                       "confirm": Schema.boolean("Required true for activate, execute, run_xcode_command, enable, and disable; the model must explicitly confirm the consequential action."),
                                       "limit": Schema.integer("Max rows for list and diagnostics (default 50, capped at 200).")],
                                      required: ["action"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.useExtension(call)
            },
            tool("use_composio", "Execute Composio Tool",
                 "Execute external connected tools (GitHub, Slack, Google Calendar, Jira, Linear, Gmail, etc.) via Composio Platform or CLI.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "toolSlug": Schema.string("The slug of the Composio tool to execute (e.g. 'GITHUB_GET_THE_AUTHENTICATED_USER', 'GITHUB_LIST_REPOSITORIES_FOR_THE_AUTHENTICATED_USER', 'GITHUB_CREATE_AN_ISSUE', 'SLACK_SEND_A_MESSAGE_TO_A_SLACK_CHANNEL')."),
                                       "arguments": Schema.string("A JSON-serialized object string containing the arguments to pass to the tool.")],
                                      required: ["toolSlug", "arguments"]),
                 annotations: external, writes: true) { h, call in
                try await h.useComposioExecute(call)
            },
            tool("use_workers", "Create and Coordinate Assist Workers",
                 "Decomposes and schedules parallel or sequenced autonomous Workers for sub-tasks.\nEach worker must have a distinct name, non-overlapping scope, and concise task (under 500 characters).\nWorkers execute real work through the Assist tool suite; results are verified against the filesystem.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "workers": Schema.array(Schema.anyObject, "List of distinct worker assignments. Each element is an object with:\n- name (string, required): unique worker name.\n- scope (string, required): explicit area of responsibility (module or directory). Must not overlap with other workers' scopes.\n- task (string, required): concrete task description, max 500 characters.\n- role (string, optional): e.g. \"General Engineer\", \"Systems Architect\".\n- dependencies (array of strings, optional): names of other workers in this batch that must complete first.\n- targetFiles (array of strings, optional): specific files this worker may modify. Must not overlap with other workers' target files.")],
                                      required: ["workers"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.useWorkersReal(call)
            },
            tool("environment_variable_manager", "Environment Variable Manager",
                 "Inspects, checks, or updates workspace .env configuration files and environment keys.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'list_keys', 'get', 'set'."),
                                       "key": Schema.string("Variable name when action is 'get' or 'set'."),
                                       "value": Schema.string("Value to write when action is 'set'."),
                                       "envFilePath": Schema.string("Optional path to .env file. Defaults to '.env'.")],
                                      required: ["action"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.environmentVariableManager(call)
            },
            tool("clipboard_manager_tool", "Clipboard Manager",
                 "Reads text from or copies content to the macOS system clipboard (NSPasteboard).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'read' (read current clipboard) or 'copy' (write content to clipboard)."),
                                       "content": Schema.string("Text content to copy when action is 'copy'.")],
                                      required: ["action"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.clipboardManager(call)
            },
            tool("process_monitor_tool", "Process Monitor",
                 "Monitors active build, compiler, simulator, and child processes on macOS.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "filter": Schema.string("Optional process name filter (e.g. 'xcodebuild', 'swift', 'Simulator').")]),
                 annotations: .read) { h, call in
                try await h.processMonitor(call)
            },
            tool("disk_space_analyzer", "Disk Space Analyzer",
                 "Calculates disk consumption across DerivedData, project build outputs, and caches.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional specific directory path to inspect. Defaults to workspace root and DerivedData.")]),
                 annotations: .read) { h, call in
                try h.diskSpaceAnalyzer(call)
            },
            tool("system_notification_tool", "Post macOS System Notification",
                 "Posts a genuine macOS system notification banner or alert with custom title, subtitle, sound, and message body for build status, task completions, or developer alerts.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "title": Schema.string("Notification title. Defaults to \"SwiftCode Assist\"."),
                                       "subtitle": Schema.string("Notification subtitle."),
                                       "message": Schema.string("Notification message body. Defaults to \"Task completed.\"."),
                                       "body": Schema.string("Alias for message: notification message body."),
                                       "sound": Schema.string("Sound name: \"default\", \"none\", or a sound file name. Defaults to \"default\"."),
                                       "critical": Schema.boolean("Whether the notification sound is critical. Defaults to false.")]),
                 annotations: externalRead) { h, call in
                try await h.systemNotification(call)
            },
            tool("use_system", "System Diagnostics",
                 "macOS system diagnostics and one authorized user-level configuration op. Diagnostics: system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read (sysctl allowlist). Mutation: user_defaults_write (requires confirm: true; verified by read-back). Fixed-argv subprocesses only; privileged actions are refused, never escalated.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "operation": Schema.string("One of: system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read, user_defaults_write."),
                                       "target": Schema.string("Operation-dependent: process name filter (process_list), interface name (network_interfaces), hostname (connectivity), sysctl name (config_read, must be on the allowlist), defaults domain (user_defaults_write)."),
                                       "parameters": Schema.object(["port": Schema.integer("TCP port for connectivity (1-65535, required)."),
                                                                 "timeoutSeconds": ["type": "number", "description": .string("Timeout for connectivity in seconds (default 5, max 30).")],
                                                                 "limit": Schema.integer("Max rows for process_list (default 50, capped at 200)."),
                                                                 "filter": Schema.string("Name filter for process_list (also accepted via target)."),
                                                                 "predicate": Schema.string("NSPredicate string for system_log (e.g. 'process == \"kernel\"')."),
                                                                 "minutes": Schema.integer("Lookback window for system_log in minutes (1-60, default 15)."),
                                                                 "domain": Schema.string("Defaults domain for user_defaults_write (also accepted via target)."),
                                                                 "key": Schema.string("Defaults key for user_defaults_write (required)."),
                                                                 "value": ["description": .string("Value for user_defaults_write (string, number, or boolean; required).")]],
                                                                required: []),
                                       "confirm": Schema.boolean("Required true for user_defaults_write; the model must explicitly confirm the mutation.")],
                                      required: ["operation"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.useSystem(call)
            },
            tool("take_screenshot", "take_screenshot",
                 "Captures the user's entire screen or a user-selected screen region, produces a valid PNG image, and makes the resulting image available to the active AI model for visual analysis.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "capture_mode": Schema.string("Screen capture mode: 'fullscreen' for entire screen, 'region' for a screen rect (needs 'region'), or 'window' for one window (needs 'window_id'). Defaults to 'fullscreen'."),
                                       "display_id": Schema.integer("Optional display identifier when multiple displays are connected."),
                                       "region": Schema.object(["x": ["type": "number", "description": .string("Left edge in screen points, origin top-left of the main display.")],
                                                               "y": ["type": "number", "description": .string("Top edge in screen points, origin top-left of the main display.")],
                                                               "width": ["type": "number", "description": .string("Region width in screen points.")],
                                                               "height": ["type": "number", "description": .string("Region height in screen points.")] ],
                                                              required: []),
                                       "window_id": Schema.string("Target window identifier for capture_mode 'window' (e.g. 'window_12345' as listed by use_app list_windows, or a bare window number)."),
                                       "include_cursor": Schema.boolean("Whether to include the mouse cursor in the capture. Defaults to true."),
                                       "image_format": Schema.string("Image output format. Must be 'png'. Defaults to 'png'."),
                                       "purpose": Schema.string("Optional explanation of what Assist needs to inspect in the screenshot.")]),
                 output: Schema.output(["path": Schema.str, "width": Schema.int, "height": Schema.int, "display_id": Schema.int,
                                        "capture_mode": Schema.str, "artifact_id": Schema.str, "base64": Schema.str,
                                        "format": Schema.str, "size_bytes": Schema.int]),
                 annotations: MCPToolAnnotations(readOnly: false, idempotent: true, openWorld: true), writes: true) { h, call in
                try await h.takeScreenshotReal(call)
            },
            tool("take_screenrecord", "take_screenrecord",
                 "Records the screen of a specifically identified application, subject to macOS privacy permissions and recording restrictions, and produces a usable recording artifact.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "app_identifier": Schema.string("Target application bundle identifier (e.g. 'com.apple.dt.Xcode') or application name (e.g. 'Xcode'). Preferred: bundle identifier."),
                                       "recording_duration": ["type": "number", "description": .string("Requested recording duration in seconds (between 1 and 60). Defaults to 10 seconds.")],
                                       "capture_mode": Schema.string("Capture scope: 'window' for the application's primary on-screen window, or 'application_display'. Defaults to 'window'."),
                                       "include_audio": Schema.boolean("Whether to capture application audio when supported. Defaults to false."),
                                       "output_format": Schema.string("Video container format. Supported: 'mov', 'mp4'. Defaults to 'mov'."),
                                       "purpose": Schema.string("Optional natural-language explanation of why Assist is recording this application.")],
                                      required: ["app_identifier"]),
                 annotations: externalRead) { h, call in
                try await h.takeScreenrecordReal(call)
            },
            tool("use_app", "use_app",
                 "Enables Assist to operate native macOS applications through real Accessibility APIs, CoreGraphics synthetic events, ScreenCaptureKit visual perception, and window management.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "app_identifier": Schema.string("Target application bundle identifier (e.g. 'com.apple.finder'), app name (e.g. 'Finder', 'Calculator'), process ID, or session ID."),
                                       "action": Schema.string("Action to perform: 'launch', 'activate', 'list_applications', 'inspect_application', 'list_windows', 'select_window', 'close_application', 'inspect_ui', 'get_accessibility_tree', 'get_focused_element', 'take_screenshot', 'inspect_window', 'click', 'double_click', 'right_click', 'move_pointer', 'drag', 'scroll', 'type_text', 'press_key', 'press_shortcut', 'select_all', 'copy', 'paste', 'activate_element', 'set_element_value', 'select_menu', 'wait_for_element', 'wait_for_window', 'verify'."),
                                       "target": Schema.string("Target UI element session ID (e.g. 'elem_1'), title, accessibility identifier, label, or menu path (e.g. 'File > Save')."),
                                       "value": Schema.string("Text input to type, shortcut name (e.g. 'Cmd+S'), key name (e.g. 'Return'), or expected value for verification."),
                                       "coordinates": Schema.object(["x": ["type": "number", "description": .string("X coordinate.")],
                                                                   "y": ["type": "number", "description": .string("Y coordinate.")],
                                                                   "coordinate_space": Schema.string("Coordinate space: 'screen', 'window', or 'screenshot_pixel'. Defaults to 'screen'.")],
                                                                  required: []),
                                       "drag_destination": Schema.object(["x": ["type": "number", "description": .string("Destination X coordinate.")],
                                                                        "y": ["type": "number", "description": .string("Destination Y coordinate.")]],
                                                                       required: []),
                                       "scroll_delta": Schema.object(["dx": Schema.integer("Horizontal scroll delta in pixels."),
                                                                    "dy": Schema.integer("Vertical scroll delta in pixels.")],
                                                                   required: []),
                                       "window_id": Schema.string("Optional target window identifier (e.g. 'window_1')."),
                                       "modifiers": Schema.array(Schema.str, "Optional key modifier list (e.g. ['command', 'shift'])."),
                                       "timeout": ["type": "number", "description": .string("Timeout in seconds for wait operations (1-60, default 5).")],
                                       "verification": Schema.boolean("Whether to re-inspect and verify resulting application state after action. Defaults to true."),
                                       "confirm": Schema.boolean("Explicit user authorization required for consequential actions such as 'close_application'."),
                                       "purpose": Schema.string("Natural-language explanation of the intended workflow or interaction purpose.")],
                                      required: ["app_identifier", "action"]),
                 annotations: MCPToolAnnotations(readOnly: false, idempotent: true, openWorld: true), writes: true) { h, call in
                try await h.useAppReal(call)
            },
        ]
    }

    func terminalApproveChange(tool: String, summary: String, in s: WorkspaceSession, call: MCPToolCall) async throws {
        let root = Self.folder(of: s.model)
        let change = MCPChange(tool: tool, path: root.path, relativePath: ".", original: nil, proposed: "", summary: summary)
        guard await call.approve(change) else { throw MCPToolError(MCPServer.rejectedMessage) }
    }
}

extension SwiftCodeMCPHost {

    func useTerminal(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let command = call.arguments["command"]?.string ?? ""
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Command cannot be empty")
        }
        let relativeWorkDir = call.string("workingDirectory") ?? ""
        let explanation = call.string("explanation") ?? "Executing shell command"
        let estimatedImpact = call.string("estimatedImpact") ?? "Runs terminal command"
        let modifiesRepo: Bool
        if let boolVal = call.arguments["modifiesRepo"]?.bool {
            modifiesRepo = boolVal
        } else if let strVal = call.arguments["modifiesRepo"]?.string {
            modifiesRepo = strVal.lowercased() == "true"
        } else {
            modifiesRepo = false
        }

        let workingDirURL: URL
        if relativeWorkDir.isEmpty {
            workingDirURL = fileReadingDirectory(in: s)
        } else {
            do {
                workingDirURL = try resolveFileReadingPath(relativeWorkDir, in: s)
            } catch {
                throw MCPToolError("Invalid workingDirectory '\(relativeWorkDir)': \(Self.fileWritingErrorText(error))")
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: workingDirURL.path, isDirectory: &isDir), isDir.boolValue else {
                throw MCPToolError("workingDirectory does not exist or is not a directory: \(relativeWorkDir)")
            }
        }

        guard let argv = Self.terminalTokenizeCommand(command), let program = argv.first else {
            throw MCPToolError("Command '\(command)' cannot run without a shell (it uses pipes, redirects, variables, globbing, or other shell syntax). Split it into separate plain commands, or use a dedicated tool (git_*, file_*, build).")
        }
        guard let executable = Self.terminalResolveProgram(program, workingDirectory: workingDirURL) else {
            throw MCPToolError("Process execution failed: command '\(program)' was not found (no executable on PATH or at that path).")
        }

        try await terminalApproveChange(tool: call.name,
                                        summary: "Run terminal command: \(command) — \(explanation) (estimated impact: \(estimatedImpact); modifies repo: \(modifiesRepo))",
                                        in: s, call: call)

        let start = Date()
        let result = (await Task.detached {
            Self.terminalRunFixed(executable, Array(argv.dropFirst()), workingDirectory: workingDirURL,
                                  environment: Self.terminalEnvironment(), timeout: 300)
        }.value)
        guard let result else {
            throw MCPToolError("Process execution failed: could not launch \(executable)")
        }
        let duration = Date().timeIntervalSince(start)
        let durationText = String(format: "%.2fs", duration)
        if result.timedOut {
            let data: [String: AnyJSON] = ["command": .string(command), "workingDirectory": .string(workingDirURL.path),
                                           "stdout": .string(result.stdout), "stderr": .string(result.stderr),
                                           "stdoutTruncated": .bool(false), "stderrTruncated": .bool(false),
                                           "exitCode": .int(Int(result.exitCode)), "duration": .string(durationText)]
            return .error("Terminal command timed out after 300s: \(command)", structured: .object(data))
        }
        let stdoutTruncated = result.stdout.count > 3000
        let stderrTruncated = result.stderr.count > 2000
        let stdoutTail = String(result.stdout.suffix(3000)) + (stdoutTruncated ? "\n… [stdout truncated to last 3000 chars]" : "")
        let stderrTail = String(result.stderr.suffix(2000)) + (stderrTruncated ? "\n… [stderr truncated to last 2000 chars]" : "")
        let data: [String: AnyJSON] = ["command": .string(command), "workingDirectory": .string(workingDirURL.path),
                                       "stdout": .string(stdoutTail), "stderr": .string(stderrTail),
                                       "stdoutTruncated": .bool(stdoutTruncated), "stderrTruncated": .bool(stderrTruncated),
                                       "exitCode": .int(Int(result.exitCode)), "duration": .string(durationText)]
        if result.exitCode == 0 {
            let stdoutShown = result.stdout.isEmpty ? "(No stdout output)"
                : String(result.stdout.suffix(2000)) + (result.stdout.count > 2000 ? "\n… [stdout truncated to last 2000 chars]" : "")
            return .structured(.object(data), summary: "Terminal command executed successfully (exit code 0 in \(durationText)):\n\(stdoutShown)")
        }
        let errSummary = result.stderr.isEmpty ? result.stdout : result.stderr
        return .error("Terminal command failed with exit code \(result.exitCode) (\(durationText)):\n\(String(errSummary.suffix(1500)))",
                      structured: .object(data))
    }

    func runTask(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let taskId = try call.require("task_id")
        let root = Self.folder(of: s.model)
        let output: String
        do {
            switch taskId {
            case "project_indexing": output = try Self.terminalTaskProjectIndexing(root: root)
            case "dependency_analysis": output = Self.terminalTaskDependencyAnalysis(root: root)
            case "lint_project": output = Self.terminalTaskLintProject(root: root)
            case "project_test": output = Self.terminalTaskProjectTest(root: root)
            default: throw NSError(domain: "AssistExecution", code: 404,
                                   userInfo: [NSLocalizedDescriptionKey: "Task '\(taskId)' not found in registry."])
            }
        } catch {
            throw MCPToolError("Task '\(taskId)' failed: \(error.localizedDescription)")
        }
        return .structured(["output": .string(output)], summary: "Task '\(taskId)' executed successfully.")
    }

    nonisolated static func terminalTaskProjectIndexing(root: URL) throws -> String {
        let fileCount = try FileManager.default.subpathsOfDirectory(atPath: root.path).count
        return "Indexed project at \(root.lastPathComponent). Found \(fileCount) filesystem entries."
    }

    nonisolated static func terminalTaskDependencyAnalysis(root: URL) -> String {
        let hasPackageSwift = FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path)
        let hasPodfile = FileManager.default.fileExists(atPath: root.appendingPathComponent("Podfile").path)
        let hasCartfile = FileManager.default.fileExists(atPath: root.appendingPathComponent("Cartfile").path)
        return "Dependency scan complete. SPM: \(hasPackageSwift), CocoaPods: \(hasPodfile), Carthage: \(hasCartfile)."
    }

    nonisolated static func terminalTaskLintProject(root: URL) -> String {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles])
        var findings: [String] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                if line.contains("\t") {
                    findings.append("\(fileURL.lastPathComponent):\(index + 1) contains tab indentation")
                }
                if line.count > 140 {
                    findings.append("\(fileURL.lastPathComponent):\(index + 1) line exceeds 140 chars")
                }
                if line.hasSuffix(" ") {
                    findings.append("\(fileURL.lastPathComponent):\(index + 1) trailing whitespace")
                }
            }
        }
        if findings.isEmpty {
            return "Lint completed. 0 issues found across scanned Swift files."
        }
        return "Lint completed. Found \(findings.count) issue(s).\n\(findings.prefix(20).joined(separator: "\n"))"
    }

    nonisolated static func terminalTaskProjectTest(root: URL) -> String {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles])
        var testFiles: [String] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            if fileURL.path.lowercased().contains("test") {
                testFiles.append(fileURL.lastPathComponent)
            }
        }
        testFiles.sort()
        guard !testFiles.isEmpty else {
            return "No XCTest files discovered under workspace root."
        }
        return "Discovered \(testFiles.count) XCTest file(s). Sample: \(testFiles.prefix(5).joined(separator: ", "))"
    }

    func captureLogs(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await captureLogsReal(call)
    }

    func environmentInfo(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let info = ProcessInfo.processInfo
        return .structured(["os": .string(info.operatingSystemVersionString),
                            "locale": .string(Locale.current.identifier),
                            "timezone": .string(TimeZone.current.identifier),
                            "cpu_count": .int(info.processorCount),
                            "physical_memory_bytes": .int(Int(info.physicalMemory)),
                            "workspace_root": .string(Self.folder(of: s.model).path)],
                           summary: "Environment info retrieved")
    }
}

extension SwiftCodeMCPHost {

    func useMCP(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await useMCPExternal(call)
    }

    static let extensionsHostUnavailableMessage = "use_extension needs the Extensions v2 platform (ExtV2Manager + extension host with Node.js), which SwiftCode's MCP host does not have yet; no extension was listed, activated, or executed."

    func extensionLimit(_ call: MCPToolCall) -> Int {
        if let v = call.arguments["limit"]?.int { return min(200, max(1, v)) }
        if let d = call.arguments["limit"]?.double { return min(200, max(1, Int(d))) }
        return 50
    }

    func extensionCap(_ text: String) -> String {
        guard text.count > 8000 else { return text }
        return String(text.prefix(8000)) + "\n... (truncated)"
    }

    struct ExtensionXcodeFileTarget {
        let url: URL
        let relativePath: String
        let content: String
        let lines: [String]
        let startLine: Int
        let startColumn: Int
        let endLine: Int
        let endColumn: Int
    }

    func validateXcodeFileTarget(_ call: MCPToolCall) throws -> ExtensionXcodeFileTarget {
        let s = try session(for: call)
        let file = try call.require("file")
        guard !file.hasPrefix("/") else {
            throw MCPToolError("Action 'run_xcode_command' requires a workspace-relative 'file'; absolute paths are rejected: \(file)")
        }
        let url: URL
        do {
            url = try resolve(file, in: s)
        } catch {
            throw MCPToolError("Action 'run_xcode_command' requires a workspace-relative 'file': \(Self.fileWritingErrorText(error))")
        }
        let rel = relative(url.path, in: s)
        guard let content = text(of: url) else {
            throw MCPToolError("Cannot read '\(rel)': no such file in the workspace.")
        }
        let lines = content.components(separatedBy: .newlines)
        let sel = call.arguments["selection"]?.object ?? [:]
        let startLine = sel["startLine"]?.int ?? 0
        let startColumn = sel["startColumn"]?.int ?? 0
        let endLine = sel["endLine"]?.int ?? max(0, lines.count - 1)
        let endColumn = sel["endColumn"]?.int ?? (lines.indices.contains(endLine) ? lines[endLine].count : 0)
        func outOfBounds(_ why: String) -> MCPToolError {
            MCPToolError("Selection is out of bounds for '\(rel)': \(why) (\(lines.count) lines).")
        }
        guard startLine >= 0, endLine >= 0, startLine < lines.count, endLine < lines.count else {
            throw outOfBounds("lines \(startLine)–\(endLine) do not exist")
        }
        guard startColumn >= 0, endColumn >= 0,
              startColumn <= lines[startLine].count, endColumn <= lines[endLine].count else {
            throw outOfBounds("columns \(startColumn)/\(endColumn) exceed their lines")
        }
        guard (startLine, startColumn) <= (endLine, endColumn) else {
            throw outOfBounds("the selection starts after it ends")
        }
        return ExtensionXcodeFileTarget(url: url, relativePath: rel, content: content, lines: lines,
                                        startLine: startLine, startColumn: startColumn, endLine: endLine, endColumn: endColumn)
    }

    func useExtension(_ call: MCPToolCall) async throws -> MCPToolResult {
        let known = ["list", "details", "list_commands", "list_xcode_commands", "activate",
                     "deactivate", "execute", "run_xcode_command", "enable", "disable", "diagnostics"]
        guard let action = call.arguments["action"]?.string, known.contains(action) else {
            throw MCPToolError("Unknown or missing action. Use one of: \(known.joined(separator: ", ")).")
        }
        let mutating: Set<String> = ["activate", "execute", "run_xcode_command", "enable", "disable"]
        if mutating.contains(action), call.bool("confirm") != true {
            throw MCPToolError("Action '\(action)' requires confirm: true.")
        }
        let extensionId: String?
        if action == "list" || action == "list_xcode_commands" {
            extensionId = call.string("extensionId")
        } else {
            guard let id = call.string("extensionId") else {
                throw MCPToolError("Action '\(action)' requires 'extensionId'.")
            }
            extensionId = id
        }
        if action == "execute" || action == "run_xcode_command" {
            guard call.string("command") != nil else {
                throw MCPToolError("Action '\(action)' requires 'command'.")
            }
        }
        let xcodeTarget: ExtensionXcodeFileTarget?
        if action == "run_xcode_command" {
            xcodeTarget = try validateXcodeFileTarget(call)
        } else {
            xcodeTarget = nil
        }
#if canImport(SwiftCodeExtensions)
        return try await useExtensionViaHost(action, extensionId: extensionId, call: call, xcodeTarget: xcodeTarget)
#else
        _ = xcodeTarget
        throw MCPToolError(Self.extensionsHostUnavailableMessage)
#endif
    }

#if canImport(SwiftCodeExtensions)
    func useExtensionViaHost(_ action: String, extensionId: String?, call: MCPToolCall,
                             xcodeTarget: ExtensionXcodeFileTarget?) async throws -> MCPToolResult {
        do {
            return try await useExtensionHostDispatch(action, extensionId: extensionId, call: call, xcodeTarget: xcodeTarget)
        } catch let toolError as MCPToolError {
            throw toolError
        } catch {
            throw MCPToolError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func useExtensionHostDispatch(_ action: String, extensionId: String?, call: MCPToolCall,
                                  xcodeTarget: ExtensionXcodeFileTarget?) async throws -> MCPToolResult {
        let manager = ExtensionManager.shared
        if action != "list_xcode_commands" {
            await manager.ensureReady()
        }
        let limit = extensionLimit(call)
        switch action {
        case "list":
            manager.refreshInstalled()
            let rows = manager.installed.prefix(limit).map {
                " \($0.id) — \($0.metadata.displayName) v\($0.metadata.version) [\($0.metadata.kind.displayName), \($0.state.displayName)]"
            }
            let text = rows.isEmpty
                ? "No extensions installed. Discover extensions from the Extensions sidebar (Open VSX registry) or register the sample native plugin."
                : rows.joined(separator: "\n")
            return .structured(["action": .string("list"), "count": .int(rows.count)], summary: extensionCap(text))

        case "details":
            let id = extensionId!
            guard let installed = manager.installed.first(where: { $0.id == id }) else {
                throw MCPToolError(SwiftCodeExtensionError.notInstalled(id).localizedDescription)
            }
            return .structured(["action": .string("details"), "state": .string(installed.state.rawValue),
                                "kind": .string(installed.metadata.kind.rawValue)],
                               summary: extensionCap(extensionDetailsText(installed, manager: manager)))

        case "list_commands":
            let id = extensionId!
            guard manager.installed.contains(where: { $0.id == id }) else {
                throw MCPToolError(SwiftCodeExtensionError.notInstalled(id).localizedDescription)
            }
            let text = extensionCommandsText(id, manager: manager)
            return .structured(["action": .string("list_commands"), "extensionId": .string(id)], summary: extensionCap(text))

        case "list_xcode_commands":
            let ids = XcodeCommandRegistry.shared.allIdentifiers
            let text = ids.isEmpty
                ? "No Xcode-compatible commands are registered. Only registered source-editor command logic can run; XcodeKit binaries cannot run inside SwiftCode."
                : ids.joined(separator: "\n")
            return .structured(["action": .string("list_xcode_commands"), "count": .int(ids.count)], summary: extensionCap(text))

        case "activate":
            let id = extensionId!
            guard manager.installed.contains(where: { $0.id == id }) else {
                throw MCPToolError(SwiftCodeExtensionError.notInstalled(id).localizedDescription)
            }
            let s = try session(for: call)
            manager.setWorkspaceRoot(Self.folder(of: s.model))
            try await terminalApproveChange(tool: call.name,
                                            summary: "Activate extension '\(id)' (runs its code in the extension host).",
                                            in: s, call: call)
            let contribution: ExtensionContribution
            do {
                contribution = try await manager.activate(extensionId: id)
            } catch {
                throw MCPToolError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            var text = "Activated \(id)."
            if !contribution.commands.isEmpty {
                text += "\nCommands:\n" + contribution.commands.map { "- \($0.command) (\($0.title))" }.joined(separator: "\n")
            }
            if !contribution.outputLines.isEmpty {
                text += "\nOutput:\n" + contribution.outputLines.joined(separator: "\n")
            }
            return .structured(["action": .string("activate"), "state": .string("running")], summary: extensionCap(text))

        case "deactivate":
            let id = extensionId!
            manager.deactivate(extensionId: id)
            return .structured(["action": .string("deactivate")], summary: "Deactivated \(id).")

        case "execute":
            let id = extensionId!
            let command = call.string("command")!
            guard let installed = manager.installed.first(where: { $0.id == id }) else {
                throw MCPToolError(SwiftCodeExtensionError.notInstalled(id).localizedDescription)
            }
            guard installed.isEnabled, installed.state != .disabled else {
                throw MCPToolError(SwiftCodeExtensionError.disabled(id).localizedDescription)
            }
            let s = try session(for: call)
            manager.setWorkspaceRoot(Self.folder(of: s.model))
            try await terminalApproveChange(tool: call.name,
                                            summary: "Execute command '\(command)' from extension '\(id)' (runs extension code).",
                                            in: s, call: call)
            let argsObject = call.arguments["args"]?.object ?? [:]
            let args: [SwiftCodeExtensions.JSONValue] = argsObject.isEmpty ? [] : [.object(argsObject.mapValues { extensionJSONValue($0) })]
            let result: String
            do {
                result = try await manager.executeCommand(extensionId: id, command: command, args: args)
            } catch {
                throw MCPToolError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            let text = result.isEmpty ? "(command returned no output)" : result
            return .structured(["action": .string("execute"), "result": .string(result)], summary: extensionCap(text))

        case "run_xcode_command":
            let command = call.string("command")!
            let target = xcodeTarget!
            let s = try session(for: call)
            guard XcodeCommandRegistry.shared.command(for: command) != nil else {
                let ids = XcodeCommandRegistry.shared.allIdentifiers
                throw MCPToolError("Unknown Xcode command '\(command)'. Registered commands: \(ids.isEmpty ? "none" : ids.joined(separator: ", ")).")
            }
            manager.setWorkspaceRoot(Self.folder(of: s.model))
            let buffer = SourceTextBuffer(lines: target.lines,
                                          selections: [SourceRange(start: SourcePosition(line: target.startLine, column: target.startColumn),
                                                                   end: SourcePosition(line: target.endLine, column: target.endColumn))])
            let linesBefore = target.lines.count
            do {
                try await XcodeCommandRegistry.shared.perform(identifier: command, buffer: buffer)
            } catch {
                throw MCPToolError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            let newContent = buffer.completeBuffer
            guard newContent != target.content else {
                return .structured(["action": .string("run_xcode_command"), "changed": .bool(false),
                                    "filesChanged": .array([])],
                                   summary: "Command '\(command)' made no changes to \(target.relativePath).")
            }
            let linesAfter = newContent.components(separatedBy: .newlines).count
            try await commit(MCPChange(tool: call.name, path: target.url.path, relativePath: target.relativePath,
                                       original: target.content, proposed: newContent,
                                       summary: "Run Xcode command '\(command)' on \(target.relativePath)"),
                             call: call, session: s)
            let summary = "Command '\(command)' updated \(target.relativePath): \(linesBefore) lines → \(linesAfter) lines.\n\(newContent)"
            return .structured(["action": .string("run_xcode_command"), "changed": .bool(true),
                                "filesChanged": .array([.string(target.relativePath)]),
                                "linesBefore": .int(linesBefore), "linesAfter": .int(linesAfter)],
                               summary: extensionCap(summary))

        case "enable", "disable":
            let id = extensionId!
            let enabled = action == "enable"
            guard let installed = manager.installed.first(where: { $0.id == id }) else {
                throw MCPToolError(SwiftCodeExtensionError.notInstalled(id).localizedDescription)
            }
            let s = try session(for: call)
            try await terminalApproveChange(tool: call.name,
                                            summary: "\(enabled ? "Enable" : "Disable") extension '\(id)'.",
                                            in: s, call: call)
            manager.setEnabled(extensionId: id, enabled: enabled)
            manager.refreshInstalled()
            let state = manager.installed.first(where: { $0.id == id })?.state.displayName ?? installed.state.displayName
            return .structured(["action": .string(action), "state": .string(state)],
                               summary: "\(enabled ? "Enabled" : "Disabled") \(id) (state: \(state)).")

        case "diagnostics":
            let id = extensionId!
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let entries = DiagnosticsService.shared.entries(for: id).suffix(limit)
            let text = entries.isEmpty
                ? "No diagnostics recorded for \(id)."
                : entries.map { "[\(formatter.string(from: $0.timestamp))] [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
            return .structured(["action": .string("diagnostics"), "count": .int(entries.count)], summary: extensionCap(text))

        default:
            throw MCPToolError("Unknown or missing action. Use one of: list, details, list_commands, list_xcode_commands, activate, deactivate, execute, run_xcode_command, enable, disable, diagnostics.")
        }
    }

    func extensionJSONValue(_ value: AnyJSON) -> SwiftCodeExtensions.JSONValue {
        switch value {
        case .null: return .null
        case .bool(let b): return .bool(b)
        case .int(let i): return .int(i)
        case .double(let d): return .double(d)
        case .string(let s): return .string(s)
        case .array(let a): return .array(a.map { extensionJSONValue($0) })
        case .object(let o): return .object(o.mapValues { extensionJSONValue($0) })
        }
    }

    func extensionDetailsText(_ installed: InstalledExtension, manager: ExtensionManager) -> String {
        let m = installed.metadata
        var lines = ["\(m.displayName) (\(m.id))",
                     "Version: \(m.version)",
                     "Kind: \(m.kind.displayName)",
                     "State: \(installed.state.displayName)",
                     "Enabled: \(installed.isEnabled ? "yes" : "no")",
                     "Description: \(m.description.isEmpty ? "—" : m.description)"]
        let byID = Dictionary(uniqueKeysWithValues: manager.installed.map { ($0.id, $0) })
        let missing = Set(DependencyResolver.missingDependencies(for: installed, installedByID: byID))
        if installed.dependencies.isEmpty {
            lines.append("Dependencies: none")
        } else {
            lines.append("Dependencies:")
            for dep in installed.dependencies {
                lines.append("- \(dep) (\(missing.contains(dep) ? "missing" : "satisfied"))")
            }
        }
        let granted = manager.permissions.grantedCapabilities(for: installed.id)
        lines.append("Granted capabilities: \(granted.isEmpty ? "none" : granted.map(\.displayName).joined(separator: ", "))")
        if let lastError = installed.lastError, !lastError.isEmpty {
            lines.append("Last error: \(lastError)")
        }
        if m.kind == .vscode {
            let manifestURL = URL(fileURLWithPath: installed.installPath)
                .appendingPathComponent("extension/package.json")
            do {
                let manifest = try VSCodeManifestParser.parseFile(at: manifestURL)
                let report = Compatibility.evaluate(manifest: manifest)
                lines.append("Compatible: \(report.compatible)")
                for reason in report.reasons { lines.append("- \(reason)") }
            } catch {
                lines.append("Manifest could not be read: \(error.localizedDescription)")
            }
        }
        if let contribution = manager.contributions[installed.id], !contribution.commands.isEmpty {
            lines.append("Running commands:")
            for c in contribution.commands { lines.append("- \(c.command) (\(c.title))") }
        }
        return lines.joined(separator: "\n")
    }

    func extensionCommandsText(_ id: String, manager: ExtensionManager) -> String {
        guard let installed = manager.installed.first(where: { $0.id == id }) else {
            return "Extension \(id) contributes no commands (not installed)."
        }
        switch installed.metadata.kind {
        case .xcodeCommand:
            let ids = XcodeCommandRegistry.shared.allIdentifiers
            return ids.isEmpty
                ? "No Xcode-compatible commands are registered. Only registered source-editor command logic can run; XcodeKit binaries cannot run inside SwiftCode."
                : ids.joined(separator: "\n")
        case .native:
            if let manifest = NativePluginRegistry.shared.manifests.first(where: { $0.metadata.id == id }) {
                return manifest.commands.isEmpty
                    ? "Extension \(id) contributes no commands (native plugin)."
                    : manifest.commands.map { "\($0.command) (\($0.title)) — native plugin" }.joined(separator: "\n")
            }
            return "Extension \(id) contributes no commands (native plugin not registered)."
        case .vscode:
            if manager.hostManager.isRunning(extensionId: id),
               let contribution = manager.contributions[id], !contribution.commands.isEmpty {
                return contribution.commands.map { "\($0.command) (\($0.title)) (running)" }.joined(separator: "\n")
            }
            let manifestURL = URL(fileURLWithPath: installed.installPath)
                .appendingPathComponent("extension/package.json")
            do {
                let manifest = try VSCodeManifestParser.parseFile(at: manifestURL)
                return manifest.contributesCommands.isEmpty
                    ? "Extension \(id) contributes no commands (not running; activate first to execute)."
                    : manifest.contributesCommands.map { "\($0.command) (\($0.title)) — not running; activate first to execute" }.joined(separator: "\n")
            } catch {
                return "No commands found for extension \(id): manifest could not be read."
            }
        }
    }
#endif

    func useComposio(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await useComposioExecute(call)
    }

    func useWorkers(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await useWorkersReal(call)
    }

    func environmentVariableManager(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let actionRaw = call.arguments["action"]?.string else {
            throw MCPToolError("Missing required parameter: action")
        }
        let action = actionRaw.lowercased()
        let envFileName = call.string("envFilePath") ?? ".env"
        guard let envURL = resolveFileWritingPath(envFileName, in: s) else {
            throw MCPToolError("Invalid envFilePath '\(envFileName)': paths must stay inside the workspace.")
        }

        switch action {
        case "list_keys", "list":
            guard FileManager.default.fileExists(atPath: envURL.path),
                  let text = try? String(contentsOf: envURL, encoding: .utf8) else {
                return .text("No \(envFileName) file found in workspace.")
            }
            var keys: [String] = []
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                if let eq = trimmed.firstIndex(of: "=") {
                    keys.append(String(trimmed[..<eq]))
                }
            }
            return .text("Found \(keys.count) environment keys in `\(envFileName)`:\n\n" + keys.map { "- `\($0)`" }.joined(separator: "\n"))

        case "get":
            guard let key = call.arguments["key"]?.string, !key.isEmpty else {
                throw MCPToolError("Action 'get' requires 'key'.")
            }
            guard FileManager.default.fileExists(atPath: envURL.path),
                  let text = try? String(contentsOf: envURL, encoding: .utf8) else {
                throw MCPToolError("No \(envFileName) file found in workspace.")
            }
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(key)=") {
                    return .text("\(key)=\(String(trimmed.dropFirst(key.count + 1)))")
                }
            }
            throw MCPToolError("Key '\(key)' not found in \(envFileName).")

        case "set":
            guard let key = call.arguments["key"]?.string, !key.isEmpty else {
                throw MCPToolError("Action 'set' requires 'key'.")
            }
            let val = call.arguments["value"]?.string ?? ""
            let existing = text(of: envURL) ?? ""
            var lines = existing.components(separatedBy: .newlines)
            var replaced = false
            for (i, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=") {
                    lines[i] = "\(key)=\(val)"
                    replaced = true
                    break
                }
            }
            if !replaced {
                lines.append("\(key)=\(val)")
            }
            let updated = lines.joined(separator: "\n")
            let rel = fileReadingRelativePath(of: envURL, in: s)
            try await commit(MCPChange(tool: call.name, path: envURL.path, relativePath: rel, original: text(of: envURL),
                                       proposed: updated, summary: "Set \(key) in \(rel)"), call: call, session: s)
            return .text("Successfully set `\(key)` in `\(envFileName)`.")

        default:
            throw MCPToolError("Unsupported action '\(actionRaw)'. Supported: list_keys, get, set.")
        }
    }

    func clipboardManager(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let actionRaw = call.arguments["action"]?.string else {
            throw MCPToolError("Missing required parameter: action")
        }
        switch actionRaw.lowercased() {
        case "read", "get":
            let current = try terminalPasteboardRead()
            if current.isEmpty {
                return .text("Clipboard is currently empty.")
            }
            let preview = String(current.prefix(500))
            return .text("Current Clipboard Content (\(current.count) chars):\n\n```\n\(preview)\n```")
        case "copy", "write", "set":
            guard let content = call.arguments["content"]?.string else {
                throw MCPToolError("Action 'copy' requires 'content'.")
            }
            try terminalPasteboardWrite(content)
            return .text("Successfully copied \(content.count) characters to the system clipboard.")
        default:
            throw MCPToolError("Unsupported action '\(actionRaw)'. Supported: 'read', 'copy'.")
        }
    }

    func processMonitor(_ call: MCPToolCall) async throws -> MCPToolResult {
        _ = try session(for: call)
        let filter = call.string("filter")
        let result = (await Task.detached {
            Self.terminalRunFixed("/bin/ps", ["-eo", "pid,%cpu,%mem,comm"], timeout: 15)
        }.value)
        guard let result else {
            throw MCPToolError("Failed to query processes: failed to launch /bin/ps")
        }
        let output = result.stdout
        let lines = output.components(separatedBy: .newlines)
        let devKeywords = ["xcode", "swift", "clang", "simctl", "lldb", "git", "xcrun", "Simulator"]
        var matching: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("PID") { continue }
            if let f = filter, !f.isEmpty {
                if trimmed.localizedCaseInsensitiveContains(f) {
                    matching.append(trimmed)
                }
            } else {
                for kw in devKeywords where trimmed.localizedCaseInsensitiveContains(kw) {
                    matching.append(trimmed)
                    break
                }
            }
        }
        if matching.isEmpty {
            return .text("No active processes matching developer tools or filter '\(filter ?? "Xcode/Swift")'.")
        }
        var report = "### Active Developer Processes (\(matching.count) running):\n\n"
        report += "| PID | %CPU | %MEM | Command |\n|---|---|---|---|\n"
        for m in matching.prefix(25) {
            let parts = m.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 4 {
                let pid = parts[0]
                let cpu = parts[1]
                let mem = parts[2]
                let cmd = parts.dropFirst(3).joined(separator: " ")
                let shortCmd = (cmd as NSString).lastPathComponent
                report += "| `\(pid)` | \(cpu)% | \(mem)% | `\(shortCmd)` |\n"
            }
        }
        return .text(report)
    }

    func diskSpaceAnalyzer(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let targetDir: URL
        if let pathArg = call.string("path") {
            targetDir = try resolveFileReadingPath(pathArg, in: s)
        } else {
            targetDir = root
        }

        func directorySize(url: URL) -> Int64 {
            var size: Int64 = 0
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey],
                                                            options: [.skipsHiddenFiles])
            while let item = enumerator?.nextObject() as? URL {
                if let s = (try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    size += Int64(s)
                }
            }
            return size
        }

        let fm = ByteCountFormatter()
        fm.countStyle = .file
        let workspaceSize = directorySize(url: targetDir)
        let derivedData = URL(fileURLWithPath: ("~/Library/Developer/Xcode/DerivedData" as NSString).expandingTildeInPath)
        let derivedDataSize = directorySize(url: derivedData)

        var subDirReports: [(name: String, sizeStr: String, size: Int64)] = []
        if let subitems = try? FileManager.default.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for sub in subitems {
                var isD: ObjCBool = false
                if FileManager.default.fileExists(atPath: sub.path, isDirectory: &isD), isD.boolValue {
                    let s = directorySize(url: sub)
                    subDirReports.append((sub.lastPathComponent, fm.string(fromByteCount: s), s))
                }
            }
        }

        var report = "### Disk Space Analysis:\n\n"
        report += "- **Target Scope** (`\(targetDir.lastPathComponent)`): **\(fm.string(fromByteCount: workspaceSize))**\n"
        report += "- **Xcode DerivedData Cache**: **\(fm.string(fromByteCount: derivedDataSize))**\n\n"
        if !subDirReports.isEmpty {
            report += "#### Major Directory Breakdown:\n"
            for sub in subDirReports.sorted(by: { $0.size > $1.size }).prefix(10) {
                report += "- `\(sub.name)`: \(sub.sizeStr)\n"
            }
        }
        return .text(report)
    }

    func systemNotification(_ call: MCPToolCall) async throws -> MCPToolResult {
        let title = call.arguments["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "SwiftCode Assist"
        let subtitle = call.arguments["subtitle"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = call.arguments["message"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? call.arguments["body"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Task completed."
        let soundName = call.arguments["sound"]?.string ?? "default"
        let isCritical = call.bool("critical") ?? false
        let (summary, delivered) = try await terminalPostNotification(title: title, subtitle: subtitle, message: message,
                                                                      sound: soundName, critical: isCritical)
        if delivered {
            return .text(summary)
        }
        return .error(summary)
    }
}

extension SwiftCodeMCPHost {

    nonisolated static let terminalSysctlAllowlist: [String: TerminalSysctlKind] = [
        "kern.ostype": .string, "kern.osrelease": .string, "kern.osrevision": .string, "kern.version": .string,
        "kern.hostname": .string, "kern.maxproc": .int32,
        "hw.model": .string, "hw.machine": .string, "hw.ncpu": .int32,
        "hw.physicalmem": .uint64, "hw.memsize": .uint64, "hw.memsize_usable": .uint64,
        "hw.cpufrequency": .uint64, "machdep.cpu.brand_string": .string,
    ]

    nonisolated static let terminalBlockedDefaultsDomains: Set<String> = ["NSGlobalDomain"]

    nonisolated static func terminalClampedInt(_ value: AnyJSON?, default def: Int, min lo: Int, max hi: Int) -> Int {
        var v = def
        if let i = value?.int { v = i }
        else if let d = value?.double { v = Int(d) }
        else if let s = value?.string, let i = Int(s) { v = i }
        return Swift.min(Swift.max(v, lo), hi)
    }

    nonisolated static func terminalClampedDouble(_ value: AnyJSON?, default def: Double, min lo: Double, max hi: Double) -> Double {
        var v = def
        if let d = value?.double { v = d }
        else if let s = value?.string, let d = Double(s) { v = d }
        return Swift.min(Swift.max(v, lo), hi)
    }

    nonisolated static func terminalPermissionDeniedIn(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("permission denied")
            || text.localizedCaseInsensitiveContains("not permitted")
            || text.localizedCaseInsensitiveContains("operation not permitted")
    }

    func terminalUseSystemRun(_ path: String, _ args: [String], timeout: TimeInterval, workingDirectory: URL) async -> TerminalFixedRun? {
        (await Task.detached {
            Self.terminalRunFixed(path, args, workingDirectory: workingDirectory,
                                  environment: Self.terminalEnvironment(), timeout: timeout)
        }.value)
    }

    func useSystem(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let operation = call.arguments["operation"]?.string, !operation.isEmpty else {
            throw MCPToolError("Missing required parameter: operation")
        }
        let target = call.string("target")
        let params = call.arguments["parameters"]?.object ?? [:]
        switch operation {
        case "system_info": return try await terminalSystemInfo()
        case "dev_environment": return try await terminalDevEnvironment(in: s)
        case "process_list":
            let filter = params["filter"]?.string ?? target
            let limit = Self.terminalClampedInt(params["limit"], default: 50, min: 1, max: 200)
            return try await terminalProcessList(filter: filter, limit: limit, in: s)
        case "network_interfaces": return try await terminalNetworkInterfaces(interface: target, in: s)
        case "listening_sockets": return try await terminalListeningSockets(in: s)
        case "connectivity": return try await terminalConnectivity(target: target, params: params)
        case "disk_info": return terminalDiskInfo()
        case "system_log":
            let minutes = Self.terminalClampedInt(params["minutes"], default: 15, min: 1, max: 60)
            return try await terminalSystemLog(predicate: params["predicate"]?.string, minutes: minutes, in: s)
        case "service_status": return try await terminalServiceStatus(in: s)
        case "config_read":
            guard let name = target, !name.isEmpty else {
                throw MCPToolError("Missing required target: sysctl name (must be one of the allowlisted names)")
            }
            return terminalConfigRead(name: name)
        case "user_defaults_write":
            guard call.bool("confirm") == true else {
                throw MCPToolError("user_defaults_write requires explicit confirmation: re-run with confirm: true, plus target/domain, parameters.key, and parameters.value")
            }
            return try await terminalUserDefaultsWrite(target: target, params: params, in: s, call: call)
        default:
            let supported = ["system_info", "dev_environment", "process_list", "network_interfaces", "listening_sockets",
                             "connectivity", "disk_info", "system_log", "service_status", "config_read", "user_defaults_write"]
            throw MCPToolError("Unknown operation '\(operation)'. Supported: \(supported.joined(separator: ", "))")
        }
    }

    func terminalSystemInfo() async throws -> MCPToolResult {
        let info = ProcessInfo.processInfo
        let v = info.operatingSystemVersion
        let uname = (await Task.detached {
            Self.terminalRunFixed(HostTool.path("uname"), ["-m", "-r"], timeout: 15)
        }.value)
        var machine = "unknown"
        var release = "unknown"
        if let uname, uname.exitCode == 0 {
            let fields = uname.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            if fields.count >= 1 { machine = String(fields[0]) }
            if fields.count >= 2 { release = String(fields[1]) }
        }
        let uptimeSeconds = Int(info.systemUptime)
        let lines = [
            "\(info.operatingSystemVersionString) (kernel \(release))",
            "Architecture: \(machine)",
            "Hostname: \(info.hostName)",
            "CPU count: \(info.processorCount)",
            "Physical memory: \(info.physicalMemory) bytes",
            "System uptime: \(uptimeSeconds) seconds",
        ]
        return .structured(["operation": .string("system_info"),
                            "osVersion": .string("\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"),
                            "osBuild": .string(release), "arch": .string(machine), "hostname": .string(info.hostName),
                            "cpuCount": .int(info.processorCount), "physicalMemoryBytes": .int(Int(info.physicalMemory)),
                            "uptimeSeconds": .int(uptimeSeconds), "content": .string(lines.joined(separator: "\n"))],
                           summary: lines.joined(separator: "\n"))
    }

    func terminalDevEnvironment(in s: WorkspaceSession) async throws -> MCPToolResult {
        let root = Self.folder(of: s.model)
        var sections: [String] = []
        let probes: [(label: String, path: String, args: [String])] = [
            ("xcodebuild", HostTool.path("xcodebuild"), ["-version"]),
            ("swift", HostTool.path("swift"), ["--version"]),
            ("xcrun swift", HostTool.path("xcrun"), ["--find", "swift"]),
        ]
        for probe in probes {
            guard let result = await terminalUseSystemRun(probe.path, probe.args, timeout: 60, workingDirectory: root) else {
                sections.append("## \(probe.label)\nnot available: failed to launch \(probe.path)")
                continue
            }
            if result.timedOut {
                throw MCPToolError("\(probe.label) probe timed out after 60s")
            }
            let (text, wasTruncated) = Self.terminalCappedOutput(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            sections.append("## \(probe.label) (exit \(result.exitCode))\(wasTruncated ? " [truncated]" : "")\n\(text.isEmpty ? "(no output)" : text)")
        }
        let content = sections.joined(separator: "\n\n")
        return .structured(["operation": .string("dev_environment"), "tools": .string("xcodebuild,swift,xcrun"),
                            "content": .string(content)], summary: content)
    }

    func terminalProcessList(filter: String?, limit: Int, in s: WorkspaceSession) async throws -> MCPToolResult {
        guard let result = await terminalUseSystemRun("/bin/ps", ["-eo", "pid,pcpu,pmem,comm"], timeout: 15,
                                                      workingDirectory: Self.folder(of: s.model)) else {
            throw MCPToolError("Failed to launch /bin/ps")
        }
        if result.timedOut {
            throw MCPToolError("process listing timed out after 15s")
        }
        if result.exitCode != 0 {
            if Self.terminalPermissionDeniedIn(result.stdout) {
                throw MCPToolError("process listing denied by the OS: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            throw MCPToolError("/bin/ps exited \(result.exitCode): \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        var rows: [String] = []
        for line in result.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("PID") { continue }
            if let f = filter, !f.isEmpty, !trimmed.localizedCaseInsensitiveContains(f) { continue }
            rows.append(trimmed)
        }
        let shown = Array(rows.prefix(limit))
        var content = shown.joined(separator: "\n")
        if rows.count > limit {
            content += "\n…[truncated: showing \(limit) of \(rows.count) matching processes]"
        }
        if content.isEmpty {
            content = "No processes matched\(filter.map { " filter '\($0)'" } ?? "")."
        }
        return .structured(["operation": .string("process_list"), "filter": .string(filter ?? ""),
                            "count": .int(rows.count), "truncated": .bool(rows.count > limit),
                            "content": .string(content)], summary: content)
    }

    func terminalNetworkInterfaces(interface: String?, in s: WorkspaceSession) async throws -> MCPToolResult {
        let root = Self.folder(of: s.model)
        try Self.terminalRequireMacOS("use_system operation 'network_interfaces'")
        var args: [String] = []
        if let name = interface, !name.isEmpty {
            guard Self.terminalMatches(name, pattern: "^[A-Za-z0-9._-]+$") else {
                throw MCPToolError("Invalid interface name '\(name)'")
            }
            args = [name]
        }
        guard let result = await terminalUseSystemRun("/sbin/ifconfig", args, timeout: 15, workingDirectory: root) else {
            throw MCPToolError("Failed to launch /sbin/ifconfig")
        }
        if result.timedOut {
            throw MCPToolError("interface listing timed out after 15s")
        }
        if result.exitCode != 0 {
            if Self.terminalPermissionDeniedIn(result.stdout) {
                throw MCPToolError("interface listing denied by the OS")
            }
            throw MCPToolError("/sbin/ifconfig exited \(result.exitCode): \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let (content, wasTruncated) = Self.terminalCappedOutput(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        return .structured(["operation": .string("network_interfaces"), "interface": .string(interface ?? ""),
                            "truncated": .bool(wasTruncated), "content": .string(content)], summary: content)
    }

    func terminalListeningSockets(in s: WorkspaceSession) async throws -> MCPToolResult {
        let root = Self.folder(of: s.model)
        guard let lsof = Self.terminalResolveProgram("lsof", workingDirectory: Self.folder(of: s.model)) else {
            throw MCPToolError("Failed to launch lsof (not found on PATH)")
        }
        guard let result = await terminalUseSystemRun(lsof, ["-iTCP", "-sTCP:LISTEN", "-P", "-n"], timeout: 20, workingDirectory: root) else {
            throw MCPToolError("Failed to launch \(lsof)")
        }
        if result.timedOut {
            throw MCPToolError("socket listing timed out after 20s")
        }
        if result.exitCode != 0 {
            if Self.terminalPermissionDeniedIn(result.stdout) {
                throw MCPToolError("lsof was denied access to socket information (requires privileges this tool will not request). Output so far: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .structured(["operation": .string("listening_sockets"), "count": .int(0),
                                    "truncated": .bool(false), "content": .string("No TCP listeners found.")],
                                   summary: "No TCP listeners found.")
            }
            throw MCPToolError("\(lsof) exited \(result.exitCode): \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let (content, wasTruncated) = Self.terminalCappedOutput(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        let count = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return .structured(["operation": .string("listening_sockets"), "count": .int(count),
                            "truncated": .bool(wasTruncated),
                            "content": .string(content.isEmpty ? "No TCP listeners found." : content)],
                           summary: content.isEmpty ? "No TCP listeners found." : content)
    }

    func terminalConnectivity(target: String?, params: [String: AnyJSON]) async throws -> MCPToolResult {
        guard let host = target, !host.isEmpty else {
            throw MCPToolError("Missing required target: hostname or IP address to connect to")
        }
        guard let port = params["port"]?.int, (1...65535).contains(port) else {
            throw MCPToolError("Missing or invalid parameters.port (must be 1-65535)")
        }
        let timeout = Self.terminalClampedDouble(params["timeoutSeconds"], default: 5, min: 1, max: 30)
        let start = Date()
        let reachable = await Task.detached(priority: .utility) {
            Self.terminalTCPConnect(host: host, port: port, timeoutSeconds: timeout)
        }.value
        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
        let verdict = reachable ? "reachable" : "not reachable"
        let content = "TCP \(host):\(port) — \(verdict) (\(latencyMs)ms, timeout \(Int(timeout))s)"
        return .structured(["operation": .string("connectivity"), "host": .string(host), "port": .int(port),
                            "reachable": .bool(reachable), "latencyMs": .int(latencyMs), "content": .string(content)],
                           summary: content)
    }

    func terminalDiskInfo() -> MCPToolResult {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity else {
            return .error("Could not read volume capacity for /")
        }
        let used = total - available
        let usedPercent = total > 0 ? Double(used) / Double(total) * 100.0 : 0.0
        let name = values.volumeName ?? "/"
        let content = [
            "Volume: \(name) (/)",
            "Total: \(total) bytes",
            "Available: \(available) bytes",
            "Used: \(used) bytes (\(String(format: "%.1f", usedPercent))%)",
        ].joined(separator: "\n")
        return .structured(["operation": .string("disk_info"), "path": .string("/"), "totalBytes": .int(total),
                            "availableBytes": .int(available), "usedBytes": .int(used),
                            "usedPercent": .string(String(format: "%.1f", usedPercent)), "content": .string(content)],
                           summary: content)
    }

    func terminalSystemLog(predicate: String?, minutes: Int, in s: WorkspaceSession) async throws -> MCPToolResult {
        let root = Self.folder(of: s.model)
        try Self.terminalRequireMacOS("use_system operation 'system_log'")
        var args = ["show", "--style", "compact", "--last", "\(minutes)m"]
        if let p = predicate, !p.isEmpty {
            args += ["--predicate", p]
        }
        guard let result = await terminalUseSystemRun("/usr/bin/log", args, timeout: 45, workingDirectory: root) else {
            throw MCPToolError("Failed to launch /usr/bin/log")
        }
        if result.timedOut {
            throw MCPToolError("system log query timed out after 45s; narrow with a predicate or fewer minutes")
        }
        if result.exitCode != 0 {
            if Self.terminalPermissionDeniedIn(result.stdout) {
                throw MCPToolError("Reading the system log was denied by the OS (logd/TCC). This tool does not request elevated access.")
            }
            throw MCPToolError("/usr/bin/log exited \(result.exitCode): \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let (content, wasTruncated) = Self.terminalCappedOutput(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        let lineCount = content.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        return .structured(["operation": .string("system_log"), "predicate": .string(predicate ?? ""),
                            "minutes": .int(minutes), "count": .int(lineCount), "truncated": .bool(wasTruncated),
                            "content": .string(content.isEmpty ? "No log entries in the last \(minutes) minute(s)." : content)],
                           summary: content.isEmpty ? "No log entries in the last \(minutes) minute(s)." : content)
    }

    func terminalServiceStatus(in s: WorkspaceSession) async throws -> MCPToolResult {
        let root = Self.folder(of: s.model)
        try Self.terminalRequireMacOS("use_system operation 'service_status'")
        guard let result = await terminalUseSystemRun("/bin/launchctl", ["list"], timeout: 15, workingDirectory: root) else {
            throw MCPToolError("Failed to launch /bin/launchctl")
        }
        if result.timedOut {
            throw MCPToolError("service listing timed out after 15s")
        }
        if result.exitCode != 0 {
            if Self.terminalPermissionDeniedIn(result.stdout) {
                throw MCPToolError("Reading launchd services was denied by the OS")
            }
            throw MCPToolError("/bin/launchctl exited \(result.exitCode): \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let (content, wasTruncated) = Self.terminalCappedOutput(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        let rows = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let serviceCount = max(0, rows.count - 1)
        return .structured(["operation": .string("service_status"), "count": .int(serviceCount),
                            "truncated": .bool(wasTruncated), "content": .string(content)], summary: content)
    }

    func terminalConfigRead(name: String) -> MCPToolResult {
#if os(macOS)
        guard Self.terminalMatches(name, pattern: "^[a-z0-9._]+$"),
              let kind = Self.terminalSysctlAllowlist[name] else {
            return .error("sysctl '\(name)' is not on the allowlist. Allowed: \(Self.terminalSysctlAllowlist.keys.sorted().joined(separator: ", "))")
        }
        guard let value = Self.terminalSysctl(name, kind: kind) else {
            return .error("sysctlbyname failed for '\(name)'")
        }
        return .structured(["operation": .string("config_read"), "sysctlName": .string(name), "value": .string(value),
                            "content": .string("\(name) = \(value)")], summary: "\(name) = \(value)")
#else
        return .error("use_system operation 'config_read' (sysctl) is only available on macOS.")
#endif
    }

    func terminalUserDefaultsWrite(target: String?, params: [String: AnyJSON], in s: WorkspaceSession, call: MCPToolCall) async throws -> MCPToolResult {
        try Self.terminalRequireMacOS("use_system operation 'user_defaults_write'")
        let domain = params["domain"]?.string ?? target
        guard let domain, !domain.isEmpty else {
            throw MCPToolError("Missing required target/domain for user_defaults_write")
        }
        guard Self.terminalMatches(domain, pattern: "^[A-Za-z0-9.-]+$"), !domain.contains("..") else {
            throw MCPToolError("Invalid defaults domain '\(domain)': must match ^[A-Za-z0-9.-]+$")
        }
        if Self.terminalBlockedDefaultsDomains.contains(where: { $0.caseInsensitiveCompare(domain) == .orderedSame }) {
            throw MCPToolError("Domain '\(domain)' is blocked: writing the global domain affects every application and is out of scope for this tool. Choose the app's own domain (e.g. com.example.MyApp).")
        }
        guard let key = params["key"]?.string, !key.isEmpty else {
            throw MCPToolError("Missing required parameters.key for user_defaults_write")
        }
        guard Self.terminalMatches(key, pattern: "^[A-Za-z0-9._-]+$") else {
            throw MCPToolError("Invalid parameters.key '\(key)': must match ^[A-Za-z0-9._-]+$")
        }
        guard let rawValue = params["value"] else {
            throw MCPToolError("Missing required parameters.value (string, number, or boolean)")
        }
        let writeArgs: [String]
        let expectedReadback: String
        if let b = rawValue.bool {
            writeArgs = ["-bool", b ? "YES" : "NO"]
            expectedReadback = b ? "1" : "0"
        } else if let str = rawValue.string {
            writeArgs = [str]
            expectedReadback = str
        } else if let d = rawValue.double, d == d.rounded(), abs(d) < 9_000_000_000_000_000 {
            writeArgs = ["-int", "\(Int(d))"]
            expectedReadback = "\(Int(d))"
        } else if let d = rawValue.double {
            writeArgs = ["-float", "\(d)"]
            expectedReadback = "\(d)"
        } else {
            throw MCPToolError("parameters.value must be a string, number, or boolean (objects, arrays, and null are rejected)")
        }

        let before = await terminalDefaultsRead(domain: domain, key: key, in: s)
        let previousDisplay = before ?? "<not set>"
        try await terminalApproveChange(tool: call.name,
                                        summary: "defaults write \(domain) \(key): '\(previousDisplay)' -> '\(expectedReadback)'",
                                        in: s, call: call)
        guard let writeResult = await terminalUseSystemRun("/usr/bin/defaults", ["write", domain, key] + writeArgs, timeout: 10,
                                                             workingDirectory: Self.folder(of: s.model)) else {
            throw MCPToolError("Failed to launch /usr/bin/defaults")
        }
        if writeResult.timedOut {
            throw MCPToolError("defaults write timed out after 10s")
        }
        if writeResult.exitCode != 0 {
            throw MCPToolError("defaults write failed (exit \(writeResult.exitCode)): \(writeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        guard let readback = await terminalDefaultsRead(domain: domain, key: key, in: s) else {
            throw MCPToolError("defaults write reported success but the value could not be read back (before: \(previousDisplay))")
        }
        guard readback == expectedReadback else {
            throw MCPToolError("Verification failed: expected '\(expectedReadback)' after write, read back '\(readback)' (before: \(previousDisplay)). The write did not take effect.")
        }
        let content = "defaults write \(domain) \(key): '\(previousDisplay)' -> '\(readback)' (verified by read-back)"
        return .structured(["operation": .string("user_defaults_write"), "domain": .string(domain), "key": .string(key),
                            "previousValue": .string(previousDisplay), "newValue": .string(readback),
                            "verified": .bool(true), "content": .string(content)], summary: content)
    }

    func terminalDefaultsRead(domain: String, key: String, in s: WorkspaceSession) async -> String? {
        guard let result = await terminalUseSystemRun("/usr/bin/defaults", ["read", domain, key], timeout: 10,
                                                      workingDirectory: Self.folder(of: s.model)),
              !result.timedOut, result.exitCode == 0 else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SwiftCodeMCPHost {

    func takeScreenshot(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await takeScreenshotReal(call)
    }

    func takeScreenrecord(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await takeScreenrecordReal(call)
    }

    func useApp(_ call: MCPToolCall) async throws -> MCPToolResult {
        try Self.terminalRequireMacOS("use_app")
        return try await useAppReal(call)
    }
}
