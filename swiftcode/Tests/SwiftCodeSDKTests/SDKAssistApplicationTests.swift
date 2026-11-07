import XCTest
@testable import SwiftCodeSDK
import SwiftCodeExtensions

final class SDKAssistApplicationTests: XCTestCase {

    private let testExtensionID = "com.swiftcode.sdk.test.assist-app"
    private let testVersion = "1.0.0-test"

    private var createdKeyIDs: [UUID] = []

    override func tearDown() async throws {
        for keyID in createdKeyIDs {
            await SDKAPIKeyStore.shared.revoke(id: keyID)
        }
        createdKeyIDs = []
        try? await SDKExtensionRegistry.shared.removeInstallRecord(
            extensionID: testExtensionID,
            version: testVersion
        )
        try await super.tearDown()
    }

    private func validField(apiKeyID: UUID = UUID()) -> SDKAssistApplication.Field {
        SDKAssistApplication.Field(
            extensionID: testExtensionID,
            displayName: "Test Assist App",
            apiKeyID: apiKeyID,
            sdkVariant: .assistSDK,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: true,
            ownUIDescription: "A native SwiftUI panel renders the streamed response.",
            usesThirdPartyModels: false,
            thirdPartyModels: [],
            dataLeavesDevice: false,
            dataDestination: nil,
            contactEmail: "dev@example.com"
        )
    }

