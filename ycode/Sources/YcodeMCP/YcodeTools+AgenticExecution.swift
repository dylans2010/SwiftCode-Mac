import Foundation
import YcodeAssistant
import YcodeIDECore

/// The ported Legacy Agentic execution / build-runner tool family
/// (Wave 8, slice B).
///
/// Behaviour source: Legacy's `ExecuteTerminalCommandTool`,
/// `RunBuildTool`, `RunTestsTool`, `RunLinterTool`,
/// `RunFormatterTool`, `RunTypeCheckerTool`,
/// `RunStaticAnalysisTool`, `RunBenchmarkTool`,
/// `RunApplicationTool`, `StopRunningProcessTool`,
/// `GetProcessLogsTool`, `ReadBuildLogsTool`, `XcodeBuildTool`
/// and `SwiftPackageManagerTool`
/// (`SwiftCode/Tools/Agentic/*.swift`, Dylan's own code, ported
/// under MIT). Only 9 of the 14 slice IDs are registered here —
/// the other 5 are already served by ported tools or existing
/// aliases (see `specs/ide/agentic-execution-draft.md` for the
/// per-tool disposition table).
///
/// Conventions, following Waves 1–7:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter every Ycode tool carries. Descriptions
///   are Legacy's verbatim. Structured data keeps Legacy's shape
///   where Legacy had one; Legacy's Agentic tools return a plain
///   string, so the run tools report `exitCode` + `outputTail`
///   (the `package_dependency_update` shape) instead of
///   inventing Legacy keys.
/// * Every command runs as a subprocess argument vector — never a
///   shell — through `terminalRunFixed` (off the main actor),
///   workspace-confined, with stdin closed. There is no Autopilot
///   bypass. Test/build running maps onto the fixed-argv runner
///   rather than a second runner: the session build seam has no
///   build-tests action (the only `--build-tests` use in
///   `YcodeBuild` is inside the test runner, which also executes
///   the tests), so `run_type_checker` and
///   `run_static_analysis` run `swift build` directly, and
///   `run_benchmark` / `run_application` run `swift run`
///   directly. `projectPath` resolves with
///   `resolveFileReadingPath` (a leading `/` is
///   workspace-root-relative, plain relative paths resolve
///   against the `dir_cd` session directory) and must name an
///   existing directory inside the workspace — unlike
///   `project_build`, it need not be the open workspace itself,
///   so a package nested in the workspace can be built.
/// * Approval gating: the two writing tools (`run_formatter`,
///   which rewrites files in place through the SwiftFormat
///   subprocess, and `stop_running_process`, which kills a
///   process) are `writes: true` and gate through an explicit
///   `MCPChange` + `approve()` before doing anything. The
///   execution tools (`run_linter`, `run_type_checker`,
///   `run_static_analysis`, `run_benchmark`,
///   `run_application`) follow the `performance_benchmark` /
///   `test_run_single` precedent: `execution` annotations,
///   `writes: false`, no extra approval — they run real commands
///   and report actual output, creating build products the way
///   the `build` tool does. `read_build_logs` is a pure read.
///
/// Implemented (8): `run_linter`, `run_formatter`,
/// `run_type_checker`, `run_static_analysis`, `run_benchmark`,
/// `run_application`, `stop_running_process`,
/// `read_build_logs`. Honestly failing (1): `get_process_logs`
/// — registered with Legacy's ID and schema, validating its
/// inputs first, then failing with the exact prerequisite (see
/// below). No behaviour or result is invented for it.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `run_linter` / `run_formatter`: Legacy passed the raw
///   `path` string as the tool argument with the path itself as
///   the working directory (which fails to launch when the path
///   is a file). The port passes the resolved absolute path and
///   uses the path itself as the working directory when it is a
///   directory, its parent when it is a file. The binaries are
///   resolved on `PATH` (`terminalResolveProgram`) rather than
///   Legacy's fixed `/usr/bin/swiftlint` /
///   `/usr/bin/swiftformat`, so a Homebrew install works too.
/// * `run_type_checker` / `run_static_analysis` / `run_benchmark`
///   / `run_application`: Legacy waited unboundedly; the port
///   bounds each run at 300 s through `terminalRunFixed` and
///   fails on timeout. `run_application`'s `target` must be a
///   single bare target name (no whitespace, no leading `-`),
///   so it can never be reinterpreted as a `swift run` flag.
/// * `run_application`: Legacy returned the combined output
///   even when the app exited non-zero; the port reports a
///   non-zero exit as a failure with the output tail, like the
///   other run tools.
/// * `stop_running_process`: Legacy called `kill(pid, SIGTERM)`
///   directly with no guard. The port refuses PID 1 and its own
///   PID, gates through the approval path, and runs
///   `/bin/kill -TERM <pid>` as a fixed argv vector.
/// * `get_process_logs`: Legacy's `run()` returned the
///   placeholder string `"Log data for process <pid>"` with no
///   real log source behind it. The port does not reproduce the
///   placeholder: it fails naming the missing per-process log
///   buffer (Ycode keeps run output keyed by run ID, never by
///   PID, and tracks no child-process log store).
/// * `read_build_logs`: Legacy returned the whole
///   `.build/build.log` file. The port returns the last 8000
///   characters with a truncation marker when the file is
///   longer, so a large log cannot flood the result.
extension YcodeMCPHost {
    var agenticExecutionTools: [MCPTool] {
        let execution = MCPToolAnnotations(readOnly: false, idempotent: false)
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let destructive = MCPToolAnnotations(readOnly: false, destructive: true, idempotent: true)
        return [
            tool("run_linter", "Run Linter",
                 "Runs a linter (SwiftLint) on a given path.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative file or directory path to lint.")],
                                      required: ["path"]),
                 output: Schema.output(["exitCode": Schema.int, "outputTail": Schema.str]),
                 annotations: execution) { h, call in
                try await h.agenticExecutionLint(call)
            },
            tool("run_formatter", "Run Formatter",
                 "Runs a formatter (SwiftFormat) on a given path.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative file or directory path to format.")],
                                      required: ["path"]),
                 output: Schema.output(["exitCode": Schema.int, "outputTail": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticExecutionFormat(call)
            },
            tool("run_type_checker", "Run Type Checker",
                 "Runs the Swift type checker on a project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path to the Swift project directory (the directory containing Package.swift).")],
                                      required: ["projectPath"]),
                 output: Schema.output(["exitCode": Schema.int, "outputTail": Schema.str]),
                 annotations: execution) { h, call in
                try await h.agenticExecutionTypeCheck(call)
            },
            tool("run_static_analysis", "Run Static Analysis",
                 "Runs static analysis on a Swift project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path to the Swift project directory (the directory containing Package.swift).")],
                                      required: ["projectPath"]),
                 output: Schema.output(["exitCode": Schema.int, "outputTail": Schema.str]),
                 annotations: execution) { h, call in
                try await h.agenticExecutionStaticAnalysis(call)
            },
            tool("run_benchmark", "Run Benchmark",
                 "Runs benchmarks on a Swift project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path to the Swift project directory (the directory containing the benchmark target).")],
                                      required: ["projectPath"]),
                 output: Schema.output(["exitCode": Schema.int, "outputTail": Schema.str]),
                 annotations: execution) { h, call in
                try await h.agenticExecutionBenchmark(call)
            },
            tool("run_application", "Run Application",
                 "Runs a Swift application target.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path to the Swift project directory."),
                                       "target": Schema.string("Name of the executable target to run (e.g. 'greet').")],
                                      required: ["projectPath", "target"]),
                 output: Schema.output(["exitCode": Schema.int, "outputTail": Schema.str]),
                 annotations: execution) { h, call in
                try await h.agenticExecutionRunApplication(call)
            },
            tool("stop_running_process", "Stop Running Process",
                 "Stops a running process using its PID.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "pid": Schema.integer("Process ID to terminate (SIGTERM).")],
                                      required: ["pid"]),
                 annotations: destructive, writes: true) { h, call in
                try await h.agenticExecutionStopProcess(call)
            },
            tool("get_process_logs", "Get Process Logs",
                 "Retrieves logs for a running process.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "pid": Schema.integer("Process ID whose logs to retrieve.")],
                                      required: ["pid"])) { h, call in
                try await h.agenticExecutionProcessLogs(call)
            },
            tool("read_build_logs", "Read Build Logs",
                 "Reads build logs from a project directory.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path to the Swift project directory (its .build/build.log is read).")],
                                      required: ["projectPath"])) { h, call in
                try h.agenticExecutionReadBuildLogs(call)
            },
        ]
    }
}

