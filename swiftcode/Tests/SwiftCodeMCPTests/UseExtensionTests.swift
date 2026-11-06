import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeMCP

/// The three `use_extension` checks from Legacy's `ExtV2TestSuite`
/// (Legacy `SwiftCode/Backend/Extensions v2/Tests/ExtV2TestSuite.swift`,
/// Dylan's own code, ported under MIT), as black-box MCP-tool tests
/// driving the real `use_extension` tool through the server — the
/// same harness shape as `SwiftCodeExtensionToolTests` (this test
/// target does not depend on `SwiftCodeExtensions`, so the host is
/// reached only through the handler).
///
/// Legacy drove `UseExtensionRouter.validate` / `clampedLimit` /
/// `run` and the `ExtV2XcodeCommandRegistry` directly; none of those
/// types exist in the destination (the dispatch is inline in
/// `SwiftCodeTools+Terminal.swift`), so the checks are expressed
/// against the tool's own contract instead:
/// 1. validation — unknown action fails; `details` without an
///    extensionId fails; `execute` without `confirm: true` fails.
/// 2. Xcode round-trip — `run_xcode_command` sort-lines on a temp
///    workspace file sorts the lines on disk (Legacy asserted
///    `filesChanged == ["demo.txt"]`; the destination reports the
///    same fact as `changed: true` plus the on-disk content, which
///    is what this test asserts).
/// 3. honest failures — unknown command, workspace-escaping file,
///    and missing file all fail with an error and leave the file
///    unmutated.
@MainActor
@Suite(.serialized) struct UseExtensionTests {
    /// Opens a copy of Greeter and installs the ported terminal tools
    /// on the server (same shape as
    /// `SwiftCodeExtensionToolTests.opened`). Defaults to `.allow`:
    /// `use_extension` is `writes: true`, so the read-only policy
    /// refuses it before it runs.
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.terminalTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.terminalTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    /// Writes a fixture file directly (not through a tool under test).
    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - 1. Validation

    @Test func useExtensionValidation() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)

        // Unknown action fails.
        let unknown = try await host.server.callTool("use_extension", ["action": .string("explode")])
        #expect(unknown.isToolError && unknown.firstText.contains("Unknown or missing action"))

        // `details` without an extensionId fails.
        let noId = try await host.server.callTool("use_extension", ["action": .string("details")])
        #expect(noId.isToolError && noId.firstText.contains("requires 'extensionId'"))

        // `execute` without `confirm: true` fails (missing and false).
        let missingConfirm = try await host.server.callTool("use_extension",
                                                            ["action": .string("execute"), "extensionId": .string("x.y"),
                                                             "command": .string("c")])
        #expect(missingConfirm.isToolError && missingConfirm.firstText.contains("requires confirm: true"))
        let denied = try await host.server.callTool("use_extension",
                                                    ["action": .string("execute"), "extensionId": .string("x.y"),
                                                     "command": .string("c"), "confirm": .bool(false)])
        #expect(denied.isToolError && denied.firstText.contains("requires confirm: true"))
    }

    // MARK: - 2. Xcode round-trip

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
        // A second run over the already-sorted lines changes nothing.
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

    // MARK: - 3. Honest failures

    @Test func useExtensionHonestFailures() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "demo.txt", "b\na\n")
        let host = try await opened(sample)

        // Unknown command fails and leaves the file unmutated.
        let unknown = try await host.server.callTool("use_extension",
                                                     ["action": .string("run_xcode_command"),
                                                      "extensionId": .string("x.y"),
                                                      "command": .string("com.swiftcode.xcode.nope"),
                                                      "confirm": .bool(true), "file": .string("demo.txt")])
        #expect(unknown.isToolError && unknown.firstText.contains("Unknown Xcode command"))
        #expect(sample.read("demo.txt") == "b\na\n")

        // A workspace-escaping file fails and leaves the file unmutated.
        let escaping = try await host.server.callTool("use_extension",
                                                      ["action": .string("run_xcode_command"),
                                                       "extensionId": .string("x.y"),
                                                       "command": .string("com.swiftcode.xcode.sortLines"),
                                                       "confirm": .bool(true), "file": .string("../outside.txt")])
        #expect(escaping.isToolError && escaping.firstText.contains("outside the workspace"))
        #expect(sample.read("demo.txt") == "b\na\n")

        // A missing file fails.
        let missing = try await host.server.callTool("use_extension",
                                                     ["action": .string("run_xcode_command"),
                                                      "extensionId": .string("x.y"),
                                                      "command": .string("com.swiftcode.xcode.sortLines"),
                                                      "confirm": .bool(true), "file": .string("Nope.txt")])
        #expect(missing.isToolError && missing.firstText.contains("Cannot read 'Nope.txt'"))
    }
}
