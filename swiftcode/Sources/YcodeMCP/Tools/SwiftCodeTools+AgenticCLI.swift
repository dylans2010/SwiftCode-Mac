import Foundation
import YcodeAssistant
import YcodeIDECore

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

    nonisolated static func agenticCLIResolve(_ names: [String], workingDirectory: URL) -> String? {
        for name in names {
            if let found = terminalResolveProgram(name, workingDirectory: workingDirectory) { return found }
        }
        return nil
    }

    nonisolated static func agenticCLIMissingBinary(_ program: String) -> MCPToolError {
        MCPToolError("Process execution failed: command '\(program)' was not found (no executable on PATH or at that path).")
    }

    func agenticCLIWorkingDirectory(_ path: String, in s: WorkspaceSession) throws -> URL {
        let url = try resolveFileReadingPath(path, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPToolError("path does not exist or is not a directory: \(path)")
        }
        return url
    }

    func agenticCLIFile(_ path: String, in s: WorkspaceSession) throws -> URL {
        let url = try resolveFileReadingPath(path, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            throw MCPToolError("path does not exist or is not a file: \(path)")
        }
        return url
    }

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
