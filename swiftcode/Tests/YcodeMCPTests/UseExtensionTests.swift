import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct UseExtensionTests {
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.terminalTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.terminalTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func useExtensionValidation() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)

        let unknown = try await host.server.callTool("use_extension", ["action": .string("explode")])
        #expect(unknown.isToolError && unknown.firstText.contains("Unknown or missing action"))

        let noId = try await host.server.callTool("use_extension", ["action": .string("details")])
        #expect(noId.isToolError && noId.firstText.contains("requires 'extensionId'"))

        let missingConfirm = try await host.server.callTool("use_extension",
                                                            ["action": .string("execute"), "extensionId": .string("x.y"),
                                                             "command": .string("c")])
        #expect(missingConfirm.isToolError && missingConfirm.firstText.contains("requires confirm: true"))
        let denied = try await host.server.callTool("use_extension",
                                                    ["action": .string("execute"), "extensionId": .string("x.y"),
                                                     "command": .string("c"), "confirm": .bool(false)])
        #expect(denied.isToolError && denied.firstText.contains("requires confirm: true"))
    }

    @Test func useExtensionXcodeRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "demo.txt", "cherry\nbanana\napple\n")
        let host = try await opened(sample)
        let r = try await host.server.callTool("use_extension",
                                               ["action": .string("run_xcode_command"),
                                                "extensionId": .string("x.y"),
                                                "command": .string("com.swiftcode.xcode.sortLines"),
                                                "confirm": .bool(true), "file": .string("demo.txt"),
                                                "selection": .object(["startLine": .int(0), "startColumn": .int(0),
                                                                      "endLine": .int(2), "endColumn": .int(5)])])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["changed"]?.bool == true)
        #expect(sample.read("demo.txt").components(separatedBy: .newlines).prefix(3) == ["apple", "banana", "cherry"])
        let again = try await host.server.callTool("use_extension",
                                                   ["action": .string("run_xcode_command"),
                                                    "extensionId": .string("x.y"),
                                                    "command": .string("com.swiftcode.xcode.sortLines"),
                                                    "confirm": .bool(true), "file": .string("demo.txt"),
                                                    "selection": .object(["startLine": .int(0), "startColumn": .int(0),
                                                                          "endLine": .int(2), "endColumn": .int(5)])])
        #expect(!again.isToolError, "\(again.resultText)")
        #expect(again.structured?["changed"]?.bool == false)
    }

    @Test func useExtensionHonestFailures() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "demo.txt", "b\na\n")
        let host = try await opened(sample)

        let unknown = try await host.server.callTool("use_extension",
                                                     ["action": .string("run_xcode_command"),
                                                      "extensionId": .string("x.y"),
                                                      "command": .string("com.swiftcode.xcode.nope"),
                                                      "confirm": .bool(true), "file": .string("demo.txt")])
        #expect(unknown.isToolError && unknown.firstText.contains("Unknown Xcode command"))
        #expect(sample.read("demo.txt") == "b\na\n")

        let escaping = try await host.server.callTool("use_extension",
                                                      ["action": .string("run_xcode_command"),
                                                       "extensionId": .string("x.y"),
                                                       "command": .string("com.swiftcode.xcode.sortLines"),
                                                       "confirm": .bool(true), "file": .string("../outside.txt")])
        #expect(escaping.isToolError && escaping.firstText.contains("outside the workspace"))
        #expect(sample.read("demo.txt") == "b\na\n")

        let missing = try await host.server.callTool("use_extension",
                                                     ["action": .string("run_xcode_command"),
                                                      "extensionId": .string("x.y"),
                                                      "command": .string("com.swiftcode.xcode.sortLines"),
                                                      "confirm": .bool(true), "file": .string("Nope.txt")])
        #expect(missing.isToolError && missing.firstText.contains("Cannot read 'Nope.txt'"))
    }
}
