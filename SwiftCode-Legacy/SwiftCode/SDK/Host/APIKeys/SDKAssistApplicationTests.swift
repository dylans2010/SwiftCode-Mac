import XCTest
@testable import SwiftCode

final class SDKAssistApplicationTests: XCTestCase {

    private let testExtensionID = "com.swiftcode.sdk.test.assist-app"
    private let testVersion = "1.0.0-test"

    private var createdKeyIDs: [UUID] = []

    override func tearDown() async throws {
        for keyID in createdKeyIDs {
            try? await SDKAPIKeyStore.shared.revoke(id: keyID)
        }
        createdKeyIDs = []
        try? await SDKExtensionRegistry.shared.removeInstallRecord(
            extensionID: testExtensionID,
            version: testVersion
        )
        try await super.tearDown()
    }

    private func validApplication(apiKeyID: UUID = UUID()) -> SDKAssistApplication {
        SDKAssistApplication(
            extensionID: testExtensionID,
            displayName: "Test Assist App",
            apiKeyID: apiKeyID,
            sdkVariant: .assistSDK,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: true,
            ownUIDescription: "A native SwiftUI panel renders the streamed response.",
            usesThirdPartyModels: false,
            dataLeavesDevice: false,
            contactEmail: "dev@example.com"
        )
    }

