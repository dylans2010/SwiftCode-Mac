import Foundation
import Testing
import SwiftCodeAssistant
import SwiftCodeIDECore
@testable import SwiftCodeMCP

/// The ported Legacy Agentic build-system CLI / container tools
/// (Wave 8, slice E) against `Samples/AgentSamples/Greeter` (a
/// copy). No test runs a CLI with side effects: live runs use only
/// read-only actions (`--version`, `pip show pip`, `go build` in a
/// Swift package — which fails fast with no Go files — and
/// `docker logs` of a container that does not exist), and every
/// other live check is gated on the binary actually being on `PATH`
/// in this environment. A missing binary is the honest failure
/// (`was not found`, naming the binary), never invented output.
@MainActor
@Suite(.serialized) struct SwiftCodeAgenticCLITests {
    /// The 21 Wave 8 slice E Agentic tool IDs, verified live from
    /// Legacy's `ListTools.swift` (`AgentTool.identifier`).
    static let agenticCLIIDs = ["cocoapods", "carthage", "android_build", "gradle", "npm", "pnpm", "yarn", "bun",
                                "cargo", "go_build", "python_pip", "java_maven", "dotnet_cli", "flutter",
                                "react_native", "expo", "docker_build", "docker_run", "docker_compose",
                                "kubernetes_apply", "view_container_logs"]

