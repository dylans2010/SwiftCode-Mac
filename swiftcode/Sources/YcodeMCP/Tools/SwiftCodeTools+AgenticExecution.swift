import Foundation
import YcodeAssistant
import YcodeIDECore

extension SwiftCodeMCPHost {
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

extension SwiftCodeMCPHost {

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

    func agenticExecutionRunFixed(_ executable: String, _ args: [String], workingDirectory: URL,
                                  verb: String) async throws -> MCPToolResult {
        guard let run = (await Task.detached {
            Self.terminalRunFixed(executable, args, workingDirectory: workingDirectory, timeout: 300)
        }.value) else {
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

    func agenticExecutionResolveProgram(_ name: String, workingDirectory: URL, tool: String, installHint: String) throws -> String {
        guard let resolved = Self.terminalResolveProgram(name, workingDirectory: workingDirectory) else {
            throw MCPToolError("\(tool) needs \(name), which was not found on PATH. \(installHint)")
        }
        return resolved
    }

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

    func agenticExecutionStopProcess(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let pid = call.arguments["pid"]?.int else {
            throw MCPToolError("Missing required parameter: pid")
        }
        guard pid > 1 else {
            throw MCPToolError("Invalid pid '\(pid)': refusing to terminate PID 1 or lower.")
        }
        guard pid != Int(ProcessInfo.processInfo.processIdentifier) else {
            throw MCPToolError("Invalid pid '\(pid)': refusing to terminate SwiftCode's own process.")
        }
        let s = try session(for: call)
        try await terminalApproveChange(tool: call.name,
                                        summary: "Terminate process \(pid) (SIGTERM)",
                                        in: s, call: call)
        let root = Self.folder(of: s.model)
        guard let run = (await Task.detached {
            Self.terminalRunFixed("/bin/kill", ["-TERM", String(pid)], workingDirectory: root, timeout: 30)
        }.value) else {
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
                throw MCPToolError("Reading the unified log was denied by the OS (logd/TCC). Grant Full Disk Access to SwiftCode in System Settings > Privacy & Security, then retry.")
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
