import XCTest
@testable import SwiftCode

final class ConnectDiscoveryTests: XCTestCase {

    func testDiscoveredIOSDeviceModel() {
        let txtRecord: [String: String] = [
            "txtvers": "1",
            "proto": "1",
            "deviceName": "iPhone 17 Pro",
            "deviceID": "ios-device-uuid-456",
            "deviceType": "iOS",
            "port": "47124",
            "caps": "project,build,logs,assist",
            "appVers": "1.0"
        ]

        let device = DiscoveredIOSDevice(
            id: txtRecord["deviceID"] ?? "unknown",
            name: txtRecord["deviceName"] ?? "iPhone",
            host: "192.168.1.40",
            port: 47124,
            protocolVersion: txtRecord["proto"] ?? "1",
            capabilities: (txtRecord["caps"] ?? "").components(separatedBy: ","),
            deviceType: txtRecord["deviceType"] ?? "iOS",
            isAvailable: true,
            lastSeen: Date(),
            txtRecord: txtRecord
        )

        XCTAssertEqual(device.id, "ios-device-uuid-456")
        XCTAssertEqual(device.name, "iPhone 17 Pro")
        XCTAssertEqual(device.host, "192.168.1.40")
        XCTAssertEqual(device.port, 47124)
        XCTAssertEqual(device.endpointDisplay, "192.168.1.40:47124")
        XCTAssertEqual(device.protocolVersion, "1")
        XCTAssertEqual(device.deviceType, "iOS")
        XCTAssertTrue(device.capabilities.contains("build"))
        XCTAssertTrue(device.capabilities.contains("logs"))
    }

    func testHandshakeMessageEncoding() throws {
        let handshake = ConnectHandshakePayload(
            deviceID: "mac-uuid-123",
            deviceType: .macOS,
            deviceName: "Dylan’s Mac Studio",
            protocolVersion: 1,
            appVersion: "1.0",
            supportedCapabilities: ConnectCapability.allCases,
            listeningPort: 47123
        )

        let envelope = try MessageEnvelope.encode(payload: handshake, type: .handshake)
        let decoded = try envelope.decodePayload(ConnectHandshakePayload.self)

        XCTAssertEqual(decoded.deviceID, "mac-uuid-123")
        XCTAssertEqual(decoded.deviceType, .macOS)
        XCTAssertEqual(decoded.deviceName, "Dylan’s Mac Studio")
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.listeningPort, 47123)
    }

    func testPortUpdateNoticeEncoding() throws {
        let notice = ConnectPortUpdateNoticePayload(deviceID: "mac-uuid-123", newPort: 47125)
        let envelope = try MessageEnvelope.encode(payload: notice, type: .portUpdateNotice)
        let decoded = try envelope.decodePayload(ConnectPortUpdateNoticePayload.self)

        XCTAssertEqual(decoded.deviceID, "mac-uuid-123")
        XCTAssertEqual(decoded.newPort, 47125)
    }
}
