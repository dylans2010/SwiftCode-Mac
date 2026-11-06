import XCTest
@testable import YcodeSDK
import YcodeExtensions

// NOTE: No Swift toolchain exists in this environment, so these tests
// have NOT been compiled or run — statically verified only. On Dylan's
// Mac: run with `swift test --filter SDKGrantStoreTests`.
//
// Tests for `SDKGrantStore` (Wave 15, S-2): the grant-record store in
// YcodeSDK. Every test uses an injected temporary `storeURL`, so no
// test touches the real grants file. The store is a faithful port of
// Legacy `SwiftCode/SDK/Host/CapabilityBroker/Grants/SDKGrantStore.swift`
// (Dylan's own code; direct port authorised under MIT), with one Ycode
// addition: `recordRevocation`, which appends a tombstone for a grant
// that lives only in the flat `PermissionManager` store.

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

    // MARK: - Record + lookup

    func testRecordGrantsAndActiveGrantLookup() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        try await store.recordGrants([record()])
        let found = await store.activeGrant(
            extensionID: testExtensionID, capability: .workspaceRead, projectRootPath: "/tmp/TestProject")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.extensionID, testExtensionID)
        XCTAssertEqual(found?.packageDigest, testDigest)

        // A different project scope does not authorize.
        let otherScope = await store.activeGrant(
            extensionID: testExtensionID, capability: .workspaceRead, projectRootPath: "/tmp/OtherProject")
        XCTAssertNil(otherScope)

        // A different capability does not authorize.
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

    // MARK: - Revocation tombstones

    func testRevokeStampsTombstoneAndKeepsRecord() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        try await store.recordGrants([record()])
        try await store.revoke(extensionID: testExtensionID, capability: .workspaceRead)

        // The record is KEPT, with revokedAt stamped — it is a tombstone,
        // not a deletion.
        let all = await store.grants(for: testExtensionID)
        XCTAssertEqual(all.count, 1)
        XCTAssertNotNil(all[0].revokedAt)
        XCTAssertFalse(all[0].isActive())

        // And it no longer authorizes.
        let found = await store.activeGrant(
            extensionID: testExtensionID, capability: .workspaceRead, projectRootPath: "/tmp/TestProject")
        XCTAssertNil(found)
    }

    func testRevokeIsIdempotent() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        try await store.recordGrants([record()])
        try await store.revoke(extensionID: testExtensionID, capability: .workspaceRead)
        // Revoking again, and revoking an unknown capability, are no-op
        // successes.
        try await store.revoke(extensionID: testExtensionID, capability: .workspaceRead)
        try await store.revoke(extensionID: testExtensionID, capability: .buildExecute)
        XCTAssertEqual(await store.grants(for: testExtensionID).count, 1)
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
        // No record exists yet — the grant lives only in the flat store.
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
        // A flat grant is not project-scoped: the empty scope never
        // authorizes, so the tombstone can never be mistaken for a grant.
        XCTAssertEqual(all[0].scope.projectRootPath, "")
        XCTAssertNil(await store.activeGrant(
            extensionID: testExtensionID, capability: .workspaceRead, projectRootPath: "/tmp/TestProject"))
    }

    // MARK: - Expiry pruning

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
        // Long-expired is dropped; recently-expired, revoked, and
        // never-expiring records are kept.
        XCTAssertEqual(Set(remaining.map(\.capability)),
                       [.workspaceWrite, .buildExecute, .sourceControlRead])
    }

    // MARK: - Key-scope gate

    func testPrivilegedGrantWithoutCapabilitiesRequestScopeIsRejected() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        // A real key WITHOUT the `capabilities:request` scope.
        let key = SDKAPIKey(
            keyPrefix: SDKAPIKeyCodec.testPrefix,
            label: "SDKTest-grant-store",
            scopes: [.appsCreate],
            entitlements: []
        )
        // `.workspaceWrite` is privileged (risk .high).
        do {
            try await store.recordGrants(
                [record(capability: .workspaceWrite)],
                authorizedByAPIKey: key
            )
            XCTFail("privileged grant must fail without the capabilities:request scope")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .apiKeyScopeInsufficient)
        }
        // Fail closed: NOTHING was persisted.
        XCTAssertTrue(await store.grants(for: testExtensionID).isEmpty)
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
        XCTAssertEqual(await store.grants(for: testExtensionID).count, 1)
    }

    func testNonPrivilegedGrantNeedsNoScope() async throws {
        let store = SDKGrantStore(storeURL: storeURL())
        let key = SDKAPIKey(
            keyPrefix: SDKAPIKeyCodec.testPrefix,
            label: "SDKTest-grant-store",
            scopes: [.appsCreate],
            entitlements: []
        )
        // `.workspaceRead` is not privileged (risk .medium).
        try await store.recordGrants(
            [record(capability: .workspaceRead)],
            authorizedByAPIKey: key
        )
        XCTAssertEqual(await store.grants(for: testExtensionID).count, 1)
    }

    // MARK: - Corrupt file handling

    func testCorruptFileIsMovedAsideAndStoreStartsEmpty() async throws {
        let url = storeURL()
        try "this is not JSON".write(to: url, atomically: true, encoding: .utf8)
        let store = SDKGrantStore(storeURL: url)
        XCTAssertTrue(await store.grants(for: testExtensionID).isEmpty)

        // The corrupt file was moved aside (never silently deleted), and
        // the store is usable afterwards.
        let siblings = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertTrue(siblings.contains { $0.lastPathComponent.hasPrefix("SDKGrants.json.corrupt-") })
        try await store.recordGrants([record()])
        XCTAssertEqual(await store.grants(for: testExtensionID).count, 1)
    }
}
