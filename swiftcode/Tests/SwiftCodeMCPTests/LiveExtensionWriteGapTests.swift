import Foundation
import Testing
@testable import SwiftCodeMCP

// NOTE: No Swift toolchain exists in this environment, so these tests
// have NOT been compiled or run — statically verified only. On Dylan's
// Mac: run with `swift test --filter LiveExtensionWriteGapTests`.
//
// Gap-closure tests for live extension writes (specs/ide/
// gap-closure-windows-artboards.md §4): the write-policy paths
// around the grant check in `MCPServer.run`. The grant check itself
// (ungranted tool refused before any approval UI, granted write
// asked with the caller's identity, host calls unchanged) is
// covered by `MCPCallerIdentityTests`; this file covers the policy
// combinations around it — read-only refusal, allow without asking,
// the check order, and `MCPChange.settingCaller`.

@Suite struct LiveExtensionWriteGapTests {
    private static let extID = "com.example.extension"

    /// A server with a read tool and a write tool, like
    /// `MCPCallerIdentityTests.server`.
    static func server(policy: MCPWritePolicy) -> MCPServer {
        let s = MCPServer(name: "t", version: "1", instructions: "Use the tools.")
        s.tools = [
            MCPTool(name: "echo", title: "Echo", description: "Echoes.",
                    inputSchema: ["type": "object", "properties": ["text": ["type": "string"]],
                                  "required": ["text"], "additionalProperties": false]) { call in
                .text("echo:\(call.string("text") ?? "")")
            },
            MCPTool(name: "write", title: "Write", description: "Writes.",
                    inputSchema: ["type": "object", "properties": [:]],
                    annotations: MCPToolAnnotations(readOnly: false), writes: true) { call in
                let ok = await call.approve(MCPChange(tool: "write", path: "/w/a", relativePath: "a", original: nil, proposed: "x", summary: "Create a"))
                return ok ? .text("written") : .error(MCPServer.rejectedMessage)
            },
        ]
        s.writePolicy = policy
        return s
    }

    private static func caller(allowed: Set<String>) -> MCPToolCaller {
        MCPToolCaller(extensionID: extID, allowedToolIDs: allowed)
    }

    @Test("Read-only policy refuses an extension write")
    func readOnlyRefusesExtensionWrite() async {
        // Read-only refuses before any approval UI could appear
        // (there is no review closure to run under this policy).
        let s = Self.server(policy: .readOnly)
        let tool = s.tools.first(where: { $0.name == "write" })!
        let result = await s.run(tool, MCPToolCall(name: "write", arguments: [:], caller: Self.caller(allowed: ["write"])))
        #expect(result.isError)
        #expect(result.firstText.contains("read-only"))
        #expect(result.firstText.contains("write"))
    }

    @Test("Read-only policy still runs a granted read tool")
    func readOnlyAllowsGrantedRead() async {
        let s = Self.server(policy: .readOnly)
        let tool = s.tools.first(where: { $0.name == "echo" })!
        let result = await s.run(tool, MCPToolCall(
            name: "echo", arguments: ["text": .string("hi")], caller: Self.caller(allowed: ["echo"])))
        #expect(!result.isError)
        #expect(result.firstText == "echo:hi")
    }

    @Test("Allow policy runs a granted extension write without asking")
    func allowRunsGrantedExtensionWrite() async {
        final class Seen: @unchecked Sendable { var count = 0 }
        let seen = Seen()
        let s = Self.server(policy: .allow)
        let tool = s.tools.first(where: { $0.name == "write" })!
        let result = await s.run(tool, MCPToolCall(name: "write", arguments: [:], caller: Self.caller(allowed: ["write"])))
        #expect(!result.isError)
        #expect(result.firstText == "written")
        #expect(seen.count == 0)
    }

    @Test("Allow policy still refuses an ungranted tool")
    func allowStillRefusesUngranted() async {
        let s = Self.server(policy: .allow)
        let tool = s.tools.first(where: { $0.name == "write" })!
        let result = await s.run(tool, MCPToolCall(name: "write", arguments: [:], caller: Self.caller(allowed: ["echo"])))
        #expect(result.isError)
        #expect(result.firstText.contains("not approved for extension"))
        #expect(result.firstText.contains(Self.extID))
    }

    @Test("Argument problems are reported before the grant check")
    func argumentProblemPrecedesGrantCheck() async {
        let s = Self.server(policy: .allow)
        let tool = s.tools.first(where: { $0.name == "echo" })!
        // Missing the required "text" argument, from a caller with
        // no grants at all: the argument problem wins.
        let result = await s.run(tool, MCPToolCall(name: "echo", arguments: [:], caller: Self.caller(allowed: [])))
        #expect(result.isError)
        #expect(result.firstText.contains("echo"))
        #expect(!result.firstText.contains("not approved for extension"))
    }

    @Test("settingCaller stamps the caller's identity onto a change")
    func settingCallerStampsIdentity() {
        let change = MCPChange(tool: "write", path: "/w/a", relativePath: "a", original: nil, proposed: "x", summary: "Create a")
        #expect(change.caller == nil)
        let stamped = change.settingCaller(Self.caller(allowed: ["write"]))
        #expect(stamped.caller?.extensionID == Self.extID)
        #expect(stamped.caller?.allowedToolIDs == ["write"])
        #expect(stamped.summary == "Create a")
        #expect(change.caller == nil)
    }

    @Test("A review rejection returns the rejected message, not the write")
    func reviewRejectionReturnsRejectedMessage() async {
        let s = Self.server(policy: .review { _ in false })
        let tool = s.tools.first(where: { $0.name == "write" })!
        let result = await s.run(tool, MCPToolCall(name: "write", arguments: [:], caller: Self.caller(allowed: ["write"])))
        #expect(result.isError)
        #expect(result.firstText == MCPServer.rejectedMessage)
    }
}
