import XCTest
@testable import SwiftCodeSDK
import SwiftCodeExtensions

final class SDKGrantStoreTests: XCTestCase {

    private let testExtensionID = "com.swiftcode.sdk.test.grant-store"
    private let testDigest = String(repeating: "a", count: 64)

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SDKGrantStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try await super.setUp()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func storeURL() -> URL {
        tempDir.appendingPathComponent("SDKGrants.json")
    }

    private func record(
        capability: SDKCapabilityID = .workspaceRead,
        scope: SDKGrantScope = SDKGrantScope(projectRootPath: "/tmp/TestProject"),
        grantedAt: Date = Date(),
        expiresAt: Date? = nil
    ) -> SDKGrantRecord {
        SDKGrantRecord(
            extensionID: testExtensionID,
            packageDigest: testDigest,
            packageVersion: "1.0.0",
            capability: capability,
            scope: scope,
            grantedAt: grantedAt,
            grantedBy: "user-approval",
            expiresAt: expiresAt
        )
    }

    func testRecordGrantsAndActiveGrantLookup() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        try await store.recordGrants([record()])
        let found = await store.activeGrant(
            extensionID: testExtensionID, capability: .workspaceRead, projectRootPath: "/tmp/TestProject")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.extensionID, testExtensionID)
        XCTAssertEqual(found?.packageDigest, testDigest)

        let otherScope = await store.activeGrant(
            extensionID: testExtensionID, capability: .workspaceRead, projectRootPath: "/tmp/OtherProject")
        XCTAssertNil(otherScope)

        let otherCapability = await store.activeGrant(
            extensionID: testExtensionID, capability: .workspaceWrite, projectRootPath: "/tmp/TestProject")
        XCTAssertNil(otherCapability)
    }

    func testGrantsForReturnsOldestFirstIncludingTombstones() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        let older = record(capability: .workspaceRead, grantedAt: Date(timeIntervalSince1970: 1_000_000))
        let newer = record(capability: .workspaceWrite, grantedAt: Date(timeIntervalSince1970: 2_000_000))
        try await store.recordGrants([newer, older])
        let all = await store.grants(for: testExtensionID)
        XCTAssertEqual(all.map(\.capability), [.workspaceRead, .workspaceWrite])
    }

    func testRevokeStampsTombstoneAndKeepsRecord() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        try await store.recordGrants([record()])
        try await store.revoke(extensionID: testExtensionID, capability: .workspaceRead)

        let all = await store.grants(for: testExtensionID)
        XCTAssertEqual(all.count, 1)
        XCTAssertNotNil(all[0].revokedAt)
        XCTAssertFalse(all[0].isActive())

        let found = await store.activeGrant(
            extensionID: testExtensionID, capability: .workspaceRead, projectRootPath: "/tmp/TestProject")
        XCTAssertNil(found)
    }

    func testRevokeIsIdempotent() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        try await store.recordGrants([record()])
        try await store.revoke(extensionID: testExtensionID, capability: .workspaceRead)
        try await store.revoke(extensionID: testExtensionID, capability: .workspaceRead)
        try await store.revoke(extensionID: testExtensionID, capability: .buildExecute)
        let grantCount = await store.grants(for: testExtensionID).count
        XCTAssertEqual(grantCount, 1)
    }

    func testRevokeAllStampsEveryRecord() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        try await store.recordGrants([
            record(capability: .workspaceRead),
            record(capability: .workspaceWrite),
        ])
        try await store.revokeAll(for: testExtensionID)
        let all = await store.grants(for: testExtensionID)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy { $0.revokedAt != nil })
        XCTAssertTrue(all.allSatisfy { !$0.isActive() })
    }

    func testRecordRevocationAppendsTombstoneForFlatOnlyGrant() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        try await store.recordRevocation(
            extensionID: testExtensionID,
            capability: .workspaceRead,
            packageDigest: testDigest,
            packageVersion: "1.0.0"
        )
        let all = await store.grants(for: testExtensionID)
        XCTAssertEqual(all.count, 1)
        XCTAssertNotNil(all[0].revokedAt)
        XCTAssertFalse(all[0].isActive())
        XCTAssertEqual(all[0].scope.projectRootPath, "")
        let active = await store.activeGrant(
            extensionID: testExtensionID, capability: .workspaceRead, projectRootPath: "/tmp/TestProject")
        XCTAssertNil(active)
    }

    func testPruneExpiredKeepsTombstonesAndDropsLongExpiredGrants() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        let longExpired = record(
            capability: .workspaceRead,
            expiresAt: Date().addingTimeInterval(-31 * 24 * 60 * 60))
        let recentlyExpired = record(
            capability: .workspaceWrite,
            expiresAt: Date().addingTimeInterval(-1 * 24 * 60 * 60))
        let revoked = record(capability: .buildExecute).revoked()
        let neverExpires = record(capability: .sourceControlRead)
        try await store.recordGrants([longExpired, recentlyExpired, revoked, neverExpires])

        try await store.pruneExpired()
        let remaining = await store.grants(for: testExtensionID)
        XCTAssertEqual(Set(remaining.map(\.capability)),
                       [.workspaceWrite, .buildExecute, .sourceControlRead])
    }

    func testPrivilegedGrantWithoutCapabilitiesRequestScopeIsRejected() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        let key = SDKAPIKey(
            keyPrefix: SDKAPIKeyCodec.testPrefix,
            label: "SDKTest-grant-store",
            scopes: [.appsCreate],
            entitlements: []
        )
        do {
            try await store.recordGrants(
                [record(capability: .workspaceWrite)],
                authorizedByAPIKey: key
            )
            XCTFail("privileged grant must fail without the capabilities:request scope")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyScopeInsufficient)
        }
        let isEmpty = await store.grants(for: testExtensionID).isEmpty
        XCTAssertTrue(isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL().path))
    }

    func testPrivilegedGrantWithScopeSucceeds() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        let key = SDKAPIKey(
            keyPrefix: SDKAPIKeyCodec.testPrefix,
            label: "SDKTest-grant-store",
            scopes: [.appsCreate, .capabilitiesRequest],
            entitlements: []
        )
        try await store.recordGrants(
            [record(capability: .workspaceWrite)],
            authorizedByAPIKey: key
        )
        let grantCount = await store.grants(for: testExtensionID).count
        XCTAssertEqual(grantCount, 1)
    }

    func testNonPrivilegedGrantNeedsNoScope() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        let key = SDKAPIKey(
            keyPrefix: SDKAPIKeyCodec.testPrefix,
            label: "SDKTest-grant-store",
            scopes: [.appsCreate],
            entitlements: []
        )
        try await store.recordGrants(
            [record(capability: .workspaceRead)],
            authorizedByAPIKey: key
        )
        let grantCount = await store.grants(for: testExtensionID).count
        XCTAssertEqual(grantCount, 1)
    }

    func testCorruptFileIsMovedAsideAndStoreStartsEmpty() async throws {
        let url = storeURL()
        try "this is not JSON".write(to: url, atomically: true, encoding: .utf8)
        let store = SDKGrantStore(storeURL: url)
        let isEmpty = await store.grants(for: testExtensionID).isEmpty
        XCTAssertTrue(isEmpty)

        let siblings = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertTrue(siblings.contains { $0.lastPathComponent.hasPrefix("SDKGrants.json.corrupt-") })
        try await store.recordGrants([record()])
        let grantCount = await store.grants(for: testExtensionID).count
        XCTAssertEqual(grantCount, 1)
    }
}
