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

    func testSyncStatePayloadEncodingAndDecoding() throws {
        let project = ConnectProjectInfo(
            id: "proj-123",
            name: "SwiftCode",
            path: "/path/to/project",
            activeScheme: "SwiftCode",
            activeTarget: "SwiftCode",
            destinations: ["macOS"],
            swiftVersion: "6.0"
        )

        let syncPayload = ConnectSyncStatePayload(
            activeProject: project,
            availableProjects: [project],
            gitStatus: nil,
            currentBuildState: "idle",
            capabilities: ConnectCapability.allCases,
            permissions: ConnectPermission.allCases
        )

        let envelope = try MessageEnvelope.encode(payload: syncPayload, type: .syncStateResponse)
        let decoded = try envelope.decodePayload(ConnectSyncStatePayload.self)

        XCTAssertEqual(decoded.activeProject?.name, "SwiftCode")
        XCTAssertEqual(decoded.availableProjects.count, 1)
        XCTAssertEqual(decoded.currentBuildState, "idle")
        XCTAssertEqual(decoded.capabilities.count, ConnectCapability.allCases.count)
    }
}
