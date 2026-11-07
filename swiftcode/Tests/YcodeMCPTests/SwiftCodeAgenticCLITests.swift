import Foundation
import Testing
import YcodeAssistant
import YcodeIDECore
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeAgenticCLITests {
    static let agenticCLIIDs = ["cocoapods", "carthage", "android_build", "gradle", "npm", "pnpm", "yarn", "bun",
                                "cargo", "go_build", "python_pip", "java_maven", "dotnet_cli", "flutter",
                                "react_native", "expo", "docker_build", "docker_run", "docker_compose",
                                "kubernetes_apply", "view_container_logs"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.agenticCLITools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticCLITools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

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
        for id in ["react_native", "expo"] {
            if !binaryOnPath("npx") {
                let r = try await host.server.callTool(id, ["action": .string("--version"), "path": .string(".")])
                #expect(r.isToolError && r.firstText.contains("command 'npx' was not found"), "\(id): \(r.firstText)")
            }
        }
        if binaryOnPath("go") {
            let r = try await host.server.callTool("go_build", ["path": .string(".")])
            #expect(r.isToolError && r.firstText.contains("exit code"), "go build in a Swift package: \(r.firstText)")
            #expect(r.structured?["exitCode"] != nil, "go build must still carry structured data")
        } else {
            let r = try await host.server.callTool("go_build", ["path": .string(".")])
            #expect(r.isToolError && r.firstText.contains("command 'go' was not found"), "go_build: \(r.firstText)")
        }
        if !binaryOnPath("gradle") && !FileManager.default.isExecutableFile(atPath: sample.path("gradlew")) {
            let r = try await host.server.callTool("android_build", ["path": .string(".")])
            #expect(r.isToolError && r.firstText.contains("command 'gradle' was not found"), "android_build: \(r.firstText)")
        }
        if binaryOnPath("pip") || binaryOnPath("pip3") {
            let r = try await host.server.callTool("python_pip", ["action": .string("show"), "package": .string("pip")])
            #expect(!r.isToolError, "pip show pip must run honestly: \(r.firstText)")
            #expect(r.structured?["exitCode"] == .int(0), "pip show pip exit code")
        } else {
            let r = try await host.server.callTool("python_pip", ["action": .string("show"), "package": .string("pip")])
            #expect(r.isToolError && r.firstText.contains("command 'pip' was not found"), "python_pip: \(r.firstText)")
        }
        if !binaryOnPath("docker") {
            let build = try await host.server.callTool("docker_build", ["path": .string("."), "tag": .string("greeter:latest")])
            #expect(build.isToolError && build.firstText.contains("command 'docker' was not found"), "docker_build: \(build.firstText)")
            let run = try await host.server.callTool("docker_run", ["image": .string("hello-world")])
            #expect(run.isToolError && run.firstText.contains("command 'docker' was not found"), "docker_run: \(run.firstText)")
            let logs = try await host.server.callTool("view_container_logs", ["containerID": .string("no-such-container")])
            #expect(logs.isToolError && logs.firstText.contains("command 'docker' was not found"), "view_container_logs: \(logs.firstText)")
        } else {
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
        let logs = try await host.server.callTool("view_container_logs", ["containerID": .string("no-such-container")])
        #expect(!logs.firstText.contains("read-only"), "view_container_logs must not be refused by the read-only policy: \(logs.firstText)")
    }
}
