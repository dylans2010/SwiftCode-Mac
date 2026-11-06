import XCTest
@testable import YcodeSDK
import YcodeExtensions

// NOTE: No Swift toolchain exists in this environment, so these tests
// have NOT been compiled or run — statically verified only. On Dylan's
// Mac: run with `swift test --filter SDKAssistApplicationTests`.
//
// Ported from Legacy
// `SwiftCode/SDK/Host/APIKeys/SDKAssistApplicationTests.swift` (Dylan's
// own code; direct port authorised under MIT), adapted to the Ycode
// host shapes:
//   - Legacy's flat `SDKAssistApplication` struct (with `apiKeyID: UUID`
//     and `validate() -> [field: error]`) is Ycode's
//     `SDKAssistApplication` + nested `Field` (with `apiKey: String`,
//     the presented secret, and `validate() throws` — first failure
//     only, no field-error map). Field-level assertions therefore check
//     that validation throws / does not throw, not which map key.
//   - Legacy's submit rejection errors
//     (`SDKAssistApplicationValidationError` with field errors) are
//     Ycode `SDKError`s: unknown extension -> `.invalidArgument`,
//     unknown key -> `.apiKeyInvalid`.
//   - `SDKAPIKeyStore` / `SDKExtensionRegistry` /
//     `SDKAssistApplicationStore` are the shared instances, so the
//     store tests perform REAL secret-store and extensions-directory
//     I/O (createKey, recordInstall, submit, approve, deny, revoke),
//     exactly like Legacy's real-Keychain tests. Test keys are labeled
//     "SDKTest-assist-…" and revoked in tearDown; the test install
//     record is removed. Assist application records
//     (`sdk.assistapp.<uuid>` in the secret store) have no delete API,
//     so the approved/denied test records remain as inert test data —
//     the fixed test extension ID keeps them identifiable.

// MARK: - SDKAssistApplicationTests
//
// Tests for the Assist access application flow:
//   - field validation: valid/invalid submissions (Ycode: throwing)
//   - store: submit rejection paths, approve -> entitlement grant,
//     deny -> no grant

final class SDKAssistApplicationTests: XCTestCase {

    /// The fixed extension ID used for the install-record round-trip.
    /// Kept stable so leftover test records stay identifiable.
    private let testExtensionID = "com.swiftcode.sdk.test.assist-app"
    private let testVersion = "1.0.0-test"

    private var createdKeyIDs: [UUID] = []

    override func tearDown() async throws {
        // Best-effort cleanup: revoke every test key we created. Runs even
        // when a test fails mid-flow.
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

    // MARK: - Helpers

    private func validField(apiKey: String = "placeholder-secret") -> SDKAssistApplication.Field {
        SDKAssistApplication.Field(
            extensionID: testExtensionID,
            displayName: "Test Assist App",
            apiKey: apiKey,
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

    /// Registers a real install record so `submit` passes the
    /// installed-app check, and creates a real developer API key.
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

    // MARK: - Field-level validation

    func testValidFieldPassesValidation() throws {
        try validField().validate()
    }

    func testEmptyFieldsFailValidation() {
        // Ycode validation throws the first failure; each of these fields
        // must fail on its own. Conditional fields with "no" answers must
        // NOT fail.
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: "  ", displayName: "Test Assist App", apiKey: "x",
            sdkVariant: .assistSDKUI,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "", apiKey: "x",
            sdkVariant: .assistSDKUI,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKey: "x",
            sdkVariant: .assistSDKUI, usageDescription: "",
            hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKey: "x",
            sdkVariant: .assistSDKUI,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "").validate())
        // All "no" answers, everything else valid: passes.
        XCTAssertNoThrow(try validField().validate())
    }

    func testUsageDescriptionMinimumLength() {
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKey: "x",
            sdkVariant: .assistSDK,
            usageDescription: String(repeating: "x", count: 39),
            hasOwnUI: true, ownUIDescription: "A panel.",
            usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())
        XCTAssertNoThrow(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKey: "x",
            sdkVariant: .assistSDK,
            usageDescription: String(repeating: "x", count: 40),
            hasOwnUI: true, ownUIDescription: "A panel.",
            usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())
    }

    func testConditionalDescriptionsRequiredWhenYes() {
        // hasOwnUI = true without a description fails; with one it passes.
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKey: "x",
            sdkVariant: .assistSDK,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: true, ownUIDescription: nil,
            usesThirdPartyModels: false, dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())