extension YcodeMCPHost {
    // MARK: - Shared seams (agentic execution)

    /// Resolves Legacy's required `projectPath` to an existing
    /// directory inside the workspace.
    func agenticExecutionProjectDir(_ call: MCPToolCall) throws -> URL {
        let s = try session(for: call)
        guard let raw = call.arguments["projectPath"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: projectPath")
        }
        let url: URL
        do {
            url = try resolveFileReadingPath(raw, in: s)
        } catch {
            throw MCPToolError("Invalid projectPath '\(raw)': paths must stay inside the workspace.")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPToolError("projectPath does not exist or is not a directory: \(raw)")
        }
        return url
    }

    /// Resolves Legacy's required `path` (a file or a directory)
    /// inside the workspace, and the working directory to run a
    /// file tool from: the path itself when it is a directory, its
    /// parent when it is a file.
    func agenticExecutionTargetPath(_ call: MCPToolCall) throws -> (url: URL, workingDirectory: URL) {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: path")
        }
        let url: URL
        do {
            url = try resolveFileReadingPath(raw, in: s)
        } catch {
            throw MCPToolError("Invalid path '\(raw)': paths must stay inside the workspace.")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw MCPToolError("Path does not exist: \(raw)")
        }
        return (url, isDir.boolValue ? url : url.deletingLastPathComponent())
    }

    /// Runs `executable` with a fixed argv vector in
    /// `workingDirectory`, bounded at 300 s, and turns the real
    /// outcome into a structured result. `nil` from the runner
    /// (could not launch) and a timeout are failures; a non-zero
    /// exit is a failure carrying the output tail, as Legacy's
    /// `execute()` did when the command failed.
    func agenticExecutionRunFixed(_ executable: String, _ args: [String], workingDirectory: URL,
                                  verb: String) async throws -> MCPToolResult {
        guard let run = await Task.detached {
            Self.terminalRunFixed(executable, args, workingDirectory: workingDirectory, timeout: 300)
        }.value else {
            throw MCPToolError("Failed to start \(verb): could not launch \(executable).")
        }
        if run.timedOut {
            throw MCPToolError("\(verb) timed out after 300 seconds.")
        }
        let tail = String((run.stdout + "\n" + run.stderr).suffix(2000))
        if run.exitCode == 0 {
            return .structured(["exitCode": .int(Int(run.exitCode)), "outputTail": .string(tail)],
                               summary: "\(verb) succeeded (exit 0).\n\(tail)")
        }
        throw MCPToolError("\(verb) failed with exit code \(run.exitCode).\n\(tail)")
    }

    /// Resolves a program on `PATH` (Legacy's fixed
    /// `/usr/bin/<name>` is on `PATH`, so a Homebrew install
    /// works too), failing with the exact missing prerequisite.
    func agenticExecutionResolveProgram(_ name: String, workingDirectory: URL, tool: String, installHint: String) throws -> String {
        guard let resolved = Self.terminalResolveProgram(name, workingDirectory: workingDirectory) else {
            throw MCPToolError("\(tool) needs \(name), which was not found on PATH. \(installHint)")
        }
        return resolved
    }

    // MARK: - `run_linter` / `run_formatter`

    func agenticExecutionLint(_ call: MCPToolCall) async throws -> MCPToolResult {
        let (url, workingDirectory) = try agenticExecutionTargetPath(call)
        let swiftlint = try agenticExecutionResolveProgram("swiftlint", workingDirectory: workingDirectory,
                                                           tool: "run_linter", installHint: "Install SwiftLint (e.g. `brew install swiftlint`) to use run_linter.")
        return try await agenticExecutionRunFixed(swiftlint, ["lint", url.path], workingDirectory: workingDirectory,
                                                  verb: "SwiftLint lint")
    }

    func agenticExecutionFormat(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let (url, workingDirectory) = try agenticExecutionTargetPath(call)
        let swiftformat = try agenticExecutionResolveProgram("swiftformat", workingDirectory: workingDirectory,
                                                             tool: "run_formatter", installHint: "Install SwiftFormat (e.g. `brew install swiftformat`) to use run_formatter.")
        let rel = fileReadingRelativePath(of: url, in: s)
        try await terminalApproveChange(tool: call.name,
                                        summary: "Format \(rel) with SwiftFormat (rewrites files in place)",
                                        in: s, call: call)
        return try await agenticExecutionRunFixed(swiftformat, [url.path], workingDirectory: workingDirectory,
                                                  verb: "SwiftFormat")
    }

    // MARK: - `run_type_checker` / `run_static_analysis` / `run_benchmark` / `run_application`

    func agenticExecutionTypeCheck(_ call: MCPToolCall) async throws -> MCPToolResult {
        let dir = try agenticExecutionProjectDir(call)
        let swift = try agenticExecutionResolveProgram("swift", workingDirectory: dir,
                                                       tool: "run_type_checker", installHint: "A Swift toolchain is required to type-check a project.")
        return try await agenticExecutionRunFixed(swift, ["build", "--build-tests"], workingDirectory: dir,
                                                  verb: "swift build --build-tests")
    }

    func agenticExecutionStaticAnalysis(_ call: MCPToolCall) async throws -> MCPToolResult {
        let dir = try agenticExecutionProjectDir(call)
        let swift = try agenticExecutionResolveProgram("swift", workingDirectory: dir,
                                                       tool: "run_static_analysis", installHint: "A Swift toolchain is required to run static analysis.")
        return try await agenticExecutionRunFixed(swift, ["build", "--build-tests", "-Xswiftc", "-analyze"],
                                                  workingDirectory: dir, verb: "swift build --build-tests -Xswiftc -analyze")
    }

    func agenticExecutionBenchmark(_ call: MCPToolCall) async throws -> MCPToolResult {
        let dir = try agenticExecutionProjectDir(call)
        let swift = try agenticExecutionResolveProgram("swift", workingDirectory: dir,
                                                       tool: "run_benchmark", installHint: "A Swift toolchain is required to run benchmarks.")
        return try await agenticExecutionRunFixed(swift, ["run", "-c", "release", "benchmark"], workingDirectory: dir,
                                                  verb: "swift run -c release benchmark")
    }

    func agenticExecutionRunApplication(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let target = call.arguments["target"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
            throw MCPToolError("Missing required parameter: target")
        }
        guard !target.contains(where: \.isWhitespace) && !target.hasPrefix("-") else {
            throw MCPToolError("Invalid target '\(target)': expected a single bare target name.")
        }
        let dir = try agenticExecutionProjectDir(call)
        let swift = try agenticExecutionResolveProgram("swift", workingDirectory: dir,
                                                       tool: "run_application", installHint: "A Swift toolchain is required to run an application target.")
        return try await agenticExecutionRunFixed(swift, ["run", target], workingDirectory: dir,
                                                  verb: "swift run \(target)")
    }

    // MARK: - `stop_running_process` (real kill, approval-gated)

    func agenticExecutionStopProcess(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let pid = call.arguments["pid"]?.int else {
            throw MCPToolError("Missing required parameter: pid")
        }
        guard pid > 1 else {
            throw MCPToolError("Invalid pid '\(pid)': refusing to terminate PID 1 or lower.")
        }
        guard pid != Int(ProcessInfo.processInfo.processIdentifier) else {
            throw MCPToolError("Invalid pid '\(pid)': refusing to terminate Ycode's own process.")
        }
        let s = try session(for: call)
        try await terminalApproveChange(tool: call.name,
                                        summary: "Terminate process \(pid) (SIGTERM)",
                                        in: s, call: call)
        let root = Self.folder(of: s.model)
        guard let run = await Task.detached {
            Self.terminalRunFixed("/bin/kill", ["-TERM", String(pid)], workingDirectory: root, timeout: 30)
        }.value else {
            throw MCPToolError("Failed to stop process \(pid): could not launch /bin/kill.")
        }
        if run.timedOut {
            throw MCPToolError("Failed to stop process \(pid): /bin/kill timed out.")
        }
        guard run.exitCode == 0 else {
            let tail = String((run.stdout + "\n" + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines))
            throw MCPToolError("Failed to stop process \(pid) (exit code \(run.exitCode))\(tail.isEmpty ? "." : ": \(tail)")")
        }
        return .text("Process \(pid) terminated.")
    }

    // MARK: - `get_process_logs` (real log reading)

    /// First hit wins: (1) the host's own runs keyed by PID
    /// (`HostRun.process.processIdentifier`) with their captured
    /// output; (2) on macOS, the unified log
    /// (`/usr/bin/log show --predicate 'processID == <pid>'`,
    /// 45 s, TCC-denied fails honestly); (3) on Linux,
    /// `journalctl _PID=<pid>` when present, plus `/proc/<pid>`
    /// facts labelled as process info, not logs. Legacy returned
    /// a placeholder string with no log source — that placeholder
    /// is NOT reproduced: an unknown pid fails.
    func agenticExecutionProcessLogs(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let pid = call.arguments["pid"]?.int else {
            throw MCPToolError("Missing required parameter: pid")
        }
        let pid32 = Int32(pid)
        if let run = failingToolsHostRuns(pid: pid32).first {
            let output = run.output.joined(separator: "\n")
            let (capped, truncated) = Self.terminalCappedOutput(output)
            return .structured(["pid": .int(pid), "source": .string("host_run"),
                                "executable": .string(run.executable), "state": .string(run.state),
                                "truncated": .bool(truncated),
                                "logs": .string(capped.isEmpty ? "No output captured for process \(pid) yet." : capped)],
                               summary: capped.isEmpty
                                ? "Process \(pid) (\(run.executable)) is \(run.state) with no captured output yet."
                                : "Logs for process \(pid) (\(run.executable), \(run.state)):\n\(capped)")
        }
#if os(macOS)
        guard let result = await terminalUseSystemRun("/usr/bin/log", Self.failingToolsUnifiedLogArgs(pid: pid32),
                                                      timeout: 45, workingDirectory: FileManager.default.temporaryDirectory) else {
            throw MCPToolError("Failed to launch /usr/bin/log")
        }
        if result.timedOut {
            throw MCPToolError("Unified-log query for process \(pid) timed out after 45s.")
        }
        if result.exitCode != 0 {
            if Self.terminalPermissionDeniedIn(result.stdout) {
                throw MCPToolError("Reading the unified log was denied by the OS (logd/TCC). Grant Full Disk Access to Ycode in System Settings > Privacy & Security, then retry.")
            }
            throw MCPToolError("/usr/bin/log exited \(result.exitCode): \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if await failingToolsProcessExists(pid: pid32) {
                return .structured(["pid": .int(pid), "source": .string("unified_log"),
                                    "logs": .string("No unified-log entries for process \(pid) in the last 15 minutes.")],
                                   summary: "No unified-log entries for process \(pid) in the last 15 minutes.")
            }
            throw MCPToolError("No process with PID \(pid) exists, and no unified-log entries were found for it.")
        }
        let (capped, truncated) = Self.terminalCappedOutput(trimmed)
        return .structured(["pid": .int(pid), "source": .string("unified_log"), "truncated": .bool(truncated),
                            "logs": .string(capped)],
                           summary: "Unified-log entries for process \(pid) (last 15 minutes):\n\(capped)")
#else
        if let journalctl = Self.failingToolsJournalctlPath(),
           let result = await archiveRunFixed(journalctl, Self.failingToolsJournalArgs(pid: pid32)) {
            if result.exitCode == 0 {
                let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let (capped, truncated) = Self.terminalCappedOutput(trimmed)
                    return .structured(["pid": .int(pid), "source": .string("journalctl"), "truncated": .bool(truncated),
                                        "logs": .string(capped)],
                                       summary: "journald entries for process \(pid) (last 15 minutes):\n\(capped)")
                }
            }
        }
        if let facts = Self.failingToolsProcFacts(pid: pid32) {
            return .structured(["pid": .int(pid), "source": .string("proc"),
                                "logs": .string(facts + "\n\nNo journald entries were found for this process in the last 15 minutes.")],
                               summary: facts + "\n\nNo journald entries were found for this process in the last 15 minutes. (These are process facts from /proc, not log lines.)")
        }
        throw MCPToolError("No process with PID \(pid) exists, and no journald entries were found for it.")
#endif
    }

    // MARK: - `read_build_logs` (pure read)

    func agenticExecutionReadBuildLogs(_ call: MCPToolCall) throws -> MCPToolResult {
        let dir = try agenticExecutionProjectDir(call)
        let logURL = dir.appendingPathComponent(".build/build.log")
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            let raw = call.arguments["projectPath"]?.string ?? ""
            throw MCPToolError("Build log not found at '\(raw)/.build/build.log'. Run a build first to produce one.")
        }
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else {
            throw MCPToolError("Could not read build log at '.build/build.log' as UTF-8 text.")
        }
        if content.count > 8000 {
            return .text(String(content.suffix(8000)) + "\n… [build log truncated to last 8000 chars]")
        }
        return .text(content)
    }
}