    private func seedExtensionAndKey() async throws -> (key: SDKAPIKey, secret: String) {
        let manifest = SDKManifest(
            manifestVersion: 1,
            id: testExtensionID,
            name: "Test Assist App",
            version: testVersion,
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
            capabilities: []
        )
        let install = SDKInstalledExtension(
            id: testExtensionID,
            name: "Test Assist App",
            version: testVersion,
            packageDigest: String(repeating: "0", count: 64),
            installPath: FileManager.default.temporaryDirectory
                .appendingPathComponent("SDKAssistApplicationTests-\(UUID().uuidString)").path,
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

    func testValidApplicationPassesValidation() {
        XCTAssertTrue(validApplication().validate().isEmpty)
    }

    func testEmptyFieldsProduceFieldLevelErrors() {
        var app = validApplication()
        app = SDKAssistApplication(
            extensionID: "  ",
            displayName: "",
            apiKeyID: app.apiKeyID,
            sdkVariant: .assistSDKUI,
            usageDescription: "",
            hasOwnUI: false,
            usesThirdPartyModels: false,
            dataLeavesDevice: false,
            contactEmail: ""
        )
        let errors = app.validate()
        XCTAssertNotNil(errors[.extensionID])
        XCTAssertNotNil(errors[.displayName])
        XCTAssertNotNil(errors[.usageDescription])
        XCTAssertNotNil(errors[.contactEmail])
        XCTAssertNil(errors[.ownUIDescription])
        XCTAssertNil(errors[.thirdPartyModels])
        XCTAssertNil(errors[.dataDestination])
    }

    func testUsageDescriptionMinimumLength() {
        var short = validApplication()
        short = SDKAssistApplication(
            extensionID: short.extensionID,
            displayName: short.displayName,
            apiKeyID: short.apiKeyID,
            sdkVariant: short.sdkVariant,
            usageDescription: String(repeating: "x", count: 39),
            hasOwnUI: short.hasOwnUI,
            ownUIDescription: short.ownUIDescription,
            usesThirdPartyModels: short.usesThirdPartyModels,
            dataLeavesDevice: short.dataLeavesDevice,
            contactEmail: short.contactEmail
        )
        XCTAssertNotNil(short.validate()[.usageDescription])

        var exact = validApplication()
        exact = SDKAssistApplication(
            extensionID: exact.extensionID,
            displayName: exact.displayName,
            apiKeyID: exact.apiKeyID,
            sdkVariant: exact.sdkVariant,
            usageDescription: String(repeating: "x", count: 40),
            hasOwnUI: exact.hasOwnUI,
            ownUIDescription: exact.ownUIDescription,
            usesThirdPartyModels: exact.usesThirdPartyModels,
            dataLeavesDevice: exact.dataLeavesDevice,
            contactEmail: exact.contactEmail
        )
        XCTAssertNil(exact.validate()[.usageDescription])
    }

    func testConditionalDescriptionsRequiredWhenYes() {
        let base = validApplication()
        var noUIDesc = base
        noUIDesc = SDKAssistApplication(
            extensionID: base.extensionID, displayName: base.displayName,
            apiKeyID: base.apiKeyID, sdkVariant: base.sdkVariant,
            usageDescription: base.usageDescription,
            hasOwnUI: true, ownUIDescription: nil,
            usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: base.contactEmail
        )
        XCTAssertNotNil(noUIDesc.validate()[.ownUIDescription])

        var noModelList = base
        noModelList = SDKAssistApplication(
            extensionID: base.extensionID, displayName: base.displayName,
            apiKeyID: base.apiKeyID, sdkVariant: base.sdkVariant,
            usageDescription: base.usageDescription,
            hasOwnUI: false,
            usesThirdPartyModels: true, thirdPartyModels: "   ",
            dataLeavesDevice: false,
            contactEmail: base.contactEmail
        )
        XCTAssertNotNil(noModelList.validate()[.thirdPartyModels])

        var noDestination = base
        noDestination = SDKAssistApplication(
            extensionID: base.extensionID, displayName: base.displayName,
            apiKeyID: base.apiKeyID, sdkVariant: base.sdkVariant,
            usageDescription: base.usageDescription,
            hasOwnUI: false, usesThirdPartyModels: false,
            dataLeavesDevice: true, dataDestination: "",
            contactEmail: base.contactEmail
        )
        XCTAssertNotNil(noDestination.validate()[.dataDestination])
    }

    func testContactEmailValidation() {
        XCTAssertTrue(SDKAssistApplication.isValidEmail("dev@example.com"))
        XCTAssertTrue(SDKAssistApplication.isValidEmail("a.b+tag@sub.example.co"))
        XCTAssertFalse(SDKAssistApplication.isValidEmail("not-an-email"))
        XCTAssertFalse(SDKAssistApplication.isValidEmail("dev@"))
        XCTAssertFalse(SDKAssistApplication.isValidEmail("@example.com"))
        XCTAssertFalse(SDKAssistApplication.isValidEmail("dev@example"))

        var bad = validApplication()
        bad = SDKAssistApplication(
            extensionID: bad.extensionID, displayName: bad.displayName,
            apiKeyID: bad.apiKeyID, sdkVariant: bad.sdkVariant,
            usageDescription: bad.usageDescription,
            hasOwnUI: bad.hasOwnUI, ownUIDescription: bad.ownUIDescription,
            usesThirdPartyModels: bad.usesThirdPartyModels,
            dataLeavesDevice: bad.dataLeavesDevice,
            contactEmail: "not-an-email"
        )
        XCTAssertNotNil(bad.validate()[.contactEmail])
    }

    func testSubmitRejectsUnknownExtensionID() async {
        let (key, _) = try! await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-assist-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key.id)

        let app = SDKAssistApplication(
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
            _ = try await SDKAssistApplicationStore.shared.submit(app)
            XCTFail("submit must reject an unknown extension ID")
        } catch let validation as SDKAssistApplicationValidationError {
            XCTAssertNotNil(validation.errors[.extensionID])
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testSubmitRejectsUnknownAPIKey() async throws {
        let (_, _) = try await seedExtensionAndKey()
        var app = validApplication()
        app = SDKAssistApplication(
            extensionID: app.extensionID, displayName: app.displayName,
            apiKeyID: UUID(), sdkVariant: app.sdkVariant,
            usageDescription: app.usageDescription,
            hasOwnUI: app.hasOwnUI, ownUIDescription: app.ownUIDescription,
            usesThirdPartyModels: app.usesThirdPartyModels,
            dataLeavesDevice: app.dataLeavesDevice,
            contactEmail: app.contactEmail
        )
        do {
            _ = try await SDKAssistApplicationStore.shared.submit(app)
            XCTFail("submit must reject an unknown API key")
        } catch let validation as SDKAssistApplicationValidationError {
            XCTAssertNotNil(validation.errors[.apiKey])
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testApproveGrantsEntitlements() async throws {
        let (key, secret) = try await seedExtensionAndKey()
        var app = validApplication(apiKeyID: key.id)
        app = SDKAssistApplication(
            extensionID: app.extensionID, displayName: app.displayName,
            apiKeyID: app.apiKeyID, sdkVariant: app.sdkVariant,
            usageDescription: app.usageDescription,
            hasOwnUI: app.hasOwnUI, ownUIDescription: app.ownUIDescription,
            usesThirdPartyModels: true, thirdPartyModels: "openai/gpt-4o",
            dataLeavesDevice: app.dataLeavesDevice,
            contactEmail: app.contactEmail
        )
        let submitted = try await SDKAssistApplicationStore.shared.submit(app)
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
        let app = validApplication(apiKeyID: key.id)
        let submitted = try await SDKAssistApplicationStore.shared.submit(app)
        _ = try await SDKAssistApplicationStore.shared.approve(id: submitted.id)

        let verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertTrue(verified.entitlements.contains(.developerAIAssist))
        XCTAssertFalse(verified.entitlements.contains(.developerAIAllowsCloud))
    }

    func testDenyGrantsNothing() async throws {
        let (key, secret) = try await seedExtensionAndKey()
        let app = validApplication(apiKeyID: key.id)
        let submitted = try await SDKAssistApplicationStore.shared.submit(app)

        let decided = try await SDKAssistApplicationStore.shared.deny(id: submitted.id)
        XCTAssertEqual(decided.status, .denied)
        XCTAssertNotNil(decided.decidedAt)

        let verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertTrue(verified.entitlements.isEmpty)
    }

    func testDecideIsSingleShot() async throws {
        let (_, _) = try await seedExtensionAndKey()
        let (key2, _) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-assist-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key2.id)

        let app = validApplication(apiKeyID: key2.id)
        let submitted = try await SDKAssistApplicationStore.shared.submit(app)
        _ = try await SDKAssistApplicationStore.shared.deny(id: submitted.id)
        do {
            _ = try await SDKAssistApplicationStore.shared.approve(id: submitted.id)
            XCTFail("approve must fail on an already-decided application")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .invalidArgument)
        }
    }
}
