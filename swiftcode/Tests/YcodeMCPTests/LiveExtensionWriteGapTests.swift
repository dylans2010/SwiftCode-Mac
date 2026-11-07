import Foundation
import Testing
@testable import YcodeMCP

@Suite struct LiveExtensionWriteGapTests {
    private static let extID = "com.example.extension"

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
