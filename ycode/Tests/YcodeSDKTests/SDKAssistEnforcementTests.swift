import XCTest
@testable import YcodeSDK
import YcodeExtensions

// NOTE: No Swift toolchain exists in this environment, so these tests
// have NOT been compiled or run — statically verified only. On Dylan's
// Mac: run with `swift test --filter SDKAssistEnforcementTests`.
//
// Ported from Legacy
// `SwiftCode/SDK/Host/APIKeys/SDKAssistEnforcementTests.swift` (Dylan's
// own code; direct port authorised under MIT), adapted to the Ycode
// host shapes:
//   - The caller is always `SDKCallerIdentity(extensionID:packageDigest:
//     projectRootPath:apiKey:)`; sessions are created through
//     `SDKAssistService.createSession(key:extensionID:options:)`
//     (no `caller:` parameter, no provider routing). Ycode requires a
//     key for every Assist call, so Legacy's "no key" case is the
//     unentitled-key case here.
//   - `requireEntitlement(_:on:)` is sync in Ycode — no `await`.
//   - `SDKAssistGate.check` is case-insensitive on the exemption:
//     "ASSIST.INVOKE" passes, like Legacy's exemption.
//   - `manifestRequestsAssist` takes capabilities (`[SDKCapabilityID]`)
//     instead of a manifest: the forged-manifest test asserts the gate
//     reports assist from `[.assistInvoke]` and the boundary denies
//     the forged app regardless of the claim.
//   - Grant-to-revoked-key now throws `.apiKeyRevoked` (Legacy
//     behaviour), and `revokeEntitlement` returns the count of
//     sessions it closed.
//   - Ycode's `listSessions(forExtensionID:)` and `closeSession` are
//     host-only by design (no entitlement check), so they are excluded
//     from the denial matrix below — the matrix covers createSession,
//     send, sendStreaming, executeTool, and the UI opener.
//
// The denial messages are pinned as literals (verbatim from Legacy):
// the error message is the user-facing truth, and any change to it is
// a deliberate product decision.

// MARK: - SDKAssistEnforcementTests
//
// Tests for the SDK Assist entitlement boundary: unentitled callers get
// the verbatim denial at every entry point; grant -> use -> revoke
// closes live sessions and denies the next call; forged manifest
// claims never grant access.

final class SDKAssistEnforcementTests: XCTestCase {

    /// The plain denial message, verbatim (Legacy).
    private let denialMessage = "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information."

    /// The cloud-model denial message, verbatim (Legacy). PROPOSED
    /// WORDING — Dylan finalizes it; when he does, this literal and
    /// `SDKAssistGate.cloudModelDeniedUserMessage` must change together.
    private let cloudDenialMessage = "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information."

    private let testExtensionID = "com.swiftcode.sdk.test.enforcement"
    private let forgedExtensionID = "com.swiftcode.sdk.test.forged"
    private let testVersion = "1.0.0-test"

    private var createdKeyIDs: [UUID] = []
    private var createdSessionIDs: [UUID] = []

    override func tearDown() async throws {
        for sessionID in createdSessionIDs {
            try? await SDKAssistService.shared.closeSession(id: sessionID, extensionID: testExtensionID)
            try? await SDKAssistService.shared.closeSession(id: sessionID, extensionID: forgedExtensionID)
        }
        createdSessionIDs = []
        for keyID in createdKeyIDs {
            await SDKAPIKeyStore.shared.revoke(id: keyID)
        }
        createdKeyIDs = []
        try? await SDKExtensionRegistry.shared.removeInstallRecord(
            extensionID: testExtensionID, version: testVersion)
        try? await SDKExtensionRegistry.shared.removeInstallRecord(
            extensionID: forgedExtensionID, version: testVersion)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func caller(for extensionID: String, key: SDKAPIKey, digest: String = "") -> SDKCallerIdentity {
        SDKCallerIdentity(
            extensionID: extensionID,
            packageDigest: digest,
            projectRootPath: "",
            apiKey: key
        )
    }

    private func testKey(scopes: Set<SDKAPIKeyScope> = [.appsCreate]) async throws -> (SDKAPIKey, String) {
        let (key, secret) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-enforcement-\(UUID().uuidString)",
            scopes: scopes,
            isLive: false
        )
        createdKeyIDs.append(key.id)
        return (key, secret)
    }

    private func seedTestExtension() async throws {
        let manifest = SwiftCodeManifest(
            id: testExtensionID,
            name: "Test Enforcement App",
            version: testVersion,
            capabilities: [ManifestCapability(id: "assist.invoke", reason: "Test")]
        )
        let install = SDKInstalledExtension(
            id: testExtensionID,
            name: "Test Enforcement App",
            version: testVersion,
            packageDigest: String(repeating: "0", count: 64),
            installPath: FileManager.default.temporaryDirectory
                .appendingPathComponent("SDKAssistEnforcementTests-\(UUID().uuidString)"),
            installedAt: Date(),
            updatedAt: Date(),
            enabled: true,
            manifest: manifest
        )
        try await SDKExtensionRegistry.shared.recordInstall(install)
    }

