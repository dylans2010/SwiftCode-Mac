import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The ported Legacy Agentic build-system CLI / container tool family
/// (Wave 8, slice E).
///
/// Behaviour source: Legacy's `CocoaPodsTool`, `CarthageTool`,
/// `AndroidBuildTool`, `GradleTool`, `NpmTool`, `PnpmTool`,
/// `YarnTool`, `BunTool`, `CargoTool`, `GoBuildTool`,
/// `PythonPipTool`, `JavaMavenTool`, `DotNetCLITool`,
/// `FlutterTool`, `ReactNativeTool`, `ExpoTool`,
/// `DockerBuildTool`, `DockerRunTool`, `DockerComposeTool`,
/// `KubernetesApplyTool` and `ViewContainerLogsTool`
/// (`SwiftCode/Tools/Agentic/`, Dylan's own code, ported under MIT).
/// Each Legacy tool is a thin wrapper: one fixed binary, one fixed
/// argument vector, stdout + stderr concatenated as the result.
/// The Agentic registry (`ListTools.swift`) declares no capability,
/// risk, or permission metadata for these tools, so none is ported
/// for them.
///
/// Classification (checked against the 316 already-ported MCP tools
/// and the `toolAliases` table in `MCPServer.swift`): all 21 are
/// PORTED. None is already served and none is a duplicate: the
/// nearest neighbours only inspect (`carthage_cartfile_inspector`,
/// `podfile_inspector`, `build_system_detect`) or take a free-form
/// command string (`use_terminal`, which requires a `command`
/// parameter these tools do not have), so no alias is valid — an
/// alias passes arguments through unchanged and `Schema.object`
/// rejects unknown keys.
///
/// Conventions, following Waves 1–7:
///
/// * Schemas are Legacy's `parametersSchema` verbatim (same property
///   names, same required lists), plus the `workspace` parameter
///   every SwiftCode tool carries and short descriptions on the
///   parameters (Legacy declares none). Descriptions are Legacy's
///   verbatim. Structured data keeps Legacy's result shape — the
///   command's stdout and stderr — in the `use_terminal` output
///   keys (`command`, `workingDirectory`, `stdout`, `stderr`,
///   `stdoutTruncated`, `stderrTruncated`, `exitCode`, `duration`).
/// * Every command runs as a subprocess argument vector — never a
///   shell — with stdin closed and the never-wait-for-a-person
///   environment (`terminalEnvironment`), bounded at 300 s like
///   `use_terminal`. The `action` argument is passed as a single
///   argv element, so shell syntax inside it can never run; it is
///   the CLI's own subcommand, not a command line.
/// * Binaries resolve on `PATH` (`terminalResolveProgram`); a
///   missing binary fails honestly with `use_terminal`'s
///   "was not found" message, naming the binary — never invented
///   output. Legacy's fixed `/usr/bin/...` / `/usr/local/bin/...`
///   paths are not reproduced: those paths do not exist for most of
///   these tools on a modern Mac (Homebrew installs to
///   `/opt/homebrew/bin`), and `use_system` already set the
///   resolve-on-`PATH` precedent for a fixed Legacy path that does
///   not exist.
/// * Paths are workspace-confined (`resolveFileReadingPath`): a
///   `path` that names a working directory must exist and be a
///   directory; a `path` that names a file (manifest, compose file)
///   must exist and be a file. Legacy accepted any absolute path.
/// * Approval, no Autopilot: every executing tool gates its run
///   through `terminalApproveChange` before the subprocess starts,
///   exactly like `use_terminal`. The one pure read,
///   `view_container_logs` (`docker logs`), requests no approval
///   and is registered `writes: false`, like `process_monitor_tool`.
///   All other tools are `writes: true` with execution annotations
///   (`readOnly: false, idempotent: false`), so the server-level
///   gate refuses them in `readOnly` mode before the handler runs.
/// * A non-zero exit is an error result carrying the structured
///   data; a timeout is an error result carrying the partial data.
///   The real CLI output is always reported, never invented.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `android_build`: Legacy ran system `gradle assembleDebug`.
///   The port prefers the project's `gradlew` wrapper when an
///   executable one exists in the project directory (the standard
///   Android build entry point), falling back to `gradle` on `PATH`.
/// * `docker_compose`: Legacy ran the `docker-compose` binary.
///   The port prefers it, falling back to `docker compose`
///   (the v2 subcommand) when only `docker` is on `PATH`.
/// * `python_pip`: Legacy ran `pip`. The port falls back to `pip3`
///   when `pip` is not on `PATH`.
/// * `react_native` / `expo`: Legacy ran `npx react-native <action>`
///   / `npx expo <action>`; the port resolves `npx` on `PATH`
///   instead of Legacy's fixed `/usr/bin/npx`.
/// * `docker_build`: Legacy passed the build-context path as the
///   `docker build` context argument with no working directory. The
///   port runs with the context directory as its working directory
///   and passes `.` as the context, which is equivalent and keeps
///   the context inside the workspace.
extension SwiftCodeMCPHost {
    var agenticCLITools: [MCPTool] {
        let execution = MCPToolAnnotations(readOnly: false, idempotent: false)
        let output = Schema.output(["command": Schema.str, "workingDirectory": Schema.str, "stdout": Schema.str,
                                    "stderr": Schema.str, "stdoutTruncated": Schema.bool, "stderrTruncated": Schema.bool,
                                    "exitCode": Schema.int, "duration": Schema.str])
        let actionPath: [String: AnyJSON] = ["workspace": Schema.workspace,
                                             "action": Schema.string("The subcommand to run (e.g. 'install'). Passed as a single argument; never a shell."),
                                             "path": Schema.string("Workspace-relative path to the project directory to run in.")]
        return [
            tool("cocoapods", "CocoaPods",
                 "Runs CocoaPods commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "pod")
            },
            tool("carthage", "Carthage",
                 "Runs Carthage commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "carthage")
            },
            tool("android_build", "Build Android Project",
                 "Builds an Android project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the Android project directory to build.")],
                                      required: ["path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIAndroidBuild(call)
            },
            tool("gradle", "Gradle",
                 "Runs Gradle commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "gradle")
            },
            tool("npm", "npm",
                 "Runs npm commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "npm")
            },
            tool("pnpm", "pnpm",
                 "Runs pnpm commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "pnpm")
            },
            tool("yarn", "Yarn",
                 "Runs yarn commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "yarn")
            },
            tool("bun", "Bun",
                 "Runs bun commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "bun")
            },
            tool("cargo", "Cargo",
                 "Runs cargo commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "cargo")
            },
            tool("go_build", "Build Go Project",
                 "Builds a Go project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the Go project directory to build.")],
                                      required: ["path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIGoBuild(call)
            },
            tool("python_pip", "Python pip",
                 "Runs pip commands.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("The pip subcommand to run (e.g. 'install'). Passed as a single argument; never a shell."),
                                       "package": Schema.string("Package name for the pip action.")],
                                      required: ["action", "package"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIPythonPip(call)
            },
            tool("java_maven", "Maven",
                 "Runs Maven commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "mvn")
            },
            tool("dotnet_cli", ".NET CLI",
                 "Runs .NET CLI commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "dotnet")
            },
            tool("flutter", "Flutter",
                 "Runs Flutter commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "flutter")
            },
            tool("react_native", "React Native",
                 "Runs React Native commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "npx", prefix: ["react-native"])
            },
            tool("expo", "Expo",
                 "Runs Expo commands.",
                 input: Schema.object(actionPath, required: ["action", "path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIActionPath(call, program: "npx", prefix: ["expo"])
            },
            tool("docker_build", "Build Docker Image",
                 "Builds a Docker image.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the build-context directory (the directory containing the Dockerfile)."),
                                       "tag": Schema.string("Image tag for the build (e.g. 'myapp:latest').")],
                                      required: ["path", "tag"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIDockerBuild(call)
            },
            tool("docker_run", "Run Docker Container",
                 "Runs a Docker container.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "image": Schema.string("Docker image to run (e.g. 'ubuntu:latest').")],
                                      required: ["image"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIDockerRun(call)
            },
            tool("docker_compose", "Docker Compose",
                 "Runs docker-compose commands.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the compose file."),
                                       "action": Schema.string("The compose subcommand to run (e.g. 'up'). Passed as a single argument; never a shell.")],
                                      required: ["path", "action"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIDockerCompose(call)
            },
            tool("kubernetes_apply", "Apply Kubernetes Configuration",
                 "Applies a Kubernetes configuration.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the Kubernetes manifest file to apply.")],
                                      required: ["path"]),
                 output: output,
                 annotations: execution, writes: true) { h, call in
                try await h.agenticCLIKubernetesApply(call)
            },
            tool("view_container_logs", "View Container Logs",
                 "Views logs for a Docker container.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "containerID": Schema.string("Container ID or name whose logs to show.")],
                                      required: ["containerID"]),
                 output: output) { h, call in
                try await h.agenticCLIViewContainerLogs(call)
            },
        ]
    }
}

