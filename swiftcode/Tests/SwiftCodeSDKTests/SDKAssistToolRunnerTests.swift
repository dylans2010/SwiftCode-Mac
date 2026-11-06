import XCTest
@testable import SwiftCodeSDK

// NOTE: No Swift toolchain exists in this environment, so these tests
// have NOT been compiled or run — statically verified only. On Dylan's
// Mac: run with `swift test --filter SDKAssistToolRunnerTests`.
//
// Wave 17, Slice B: tests for the grant-enforcing tool runner seam
// (`SDKAssistHostBackend.executeTool` + `SDKAssistToolRunning`).
// The runner is a fake: the real MCP-backed runner is covered in
// `SwiftCodeUITests/SwiftCodeSDKToolRunnerTests` and the approval gate in
// `SwiftCodeMCPTests/MCPCallerIdentityTests`. What is proven here is the
// backend's enforcement order — closed session, snapshot ceiling,
// live-grant revocation, caller isolation — and that a refusal
// happens before the runner is ever called (no approval UI, no tool
// run, no fabricated result).

final class SDKAssistToolRunnerTests: XCTestCase {

    // MARK: - Fakes

    /// A recording runner: answers the live-grant query from `live`
    /// (nil = the host cannot answer live) and plays back `result`
    /// (or throws `runError`).
    private final class FakeToolRunner: SDKAssistToolRunning, @unchecked Sendable {
        var live: Set<String>?
        var result = SDKAssistToolResult(toolName: "workspace.read", succeeded: true, output: "fake-output")
        var runError: (any Error)?
        private(set) var runCalls: [(session: SDKAssistSession, call: SDKAssistToolCall)] = []

        func liveAllowedToolIDs(for extensionID: String) async -> Set<String>? { live }

        func runTool(session: SDKAssistSession, call: SDKAssistToolCall) async throws -> SDKAssistToolResult {
            runCalls.append((session, call))
            if let runError { throw runError }
            return result
        }
    }

    // MARK: - Helpers

