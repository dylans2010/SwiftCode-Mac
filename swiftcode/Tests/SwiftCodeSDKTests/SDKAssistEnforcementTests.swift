import XCTest
@testable import SwiftCodeSDK
import SwiftCodeExtensions

final class SDKAssistEnforcementTests: XCTestCase {

    private let denialMessage = "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information."

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

    func testGrantAndRevokeEntitlementRoundTrip() async throws {
        let (key, secret) = try await testKey()
        let initial = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertFalse(initial.entitlements.contains(.developerAIAssist))

        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, toKeyID: key.id)
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, toKeyID: key.id)
        let granted = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertTrue(granted.entitlements.contains(.developerAIAssist))

        let closed = try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, fromKeyID: key.id)
        XCTAssertEqual(closed, 0)
        let revoked = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertFalse(revoked.entitlements.contains(.developerAIAssist))

        _ = try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, fromKeyID: key.id)
    }

    func testGrantEntitlementRefusesRevokedKey() async throws {
        let (key, _) = try await testKey()
        await SDKAPIKeyStore.shared.revoke(id: key.id)
        do {
            _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, toKeyID: key.id)
            XCTFail("grantEntitlement must fail for a revoked key")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyRevoked)
        }
    }

    func testRequireEntitlementThrowsOnMissingEntitlement() async throws {
        let (key, _) = try await testKey()
        do {
            _ = try await SDKAPIKeyStore.shared.requireEntitlement(.developerAIAssist, on: key)
            XCTFail("requireEntitlement must throw for a missing entitlement")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }
    }

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
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, toKeyID: key.id)
        let session = try await SDKAssistService.shared.createSession(
            key: key, extensionID: testExtensionID, options: SDKAssistSessionOptions())
        createdSessionIDs.append(session.id)
        XCTAssertFalse(session.isClosed)

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

        do {
            _ = try await SDKAssistService.shared.createSession(
                key: key, extensionID: testExtensionID, options: SDKAssistSessionOptions())
            XCTFail("createSession must deny an unentitled caller")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }

        do {
            _ = try await SDKAssistService.shared.send(
                sessionID: UUID(), key: key, extensionID: testExtensionID, message: "hi")
            XCTFail("send must deny an unentitled caller")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .assistDenied)
            XCTAssertEqual(sdkError.message, denialMessage)
        }

        let stream = await SDKAssistService.shared.sendStreaming(
            sessionID: UUID(), key: key, extensionID: testExtensionID, message: "hi")
        var seenFailure: SDKError?
        for try await event in stream {
            if case let .failed(error) = event { seenFailure = error }
        }
        guard let denial = seenFailure else { return XCTFail("stream must fail with .assistDenied") }
        XCTAssertEqual(denial.code, .assistDenied)
        XCTAssertEqual(denial.message, denialMessage)

        do {
            _ = try await SDKAssistService.shared.executeTool(
                sessionID: UUID(), key: key, extensionID: testExtensionID,
                call: SDKAssistToolCall(toolName: "fs.readFile", arguments: [:]))
            XCTFail("executeTool must deny an unentitled caller")
        } catch let sdkError as SDKError {
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

    func testForgedManifestClaimDoesNotGrantAssist() async throws {
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

    func testGateExemptsExactlyAssistInvoke() async throws {
        try await SDKAssistGate.check(ipcMethod: "assist.invoke", callerExtensionID: testExtensionID)
        try await SDKAssistGate.check(ipcMethod: "ASSIST.INVOKE", callerExtensionID: testExtensionID)
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

    func testCloudModelDeniedWithoutAllowsCloudEntitlement() async throws {
        let (key, _) = try await testKey()
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, toKeyID: key.id)
        do {
            try await SDKCapabilityBroker.authorize(
                .useSwiftCodeModel, for: caller(for: testExtensionID, key: key))
            XCTFail("cloud model use must deny without the allows-cloud entitlement")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .cloudModelDenied)
            XCTAssertEqual(sdkError.message, cloudDenialMessage)
        }
    }

    func testCloudModelAllowedWithEntitlement() async throws {
        let (key, _) = try await testKey()
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, toKeyID: key.id)
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAllowsCloud, toKeyID: key.id)
        try await SDKCapabilityBroker.authorize(
            .useSwiftCodeModel, for: caller(for: testExtensionID, key: key))
    }

    func testAllowsCloudEntitlementAloneOpensCloudGate() async throws {
        let (key, _) = try await testKey()
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAllowsCloud, toKeyID: key.id)
        try await SDKCapabilityBroker.authorize(
            .useSwiftCodeModel, for: caller(for: testExtensionID, key: key))
    }

    func testRevokeEntitlementClosesInFlightSessionsAndDeniesNextCall() async throws {
        let (key, _) = try await testKey()
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, toKeyID: key.id)
        let session = try await SDKAssistService.shared.createSession(
            key: key, extensionID: testExtensionID, options: SDKAssistSessionOptions())
        createdSessionIDs.append(session.id)
        XCTAssertFalse(session.isClosed)

        let closed = try await SDKAPIKeyStore.shared.revokeEntitlement(.developerAIAssist, fromKeyID: key.id)
        XCTAssertEqual(closed, 1)
        let sessions = await SDKAssistService.shared.listSessions(forExtensionID: testExtensionID)
        XCTAssertTrue(sessions.first(where: { $0.id == session.id })?.isClosed == true)

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
        _ = try await SDKAPIKeyStore.shared.grantEntitlement(.developerAIAssist, toKeyID: key.id)
        await SDKAPIKeyStore.shared.revoke(id: key.id)
        do {
            _ = try await SDKAPIKeyStore.shared.verify(secret: secret)
            XCTFail("verify must fail for a revoked key")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyRevoked)
        }
    }
}
