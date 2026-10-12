// NOTE (2026-10-12): No Swift toolchain exists in this environment, so
// these tests have NOT been compiled or run — statically verified only.
// They also require a real XCTest test target: this project currently
// has none (the app target is the only target), so this file is
// registered in the xcodeproj as a source reference only and is NOT in
// any target's Sources build phase — `import XCTest` would not compile
// in the app target. On Dylan's Mac: create an XCTest target for the
// project, add this file to it, then run the suite with xcodebuild.
//
// The revocation test performs REAL Keychain I/O (createKey, verify,
// revokeEntitlement). Test keys are labeled "SDKTest-enforce-…" and
// revoked in async tearDown.

import XCTest
@testable import SwiftCode

// MARK: - SDKAssistEnforcementTests
//
// Tests for Part-B enforcement (Docs/Intro-to-SDK.md §13–§14, task B6):
//   - entitlement grant / revoke / require on `SDKAPIKeyStore`
//   - `SDKAssistService` boundary: entitled vs not, wrong-key denial,
//     the verbatim §13 message on EVERY denied path, forged manifest
//     claims ignored (manifest is descriptive metadata only)
//   - `SDKAssistGate.check`: the `assist.invoke` exemption is exact —
//     lookalikes are still denied
//   - cloud gate: `use.SwiftCodeModel` denied without
//     `com.SwiftCode.developer-AI-Allows-Cloud`, allowed with it
//   - revocation mid-session: entitlement revoked → in-flight session
//     closed, subsequent calls denied at the boundary

final class SDKAssistEnforcementTests: XCTestCase {

    /// The verbatim §13 user error — pinned as a literal here (not via
    /// the shared constant) so the test independently verifies the exact
    /// user-facing text. Do not reword.
    private let verbatimAssistDenial =
        "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information."

    /// The proposed §13 cloud-model denial. PROPOSED WORDING — Dylan
    /// finalizes it; when he does, this literal and
    /// `SDKAssistGate.cloudModelDeniedUserMessage` must change together.
    private let verbatimCloudDenial =
        "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information."

    private var createdKeyIDs: [UUID] = []