    private func seedExtensionAndKey() async throws -> (key: SDKAPIKey, secret: String) {
        let manifest = SwiftCodeManifest(
            id: testExtensionID,
            name: "Test Assist App",
            version: testVersion
        )
        let install = SDKInstalledExtension(
            id: testExtensionID,
            name: "Test Assist App",
            version: testVersion,
            packageDigest: String(repeating: "0", count: 64),
            installPath: FileManager.default.temporaryDirectory
                .appendingPathComponent("SDKAssistApplicationTests-\(UUID().uuidString)"),
            installedAt: Date(),
            updatedAt: Date(),
            enabled: true,
            manifest: manifest
        )
        try await SDKExtensionRegistry.shared.recordInstall(install)

        let (key, secret) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-assist-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key.id)
        return (key, secret)
    }

    func testValidFieldPassesValidation() throws {
        try validField().validate()
    }

    func testEmptyFieldsFailValidation() {
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: "  ", displayName: "Test Assist App", apiKeyID: UUID(),
            sdkVariant: .assistSDKUI,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "", apiKeyID: UUID(),
            sdkVariant: .assistSDKUI,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKeyID: UUID(),
            sdkVariant: .assistSDKUI, usageDescription: "",
            hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKeyID: UUID(),
            sdkVariant: .assistSDKUI,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "").validate())
        XCTAssertNoThrow(try validField().validate())
    }

    func testUsageDescriptionMinimumLength() {
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKeyID: UUID(),
            sdkVariant: .assistSDK,
            usageDescription: String(repeating: "x", count: 39),
            hasOwnUI: true, ownUIDescription: "A panel.",
            usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())
        XCTAssertNoThrow(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKeyID: UUID(),
            sdkVariant: .assistSDK,
            usageDescription: String(repeating: "x", count: 40),
            hasOwnUI: true, ownUIDescription: "A panel.",
            usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())
    }

    func testConditionalDescriptionsRequiredWhenYes() {
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKeyID: UUID(),
            sdkVariant: .assistSDK,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: true, ownUIDescription: nil,
            usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())

        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKeyID: UUID(),
            sdkVariant: .assistSDK,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: false,
            usesThirdPartyModels: true, thirdPartyModels: [],
            dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())

        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKeyID: UUID(),
            sdkVariant: .assistSDK,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: false, usesThirdPartyModels: false,
            dataLeavesDevice: true, dataDestination: "",
            contactEmail: "dev@example.com").validate())
    }

    func testContactEmailValidation() {
        for email in ["dev@example.com", "a.b+tag@sub.example.co"] {
            XCTAssertNoThrow(try SDKAssistApplication.Field(
                extensionID: testExtensionID, displayName: "Test Assist App", apiKeyID: UUID(),
                sdkVariant: .assistSDK,
                usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
                hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
                contactEmail: email).validate(), email)
        }
        for email in ["not-an-email", "dev@", "@example.com", "dev@example"] {
            XCTAssertThrowsError(try SDKAssistApplication.Field(
                extensionID: testExtensionID, displayName: "Test Assist App", apiKeyID: UUID(),
                sdkVariant: .assistSDK,
                usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
                hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
                contactEmail: email).validate(), email)
        }
    }

    func testSubmitRejectsUnknownExtensionID() async throws {
        let (key, secret) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-assist-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key.id)

        let field = SDKAssistApplication.Field(
            extensionID: "com.swiftcode.sdk.test.no-such-app-\(UUID().uuidString)",
            displayName: "No Such App",
            apiKeyID: key.id,
            sdkVariant: .assistSDK,
            usageDescription: String(repeating: "Valid usage description. ", count: 3),
            hasOwnUI: false,
            usesThirdPartyModels: false,
            dataLeavesDevice: false,
            contactEmail: "dev@example.com"
        )
        do {
            _ = try await SDKAssistApplicationStore.shared.submit(field, apiKeySecret: secret)
            XCTFail("submit must reject an unknown extension ID")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .invalidArgument)
        }
    }

    func testSubmitRejectsUnknownAPIKey() async throws {
        _ = try await seedExtensionAndKey()
        let field = validField()
        do {
            _ = try await SDKAssistApplicationStore.shared.submit(field, apiKeySecret: "sc_dev_test_not-a-real-secret")
            XCTFail("submit must reject an unknown API key")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyInvalid)
        }
    }

    func testSubmitRejectsSecretForDifferentKey() async throws {
        let (keyA, _) = try await seedExtensionAndKey()
        let (keyB, secretB) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-assist-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(keyB.id)
        XCTAssertNotEqual(keyA.id, keyB.id)

        do {
            _ = try await SDKAssistApplicationStore.shared.submit(validField(apiKeyID: keyA.id), apiKeySecret: secretB)
            XCTFail("submit must reject a secret for a different key than the field names")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyInvalid)
        }
    }

    func testSubmittedRecordStoresKeyIDNotSecret() async throws {
        let (key, secret) = try await seedExtensionAndKey()
        let submitted = try await SDKAssistApplicationStore.shared.submit(
            validField(apiKeyID: key.id), apiKeySecret: secret)
        XCTAssertEqual(submitted.field.apiKeyID, key.id)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(submitted)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(key.id.uuidString), "encoded record must carry the key ID")
        XCTAssertFalse(json.contains("sc_dev_"), "encoded record must not contain the presented secret")
        XCTAssertFalse(json.contains("\"apiKey\""), "encoded record must not contain a legacy apiKey key")
    }

    func testLegacySecretRecordMigratesToKeyID() throws {
        let keyID = UUID()
        let fakeSecret = Self.fakePresentedSecret(for: keyID)
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","field":{"extensionID":"\(testExtensionID)","displayName":"Test Assist App","apiKey":"\(fakeSecret)","sdkVariant":"assistSDK","usageDescription":"This app summarizes the user's open document on demand using Assist sessions.","hasOwnUI":false,"usesThirdPartyModels":false,"thirdPartyModels":[],"dataLeavesDevice":false,"contactEmail":"dev@example.com"},"status":"pending","submittedAt":"2026-11-06T00:00:00Z","decidedAt":null}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SDKAssistApplication.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.field.apiKeyID, keyID)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let reencoded = String(decoding: try encoder.encode(decoded), as: UTF8.self)
        XCTAssertTrue(reencoded.contains(keyID.uuidString))
        XCTAssertFalse(reencoded.contains("sc_dev_"), "migrated record must not re-emit the secret")
        XCTAssertFalse(reencoded.contains("\"apiKey\""), "migrated record must not re-emit the legacy key")
    }

    private static func fakePresentedSecret(for keyID: UUID) -> String {
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let payload = "{\"id\":\"\(keyID.uuidString)\",\"prefix\":\"sc_dev_test\",\"iat\":0}"
        let payloadB64 = base64URL(Data(payload.utf8))
        let signatureB64 = base64URL(Data(repeating: 0, count: 32))
        return "sc_dev_test_\(payloadB64).\(signatureB64)"
    }

    func testApproveGrantsEntitlements() async throws {
        let (key, secret) = try await seedExtensionAndKey()
        let field = SDKAssistApplication.Field(
            extensionID: testExtensionID,
            displayName: "Test Assist App",
            apiKeyID: key.id,
            sdkVariant: .assistSDK,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: true,
            ownUIDescription: "A native SwiftUI panel renders the streamed response.",
            usesThirdPartyModels: true, thirdPartyModels: ["openai/gpt-4o"],
            dataLeavesDevice: false,
            contactEmail: "dev@example.com"
        )
        let submitted = try await SDKAssistApplicationStore.shared.submit(field, apiKeySecret: secret)
        XCTAssertEqual(submitted.status, .pending)

        let decided = try await SDKAssistApplicationStore.shared.approve(id: submitted.id)
        XCTAssertEqual(decided.status, .approved)
        XCTAssertNotNil(decided.decidedAt)

        let verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertTrue(verified.entitlements.contains(.developerAIAssist))
        XCTAssertTrue(verified.entitlements.contains(.developerAIAllowsCloud))
    }

    func testApproveWithoutThirdPartyModelsGrantsAssistOnly() async throws {
        let (key, secret) = try await seedExtensionAndKey()
        let submitted = try await SDKAssistApplicationStore.shared.submit(validField(apiKeyID: key.id), apiKeySecret: secret)
        _ = try await SDKAssistApplicationStore.shared.approve(id: submitted.id)

        let verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertTrue(verified.entitlements.contains(.developerAIAssist))
        XCTAssertFalse(verified.entitlements.contains(.developerAIAllowsCloud))
    }

    func testDenyGrantsNothing() async throws {
        let (key, secret) = try await seedExtensionAndKey()
        let submitted = try await SDKAssistApplicationStore.shared.submit(validField(apiKeyID: key.id), apiKeySecret: secret)

        let decided = try await SDKAssistApplicationStore.shared.deny(id: submitted.id)
        XCTAssertEqual(decided.status, .denied)
        XCTAssertNotNil(decided.decidedAt)

        let verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertTrue(verified.entitlements.isEmpty)
    }

    func testDecideIsSingleShot() async throws {
        _ = try await seedExtensionAndKey()
        let (key2, secret2) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-assist-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key2.id)

        let submitted = try await SDKAssistApplicationStore.shared.submit(validField(apiKeyID: key2.id), apiKeySecret: secret2)
        _ = try await SDKAssistApplicationStore.shared.deny(id: submitted.id)
        do {
            _ = try await SDKAssistApplicationStore.shared.approve(id: submitted.id)
            XCTFail("approve must fail on an already-decided application")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .invalidArgument)
        }
    }
}
