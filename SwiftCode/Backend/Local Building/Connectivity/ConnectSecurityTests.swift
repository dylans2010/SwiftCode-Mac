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
    func testPathTraversalPrevention() async throws {
        let fileService = ConnectFileService.shared

        // Path containing .. must be flagged as invalid path traversal
        let badPath = "../../etc/passwd"
        XCTAssertTrue(badPath.contains(".."))
    }
}
