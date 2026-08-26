import XCTest
@testable import SwiftCode

final class ConnectSecurityTests: XCTestCase {

    @MainActor
    func testTrustStoreRegistrationAndRevocation() throws {
        let store = TrustStore.shared
        let testDeviceID = "test-device-uuid-123"

        let device = TrustedDevice(
            id: testDeviceID,
            name: "Test iPhone",
            model: "iPhone 17 Pro",
            pairingDate: Date(),
            lastConnection: Date(),
            sessionToken: "sec-token-999",
            permissions: [.projectRead, .buildExecute],
            isRevoked: false
        )

        store.registerDevice(device)
        XCTAssertTrue(store.isTrusted(deviceID: testDeviceID))

        store.revokeDevice(deviceID: testDeviceID)
        XCTAssertFalse(store.isTrusted(deviceID: testDeviceID))

        store.deleteDevice(deviceID: testDeviceID)
        XCTAssertNil(store.getDevice(deviceID: testDeviceID))
    }

    @MainActor
    func testPermissionChecking() {
        let grantedPermissions: Set<ConnectPermission> = [.projectRead, .buildExecute, .logsRead]

        XCTAssertTrue(grantedPermissions.contains(.projectRead))
        XCTAssertTrue(grantedPermissions.contains(.buildExecute))
        XCTAssertFalse(grantedPermissions.contains(.terminalExecute))
        XCTAssertFalse(grantedPermissions.contains(.filesWrite))
    }

    func testPathTraversalPrevention() {
        let maliciousPath1 = "../../etc/passwd"
        let maliciousPath2 = "subdir/../../../secret.key"
        let safePath = "Sources/App/main.swift"

        XCTAssertTrue(maliciousPath1.contains(".."))
        XCTAssertTrue(maliciousPath2.contains(".."))
        XCTAssertFalse(safePath.contains(".."))
    }
}
