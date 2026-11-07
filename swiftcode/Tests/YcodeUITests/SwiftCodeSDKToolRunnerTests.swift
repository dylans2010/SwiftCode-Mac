import XCTest
@testable import YcodeUI
import YcodeMCP
import SwiftCodeSDK
import SwiftCodeExtensions

final class SwiftCodeSDKToolRunnerTests: XCTestCase {

    private final class WriteLog: @unchecked Sendable {
        var effects: [String] = []
        var seenChanges: [MCPChange] = []
        var ask: Bool = true
    }

    private func makeServer(log: WriteLog) -> MCPServer {
        let s = MCPServer(name: "t", version: "1")
        s.tools = [
            MCPTool(name: "file_read", title: "Read", description: "Reads.",
                    inputSchema: ["type": "object", "properties": ["path": ["type": "string"], "times": ["type": "integer"]],
                                  "required": ["path"], "additionalProperties": false]) { call in
                let times = call.int("times") ?? 1
                return .text(String(repeating: "contents:\(call.string("path") ?? "")", count: times))
            },
            MCPTool(name: "file_write", title: "Write", description: "Writes.",
                    inputSchema: ["type": "object", "properties": ["path": ["type": "string"]],
                                  "required": ["path"], "additionalProperties": false],
                    annotations: MCPToolAnnotations(readOnly: false), writes: true) { call in
                let change = MCPChange(tool: "file_write", path: "/w/\(call.string("path") ?? "")",
                                       relativePath: call.string("path") ?? "", original: nil,
                                       proposed: "new", summary: "Write \(call.string("path") ?? "")")
                guard await call.approve(change) else { return .error(MCPServer.rejectedMessage) }
                log.effects.append(call.string("path") ?? "")
                return .text("written")
            },
        ]
        s.writePolicy = .review { change in
            log.seenChanges.append(change)
            return log.ask
        }
        return s
    }

    private func makeSession(extensionID: String = "com.example.test-a", allowedToolIDs: [String]) -> SDKAssistSession {
        SDKAssistSession(extensionID: extensionID, allowedToolIDs: allowedToolIDs)
    }

