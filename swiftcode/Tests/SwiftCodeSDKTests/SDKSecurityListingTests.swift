import XCTest
@testable import SwiftCodeSDK
import SwiftCodeExtensions

final class SDKSecurityListingTests: XCTestCase {

    private let testExtensionID = "com.swiftcode.sdk.test.security-listing"
    private let testAppID = "test-app"

    private var namespacedID: String {
        "\(testExtensionID).\(testAppID)"
    }

    override func tearDown() async throws {
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

        let encoded = try JSONEncoder().encode(apps)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains(marker))
        XCTAssertTrue(text.contains("api-key"))
    }

    func testListAllAppsEmptyWhenNothingStored() async throws {
        let apps = try await SDKSecurityService.shared.listAllApps()
        XCTAssertNil(apps.first(where: { $0.securityID == namespacedID }))
    }

    func testDeleteAllValuesRemovesNamespaceFromListing() async throws {
        _ = try KeychainSDK.addValue(
            securityID: namespacedID, valueID: "temp",
            value: Data("x".utf8), label: nil)
        let beforeDelete = try await SDKSecurityService.shared.listAllApps()
        XCTAssertNotNil(beforeDelete.first(where: { $0.securityID == namespacedID }))

        _ = try KeychainSDK.deleteAllValues(securityID: namespacedID)
        let afterDelete = try await SDKSecurityService.shared.listAllApps()
        XCTAssertNil(afterDelete.first(where: { $0.securityID == namespacedID }))
    }
}
