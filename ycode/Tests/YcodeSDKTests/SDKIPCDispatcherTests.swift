import XCTest
import YcodeExtensions
@testable import YcodeSDK

/// IPC dispatcher: envelope handling, the Assist gate, command table,
/// and log routes. No live network, no real credentials — the session
/// is keyless, so any route needing a grant denies (which is itself
/// the assertion for several cases).
final class SDKIPCDispatcherTests: XCTestCase {
    private func makeDispatcher() -> SDKIPCDispatcher {
        SDKIPCDispatcher(session: SDKRuntimeSessionInfo(
            extensionID: "com.example.ext",
            packageDigest: "digest",
            projectRootPath: "/tmp/project"
        ))
    }

    private func requestFrame(method: String, payload: JSONValue, requestId: String = "req-1") -> Data {
        let envelope = SDKRequestEnvelope(requestId: requestId, method: method, payload: payload)
        return SDKIPCCodec.encodeRequest(envelope)
    }

    private func decodeResponse(_ data: Data) throws -> SDKResponseEnvelope<JSONValue> {
        try JSONDecoder().decode(SDKResponseEnvelope<JSONValue>.self, from: data)
    }

    func testMalformedFrameIsIPCError() async throws {
        let dispatcher = makeDispatcher()
        let response = try decodeResponse(await dispatcher.dispatch(Data("not json".utf8)))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "IPC_MALFORMED")
    }

    func testOversizeFrameIsResourceLimit() async throws {
        let dispatcher = makeDispatcher()
        let response = try decodeResponse(await dispatcher.dispatch(Data(repeating: 0x78, count: 1_048_577)))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "RESOURCE_LIMIT_EXCEEDED")
    }

    func testWrongProtocolVersionIsMismatch() async throws {
        let dispatcher = makeDispatcher()
        let envelope = SDKRequestEnvelope<JSONValue>(protocolVersion: 99, requestId: "req-9", method: "log.info", payload: .object(["message": .string("hi")]))
        let response = try decodeResponse(await dispatcher.dispatch(SDKIPCCodec.encodeRequest(envelope)))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "IPC_PROTOCOL_MISMATCH")
        XCTAssertEqual(response.requestId, "req-9")
    }

    func testNonRequestFrameIsMalformed() async throws {
        let dispatcher = makeDispatcher()
        let event = SDKEventEnvelope<JSONValue>(requestId: "req-1", event: "ping", payload: .null)
        let response = try decodeResponse(await dispatcher.dispatch(SDKIPCCodec.encodeEvent(event)))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "IPC_MALFORMED")
    }

    func testUnknownMethodIsInvalidArgument() async throws {
        let dispatcher = makeDispatcher()
        let response = try decodeResponse(await dispatcher.dispatch(requestFrame(method: "nope.nope", payload: .null)))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "INVALID_ARGUMENT")
    }

    func testAssistShapedMethodIsDeniedByGate() async throws {
        let dispatcher = makeDispatcher()
        // `llm.complete` contains the deny-listed `llm.` fragment.
        let response = try decodeResponse(await dispatcher.dispatch(requestFrame(method: "llm.complete", payload: .null)))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "ASSIST_DENIED")
    }

    func testAssistInvokeWithoutKeyIsDenied() async throws {
        let dispatcher = makeDispatcher()
        let response = try decodeResponse(await dispatcher.dispatch(requestFrame(
            method: "assist.invoke",
            payload: .object(["op": .string("session.list")])
        )))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "ASSIST_DENIED")
    }

    func testLogInfoSucceeds() async throws {
        let dispatcher = makeDispatcher()
        let response = try decodeResponse(await dispatcher.dispatch(requestFrame(
            method: "log.info",
            payload: .object(["message": .string("hello"), "title": .string("Test")])
        )))
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.requestId, "req-1")
    }

    func testCommandsRegisterAndUnregister() async throws {
        let dispatcher = makeDispatcher()
        // Register needs the `.uiContribute` grant — the keyless session
        // has none, so this denies. That denial is the point: the
        // dispatcher authorizes before touching the table.
        let denied = try decodeResponse(await dispatcher.dispatch(requestFrame(
            method: "commands.register",
            payload: .object(["id": .string("my-command"), "title": .string("My Command")])
        )))
        XCTAssertFalse(denied.ok)
        XCTAssertEqual(denied.error?.code, "PERMISSION_DENIED")
        // Unregister of an unknown ID is a silent no-op success.
        let unregistered = try decodeResponse(await dispatcher.dispatch(requestFrame(
            method: "commands.unregister",
            payload: .object(["id": .string("my-command")])
        )))
        XCTAssertTrue(unregistered.ok)
    }

    func testBuildWaitWithUnknownHandleIsInvalidArgument() async throws {
        let dispatcher = makeDispatcher()
        let response = try decodeResponse(await dispatcher.dispatch(requestFrame(
            method: "build.wait",
            payload: .object(["handleId": .string(UUID().uuidString)])
        )))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "INVALID_ARGUMENT")
    }

    func testOpenUnknownViewIsUnknownCapability() async throws {
        let dispatcher = makeDispatcher()
        let response = try decodeResponse(await dispatcher.dispatch(requestFrame(
            method: "ui.openView",
            payload: .object(["viewId": .string("nope.view")])
        )))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "UNKNOWN_CAPABILITY")
    }
}
