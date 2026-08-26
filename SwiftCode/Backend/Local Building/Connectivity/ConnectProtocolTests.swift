import XCTest
@testable import SwiftCode

final class ConnectProtocolTests: XCTestCase {

    func testEnvelopeEncodingAndDecoding() throws {
        let payload = ConnectBuildRequestPayload(projectID: "test-proj", scheme: "SwiftCode", configuration: "Debug", destinationSDK: "macOS")
        let envelope = try MessageEnvelope.encode(payload: payload, type: .buildRequest, correlationID: "corr-123")

        XCTAssertEqual(envelope.protocolVersion, ConnectProtocolVersion.current)
        XCTAssertEqual(envelope.type, .buildRequest)
        XCTAssertEqual(envelope.correlationID, "corr-123")

        let decodedPayload = try envelope.decodePayload(ConnectBuildRequestPayload.self)
        XCTAssertEqual(decodedPayload.projectID, "test-proj")
        XCTAssertEqual(decodedPayload.scheme, "SwiftCode")
        XCTAssertEqual(decodedPayload.configuration, "Debug")
        XCTAssertEqual(decodedPayload.destinationSDK, "macOS")
    }

    func testPairingResponseEncoding() throws {
        let payload = ConnectPairingResponsePayload(
            approved: true,
            macName: "Dylan's Mac",
            sessionToken: "token-abc",
            verificationCode: "123456",
            capabilities: ConnectCapability.allCases,
            grantedPermissions: ConnectPermission.allCases
        )

        let envelope = try MessageEnvelope.encode(payload: payload, type: .pairingResponse)
        let decoded = try envelope.decodePayload(ConnectPairingResponsePayload.self)

        XCTAssertTrue(decoded.approved)
        XCTAssertEqual(decoded.macName, "Dylan's Mac")
        XCTAssertEqual(decoded.sessionToken, "token-abc")
        XCTAssertEqual(decoded.capabilities.count, ConnectCapability.allCases.count)
    }
}