extension SwiftCodeMCPHost {
    // MARK: - Shared runner

    /// Runs one fixed-argv CLI (`displayCommand` is the human form,
    /// e.g. `npm install`), after the approval gate when `gate` is
    /// true. Mirrors `use_terminal`'s result shape: full stdout in
    /// the summary's first 2000 chars, structured stdout capped at
    /// the last 3000 chars and stderr at the last 2000, exit code
    /// and duration as data. A non-zero exit or a timeout is an
    /// error result carrying the same data — the CLI's real output
    /// is always reported, never invented.
    func agenticCLIExecute(_ call: MCPToolCall, session s: WorkspaceSession, displayCommand: String,
                           executable: String, args: [String], workingDirectory: URL, gate: Bool) async throws -> MCPToolResult {
        if gate {
            try await terminalApproveChange(tool: call.name,
                                            summary: "Run \(displayCommand) in \(workingDirectory.path)",
                                            in: s, call: call)
        }
        let start = Date()
        let result = (await Task.detached {
            Self.terminalRunFixed(executable, args, workingDirectory: workingDirectory,
                                  environment: Self.terminalEnvironment(), timeout: 300)
        }.value)
        guard let result else {
            throw MCPToolError("Process execution failed: could not launch \(executable)")
        }
        let duration = Date().timeIntervalSince(start)
        let durationText = String(format: "%.2fs", duration)
        let stdoutTruncated = result.stdout.count > 3000
        let stderrTruncated = result.stderr.count > 2000
        let stdoutTail = String(result.stdout.suffix(3000)) + (stdoutTruncated ? "\n… [stdout truncated to last 3000 chars]" : "")
        let stderrTail = String(result.stderr.suffix(2000)) + (stderrTruncated ? "\n… [stderr truncated to last 2000 chars]" : "")
        let data: [String: AnyJSON] = ["command": .string(displayCommand), "workingDirectory": .string(workingDirectory.path),
                                       "stdout": .string(stdoutTail), "stderr": .string(stderrTail),
                                       "stdoutTruncated": .bool(stdoutTruncated), "stderrTruncated": .bool(stderrTruncated),
                                       "exitCode": .int(Int(result.exitCode)), "duration": .string(durationText)]
        if result.timedOut {
            return .error("Command timed out after 300s: \(displayCommand)", structured: .object(data))
        }
        if result.exitCode == 0 {
            let stdoutShown = result.stdout.isEmpty ? "(No stdout output)"
                : String(result.stdout.suffix(2000)) + (result.stdout.count > 2000 ? "\n… [stdout truncated to last 2000 chars]" : "")
            return .structured(.object(data), summary: "\(displayCommand) completed successfully (exit code 0 in \(durationText)):\n\(stdoutShown)")
        }
        let errSummary = result.stderr.isEmpty ? result.stdout : result.stderr
        return .error("\(displayCommand) failed with exit code \(result.exitCode) (\(durationText)):\n\(String(errSummary.suffix(1500)))",
                      structured: .object(data))
    }

