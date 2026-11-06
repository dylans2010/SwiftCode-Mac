import Foundation
import Testing
import SwiftCodeAssistant
import SwiftCodeIDECore
@testable import SwiftCodeMCP

/// Opt-in, on the real remote simulator host: `SWIFTCODE_MCP_THOR=1` with the
/// host in `SWIFTCODE_MCP_SIM_*` (or `SWIFTCODE_MCP_SIM_CONFIG`, a JSON file as
/// `swiftcode mcp --simulator-config` reads). Boots the device through the
/// tools, waits for a screenshot, and shuts the device down.
/// `SWIFTCODE_MCP_THOR_SHOT` keeps the PNG at that path; `SWIFTCODE_MCP_THOR_WAIT`
/// is how long to wait for it (seconds, default 600).
@MainActor
@Suite(.serialized, .timeLimit(.minutes(60))) struct MCPThorTests {
    nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["SWIFTCODE_MCP_THOR"] == "1" }

    @Test(.enabled(if: MCPThorTests.enabled)) func bootAndScreenshotOnTheRemoteSimulator() async throws {
        let env = ProcessInfo.processInfo.environment
        let settings = try #require(try MCPCommand.simulatorSettings(file: env["SWIFTCODE_MCP_SIM_CONFIG"], environment: env))
        let host = SwiftCodeMCPHost()
        host.remoteSimulator = settings
        let list = try await host.server.callTool("simulator_list")
        #expect(list.structured?["configured"] == true, "\(list.resultText)")
        let boot = try await host.server.callTool("simulator_boot")
        #expect(!boot.isToolError, "\(boot.resultText)")
        // The launcher may wait for a boot slot on a shared host first.
        let wait = Double(env["SWIFTCODE_MCP_THOR_WAIT"] ?? "") ?? 600
        let deadline = Date().addingTimeInterval(wait)
        var png: Data?
        // The launcher says when the home screen shows (warm boot watches
        // the frames); the picture is taken after that, not of the boot.
        while Date() < deadline {
            try await Task.sleep(for: .seconds(10))
            let lines = try await host.server.callTool("simulator_logs", ["tail": 400]).resultText
            guard lines.contains("home screen at") else { continue }
            try await Task.sleep(for: .seconds(5))
            let shot = try await host.server.callTool("simulator_screenshot")
            if let image = shot["content"]?.array?.first(where: { $0["type"] == "image" }), let d = Data(base64Encoded: image["data"]?.string ?? "") {
                png = d
                break
            }
        }
        let logs = try await host.server.callTool("simulator_logs", ["tail": 30])
        let shutdown = try await host.server.callTool("simulator_shutdown")
        let data = try #require(png, "no screenshot within \(Int(wait)) s; launcher: \(logs.resultText)")
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        if let keep = env["SWIFTCODE_MCP_THOR_SHOT"] { try data.write(to: URL(fileURLWithPath: keep)) }
        #expect(!shutdown.isToolError, "\(shutdown.resultText)")
    }
}
