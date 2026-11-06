import XCTest
import SwiftCodeExtensions
@testable import SwiftCodeSDK

/// Capability registry, broker delegation, and scope lists.
final class SDKCapabilityTests: XCTestCase {
    func testRegistryCoversAll35Capabilities() {
        XCTAssertEqual(SDKCapabilityRegistry.all.count, 35)
        XCTAssertEqual(Set(SDKCapabilityRegistry.all.map(\.id)), Set(SDKCapabilityID.allCases))
    }

    func testGrantableFlags() {
        // Assist variants and security method scopes are never grantable.
        for id in [SDKCapabilityID.assistInvoke, .assistUI, .assistHeadless, .assistMainView,
                   .securityAddValue, .securityHasValue, .securityListValueIDs, .securityDeleteValue, .securityUseValue] {
            XCTAssertFalse(SDKCapabilityRegistry.info(for: id).grantableInCurrentRelease, "\(id) must not be grantable")
        }
        // Everything else is grantable in this release.
        XCTAssertTrue(SDKCapabilityRegistry.info(for: .docsSearch).grantableInCurrentRelease)
        XCTAssertTrue(SDKCapabilityRegistry.info(for: .buildExecute).grantableInCurrentRelease)
        XCTAssertTrue(SDKCapabilityRegistry.info(for: .useSecurity).grantableInCurrentRelease)
    }

    func testPrivilegedIsHighRiskOnly() {
        XCTAssertTrue(SDKCapabilityRegistry.isPrivileged(.buildExecute))
        XCTAssertTrue(SDKCapabilityRegistry.isPrivileged(.workspaceWrite))
        XCTAssertFalse(SDKCapabilityRegistry.isPrivileged(.docsSearch))
        // Restricted is not "privileged" — it is deny-by-default.
        XCTAssertFalse(SDKCapabilityRegistry.isPrivileged(.assistInvoke))
    }

    func testInfoForRawValue() {
        XCTAssertEqual(SDKCapabilityRegistry.info(forRawValue: "docs.search")?.title, "Documentation browser")
        XCTAssertNil(SDKCapabilityRegistry.info(forRawValue: "nope.not-a-capability"))
    }

    func testBrokerDelegatesToPermissionManager() async throws {
        let permissions = PermissionManager(grants: ["com.example.ext": [.workspaceRead]])
        let caller = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "digest", projectRootPath: "/tmp/project")
        // Granted v2 capability authorizes the mapped SDK capability.
        try await SDKCapabilityBroker.authorize(.docsSearch, for: caller, permissions: permissions)
        // An ungranted capability denies.
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
        // Key WITH the cloud entitlement authorizes without any grant.
        let entitledKey = SDKAPIKey(keyPrefix: SDKAPIKeyCodec.testPrefix, label: "x", scopes: [.appsCreate], entitlements: [.developerAIAllowsCloud])
        let entitled = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "d", projectRootPath: "/tmp/p", apiKey: entitledKey)
        try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: entitled, permissions: permissions)
        // Key WITHOUT it denies with the cloud-model code.
        let plainKey = SDKAPIKey(keyPrefix: SDKAPIKeyCodec.testPrefix, label: "x", scopes: [.appsCreate])
        let plain = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "d", projectRootPath: "/tmp/p", apiKey: plainKey)
        await XCTAssertThrowsErrorAsync(try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: plain, permissions: permissions)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .cloudModelDenied)
        }
    }

    func testBrokerRequiresScopeForPrivilegedCapabilityWithKey() async {
        let permissions = PermissionManager(grants: ["com.example.ext": [.build]])
        // Key without `capabilities:request` denies a privileged cap.
        let plainKey = SDKAPIKey(keyPrefix: SDKAPIKeyCodec.testPrefix, label: "x", scopes: [.appsCreate])
        let plain = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "d", projectRootPath: "/tmp/p", apiKey: plainKey)
        await XCTAssertThrowsErrorAsync(try await SDKCapabilityBroker.authorize(.buildExecute, for: plain, permissions: permissions)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .apiKeyScopeInsufficient)
        }
        // Key WITH the scope authorizes.
        let scopedKey = SDKAPIKey(keyPrefix: SDKAPIKeyCodec.testPrefix, label: "x", scopes: [.capabilitiesRequest])
        let scoped = SDKCallerIdentity(extensionID: "com.example.ext", packageDigest: "d", projectRootPath: "/tmp/p", apiKey: scopedKey)
        try await SDKCapabilityBroker.authorize(.buildExecute, for: scoped, permissions: permissions)
    }

    func testScopesListHas32Entries() {
        XCTAssertEqual(ScopesIDLists.all.count, 32)
        XCTAssertEqual(ScopesIDLists.all.filter { $0.kind == .view }.count, 12)
        XCTAssertEqual(ScopesIDLists.all.filter { $0.kind == .api }.count, 20)
        // `use.Security` and `assist.main` are umbrella/entitlement
        // surfaces, not separately requestable scopes.
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