    /// Resolves the first `names` entry found executable on `PATH`
    /// (or as a path), or `nil` when none resolves.
    nonisolated static func agenticCLIResolve(_ names: [String], workingDirectory: URL) -> String? {
        for name in names {
            if let found = terminalResolveProgram(name, workingDirectory: workingDirectory) { return found }
        }
        return nil
    }

    /// `use_terminal`'s honest missing-binary failure for `program`.
    nonisolated static func agenticCLIMissingBinary(_ program: String) -> MCPToolError {
        MCPToolError("Process execution failed: command '\(program)' was not found (no executable on PATH or at that path).")
    }

    /// A `path` argument naming a working directory: it must resolve
    /// inside the workspace, exist, and be a directory.
    func agenticCLIWorkingDirectory(_ path: String, in s: WorkspaceSession) throws -> URL {
        let url = try resolveFileReadingPath(path, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPToolError("path does not exist or is not a directory: \(path)")
        }
        return url
    }

    /// A `path` argument naming a file: it must resolve inside the
    /// workspace, exist, and not be a directory.
    func agenticCLIFile(_ path: String, in s: WorkspaceSession) throws -> URL {
        let url = try resolveFileReadingPath(path, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            throw MCPToolError("path does not exist or is not a file: \(path)")
        }
        return url
    }