    private func assertThrowsCode(
        _ code: SDKErrorCode,
        _ work: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await work()
            XCTFail("Expected SDKError \(code)", file: file, line: line)
        } catch let error as SDKError {
            XCTAssertEqual(error.code, code, file: file, line: line)
        } catch {
            XCTFail("Expected SDKError, got \(error)", file: file, line: line)
        }
    }

    func testMappingIsDenyByDefault() {
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .workspaceRead).contains("file_read"))
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .workspaceRead).contains("dir_read"))
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .workspaceWrite).contains("file_write"))
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .sourceControlWrite).contains("git_commit"))
        XCTAssertFalse(SDKAssistToolMapping.mcpTools(for: .sourceControlWrite).contains("git_push"))
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .buildExecute).contains("project_build"))
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .terminalSandbox).contains("use_terminal"))
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .networkRequest).contains("fetch_url"))
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .assistInvoke).isEmpty)
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .uiContribute).isEmpty)
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .credentialsUse).isEmpty)
        XCTAssertTrue(SDKAssistToolMapping.mcpTools(for: .simulatorView).isEmpty)
    }

    func testScalarArgumentConversion() {
        XCTAssertEqual(SwiftCodeSDKToolRunner.mcpArgument("true"), .bool(true))
        XCTAssertEqual(SwiftCodeSDKToolRunner.mcpArgument("false"), .bool(false))
        XCTAssertEqual(SwiftCodeSDKToolRunner.mcpArgument("12"), .int(12))
        XCTAssertEqual(SwiftCodeSDKToolRunner.mcpArgument("1.5"), .double(1.5))
        XCTAssertEqual(SwiftCodeSDKToolRunner.mcpArgument("README.md"), .string("README.md"))
        XCTAssertEqual(SwiftCodeSDKToolRunner.mcpArgument(""), .string(""))
    }

    func testGrantedReadRuns() async throws {
        let log = WriteLog()
        let server = makeServer(log: log)
        let runner = SwiftCodeSDKToolRunner(serverProvider: { server })
        let result = try await runner.runTool(
            session: makeSession(allowedToolIDs: ["workspace.read"]),
            call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read", "path": "README.md", "times": "2"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "contents:README.mdcontents:README.md")
        XCTAssertTrue(log.seenChanges.isEmpty)
    }

    func testAliasResolvesToCanonicalTool() async throws {
        let log = WriteLog()
        let server = makeServer(log: log)
        let runner = SwiftCodeSDKToolRunner(serverProvider: { server })
        let result = try await runner.runTool(
            session: makeSession(allowedToolIDs: ["workspace.read"]),
            call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "read_file", "path": "README.md"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "contents:README.md")
    }

    func testUngrantedWriteRefusedBeforeApproval() async {
        let log = WriteLog()
        let server = makeServer(log: log)
        let runner = SwiftCodeSDKToolRunner(serverProvider: { server })
        await assertThrowsCode(.permissionDenied) {
            try await runner.runTool(
                session: self.makeSession(allowedToolIDs: ["workspace.read"]),
                call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_write", "path": "x.txt"]))
        }
        XCTAssertTrue(log.seenChanges.isEmpty)
        XCTAssertTrue(log.effects.isEmpty)
    }

    func testUnmappedCapabilityRefused() async {
        let log = WriteLog()
        let server = makeServer(log: log)
        let runner = SwiftCodeSDKToolRunner(serverProvider: { server })
        await assertThrowsCode(.permissionDenied) {
            try await runner.runTool(
                session: self.makeSession(allowedToolIDs: ["assist.invoke"]),
                call: SDKAssistToolCall(toolName: "assist.invoke", arguments: ["tool": "file_read", "path": "README.md"]))
        }
        XCTAssertTrue(log.seenChanges.isEmpty)
    }

    func testMissingToolArgumentIsInvalid() async {
        let log = WriteLog()
        let server = makeServer(log: log)
        let runner = SwiftCodeSDKToolRunner(serverProvider: { server })
        await assertThrowsCode(.invalidArgument) {
            try await runner.runTool(
                session: self.makeSession(allowedToolIDs: ["workspace.read"]),
                call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["path": "README.md"]))
        }
    }

    func testUnknownToolNameOnServerIsInvalid() async {
        let log = WriteLog()
        let server = makeServer(log: log)
        let runner = SwiftCodeSDKToolRunner(serverProvider: { server })
        await assertThrowsCode(.invalidArgument) {
            try await runner.runTool(
                session: self.makeSession(allowedToolIDs: ["source-control.read"]),
                call: SDKAssistToolCall(toolName: "source-control.read", arguments: ["tool": "git_status"]))
        }
    }

    func testGrantedWriteAsksUserAndEffectFollowsAnswer() async throws {
        let log = WriteLog()
        let server = makeServer(log: log)
        let runner = SwiftCodeSDKToolRunner(serverProvider: { server })
        let session = makeSession(allowedToolIDs: ["workspace.write"])
        let call = SDKAssistToolCall(toolName: "workspace.write", arguments: ["tool": "file_write", "path": "x.txt"])

        log.ask = false
        let rejected = try await runner.runTool(session: session, call: call)
        XCTAssertFalse(rejected.succeeded)
        XCTAssertEqual(rejected.output, MCPServer.rejectedMessage)
        XCTAssertTrue(log.effects.isEmpty)
        XCTAssertEqual(log.seenChanges.count, 1)
        XCTAssertEqual(log.seenChanges.first?.caller?.extensionID, "com.example.test-a")
        XCTAssertEqual(log.seenChanges.first?.tool, "file_write")

        log.ask = true
        let approved = try await runner.runTool(session: session, call: call)
        XCTAssertTrue(approved.succeeded)
        XCTAssertEqual(approved.output, "written")
        XCTAssertEqual(log.effects, ["x.txt"])
        XCTAssertEqual(log.seenChanges.count, 2)
    }

    func testCallerIsolation() async {
        let log = WriteLog()
        let server = makeServer(log: log)
        let runner = SwiftCodeSDKToolRunner(serverProvider: { server })
        await assertThrowsCode(.permissionDenied) {
            try await runner.runTool(
                session: self.makeSession(extensionID: "com.example.test-b", allowedToolIDs: ["workspace.write"]),
                call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read", "path": "README.md"]))
        }
        XCTAssertTrue(log.effects.isEmpty)
    }

    func testNoServerIsServiceUnavailable() async {
        let runner = SwiftCodeSDKToolRunner(serverProvider: { nil })
        await assertThrowsCode(.serviceUnavailable) {
            try await runner.runTool(
                session: self.makeSession(allowedToolIDs: ["workspace.read"]),
                call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read", "path": "README.md"]))
        }
    }
}
