import Foundation
import Testing
import SwiftCodeAssistant
import SwiftCodeIDECore
@testable import SwiftCodeMCP

@MainActor
@Suite(.serialized, .timeLimit(.minutes(60))) struct MCPThorTests {
    nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["SWIFTCODE_MCP_THOR"] == "1" }

    @Test(.enabled(if: MCPThorTests.enabled)) func bootAndScreenshotOnTheRemoteSimulator() async throws {
        let env = ProcessInfo.processInfo.environment
        let settings = try #require(try MCPCommand.simulatorSettings(file: env["SWIFTCODE_MCP_SIM_CONFIG"], environment: env))
        let host = SwiftCodeMCPHost()
        host.remoteSimulator = settings
        let list = try await host.server.callTool("simulator_list")
        #expect(list.structured?["configured"]?.bool == true, "\(list.resultText)")
        let boot = try await host.server.callTool("simulator_boot")
        #expect(!boot.isToolError, "\(boot.resultText)")
        let wait = Double(env["SWIFTCODE_MCP_THOR_WAIT"] ?? "") ?? 600
        let deadline = Date().addingTimeInterval(wait)
        var png: Data?
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