    // MARK: - Entitlement grant / revoke round-trip

    func testGrantAndRevokeEntitlementRoundTrip() async throws {
        let (key, secret) = try await testKey()
        XCTAssertFalse(try await SDKAPIKeyStore.shared.verify(secret: secret).entitlements.contains(.developerAIAssist))

        // Granting twice is idempotent — no error, no duplicate.
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key)
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key)
        XCTAssertTrue(try await SDKAPIKeyStore.shared.verify(secret: secret).entitlements.contains(.developerAIAssist))

        // Revoking returns the number of sessions it closed (none live).
        let closed = try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, from: key)
        XCTAssertEqual(closed, 0)
        XCTAssertFalse(try await SDKAPIKeyStore.shared.verify(secret: secret).entitlements.contains(.developerAIAssist))

        // Revoking twice is idempotent — no error.
        _ = try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, from: key)
    }

    func testGrantEntitlementRefusesRevokedKey() async throws {
        let (key, _) = try await testKey()
        await SDKAPIKeyStore.shared.revoke(id: key.id)
        do {
            _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key)
            XCTFail("grantEntitlement must fail for a revoked key")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyRevoked)
        }
    }

    func testRequireEntitlementThrowsOnMissingEntitlement() async throws {
        let (key, _) = try await testKey()
        // Sync in Ycode — no await on the method itself, but the actor
        // hop still needs one.
        XCTAssertThrowsError(try await SDKAPIKeyStore.shared.requireEntitlement(.developerAIAssist, on: key)) { error in
            guard let sdkError = error as? SDKError else { return XCTFail("expected SDKError, got \(error)") }
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }
    }

    // MARK: - Session entry points

    func testCreateSessionDeniedWithUnentitledKey() async throws {
        let (key, _) = try await testKey()
        do {
            _ = try await SDKAssistService.shared.createSession(
                key: key, extensionID: testExtensionID, options: SDKAssistSessionOptions())
            XCTFail("createSession must deny an unentitled key")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }
    }

    func testCreateSessionSucceedsWithEntitledKey() async throws {
        let (key, _) = try await testKey()
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key)
        let session = try await SDKAssistService.shared.createSession(
            key: key, extensionID: testExtensionID, options: SDKAssistSessionOptions())
        createdSessionIDs.append(session.id)
        XCTAssertFalse(session.isClosed)

        // A session is bound to its extension: a different extension ID
        // cannot use it.
        do {
            _ = try await SDKAssistService.shared.send(
                sessionID: session.id, key: key, extensionID: forgedExtensionID, message: "hi")
            XCTFail("send must deny a different extension ID")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .permissionDenied)
        }
    }

    func testEveryServiceEntryPointDeniesUnentitledCallers() async throws {
        let (key, _) = try await testKey()

        // createSession
        XCTAssertThrowsError(try await SDKAssistService.shared.createSession(
            key: key, extensionID: testExtensionID, options: SDKAssistSessionOptions())) { error in
            guard let sdkError = error as? SDKError else { return XCTFail("expected SDKError, got \(error)") }
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }

        // send
        XCTAssertThrowsError(try await SDKAssistService.shared.send(
            sessionID: UUID(), key: key, extensionID: testExtensionID, message: "hi")) { error in
            guard let sdkError = error as? SDKError else { return XCTFail("expected SDKError, got \(error)") }
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }

        // sendStreaming: the denial arrives as a .failed event, not a
        // thrown error (the stream is the transport). `sendStreaming`
        // is sync on the actor — only `await` (actor hop), no `try`.
        let stream = await SDKAssistService.shared.sendStreaming(
            sessionID: UUID(), key: key, extensionID: testExtensionID, message: "hi")
        var seenFailure: SDKError?
        for try await event in stream {
            if case let .failed(error) = event { seenFailure = error }
        }
        guard let denial = seenFailure else { return XCTFail("stream must fail with .assistDenied") }
        XCTAssertEqual(denial.code, .assistDenied)
        XCTAssertEqual(denial.message, denialMessage)

        // executeTool
        XCTAssertThrowsError(try await SDKAssistService.shared.executeTool(
            sessionID: UUID(), key: key, extensionID: testExtensionID,
            call: SDKAssistToolCall(toolName: "fs.readFile", arguments: [:]))) { error in
            guard let sdkError = error as? SDKError else { return XCTFail("expected SDKError, got \(error)") }
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }
    }

    func testUIVariantDeniedWithoutEntitlement() async throws {
        let (key, _) = try await testKey()
        do {
            try await SDKAssistUIOpener.openAssistView(caller: caller(for: testExtensionID, key: key))
            XCTFail("openAssistView must deny an unentitled key")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }
    }

    // MARK: - Forged manifest claims

    func testForgedManifestClaimDoesNotGrantAssist() async throws {
        // A manifest that CLAIMS assist.invoke does not grant anything:
        // the gate reads the declared capabilities (the claim), but the
        // boundary still requires the entitlement on the verified key.
        XCTAssertTrue(SDKAssistGate.manifestRequestsAssist([.assistInvoke]))
        XCTAssertFalse(SDKAssistGate.manifestRequestsAssist([.workspaceRead]))

        let (key, _) = try await testKey()
        do {
            _ = try await SDKAssistService.shared.createSession(
                key: key, extensionID: forgedExtensionID, options: SDKAssistSessionOptions())
            XCTFail("a forged manifest claim must not grant Assist")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }
    }

    // MARK: - Gate: capability boundary

    func testGateExemptsExactlyAssistInvoke() async throws {
        // `check` throws on denial and returns on pass. "assist.invoke"
        // is exempt from the gate (the session's own entry point); the
        // exemption is case-insensitive, so "ASSIST.INVOKE" passes too
        // (Legacy behaviour).
        try await SDKAssistGate.check(ipcMethod: "assist.invoke", callerExtensionID: testExtensionID)
        try await SDKAssistGate.check(ipcMethod: "ASSIST.INVOKE", callerExtensionID: testExtensionID)
        // Everything else Assist-shaped is denied with the verbatim
        // message, including the historical deny-list members and
        // near-miss names.
        for method in ["assist.sendMessage", "assist.invoke.extra", "llm.sendChatRequest", "chat.send"] {
            do {
                try await SDKAssistGate.check(ipcMethod: method, callerExtensionID: testExtensionID)
                XCTFail("gate must deny \(method)")
            } catch let sdkError as SDKError {
                XCTAssertEqual(sdkError.code, .assistDenied, method)
                XCTAssertEqual(sdkError.message, denialMessage, method)
            }
        }
    }

    // MARK: - Cloud model gate

    func testCloudModelDeniedWithoutAllowsCloudEntitlement() async throws {
        let (key, _) = try await testKey()
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key)
        // The cloud gate is the broker authorizing `useSwiftCodeModel` —
        // without the allows-cloud entitlement it denies, with the
        // cloud-specific message.
        do {
            try await SDKCapabilityBroker.shared.authorize(
                .useSwiftCodeModel, for: caller(for: testExtensionID, key: key))
            XCTFail("cloud model use must deny without the allows-cloud entitlement")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .cloudModelDenied)
            XCTAssertEqual(sdkError.message, cloudDenialMessage)
        }
    }

    func testCloudModelAllowedWithEntitlement() async throws {
        let (key, _) = try await testKey()
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key)
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAllowsCloud, to: key)
        // Both entitlements present: the broker authorizes cloud use.
        try await SDKCapabilityBroker.shared.authorize(
            .useSwiftCodeModel, for: caller(for: testExtensionID, key: key))
    }

    func testAllowsCloudEntitlementAloneOpensCloudGate() async throws {
        // The cloud gate is entitlement-only: a key WITH the
        // allows-cloud entitlement authorizes cloud use even without
        // the Assist entitlement — the cloud gate never silently falls
        // back to a local model, and granting `developerAIAllowsCloud`
        // is the only way it opens.
        let (key, _) = try await testKey()
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAllowsCloud, to: key)
        try await SDKCapabilityBroker.shared.authorize(
            .useSwiftCodeModel, for: caller(for: testExtensionID, key: key))
    }

    // MARK: - Revoke closes sessions

    func testRevokeEntitlementClosesInFlightSessionsAndDeniesNextCall() async throws {
        let (key, _) = try await testKey()
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key)
        let session = try await SDKAssistService.shared.createSession(
            key: key, extensionID: testExtensionID, options: SDKAssistSessionOptions())
        createdSessionIDs.append(session.id)
        XCTAssertFalse(session.isClosed)

        // Revoking closes the live session and reports the count.
        let closed = try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, from: key)
        XCTAssertEqual(closed, 1)
        let sessions = await SDKAssistService.shared.listSessions(forExtensionID: testExtensionID)
        XCTAssertTrue(sessions.first(where: { $0.id == session.id })?.isClosed == true)

        // The next call is denied.
        do {
            _ = try await SDKAssistService.shared.send(
                sessionID: session.id, key: key, extensionID: testExtensionID, message: "hello again")
            XCTFail("send must deny after the entitlement is revoked")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }
    }

    func testRevokeKeyDeniesSubsequentVerification() async throws {
        let (key, secret) = try await testKey()
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key)
        await SDKAPIKeyStore.shared.revoke(id: key.id)
        do {
            _ = try await SDKAPIKeyStore.shared.verify(secret: secret)
            XCTFail("verify must fail for a revoked key")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyRevoked)
        }
    }
}
