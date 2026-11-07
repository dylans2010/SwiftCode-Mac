import XCTest
import SwiftCodeExtensions
@testable import SwiftCodeSDK

final class SDKCapabilityTests: XCTestCase {
    func testRegistryCoversAll35Capabilities() {
        XCTAssertEqual(SDKCapabilityRegistry.all.count, 35)
        XCTAssertEqual(Set(SDKCapabilityRegistry.all.map(\.id)), Set(SDKCapabilityID.allCases))
    }

    func testGrantableFlags() {
        for id in [SDKCapabilityID.assistInvoke, .assistUI, .assistHeadless, .assistMainView,
                   .securityAddValue, .securityHasValue, .securityListValueIDs, .securityDeleteValue, .securityUseValue] {
            XCTAssertFalse(SDKCapabilityRegistry.info(for: id).grantableInCurrentRelease, "\(id) must not be grantable")
        }
        XCTAssertTrue(SDKCapabilityRegistry.info(for: .docsSearch).grantableInCurrentRelease)
        XCTAssertTrue(SDKCapabilityRegistry.info(for: .buildExecute).grantableInCurrentRelease)
        XCTAssertTrue(SDKCapabilityRegistry.info(for: .useSecurity).grantableInCurrentRelease)
    }

    func testPrivilegedIsHighRiskOnly() {
        XCTAssertTrue(SDKCapabilityRegistry.isPrivileged(.buildExecute))
        XCTAssertTrue(SDKCapabilityRegistry.isPrivileged(.workspaceWrite))
        XCTAssertFalse(SDKCapabilityRegistry.isPrivileged(.docsSearch))
        XCTAssertFalse(SDKCapabilityRegistry.isPrivileged(.assistInvoke))
    }

    func testInfoForRawValue() {
        XCTAssertEqual(SDKCapabilityRegistry.info(forRawValue: "docs.search")?.title, "Documentation browser")
        XCTAssertNil(SDKCapabilityRegistry.info(forRawValue: "nope.not-a-capability"))
    }

    func testBrokerDelegatesToPermissionManager() async throws {
        let permissions = PermissionManager(grants: ["com.example.ext": [.workspaceRead]])
        let caller = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "digest", projectRootPath: "/tmp/project")
        try await SDKCapabilityBroker.authorize(.docsSearch, for: caller, permissions: permissions)
        await XCTAssertThrowsErrorAsync(try await SDKCapabilityBroker.authorize(.buildExecute, for: caller, permissions: permissions)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .permissionDenied)
        }
    }

    func testBrokerAlwaysDeniesAssistInvoke() async {
        let permissions = PermissionManager(grants: ["com.example.ext": [.assistTools]])
        let caller = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "digest", projectRootPath: "/tmp/project")
        await XCTAssertThrowsErrorAsync(try await SDKCapabilityBroker.authorize(.assistInvoke, for: caller, permissions: permissions)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .assistDenied)
        }
    }

    func testBrokerCloudModelEntitlement() async throws {
        let permissions = PermissionManager(grants: [:])
        let entitledKey = SDKAPIKey(keyPrefix: SDKAPIKeyCodec.testPrefix, label: "x", scopes: [.appsCreate], entitlements: [.developerAIAllowsCloud])
        let entitled = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "d", projectRootPath: "/tmp/p", apiKey: entitledKey)
        try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: entitled, permissions: permissions)
        let plainKey = SDKAPIKey(keyPrefix: SDKAPIKeyCodec.testPrefix, label: "x", scopes: [.appsCreate])
        let plain = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "d", projectRootPath: "/tmp/p", apiKey: plainKey)
        await XCTAssertThrowsErrorAsync(try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: plain, permissions: permissions)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .cloudModelDenied)
        }
    }

    func testBrokerRequiresScopeForPrivilegedCapabilityWithKey() async throws {
        let permissions = PermissionManager(grants: ["com.example.ext": [.build]])
        let plainKey = SDKAPIKey(keyPrefix: SDKAPIKeyCodec.testPrefix, label: "x", scopes: [.appsCreate])
        let plain = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "d", projectRootPath: "/tmp/p", apiKey: plainKey)
        await XCTAssertThrowsErrorAsync(try await SDKCapabilityBroker.authorize(.buildExecute, for: plain, permissions: permissions)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .apiKeyScopeInsufficient)
        }
        let scopedKey = SDKAPIKey(keyPrefix: SDKAPIKeyCodec.testPrefix, label: "x", scopes: [.capabilitiesRequest])
        let scoped = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "d", projectRootPath: "/tmp/p", apiKey: scopedKey)
        try await SDKCapabilityBroker.authorize(.buildExecute, for: scoped, permissions: permissions)
    }

    func testScopesListHas32Entries() {
        XCTAssertEqual(ScopesIDLists.all.count, 32)
        XCTAssertEqual(ScopesIDLists.all.filter { $0.kind == .view }.count, 12)
        XCTAssertEqual(ScopesIDLists.all.filter { $0.kind == .api }.count, 20)
        XCTAssertNil(ScopesIDLists.byId["use.Security"])
        XCTAssertNil(ScopesIDLists.byId["assist.main"])
    }

    func testOpenScopeRejectsAPIEntries() async {
        await XCTAssertThrowsErrorAsync(try await ScopesIDLists.openScope(id: "build.execute")) { error in
            XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
        }
        await XCTAssertThrowsErrorAsync(try await ScopesIDLists.openScope(id: "nope")) { error in
            XCTAssertEqual((error as? SDKError)?.code, .unknownCapability)
        }
    }
}