    override func tearDown() async throws {
        for keyID in createdKeyIDs {
            try? await SDKAPIKeyStore.shared.revoke(id: keyID)
        }
        createdKeyIDs = []
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func caller(
        extensionID: String = "com.swiftcode.sdk.test.enforce",
        apiKey: SDKAPIKey? = nil
    ) -> SDKCallerIdentity {
        SDKCallerIdentity(
            extensionID: extensionID,
            packageDigest: String(repeating: "a", count: 64),
            projectRootPath: "/tmp",
            apiKey: apiKey
        )
    }

    private func testKey(entitlements: Set<SDKEntitlement> = []) -> SDKAPIKey {
        SDKAPIKey(
            keyPrefix: SDKAPIKeyCodec.testPrefix,
            label: "SDKTest-enforce",
            scopes: [.appsCreate],
            entitlements: entitlements
        )
    }

    private func assertAssistDenied<T>(
        _ operation: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("expected an .assistDenied denial", file: file, line: line)
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .assistDenied, file: file, line: line)
            XCTAssertEqual(sdkError.message, verbatimAssistDenial, file: file, line: line)
        } catch {
            XCTFail("expected SDKError, got \(type(of: error))", file: file, line: line)
        }
    }

    // MARK: - Entitlement grant / revoke / require

    func testGrantAndRevokeEntitlementRoundTrip() async throws {
        let (key, secret) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-enforce-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key.id)

        try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key.id)
        var verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertTrue(verified.entitlements.contains(.developerAIAssist))

        // Granting twice is idempotent — no duplicate, no error.
        try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key.id)
        verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertEqual(verified.entitlements.filter { $0 == .developerAIAssist }.count, 1)

        try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, from: key.id)
        verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertFalse(verified.entitlements.contains(.developerAIAssist))

        // Revoking again is idempotent.
        try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, from: key.id)
    }

    func testGrantEntitlementRefusesRevokedKey() async throws {
        let (key, _) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-enforce-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key.id)
        try await SDKAPIKeyStore.shared.revoke(id: key.id)

        do {
            try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key.id)
            XCTFail("granting to a revoked key must fail")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyRevoked)
        }
    }

    func testRequireEntitlementThrowsOnMissingEntitlement() async throws {
        let key = testKey() // no entitlements
        do {
            try await SDKAPIKeyStore.shared.requireEntitlement(.developerAIAssist, for: key)
            XCTFail("requireEntitlement must throw when the entitlement is absent")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyScopeInsufficient)
        }
        // And passes when present.
        let entitled = testKey(entitlements: [.developerAIAssist])
        try await SDKAPIKeyStore.shared.requireEntitlement(.developerAIAssist, for: entitled)
    }

    // MARK: - Service boundary: entitled vs not, wrong key, verbatim message

    func testCreateSessionDeniedWithoutKey() async {
        await assertAssistDenied {
            try await SDKAssistService.shared.createSession(caller: caller())
        }
    }

    func testCreateSessionDeniedWithUnentitledKey() async {
        await assertAssistDenied {
            try await SDKAssistService.shared.createSession(caller: caller(apiKey: testKey()))
        }
    }

    func testCreateSessionSucceedsWithEntitledKey() async throws {
        let key = testKey(entitlements: [.developerAIAssist])
        let session = try await SDKAssistService.shared.createSession(
            caller: caller(apiKey: key)
        )
        XCTAssertEqual(session.extensionID, "com.swiftcode.sdk.test.enforce")
        XCTAssertFalse(session.isClosed)
        // The wrong-key rule: the SAME session is not usable from another
        // extension, even with an entitled key.
        let otherKey = testKey(entitlements: [.developerAIAssist])
        let other = caller(extensionID: "com.swiftcode.sdk.test.other", apiKey: otherKey)
        do {
            _ = try await SDKAssistService.shared.send(
                sessionID: session.id, message: "hi", caller: other
            )
            XCTFail("cross-extension session use must be denied")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .permissionDenied)
        }
        // Clean up the session we created (entitlement still required).
        try await SDKAssistService.shared.closeSession(
            id: session.id, caller: caller(apiKey: key)
        )
    }

    func testEveryServiceEntryPointDeniesUnentitledCallers() async throws {
        let unentitled = caller(apiKey: testKey())
        await assertAssistDenied {
            try await SDKAssistService.shared.createSession(caller: unentitled)
        }
        await assertAssistDenied {
            try await SDKAssistService.shared.listSessions(caller: unentitled)
        }
        await assertAssistDenied {
            try await SDKAssistService.shared.send(sessionID: UUID(), message: "hi", caller: unentitled)
        }
        await assertAssistDenied {
            try await SDKAssistService.shared.sendStreaming(sessionID: UUID(), message: "hi", caller: unentitled)
        }
        await assertAssistDenied {
            try await SDKAssistService.shared.executeTool(
                sessionID: UUID(),
                toolCall: SDKAssistToolCall(toolName: "x"),
                caller: unentitled
            )
        }
        await assertAssistDenied {
            try await SDKAssistService.shared.closeSession(id: UUID(), caller: unentitled)
        }
    }

    func testUIVariantDeniedWithoutEntitlement() async {
        // SDKAssistUIOpener is the assistSDK.UI boundary: unentitled
        // callers get the verbatim §13 message (single source of truth —
        // the same string the headless variant emits).
        do {
            try await SDKAssistUIOpener.openAssistView(caller: caller(apiKey: testKey()))
            XCTFail("expected an .assistDenied denial")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, verbatimAssistDenial)
        } catch {
            XCTFail("expected SDKError, got \(type(of: error))")
        }
    }

    // MARK: - Forged manifest claims are ignored

    func testForgedManifestClaimDoesNotGrantAssist() async {
        // A manifest declaring `"assist": {"requested": true}` is
        // DESCRIPTIVE metadata only: the gate reports it, the boundary
        // never reads it.
        let manifest = SDKManifest(
            manifestVersion: 1,
            id: "com.swiftcode.sdk.test.forged",
            name: "Forged",
            version: "1.0.0",
            runtime: SDKManifestRuntime(
                language: "typescript",
                entrypoint: "dist/index.js",
                minimumSwiftCodeVersion: "1.0.0"
            ),
            sdk: SDKManifestSDKRef(
                name: "@swiftcode/sdk",
                versionRange: "^1.0.0",
                protocolVersion: 1
            ),
            capabilities: [],
            assist: SDKManifestAssist(requested: true)
        )
        XCTAssertTrue(SDKAssistGate.manifestRequestsAssist(manifest))

        // …and yet the service boundary denies: only the key record counts.
        let forged = caller(extensionID: "com.swiftcode.sdk.test.forged")
        await assertAssistDenied {
            try await SDKAssistService.shared.createSession(caller: forged)
        }
    }

    // MARK: - IPC gate: the assist.invoke exemption is exact

    func testGateExemptsExactlyAssistInvoke() async throws {
        // The entitled route passes the gate; everything else containing a
        // denied substring is still denied — including near-misses.
        try await SDKAssistGate.check(ipcMethod: "assist.invoke", callerExtensionID: "x")
        try await SDKAssistGate.check(ipcMethod: "ASSIST.INVOKE", callerExtensionID: "x")

        for method in ["assist.sendMessage", "assist.invoke.extra", "llm.sendChatRequest", "chat.send"] {
            do {
                try await SDKAssistGate.check(ipcMethod: method, callerExtensionID: "x")
                XCTFail("gate must deny \(method)")
            } catch let sdkError as SDKError {
                XCTAssertEqual(sdkError.code, .assistDenied)
                XCTAssertEqual(sdkError.message, verbatimAssistDenial)
            }
        }
    }

    // MARK: - Cloud gate

    func testCloudModelDeniedWithoutAllowsCloudEntitlement() async {
        let key = testKey() // entitled for nothing
        do {
            try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: caller(apiKey: key))
            XCTFail("expected a .cloudModelDenied denial")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .cloudModelDenied)
            XCTAssertEqual(sdkError.message, verbatimCloudDenial)
        } catch {
            XCTFail("expected SDKError, got \(type(of: error))")
        }
    }

    func testCloudModelAllowedWithAllowsCloudEntitlement() async throws {
        // The entitlement is the authorization: no grant lookup happens,
        // and the call returns authorized. Quota is still enforced
        // downstream by SDKCloudModelAdapter on every call.
        let key = testKey(entitlements: [.developerAIAllowsCloud])
        try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: caller(apiKey: key))
    }

    func testCloudModelKeylessKeepsGrantPath() async {
        // Keyless sessions keep the pre-Part-B grant path: with no grant
        // for the fake extension ID this is .permissionDenied (not the
        // entitlement denial).
        do {
            try await SDKCapabilityBroker.authorize(
                .useSwiftCodeModel,
                for: caller(extensionID: "com.swiftcode.sdk.test.no-grants-\(UUID().uuidString)")
            )
            XCTFail("expected .permissionDenied for a grantless keyless caller")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .permissionDenied)
        } catch {
            XCTFail("expected SDKError, got \(type(of: error))")
        }
    }

    // MARK: - Revocation mid-session

    func testRevokeEntitlementClosesInFlightSessionsAndDeniesNextCall() async throws {
        let (key, secret) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-enforce-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key.id)
        try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key.id)

        // The production flow: the dispatcher re-verifies the secret on
        // EVERY request, so the caller below carries fresh metadata.
        let verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        let extID = "com.swiftcode.sdk.test.revoke-\(UUID().uuidString)"
        let session = try await SDKAssistService.shared.createSession(
            caller: caller(extensionID: extID, apiKey: verified)
        )

        // Revoke: the store hook closes the key's in-flight sessions.
        try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, from: key.id)
        let closedByHook = await SDKAssistService.shared.closeSessions(forKeyID: key.id)
        XCTAssertEqual(closedByHook, 0, "revokeEntitlement must already have closed the session")

        // The next call re-verifies (fresh metadata, no entitlement) and
        // is denied at the boundary with the verbatim message.
        let refreshed = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertFalse(refreshed.entitlements.contains(.developerAIAssist))
        let refreshedCaller = caller(extensionID: extID, apiKey: refreshed)
        await assertAssistDenied {
            try await SDKAssistService.shared.send(
                sessionID: session.id, message: "hi", caller: refreshedCaller
            )
        }
    }

    func testRevokeKeyDeniesSubsequentVerification() async throws {
        let (key, secret) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-enforce-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key.id)
        try await SDKAPIKeyStore.shared.revoke(id: key.id)
        do {
            _ = try await SDKAPIKeyStore.shared.verify(secret: secret)
            XCTFail("verify must fail for a revoked key")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyRevoked)
        }
    }
}
