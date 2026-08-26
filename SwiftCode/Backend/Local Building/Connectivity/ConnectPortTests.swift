import XCTest
@testable import SwiftCode

final class ConnectPortTests: XCTestCase {

    func testPortRangeValidation() {
        XCTAssertTrue(ConnectProtocol.validPortRange.contains(47123))
        XCTAssertTrue(ConnectProtocol.validPortRange.contains(1024))
        XCTAssertTrue(ConnectProtocol.validPortRange.contains(65535))

        XCTAssertFalse(ConnectProtocol.validPortRange.contains(80))
        XCTAssertFalse(ConnectProtocol.validPortRange.contains(443))
        XCTAssertFalse(ConnectProtocol.validPortRange.contains(0))
    }

    @MainActor
    func testPortConfigurationDefault() {
        let server = ConnectServer.shared
        XCTAssertTrue(ConnectProtocol.validPortRange.contains(server.configuredPort))
    }

    func testErrorPayloadMapping() {
        let error = ConnectErrorPayload(
            errorCode: .portUnavailable,
            message: "SwiftCode could not listen on port 47123. The port may already be in use.",
            details: "Address in use (POSIX 48)"
        )

        XCTAssertEqual(error.code, ConnectErrorCode.portUnavailable.rawValue)
        XCTAssertTrue(error.message.contains("47123"))
        XCTAssertEqual(error.details, "Address in use (POSIX 48)")
    }
}
