import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

// NOTE: No Swift toolchain exists in this environment, so these tests
// have NOT been compiled or run — statically verified only. On Dylan's
// Mac: run with `swift test --filter MCPCallerIdentityTests`.
//
// Wave 17, Slice B: tests for extension caller identity in the MCP
// approval gate (`MCPToolCaller`, `MCPServer.run`). The gate must
// refuse an ungranted tool BEFORE any approval UI appears, and a
// granted write must still ask the user exactly as a host write
// would — with the change attributed to the extension that asked
// for it. Host calls (`caller == nil`) are unchanged.

@Suite struct MCPCallerIdentityTests {
    private static let extID = "com.example.extension"

    /// A server with a read tool and a write tool, like
    /// `MCPServerTests.server()`.
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

    private static func resultText(_ result: MCPToolResult) -> String {
        result.content.compactMap { $0["text"]?.string }.joined(separator: "\n")
    }

    private static func caller(allowed: Set<String>) -> MCPToolCaller {
        MCPToolCaller(extensionID: extID, allowedToolIDs: allowed)
    }

    @Test func ungrantedWriteRefusedBeforeApproval() async {
        final class Seen: @unchecked Sendable { var count = 0 }
        let seen = Seen()
        let s = Self.server(policy: .review { _ in seen.count += 1; return true })
        let tool = s.tools.first(where: { $0.name == "write" })!
        // The caller may only echo: the write is refused before the
        // review closure is ever asked.
        let result = await s.run(tool, MCPToolCall(name: "write", arguments: [:], caller: Self.caller(allowed: ["echo"])))
        #expect(result.isError)
        #expect(Self.resultText(result).contains("not approved for extension"))
        #expect(Self.resultText(result).contains(Self.extID))
        #expect(seen.count == 0)
    }

    @Test func ungrantedReadRefused() async {
        let s = Self.server(policy: .allow)
        let tool = s.tools.first(where: { $0.name == "echo" })!
        let result = await s.run(tool, MCPToolCall(
            name: "echo", arguments: ["text": .string("hi")], caller: Self.caller(allowed: [])))
        #expect(result.isError)
        #expect(Self.resultText(result).contains("not approved for extension"))
    }

    @Test func grantedReadRunsWithoutApproval() async {
        final class Seen: @unchecked Sendable { var count = 0 }
        let seen = Seen()
        let s = Self.server(policy: .review { _ in seen.count += 1; return true })
        let tool = s.tools.first(where: { $0.name == "echo" })!
        let result = await s.run(tool, MCPToolCall(
            name: "echo", arguments: ["text": .string("hi")], caller: Self.caller(allowed: ["echo"])))
        #expect(!result.isError)
        #expect(Self.resultText(result) == "echo:hi")
        #expect(seen.count == 0)
    }

    @Test func grantedWriteAsksUserWithCallerIdentity() async {
        final class Seen: @unchecked Sendable { var changes: [MCPChange] = [] }
        let seen = Seen()
        let s = Self.server(policy: .review { change in seen.changes.append(change); return true })
        let tool = s.tools.first(where: { $0.name == "write" })!
        let result = await s.run(tool, MCPToolCall(name: "write", arguments: [:], caller: Self.caller(allowed: ["write"])))
        #expect(!result.isError)
        #expect(Self.resultText(result) == "written")
        #expect(seen.changes.count == 1)
        #expect(seen.changes.first?.caller?.extensionID == Self.extID)
        #expect(seen.changes.first?.caller?.allowedToolIDs == ["write"])
        #expect(seen.changes.first?.summary == "Create a")
    }

    @Test func grantedWriteRejectedByUser() async {
        final class Seen: @unchecked Sendable { var changes: [MCPChange] = [] }
        let seen = Seen()
        let s = Self.server(policy: .review { change in seen.changes.append(change); return false })
        let tool = s.tools.first(where: { $0.name == "write" })!
        let result = await s.run(tool, MCPToolCall(name: "write", arguments: [:], caller: Self.caller(allowed: ["write"])))
        #expect(result.isError)
        #expect(Self.resultText(result) == MCPServer.rejectedMessage)
        #expect(seen.changes.count == 1)
        #expect(seen.changes.first?.caller?.extensionID == Self.extID)
    }

    @Test func hostCallerUnchanged() async {
        // No caller: the review closure sees a change with no
        // extension attribution, exactly as before.
        final class Seen: @unchecked Sendable { var changes: [MCPChange] = [] }
        let seen = Seen()
        let s = Self.server(policy: .review { change in seen.changes.append(change); return true })
        let tool = s.tools.first(where: { $0.name == "write" })!
        let result = await s.run(tool, MCPToolCall(name: "write", arguments: [:]))
        #expect(!result.isError)
        #expect(Self.resultText(result) == "written")
        #expect(seen.changes.count == 1)
        #expect(seen.changes.first?.caller == nil)

        // And under `.allow` a host write still needs no approval.
        let allowed = await Self.server(policy: .allow).run(tool, MCPToolCall(name: "write", arguments: [:]))
        #expect(!allowed.isError)
        #expect(Self.resultText(allowed) == "written")
    }
}
