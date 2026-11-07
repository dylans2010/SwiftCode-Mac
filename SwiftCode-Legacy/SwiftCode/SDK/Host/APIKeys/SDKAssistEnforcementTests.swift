import XCTest
@testable import SwiftCode

final class SDKAssistEnforcementTests: XCTestCase {

    private let verbatimAssistDenial =
        "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information."

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

        try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key.id)
        verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertEqual(verified.entitlements.filter { $0 == .developerAIAssist }.count, 1)

        try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, from: key.id)
        verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertFalse(verified.entitlements.contains(.developerAIAssist))

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
        let key = testKey()
        do {
            try await SDKAPIKeyStore.shared.requireEntitlement(.developerAIAssist, for: key)
            XCTFail("requireEntitlement must throw when the entitlement is absent")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyScopeInsufficient)
        }
        let entitled = testKey(entitlements: [.developerAIAssist])
        try await SDKAPIKeyStore.shared.requireEntitlement(.developerAIAssist, for: entitled)
    }

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

    func testForgedManifestClaimDoesNotGrantAssist() async {
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

        let forged = caller(extensionID: "com.swiftcode.sdk.test.forged")
        await assertAssistDenied {
            try await SDKAssistService.shared.createSession(caller: forged)
        }
    }

    func testGateExemptsExactlyAssistInvoke() async throws {
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

    func testCloudModelDeniedWithoutAllowsCloudEntitlement() async {
        let key = testKey()
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
        let key = testKey(entitlements: [.developerAIAllowsCloud])
        try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: caller(apiKey: key))
    }

    func testCloudModelKeylessKeepsGrantPath() async {
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

    func testRevokeEntitlementClosesInFlightSessionsAndDeniesNextCall() async throws {
        let (key, secret) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-enforce-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key.id)
        try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, to: key.id)

        let verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        let extID = "com.swiftcode.sdk.test.revoke-\(UUID().uuidString)"
        let session = try await SDKAssistService.shared.createSession(
            caller: caller(extensionID: extID, apiKey: verified)
        )

        try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, from: key.id)
        let closedByHook = await SDKAssistService.shared.closeSessions(forKeyID: key.id)
        XCTAssertEqual(closedByHook, 0, "revokeEntitlement must already have closed the session")

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
