import XCTest
@testable import YcodeSDK
import YcodeExtensions

// NOTE: No Swift toolchain exists in this environment, so these tests
// have NOT been compiled or run — statically verified only. On Dylan's
// Mac: run with `swift test --filter SDKSecurityListingTests`.
//
// Tests for the S-4 `use.Security` store listing
// (`SDKSecurityService.listAllApps`, wired into Studio through
// `SDKHostSecurityStore`).
//
// The listing is host-only and returns metadata only: value IDs,
// labels, and creation times — secret values are never returned. The
// tests use the REAL secret store (like Legacy's real-Keychain tests)
// because `KeychainSDK`'s store is a private static and not injectable.
// Values are written under a test-only extension ID and wiped in
// tearDown.

final class SDKSecurityListingTests: XCTestCase {

    private let testExtensionID = "com.swiftcode.sdk.test.security-listing"
    private let testAppID = "test-app"

    private var namespacedID: String {
        "\(testExtensionID).\(testAppID)"
    }

    override func tearDown() async throws {
        // Wipe every value under the test namespace, even when a test
        // fails mid-flow.
        try? KeychainSDK.deleteAllValues(securityID: namespacedID)
        try await super.tearDown()
    }

    func testListAllAppsGroupsValuesByNamespacedSecurityID() async throws {
        let secret = Data("do-not-return-me".utf8)
        _ = try KeychainSDK.addValue(
            securityID: namespacedID, valueID: "github-token",
            value: secret, label: "GitHub Token")
        _ = try KeychainSDK.addValue(
            securityID: namespacedID, valueID: "npm-token",
            value: secret, label: "npm Token")

        let apps = try await SDKSecurityService.shared.listAllApps()
        guard let summary = apps.first(where: { $0.securityID == namespacedID }) else {
            return XCTFail("listAllApps must include the test security namespace")
        }
        // The extension is not installed, so no extension ID resolves —
        // leftover values from an uninstalled extension.
        XCTAssertNil(summary.extensionID)
        XCTAssertEqual(Set(summary.values.map(\.valueID)), ["github-token", "npm-token"])
        XCTAssertEqual(Set(summary.values.map(\.label)), ["GitHub Token", "npm Token"])
    }

    func testListAllAppsNeverReturnsSecretValues() async throws {
        let marker = "SECRET-MARKER-\(UUID().uuidString)"
        _ = try KeychainSDK.addValue(
            securityID: namespacedID, valueID: "api-key",
            value: Data(marker.utf8), label: nil)

        let apps = try await SDKSecurityService.shared.listAllApps()
        let summary = apps.first(where: { $0.securityID == namespacedID })
        XCTAssertNotNil(summary)

        // The summary carries no secret material anywhere: the marker
        // must not appear in any field of the returned summaries.
        let encoded = try JSONEncoder().encode(apps)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains(marker))
        // The value ID itself is metadata, not secret material, so it
        // IS present in the listing.
        XCTAssertTrue(text.contains("api-key"))
    }

    func testListAllAppsEmptyWhenNothingStored() async throws {
        // Nothing was written under the test namespace; the listing must
        // not invent it. (Other apps may exist from other tests — the
        // assertion is only about this namespace.)
        let apps = try await SDKSecurityService.shared.listAllApps()
        XCTAssertNil(apps.first(where: { $0.securityID == namespacedID }))
    }

    func testDeleteAllValuesRemovesNamespaceFromListing() async throws {
        _ = try KeychainSDK.addValue(
            securityID: namespacedID, valueID: "temp",
            value: Data("x".utf8), label: nil)
        XCTAssertNotNil(try await SDKSecurityService.shared.listAllApps()
            .first(where: { $0.securityID == namespacedID }))

        _ = try KeychainSDK.deleteAllValues(securityID: namespacedID)
        XCTAssertNil(try await SDKSecurityService.shared.listAllApps()
            .first(where: { $0.securityID == namespacedID }))
    }
}
