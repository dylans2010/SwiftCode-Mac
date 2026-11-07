import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeAgenticExecutionTests {
    static let sliceBIDs = ["run_linter", "run_formatter", "run_type_checker", "run_static_analysis",
                            "run_benchmark", "run_application", "stop_running_process", "get_process_logs",
                            "read_build_logs"]

    static func programOnPath(_ name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in path.split(separator: ":") {
            let candidate = (dir.isEmpty ? "." : String(dir)) + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.agenticExecutionTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticExecutionTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ sample: TempSample, _ rel: String) -> String {
        (try? String(contentsOfFile: sample.path(rel), encoding: .utf8)) ?? ""
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.agenticExecutionTools
        #expect(tools.map(\.name) == Self.sliceBIDs)
        let expectedTitles: [String: String] = [
            "run_linter": "Run Linter", "run_formatter": "Run Formatter", "run_type_checker": "Run Type Checker",
            "run_static_analysis": "Run Static Analysis", "run_benchmark": "Run Benchmark",
            "run_application": "Run Application", "stop_running_process": "Stop Running Process",
            "get_process_logs": "Get Process Logs", "read_build_logs": "Read Build Logs",
        ]
        let expectedDescriptions: [String: String] = [
            "run_linter": "Runs a linter (SwiftLint) on a given path.",
            "run_formatter": "Runs a formatter (SwiftFormat) on a given path.",
            "run_type_checker": "Runs the Swift type checker on a project.",
            "run_static_analysis": "Runs static analysis on a Swift project.",
            "run_benchmark": "Runs benchmarks on a Swift project.",
            "run_application": "Runs a Swift application target.",
            "stop_running_process": "Stops a running process using its PID.",
            "get_process_logs": "Retrieves logs for a running process.",
            "read_build_logs": "Reads build logs from a project directory.",
        ]
        let expectedRequired: [String: [String]] = [
            "run_linter": ["path"], "run_formatter": ["path"], "run_type_checker": ["projectPath"],
            "run_static_analysis": ["projectPath"], "run_benchmark": ["projectPath"],
            "run_application": ["projectPath", "target"], "stop_running_process": ["pid"],
            "get_process_logs": ["pid"], "read_build_logs": ["projectPath"],
        ]
        let expectedOutputs: [String: [String]] = [
            "run_linter": ["exitCode", "outputTail"], "run_formatter": ["exitCode", "outputTail"],
            "run_type_checker": ["exitCode", "outputTail"], "run_static_analysis": ["exitCode", "outputTail"],
            "run_benchmark": ["exitCode", "outputTail"], "run_application": ["exitCode", "outputTail"],
            "stop_running_process": [], "get_process_logs": [], "read_build_logs": [],
        ]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name], "\(tool.name) title")
            #expect(tool.description == expectedDescriptions[tool.name], "\(tool.name) description is Legacy's verbatim")
            #expect(tool.inputSchema["properties"]?.object?.keys.contains("workspace") == true, "\(tool.name) carries workspace")
            #expect(tool.inputSchema["required"]?.array?.compactMap(\.string).sorted() == expectedRequired[tool.name]?.sorted(),
                    "\(tool.name) required params")
            #expect(tool.outputSchema?["required"]?.array?.compactMap(\.string).sorted() == expectedOutputs[tool.name]?.sorted(),
                    "\(tool.name) output keys")
        }
    }

    @Test func toolIDsAreRegisteredOnce() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        #expect(host.agenticExecutionTools.map(\.name) == Self.sliceBIDs)
        for id in Self.sliceBIDs {
            #expect(host.server.tools.filter { $0.name == id }.count == 1, "\(id) must be registered exactly once")
        }
    }

    @Test func readBuildLogsReadsDotBuildLog() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, ".build/build.log", "Build succeeded.\n2 warnings.\n")
        let r = try await host.server.callTool("read_build_logs", ["projectPath": .string(".")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText == "Build succeeded.\n2 warnings.\n")
    }

    @Test func readBuildLogsTruncatesLongLogs() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let long = String(repeating: "x", count: 9000)
        try writeFixture(sample, ".build/build.log", long)
        let r = try await host.server.callTool("read_build_logs", ["projectPath": .string(".")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.hasSuffix("… [build log truncated to last 8000 chars]"))
        #expect(r.firstText.count < long.count)
    }

    @Test func readBuildLogsFailsWhenMissing() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("read_build_logs", ["projectPath": .string(".")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Build log not found"))
        let missing = try await host.server.callTool("read_build_logs", [:])
        #expect(missing.isToolError)
        let file = try await host.server.callTool("read_build_logs", ["projectPath": .string("Package.swift")])
        #expect(file.isToolError)
        #expect(file.firstText.contains("not a directory"))
    }

    @Test func getProcessLogsFailsNamingMissingBuffer() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("get_process_logs", ["pid": .int(1234)])
        #expect(r.isToolError)
        #expect(r.firstText.contains("per-process log buffer"))
        let missing = try await host.server.callTool("get_process_logs", [:])
        #expect(missing.isToolError)
    }

    @Test func stopRunningProcessTerminatesSleep() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["60"]
        sleeper.standardOutput = FileHandle.nullDevice
        sleeper.standardError = FileHandle.nullDevice
        try sleeper.run()
        defer { if sleeper.isRunning { sleeper.terminate() } }
        let pid = Int(sleeper.processIdentifier)
        let r = try await host.server.callTool("stop_running_process", ["pid": .int(pid)])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText == "Process \(pid) terminated.")
        for _ in 0..<20 where sleeper.isRunning {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!sleeper.isRunning, "the sleep process must be gone after SIGTERM")
    }

    @Test func stopRunningProcessRefusesDangerousPids() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let one = try await host.server.callTool("stop_running_process", ["pid": .int(1)])
        #expect(one.isToolError)
        #expect(one.firstText.contains("refusing"))
        let selfPid = try await host.server.callTool("stop_running_process",
                                                     ["pid": .int(Int(ProcessInfo.processInfo.processIdentifier))])
        #expect(selfPid.isToolError)
        #expect(selfPid.firstText.contains("own process"))
        let ghost = try await host.server.callTool("stop_running_process", ["pid": .int(999_999)])
        #expect(ghost.isToolError)
        let missing = try await host.server.callTool("stop_running_process", [:])
        #expect(missing.isToolError)
    }

    @Test func writeToolsAreRefusedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let formatted = try await host.server.callTool("run_formatter", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(formatted.isToolError)
        #expect(formatted.firstText.contains("read-only"))
        let stopped = try await host.server.callTool("stop_running_process", ["pid": .int(999_999)])
        #expect(stopped.isToolError)
        #expect(stopped.firstText.contains("read-only"))
    }

    @Test func runToolsRejectBadArguments() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        for (name, args) in [("run_linter", [:]), ("run_type_checker", [:]), ("run_benchmark", [:]),
                             ("run_application", ["projectPath": .string(".")])] as [(String, [String: AnyJSON])] {
            let r = try await host.server.callTool(name, args)
            #expect(r.isToolError, "\(name) must fail without its required params")
        }
        let file = try await host.server.callTool("run_type_checker", ["projectPath": .string("Package.swift")])
        #expect(file.isToolError)
        #expect(file.firstText.contains("not a directory"))
        let gone = try await host.server.callTool("run_linter", ["path": .string("NoSuchFile.swift")])
        #expect(gone.isToolError)
        #expect(gone.firstText.contains("does not exist"))
        let spaced = try await host.server.callTool("run_application", ["projectPath": .string("."), "target": .string("my target")])
        #expect(spaced.isToolError)
        #expect(spaced.firstText.contains("bare target name"))
        let flag = try await host.server.callTool("run_application", ["projectPath": .string("."), "target": .string("--help")])
        #expect(flag.isToolError)
        #expect(flag.firstText.contains("bare target name"))
    }

    @Test func runLinterNeedsSwiftLint() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        guard Self.programOnPath("swiftlint") == nil else { return }
        let r = try await host.server.callTool("run_linter", ["path": .string("Sources/Greeter")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("SwiftLint"))
        #expect(r.firstText.contains("was not found on PATH"))
    }

    @Test func runLinterRunsRealSwiftLintWhenPresent() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        guard Self.programOnPath("swiftlint") != nil else { return }
        try writeFixture(sample, "LintMe.swift", "public struct LintMe {\n    public let value: Int = 1\n}\n")
        let r = try await host.server.callTool("run_linter", ["path": .string("LintMe.swift")])
        if r.isToolError {
            #expect(r.firstText.contains("exit code"))
        } else {
            #expect(r.structured?["exitCode"]?.int == 0)
        }
    }

    @Test func runFormatterNeedsSwiftFormat() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        guard Self.programOnPath("swiftformat") == nil else { return }
        let r = try await host.server.callTool("run_formatter", ["path": .string("Sources/Greeter")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("SwiftFormat"))
        #expect(r.firstText.contains("was not found on PATH"))
    }

    @Test func runFormatterReformatsWithRealSwiftFormatWhenPresent() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        guard Self.programOnPath("swiftformat") != nil else { return }
        try writeFixture(sample, "BadFormat.swift", "struct BadFormat {\nlet x=1\n}\n")
        let r = try await host.server.callTool("run_formatter", ["path": .string("BadFormat.swift")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["exitCode"]?.int == 0)
        #expect(read(sample, "BadFormat.swift").contains("let x = 1"))
    }

    @Test func runTypeCheckerBuildsTests() async throws {
        guard canBuildPackages else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("run_type_checker", ["projectPath": .string(".")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["exitCode"]?.int == 0)
    }

    @Test func runStaticAnalysisRunsAnalyzer() async throws {
        guard canBuildPackages else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("run_static_analysis", ["projectPath": .string(".")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["exitCode"]?.int == 0)
    }

    @Test func runBenchmarkFailsWithoutBenchmarkTarget() async throws {
        guard canBuildPackages else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("run_benchmark", ["projectPath": .string(".")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("exit code"))
    }

    @Test func runApplicationRunsGreet() async throws {
        guard canBuildPackages else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("run_application", ["projectPath": .string("."), "target": .string("greet")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["exitCode"]?.int == 0)
        #expect(r.firstText.contains("Hello, world!"))
    }
}