    // MARK: - `action` + `path` tools

    /// The shared shape of Legacy's one-argument CLI wrappers:
    /// `<program> [prefix...] <action>` in the `path` directory.
    /// Legacy's missing-argument message is kept verbatim.
    func agenticCLIActionPath(_ call: MCPToolCall, program: String, prefix: [String] = []) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.string("action"), let path = call.string("path") else {
            throw MCPToolError("Missing action or path")
        }
        let dir = try agenticCLIWorkingDirectory(path, in: s)
        guard let executable = Self.agenticCLIResolve([program], workingDirectory: dir) else {
            throw Self.agenticCLIMissingBinary(program)
        }
        let display = ([program] + prefix + [action]).joined(separator: " ")
        return try await agenticCLIExecute(call, session: s, displayCommand: display, executable: executable,
                                           args: prefix + [action], workingDirectory: dir, gate: true)
    }

    // MARK: - `android_build`

    /// Legacy's `gradle assembleDebug`, preferring the project's
    /// `gradlew` wrapper when an executable one exists.
    func agenticCLIAndroidBuild(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let path = call.string("path") else {
            throw MCPToolError("Missing path")
        }
        let dir = try agenticCLIWorkingDirectory(path, in: s)
        let wrapper = dir.appendingPathComponent("gradlew")
        if FileManager.default.isExecutableFile(atPath: wrapper.path) {
            return try await agenticCLIExecute(call, session: s, displayCommand: "gradlew assembleDebug",
                                               executable: wrapper.path, args: ["assembleDebug"],
                                               workingDirectory: dir, gate: true)
        }
        guard let executable = Self.agenticCLIResolve(["gradle"], workingDirectory: dir) else {
            throw MCPToolError("Process execution failed: command 'gradle' was not found (no executable on PATH or at that path) and no gradlew wrapper exists in '\(path)'.")
        }
        return try await agenticCLIExecute(call, session: s, displayCommand: "gradle assembleDebug",
                                           executable: executable, args: ["assembleDebug"],
                                           workingDirectory: dir, gate: true)
    }

    // MARK: - `go_build`

    /// Legacy's `go build` in the project directory.
    func agenticCLIGoBuild(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let path = call.string("path") else {
            throw MCPToolError("Missing path")
        }
        let dir = try agenticCLIWorkingDirectory(path, in: s)
        guard let executable = Self.agenticCLIResolve(["go"], workingDirectory: dir) else {
            throw Self.agenticCLIMissingBinary("go")
        }
        return try await agenticCLIExecute(call, session: s, displayCommand: "go build",
                                           executable: executable, args: ["build"],
                                           workingDirectory: dir, gate: true)
    }

    // MARK: - `python_pip`

    /// Legacy's `pip <action> <package>` in the workspace root
    /// (Legacy ran with no working directory); `pip3` is the
    /// fallback when `pip` is not on `PATH`.
    func agenticCLIPythonPip(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.string("action"), let package = call.string("package") else {
            throw MCPToolError("Missing action or package")
        }
        let root = Self.folder(of: s.model)
        guard let executable = Self.agenticCLIResolve(["pip", "pip3"], workingDirectory: root) else {
            throw Self.agenticCLIMissingBinary("pip")
        }
        let display = "pip \(action) \(package)"
        return try await agenticCLIExecute(call, session: s, displayCommand: display, executable: executable,
                                           args: [action, package], workingDirectory: root, gate: true)
    }

    // MARK: - `docker_build`

    /// Legacy's `docker build -t <tag> <path>`, run with the build
    /// context as the working directory and `.` as the context.
    func agenticCLIDockerBuild(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let path = call.string("path"), let tag = call.string("tag") else {
            throw MCPToolError("Missing path or tag")
        }
        let dir = try agenticCLIWorkingDirectory(path, in: s)
        guard let executable = Self.agenticCLIResolve(["docker"], workingDirectory: dir) else {
            throw Self.agenticCLIMissingBinary("docker")
        }
        return try await agenticCLIExecute(call, session: s, displayCommand: "docker build -t \(tag) \(path)",
                                           executable: executable, args: ["build", "-t", tag, "."],
                                           workingDirectory: dir, gate: true)
    }

    // MARK: - `docker_run`

    /// Legacy's `docker run <image>` in the workspace root (Legacy
    /// ran with no working directory).
    func agenticCLIDockerRun(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let image = call.string("image") else {
            throw MCPToolError("Missing image")
        }
        let root = Self.folder(of: s.model)
        guard let executable = Self.agenticCLIResolve(["docker"], workingDirectory: root) else {
            throw Self.agenticCLIMissingBinary("docker")
        }
        return try await agenticCLIExecute(call, session: s, displayCommand: "docker run \(image)",
                                           executable: executable, args: ["run", image],
                                           workingDirectory: root, gate: true)
    }

    // MARK: - `docker_compose`

    /// Legacy's `docker-compose -f <path> <action>`, falling back to
    /// `docker compose -f <path> <action>` when only `docker` is on
    /// `PATH`.
    func agenticCLIDockerCompose(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let path = call.string("path"), let action = call.string("action") else {
            throw MCPToolError("Missing path or action")
        }
        let file = try agenticCLIFile(path, in: s)
        let root = Self.folder(of: s.model)
        if let compose = Self.agenticCLIResolve(["docker-compose"], workingDirectory: root) {
            return try await agenticCLIExecute(call, session: s, displayCommand: "docker-compose -f \(path) \(action)",
                                               executable: compose, args: ["-f", file.path, action],
                                               workingDirectory: root, gate: true)
        }
        guard let docker = Self.agenticCLIResolve(["docker"], workingDirectory: root) else {
            throw Self.agenticCLIMissingBinary("docker-compose")
        }
        return try await agenticCLIExecute(call, session: s, displayCommand: "docker compose -f \(path) \(action)",
                                           executable: docker, args: ["compose", "-f", file.path, action],
                                           workingDirectory: root, gate: true)
    }

    // MARK: - `kubernetes_apply`

    /// Legacy's `kubectl apply -f <path>` in the workspace root
    /// (Legacy ran with no working directory).
    func agenticCLIKubernetesApply(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let path = call.string("path") else {
            throw MCPToolError("Missing path")
        }
        let file = try agenticCLIFile(path, in: s)
        let root = Self.folder(of: s.model)
        guard let executable = Self.agenticCLIResolve(["kubectl"], workingDirectory: root) else {
            throw Self.agenticCLIMissingBinary("kubectl")
        }
        return try await agenticCLIExecute(call, session: s, displayCommand: "kubectl apply -f \(path)",
                                           executable: executable, args: ["apply", "-f", file.path],
                                           workingDirectory: root, gate: true)
    }

    // MARK: - `view_container_logs`

    /// Legacy's `docker logs <containerID>` in the workspace root
    /// (Legacy ran with no working directory). The one pure read in
    /// this slice: no approval gate, `writes: false`.
    func agenticCLIViewContainerLogs(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let containerID = call.string("containerID") else {
            throw MCPToolError("Missing containerID")
        }
        let root = Self.folder(of: s.model)
        guard let executable = Self.agenticCLIResolve(["docker"], workingDirectory: root) else {
            throw Self.agenticCLIMissingBinary("docker")
        }
        return try await agenticCLIExecute(call, session: s, displayCommand: "docker logs \(containerID)",
                                           executable: executable, args: ["logs", containerID],
                                           workingDirectory: root, gate: false)
    }
}