    private func makeSession(
        extensionID: String = "com.example.test-a",
        allowedToolIDs: [String] = ["workspace.read"],
        isClosed: Bool = false
    ) -> SDKAssistSession {
        SDKAssistSession(extensionID: extensionID, isClosed: isClosed, allowedToolIDs: allowedToolIDs)
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

    // MARK: - Granted runs, ungranted refused pre-runner

    func testGrantedToolRuns() async throws {
        let runner = FakeToolRunner()
        runner.live = ["workspace.read"]
        let backend = SDKAssistHostBackend()
        await backend.install(toolRunner: runner)
        let result = try await backend.executeTool(
            session: makeSession(),
            call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "fake-output")
        XCTAssertEqual(runner.runCalls.count, 1)
        XCTAssertEqual(runner.runCalls[0].session.extensionID, "com.example.test-a")
    }

    func testUngrantedToolRefusedBeforeRunner() async {
        let runner = FakeToolRunner()
        runner.live = ["workspace.read", "workspace.write"]
        let backend = SDKAssistHostBackend()
        await backend.install(toolRunner: runner)
        // "workspace.write" is live-granted but NOT in the session
        // snapshot: the snapshot is the ceiling, and the refusal
        // happens before the runner is called (no approval UI).
        await assertThrowsCode(.permissionDenied) {
            try await backend.executeTool(
                session: self.makeSession(allowedToolIDs: ["workspace.read"]),
                call: SDKAssistToolCall(toolName: "workspace.write", arguments: ["tool": "file_write"]))
        }
        XCTAssertTrue(runner.runCalls.isEmpty)
    }

    func testUnknownToolRefusedBeforeRunner() async {
        let runner = FakeToolRunner()
        let backend = SDKAssistHostBackend()
        await backend.install(toolRunner: runner)
        await assertThrowsCode(.permissionDenied) {
            try await backend.executeTool(
                session: self.makeSession(),
                call: SDKAssistToolCall(toolName: "not.a.tool", arguments: [:]))
        }
        XCTAssertTrue(runner.runCalls.isEmpty)
    }

    // MARK: - Revocation closes the path

    func testRevokedLiveGrantClosesPath() async {
        let runner = FakeToolRunner()
        runner.live = [] // every grant revoked after the session was created
        let backend = SDKAssistHostBackend()
        await backend.install(toolRunner: runner)
        await assertThrowsCode(.permissionDenied) {
            try await backend.executeTool(
                session: self.makeSession(),
                call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read"]))
        }
        XCTAssertTrue(runner.runCalls.isEmpty)
    }

    func testLiveGrantStillPresentRuns() async throws {
        let runner = FakeToolRunner()
        runner.live = ["workspace.read"]
        let backend = SDKAssistHostBackend()
        await backend.install(toolRunner: runner)
        let result = try await backend.executeTool(
            session: makeSession(),
            call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(runner.runCalls.count, 1)
    }

    func testNoLiveAnswerFallsBackToSnapshot() async throws {
        let runner = FakeToolRunner()
        runner.live = nil // host cannot answer live: snapshot alone applies
        let backend = SDKAssistHostBackend()
        await backend.install(toolRunner: runner)
        let result = try await backend.executeTool(
            session: makeSession(),
            call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(runner.runCalls.count, 1)
    }

    // MARK: - Closed session, no runner, isolation, error mapping

    func testClosedSessionRefusedBeforeRunner() async {
        let runner = FakeToolRunner()
        let backend = SDKAssistHostBackend()
        await backend.install(toolRunner: runner)
        await assertThrowsCode(.invalidArgument) {
            try await backend.executeTool(
                session: self.makeSession(isClosed: true),
                call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read"]))
        }
        XCTAssertTrue(runner.runCalls.isEmpty)
    }

    func testNoRunnerIsServiceUnavailable() async {
        let backend = SDKAssistHostBackend()
        await assertThrowsCode(.serviceUnavailable) {
            try await backend.executeTool(
                session: self.makeSession(),
                call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read"]))
        }
    }

    func testCallerIsolationBySnapshot() async throws {
        let runner = FakeToolRunner()
        runner.live = ["workspace.read", "workspace.write"]
        let backend = SDKAssistHostBackend()
        await backend.install(toolRunner: runner)
        // Caller A may read; caller B may only write. A read call on
        // B's session is refused even though A could run it: the
        // session — and its snapshot — belongs to exactly one
        // extension, so B cannot run with A's grants.
        let readCall = SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read"])
        let aResult = try await backend.executeTool(
            session: makeSession(extensionID: "com.example.test-a", allowedToolIDs: ["workspace.read"]),
            call: readCall)
        XCTAssertTrue(aResult.succeeded)
        await assertThrowsCode(.permissionDenied) {
            try await backend.executeTool(
                session: self.makeSession(extensionID: "com.example.test-b", allowedToolIDs: ["workspace.write"]),
                call: readCall)
        }
        XCTAssertEqual(runner.runCalls.count, 1)
        XCTAssertEqual(runner.runCalls[0].session.extensionID, "com.example.test-a")
    }

    func testRunnerFailureIsServiceUnavailableWithoutLeak() async {
        struct MarkerError: Error {}
        let runner = FakeToolRunner()
        runner.live = ["workspace.read"]
        runner.runError = MarkerError()
        let backend = SDKAssistHostBackend()
        await backend.install(toolRunner: runner)
        do {
            _ = try await backend.executeTool(
                session: makeSession(),
                call: SDKAssistToolCall(toolName: "workspace.read", arguments: ["tool": "file_read"]))
            XCTFail("Expected .serviceUnavailable")
        } catch let error as SDKError {
            XCTAssertEqual(error.code, .serviceUnavailable)
            XCTAssertFalse(error.message.contains("MarkerError"))
            XCTAssertFalse(error.suggestion?.contains("MarkerError") ?? false)
        } catch {
            XCTFail("Expected SDKError, got \(error)")
        }
    }
}
