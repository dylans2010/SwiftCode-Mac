import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public enum MCPCommand {
    public static let help = """
    usage: swiftcode mcp [--workspace <path>] [--allow-writes] [--http [<port>]] [--simulator-config <file.json>]
           swiftcode mcp install-skill [<folder>]   writes the SwiftCode skill for agents into <folder>
                                                (default: the current folder): .claude/skills/swiftcode/SKILL.md
                                                and .agents/skills/swiftcode/SKILL.md

    Serves SwiftCode's tools to a coding agent over the Model Context Protocol
    (revision 2026-07-28, and 2025-11-25 … 2025-03-26 for older clients).

      --workspace <path>   the package folder, Package.swift, .xcodeproj or .xcworkspace
                           opened at start (default: the one in the current folder,
                           if there is exactly one; agents can call workspace_open)
      --allow-writes       let file_write, file_edit and strings_set change files
                           (default: read-only; those tools are refused)
      --http [<port>]      Streamable HTTP at http://127.0.0.1:<port>/mcp instead of
                           stdio (loopback only). Clients send "Authorization: Bearer
                           <token>": the token is $SWIFTCODE_MCP_TOKEN, else a new one
                           printed on standard error.
      --simulator-config <file.json>
                           the remote SwiftCode Simulator host: {"destination": "user@host",
                           "dataDirectory": …, "runtimeRoot": …, "launcher": …,
                           "device": …, "additionalArguments": …}. Or set
                           SWIFTCODE_MCP_SIM_DESTINATION, SWIFTCODE_MCP_SIM_DATA,
                           SWIFTCODE_MCP_SIM_RUNTIME, SWIFTCODE_MCP_SIM_LAUNCHER and
                           SWIFTCODE_MCP_SIM_DEVICE. ssh uses keys only (BatchMode).

    Claude Code:  claude mcp add swiftcode -- swiftcode mcp
    Codex:        codex mcp add swiftcode -- swiftcode mcp

    """

    public struct Options: Equatable {
        public var workspace: String?
        public var allowWrites = false
        public var httpPort: UInt16?
        public var simulatorConfig: String?
        public init() {}
    }

    public enum ParseError: Error, Equatable { case usage(String), help }

    public static func parse(_ args: [String]) throws -> Options {
        var o = Options()
        var i = 0
        func value(_ flag: String) throws -> String {
            i += 1
            guard i < args.count else { throw ParseError.usage("\(flag) needs a value") }
            return args[i]
        }
        while i < args.count {
            switch args[i] {
            case "--workspace", "-w": o.workspace = try value("--workspace")
            case "--allow-writes": o.allowWrites = true
            case "--http":
                o.httpPort = 0
                if i + 1 < args.count, let p = UInt16(args[i + 1]) { o.httpPort = p; i += 1 }
            case "--simulator-config": o.simulatorConfig = try value("--simulator-config")
            case "--help", "-h": throw ParseError.help
            default: throw ParseError.usage("unknown option \(args[i])")
            }
            i += 1
        }
        return o
    }

    public static func simulatorSettings(file: String?, environment: [String: String]) throws -> RemoteSimulatorSettings? {
        var s = RemoteSimulatorSettings()
        if let file {
            let v = try AnyJSON.parse(Data(contentsOf: URL(fileURLWithPath: (file as NSString).expandingTildeInPath)))
            s.destination = v["destination"]?.string ?? ""
            s.dataDirectory = v["dataDirectory"]?.string ?? ""
            s.runtimeRoot = v["runtimeRoot"]?.string ?? ""
            s.simdPath = v["launcher"]?.string ?? ""
            s.deviceName = v["device"]?.string ?? "swiftcode-device"
            s.additionalArguments = v["additionalArguments"]?.string ?? ""
            if let w = v["warmBoot"]?.bool { s.warmBoot = w }
            s.otherRuntimeRoots = v["otherRuntimeRoots"]?.array?.compactMap(\.string) ?? []
        } else {
            guard let d = environment["SWIFTCODE_MCP_SIM_DESTINATION"], !d.isEmpty else { return nil }
            s.destination = d
            s.dataDirectory = environment["SWIFTCODE_MCP_SIM_DATA"] ?? ""
            s.runtimeRoot = environment["SWIFTCODE_MCP_SIM_RUNTIME"] ?? ""
            s.simdPath = environment["SWIFTCODE_MCP_SIM_LAUNCHER"] ?? ""
            s.deviceName = environment["SWIFTCODE_MCP_SIM_DEVICE"] ?? "swiftcode-device"
            s.additionalArguments = environment["SWIFTCODE_MCP_SIM_ARGS"] ?? ""
        }
        s.runtimeVersion = RemoteSimulatorSettings.version(inPath: s.runtimeRoot)
        return s
    }

    public static func run(_ args: [String]) -> Never {
        if args.first == "install-skill" {
            let folder = URL(fileURLWithPath: args.dropFirst().first.map { ($0 as NSString).expandingTildeInPath } ?? FileManager.default.currentDirectoryPath)
            let tools = MainActor.assumeIsolated { SwiftCodeMCPHost().server.tools }
            do {
                for url in try AgentSkill.install(into: folder.standardizedFileURL, tools: tools) { print(url.path) }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("swiftcode mcp: cannot write the skill: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        let options: Options
        do {
            options = try parse(args)
        } catch ParseError.help {
            FileHandle.standardError.write(Data(help.utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("swiftcode mcp: \(error)\n\n\(help)".utf8))
            exit(2)
        }
        let env = ProcessInfo.processInfo.environment
        let protocolOut = dup(STDOUT_FILENO)
        if options.httpPort == nil { dup2(STDERR_FILENO, STDOUT_FILENO) }
        UserDefaults.standard.register(defaults: ["SwiftCode.remote.debugger": false])

        let simulator: RemoteSimulatorSettings?
        do {
            simulator = try simulatorSettings(file: options.simulatorConfig, environment: env)
        } catch {
            FileHandle.standardError.write(Data("swiftcode mcp: cannot read the simulator configuration: \(error)\n".utf8))
            exit(2)
        }
        let server = MCPServer(name: "swiftcode", version: swiftcodeVersion, title: "SwiftCode")
        server.writePolicy = options.allowWrites ? .allow : .readOnly
        let hostBox = HostBox()
        MainActor.assumeIsolated {
            let host = SwiftCodeMCPHost(server: server)
            host.remoteSimulator = simulator
            let start = options.workspace.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
                ?? SwiftCodeMCPHost.discoverWorkspace(in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            if let start {
                do { try host.open(start) } catch {
                    FileHandle.standardError.write(Data("swiftcode mcp: cannot open \(start.path): \(error.localizedDescription)\n".utf8))
                    if options.workspace != nil { exit(1) }
                }
            }
            hostBox.host = host
        }
        if let port = options.httpPort {
            do {
                let token = env["SWIFTCODE_MCP_TOKEN"].flatMap { $0.isEmpty ? nil : $0 } ?? MCPHTTPTransport.newToken()
                let http = try MCPHTTPTransport(server: server, token: token, port: port)
                hostBox.http = http
                var note = "swiftcode mcp: serving \(http.endpoint)\n"
                if env["SWIFTCODE_MCP_TOKEN"] == nil { note += "swiftcode mcp: bearer token \(token)\n" }
                FileHandle.standardError.write(Data(note.utf8))
            } catch {
                FileHandle.standardError.write(Data("swiftcode mcp: \(error)\n".utf8))
                exit(1)
            }
        } else {
            let transport = MCPStdioTransport(server: server, input: STDIN_FILENO, output: protocolOut) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { hostBox.host?.shutDown() }
                    exit(0)
                }
            }
            hostBox.stdio = transport
            transport.start()
        }
        dispatchMain()
    }

    public static let swiftcodeVersion = "0.27"

    final class HostBox: @unchecked Sendable {
        var host: SwiftCodeMCPHost?
        var http: MCPHTTPTransport?
        var stdio: MCPStdioTransport?
    }
}

extension SwiftCodeMCPHost {
    public func shutDown() {
        for r in runs.values where r.status == nil { r.process.terminate() }
        if let s = session, let run = s.simulatorRun { s.stopSimulatorRun(remote: run.remote) }
    }
}