        // Third-party models declared without a list fails.
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKey: "x",
            sdkVariant: .assistSDK,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: false,
            usesThirdPartyModels: true, thirdPartyModels: [],
            dataLeavesDevice: false,
            contactEmail: "dev@example.com").validate())

        // Data leaving the device without a destination fails.
        XCTAssertThrowsError(try SDKAssistApplication.Field(
            extensionID: testExtensionID, displayName: "Test Assist App", apiKey: "x",
            sdkVariant: .assistSDK,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: false, usesThirdPartyModels: false,
            dataLeavesDevice: true, dataDestination: "",
            contactEmail: "dev@example.com").validate())
    }

    func testContactEmailValidation() {
        for email in ["dev@example.com", "a.b+tag@sub.example.co"] {
            XCTAssertNoThrow(try SDKAssistApplication.Field(
                extensionID: testExtensionID, displayName: "Test Assist App", apiKey: "x",
                sdkVariant: .assistSDK,
                usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
                hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
                contactEmail: email).validate(), email)
        }
        for email in ["not-an-email", "dev@", "@example.com", "dev@example"] {
            XCTAssertThrowsError(try SDKAssistApplication.Field(
                extensionID: testExtensionID, displayName: "Test Assist App", apiKey: "x",
                sdkVariant: .assistSDK,
                usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
                hasOwnUI: false, usesThirdPartyModels: false, dataLeavesDevice: false,
                contactEmail: email).validate(), email)
        }
    }

    // MARK: - Store: submit

    func testSubmitRejectsUnknownExtensionID() async throws {
        // Real store, real key, but NO install record: the extension-ID
        // check must fail and nothing may be persisted.
        let (key, secret) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-assist-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key.id)

        let field = SDKAssistApplication.Field(
            extensionID: "com.swiftcode.sdk.test.no-such-app-\(UUID().uuidString)",
            displayName: "No Such App",
            apiKey: secret,
            sdkVariant: .assistSDK,
            usageDescription: String(repeating: "Valid usage description. ", count: 3),
            hasOwnUI: false,
            usesThirdPartyModels: false,
            dataLeavesDevice: false,
            contactEmail: "dev@example.com"
        )
        do {
            _ = try await SDKAssistApplicationStore.shared.submit(field)
            XCTFail("submit must reject an unknown extension ID")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .invalidArgument)
        }
    }

    func testSubmitRejectsUnknownAPIKey() async throws {
        _ = try await seedExtensionAndKey()
        let field = validField(apiKey: "sc_dev_test_not-a-real-secret")
        do {
            _ = try await SDKAssistApplicationStore.shared.submit(field)
            XCTFail("submit must reject an unknown API key")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyInvalid)
        }
    }

    // MARK: - Store: approve -> grant, deny -> no grant

    func testApproveGrantsEntitlements() async throws {
        let (_, secret) = try await seedExtensionAndKey()
        // Declaring third-party models makes approval grant BOTH
        // entitlements (see SDKAssistApplicationStore.approve).
        let field = SDKAssistApplication.Field(
            extensionID: testExtensionID,
            displayName: "Test Assist App",
            apiKey: secret,
            sdkVariant: .assistSDK,
            usageDescription: "This app summarizes the user's open document on demand using Assist sessions.",
            hasOwnUI: true,
            ownUIDescription: "A native SwiftUI panel renders the streamed response.",
            usesThirdPartyModels: true, thirdPartyModels: ["openai/gpt-4o"],
            dataLeavesDevice: false,
            contactEmail: "dev@example.com"
        )
        let submitted = try await SDKAssistApplicationStore.shared.submit(field)
        XCTAssertEqual(submitted.status, .pending)

        let decided = try await SDKAssistApplicationStore.shared.approve(id: submitted.id)
        XCTAssertEqual(decided.status, .approved)
        XCTAssertNotNil(decided.decidedAt)

        // The grant is real: re-verify the secret and read the CURRENT
        // entitlements off the metadata.
        let verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertTrue(verified.entitlements.contains(.developerAIAssist))
        XCTAssertTrue(verified.entitlements.contains(.developerAIAllowsCloud))
    }

    func testApproveWithoutThirdPartyModelsGrantsAssistOnly() async throws {
        let (_, secret) = try await seedExtensionAndKey()
        let submitted = try await SDKAssistApplicationStore.shared.submit(validField(apiKey: secret))
        _ = try await SDKAssistApplicationStore.shared.approve(id: submitted.id)

        let verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertTrue(verified.entitlements.contains(.developerAIAssist))
        XCTAssertFalse(verified.entitlements.contains(.developerAIAllowsCloud))
    }

    func testDenyGrantsNothing() async throws {
        let (_, secret) = try await seedExtensionAndKey()
        let submitted = try await SDKAssistApplicationStore.shared.submit(validField(apiKey: secret))

        let decided = try await SDKAssistApplicationStore.shared.deny(id: submitted.id)
        XCTAssertEqual(decided.status, .denied)
        XCTAssertNotNil(decided.decidedAt)

        let verified = try await SDKAPIKeyStore.shared.verify(secret: secret)
        XCTAssertTrue(verified.entitlements.isEmpty)
    }

    func testDecideIsSingleShot() async throws {
        _ = try await seedExtensionAndKey()
        // Uses its own key so the first test's key stays clean.
        let (key2, secret2) = try await SDKAPIKeyStore.shared.createKey(
            label: "SDKTest-assist-\(UUID().uuidString)",
            scopes: [.appsCreate],
            isLive: false
        )
        createdKeyIDs.append(key2.id)

        let submitted = try await SDKAssistApplicationStore.shared.submit(validField(apiKey: secret2))
        _ = try await SDKAssistApplicationStore.shared.deny(id: submitted.id)
        // A second decision must fail: no double-decide.
        do {
            _ = try await SDKAssistApplicationStore.shared.approve(id: submitted.id)
            XCTFail("approve must fail on an already-decided application")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .invalidArgument)
        }
    }
}