    /// Opens a copy of Greeter and installs the ported Agentic CLI
    /// tools on the server (same shape as Wave 2's `opened`; the
    /// coordinator wires `agenticCLITools` into `installTools()`).
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        // Filter-first (Wave 2 shape): `installTools()` already wires
        // `agenticCLITools`, so a plain `+=` would register them twice.
        let ported = Set(host.agenticCLITools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticCLITools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    /// Whether `name` resolves to an executable on this process's
    /// `PATH` (the same lookup the tools use).
    func binaryOnPath(_ name: String) -> Bool {
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return pathEnv.split(separator: ":").contains { dir in
            FileManager.default.isExecutableFile(atPath: "\(dir)/\(name)")
        }
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.agenticCLITools
        #expect(tools.map(\.name) == Self.agenticCLIIDs)
        let expectedTitles: [String: String] = [
            "cocoapods": "CocoaPods", "carthage": "Carthage", "android_build": "Build Android Project",
            "gradle": "Gradle", "npm": "npm", "pnpm": "pnpm", "yarn": "Yarn", "bun": "Bun", "cargo": "Cargo",
            "go_build": "Build Go Project", "python_pip": "Python pip", "java_maven": "Maven",
            "dotnet_cli": ".NET CLI", "flutter": "Flutter", "react_native": "React Native", "expo": "Expo",
            "docker_build": "Build Docker Image", "docker_run": "Run Docker Container",
            "docker_compose": "Docker Compose", "kubernetes_apply": "Apply Kubernetes Configuration",
            "view_container_logs": "View Container Logs",
        ]
        let expectedRequired: [String: [String]] = [
            "cocoapods": ["action", "path"], "carthage": ["action", "path"], "android_build": ["path"],
            "gradle": ["action", "path"], "npm": ["action", "path"], "pnpm": ["action", "path"],
            "yarn": ["action", "path"], "bun": ["action", "path"], "cargo": ["action", "path"],
            "go_build": ["path"], "python_pip": ["action", "package"], "java_maven": ["action", "path"],
            "dotnet_cli": ["action", "path"], "flutter": ["action", "path"],
            "react_native": ["action", "path"], "expo": ["action", "path"],
            "docker_build": ["path", "tag"], "docker_run": ["image"], "docker_compose": ["path", "action"],
            "kubernetes_apply": ["path"], "view_container_logs": ["containerID"],
        ]
        // Legacy's verbatim descriptions (from each tool's
        // `description` in `SwiftCode/Tools/Agentic/`).
        let expectedDescriptions: [String: String] = [
            "cocoapods": "Runs CocoaPods commands.", "carthage": "Runs Carthage commands.",
            "android_build": "Builds an Android project.", "gradle": "Runs Gradle commands.",
            "npm": "Runs npm commands.", "pnpm": "Runs pnpm commands.", "yarn": "Runs yarn commands.",
            "bun": "Runs bun commands.", "cargo": "Runs cargo commands.", "go_build": "Builds a Go project.",
            "python_pip": "Runs pip commands.", "java_maven": "Runs Maven commands.",
            "dotnet_cli": "Runs .NET CLI commands.", "flutter": "Runs Flutter commands.",
            "react_native": "Runs React Native commands.", "expo": "Runs Expo commands.",
            "docker_build": "Builds a Docker image.", "docker_run": "Runs a Docker container.",
            "docker_compose": "Runs docker-compose commands.",
            "kubernetes_apply": "Applies a Kubernetes configuration.",
            "view_container_logs": "Views logs for a Docker container.",
        ]
        let expectedOutputs = ["command", "duration", "exitCode", "stderr", "stderrTruncated",
                               "stdout", "stdoutTruncated", "workingDirectory"]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name])
            #expect(tool.description == expectedDescriptions[tool.name], "\(tool.name) description is not Legacy-verbatim")
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            let outputKeys = tool.outputSchema?["properties"]?.object?.keys.sorted() ?? []
            #expect(outputKeys == expectedOutputs, "\(tool.name) output keys: \(outputKeys)")
            if tool.name == "view_container_logs" {
                #expect(tool.annotations.readOnly && tool.annotations.idempotent && !tool.writes,
                        "view_container_logs must be a read-only tool")
            } else {
                #expect(!tool.annotations.readOnly && !tool.annotations.idempotent && tool.writes,
                        "\(tool.name) must be a gated write/execution tool")
            }
        }
        // The host serves them once installed (the coordinator wires
        // `agenticCLITools` into `installTools()`; filter-first so they
        // are not registered twice).
        let installed = Set(host.agenticCLITools.map(\.name))
        host.server.tools = host.server.tools.filter { !installed.contains($0.name) } + host.agenticCLITools
        let served = host.server.tools.map(\.name)
        for id in Self.agenticCLIIDs { #expect(served.contains(id), "\(id) is not installed on the server") }
    }

    @Test func missingRequiredArgumentsFailAtSchema() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        for id in Self.agenticCLIIDs {
            let r = try await host.server.callTool(id, [:])
            #expect(r.isToolError, "\(id) with no arguments must fail")
            #expect(r.firstText.contains("missing the required argument"), "\(id): \(r.firstText)")
        }
    }

    @Test func emptyArgumentsFailWithLegacyMessages() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // Empty strings pass the schema (they are present) and reach
        // the handler, which reports Legacy's exact messages.
        let cases: [(String, [String: AnyJSON], String)] = [
            ("cocoapods", ["action": .string(""), "path": .string("")], "Missing action or path"),
            ("carthage", ["action": .string(""), "path": .string("")], "Missing action or path"),
            ("android_build", ["path": .string("")], "Missing path"),
            ("gradle", ["action": .string(""), "path": .string("")], "Missing action or path"),
            ("npm", ["action": .string(""), "path": .string("")], "Missing action or path"),
            ("go_build", ["path": .string("")], "Missing path"),
            ("python_pip", ["action": .string(""), "package": .string("")], "Missing action or package"),
            ("docker_build", ["path": .string(""), "tag": .string("")], "Missing path or tag"),
            ("docker_run", ["image": .string("")], "Missing image"),
            ("docker_compose", ["path": .string(""), "action": .string("")], "Missing path or action"),
            ("kubernetes_apply", ["path": .string("")], "Missing path"),
            ("view_container_logs", ["containerID": .string("")], "Missing containerID"),
        ]
        for (id, args, message) in cases {
            let r = try await host.server.callTool(id, args)
            #expect(r.isToolError, "\(id) with empty arguments must fail")
            #expect(r.firstText.contains(message), "\(id): \(r.firstText)")
        }
    }

    @Test func pathsMustStayInsideWorkspaceAndExist() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let escaping = try await host.server.callTool("npm", ["action": .string("install"), "path": .string("../outside")])
        #expect(escaping.isToolError && escaping.firstText.contains("outside the workspace folder"),
                "escaping path: \(escaping.firstText)")
        let missingDir = try await host.server.callTool("npm", ["action": .string("install"), "path": .string("Nope")])
        #expect(missingDir.isToolError && missingDir.firstText.contains("does not exist or is not a directory"),
                "missing directory: \(missingDir.firstText)")
        let missingFile = try await host.server.callTool("kubernetes_apply", ["path": .string("Nope.yaml")])
        #expect(missingFile.isToolError && missingFile.firstText.contains("does not exist or is not a file"),
                "missing manifest: \(missingFile.firstText)")
        let missingCompose = try await host.server.callTool("docker_compose", ["path": .string("Nope.yml"), "action": .string("up")])
        #expect(missingCompose.isToolError && missingCompose.firstText.contains("does not exist or is not a file"),
                "missing compose file: \(missingCompose.firstText)")
    }

    @Test func missingBinariesFailHonestly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // One-argument wrappers: when the binary is absent the tool
        // fails naming it; when present, `--version` is a read-only,
        // side-effect-free run that must report its real output.
        let versionTools: [(String, String)] = [
            ("cocoapods", "pod"), ("carthage", "carthage"), ("gradle", "gradle"), ("npm", "npm"),
            ("pnpm", "pnpm"), ("yarn", "yarn"), ("bun", "bun"), ("cargo", "cargo"),
            ("java_maven", "mvn"), ("dotnet_cli", "dotnet"), ("flutter", "flutter"),
        ]
        for (id, program) in versionTools {
            if binaryOnPath(program) {
                let r = try await host.server.callTool(id, ["action": .string("--version"), "path": .string(".")])
                #expect(!r.isToolError, "\(id) --version must run honestly: \(r.firstText)")
                #expect(r.structured?["exitCode"] == .int(0), "\(id) --version exit code")
                #expect(r.structured?["command"]?.string == "\(program) --version", "\(id) command key")
            } else {
                let r = try await host.server.callTool(id, ["action": .string("--version"), "path": .string(".")])
                #expect(r.isToolError, "\(id) must fail without \(program)")
                #expect(r.firstText.contains("command '\(program)' was not found"), "\(id): \(r.firstText)")
            }
        }
        // `react_native` / `expo` run through `npx`: when `npx` is
        // absent the failure names it; when present no live call is
        // made here, because `npx react-native` would fetch the
        // package from the network.
        for id in ["react_native", "expo"] {
            if !binaryOnPath("npx") {
                let r = try await host.server.callTool(id, ["action": .string("--version"), "path": .string(".")])
                #expect(r.isToolError && r.firstText.contains("command 'npx' was not found"), "\(id): \(r.firstText)")
            }
        }
        // `go build` in a Swift package fails fast with no Go files
        // when `go` is present; when absent it names the binary.
        if binaryOnPath("go") {
            let r = try await host.server.callTool("go_build", ["path": .string(".")])
            #expect(r.isToolError && r.firstText.contains("exit code"), "go build in a Swift package: \(r.firstText)")
            #expect(r.structured?["exitCode"] != nil, "go build must still carry structured data")
        } else {
            let r = try await host.server.callTool("go_build", ["path": .string(".")])
            #expect(r.isToolError && r.firstText.contains("command 'go' was not found"), "go_build: \(r.firstText)")
        }
        // `gradle assembleDebug` is not run live when gradle is
        // present (daemon startup plus a build attempt in a
        // non-Android directory); only the missing-binary branch is
        // asserted here.
        if !binaryOnPath("gradle") && !FileManager.default.isExecutableFile(atPath: sample.path("gradlew")) {
            let r = try await host.server.callTool("android_build", ["path": .string(".")])
            #expect(r.isToolError && r.firstText.contains("command 'gradle' was not found"), "android_build: \(r.firstText)")
        }
        // `pip show pip` is a read-only query when `pip` is present;
        // when absent the failure names `pip`.
        if binaryOnPath("pip") || binaryOnPath("pip3") {
            let r = try await host.server.callTool("python_pip", ["action": .string("show"), "package": .string("pip")])
            #expect(!r.isToolError, "pip show pip must run honestly: \(r.firstText)")
            #expect(r.structured?["exitCode"] == .int(0), "pip show pip exit code")
        } else {
            let r = try await host.server.callTool("python_pip", ["action": .string("show"), "package": .string("pip")])
            #expect(r.isToolError && r.firstText.contains("command 'pip' was not found"), "python_pip: \(r.firstText)")
        }
        // Docker / kubectl tools are never run live when the binary
        // is present (image builds, container runs, and `kubectl
        // apply` all have side effects); only the missing-binary
        // branch is asserted here.
        if !binaryOnPath("docker") {
            let build = try await host.server.callTool("docker_build", ["path": .string("."), "tag": .string("greeter:latest")])
            #expect(build.isToolError && build.firstText.contains("command 'docker' was not found"), "docker_build: \(build.firstText)")
            let run = try await host.server.callTool("docker_run", ["image": .string("hello-world")])
            #expect(run.isToolError && run.firstText.contains("command 'docker' was not found"), "docker_run: \(run.firstText)")
            let logs = try await host.server.callTool("view_container_logs", ["containerID": .string("no-such-container")])
            #expect(logs.isToolError && logs.firstText.contains("command 'docker' was not found"), "view_container_logs: \(logs.firstText)")
        } else {
            // `docker logs` of a container that does not exist is a
            // pure read: docker itself must fail honestly, exit 1.
            let logs = try await host.server.callTool("view_container_logs", ["containerID": .string("no-such-container-xyz")])
            #expect(logs.isToolError && logs.firstText.contains("exit code 1"), "docker logs of a missing container: \(logs.firstText)")
        }
        if !binaryOnPath("docker-compose") && !binaryOnPath("docker") {
            let compose = sample.path("docker-compose.yml")
            try "services:\n  greeter:\n    image: hello-world\n".write(toFile: compose, atomically: true, encoding: .utf8)
            let r = try await host.server.callTool("docker_compose", ["path": .string("docker-compose.yml"), "action": .string("version")])
            #expect(r.isToolError && r.firstText.contains("command 'docker-compose' was not found"),
                    "docker_compose with no docker binary: \(r.firstText)")
        }
        if !binaryOnPath("kubectl") {
            let manifest = sample.path("k8s.yaml")
            try "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: greeter\n".write(toFile: manifest, atomically: true, encoding: .utf8)
            let r = try await host.server.callTool("kubernetes_apply", ["path": .string("k8s.yaml")])
            #expect(r.isToolError && r.firstText.contains("command 'kubectl' was not found"), "kubernetes_apply: \(r.firstText)")
        }
    }

    @Test func writeToolsAreRefusedByReadOnlyPolicy() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .readOnly)
        let r = try await host.server.callTool("npm", ["action": .string("install"), "path": .string(".")])
        #expect(r.isToolError, "a writes:true execution tool must not run under the read-only policy")
        #expect(r.firstText.contains("read-only"), "read-only refusal: \(r.firstText)")
        // The one pure read is not refused by the policy: it fails
        // only on the missing binary (or on docker's own error),
        // never on the read-only message.
        let logs = try await host.server.callTool("view_container_logs", ["containerID": .string("no-such-container")])
        #expect(!logs.firstText.contains("read-only"), "view_container_logs must not be refused by the read-only policy: \(logs.firstText)")
    }
}
