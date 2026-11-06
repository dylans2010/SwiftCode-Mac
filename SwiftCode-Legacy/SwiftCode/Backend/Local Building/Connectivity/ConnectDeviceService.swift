import Foundation
import os.log

@MainActor
public final class ConnectDeviceService: @unchecked Sendable {
    public static let shared = ConnectDeviceService()
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectDeviceService")

    private init() {}

    public func registerHandlers() {
        ConnectServer.shared.registerHandler(for: .deviceListRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.deviceRead) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing device.read permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.handleDeviceListRequest(envelope: envelope, session: session)
        }
    }

    private func handleDeviceListRequest(envelope: MessageEnvelope, session: ConnectionSession) async {
        let devices = DeviceManager.shared.devices.map { device in
            ConnectDeviceItem(
                id: device.id,
                name: device.name,
                model: device.model,
                platform: device.platform,
                osVersion: device.osVersion,
                isConnected: device.isConnected
            )
        }

        let payload = ConnectDeviceListResponsePayload(devices: devices)
        if let respEnv = try? MessageEnvelope.encode(payload: payload, type: .deviceListResponse, correlationID: envelope.messageID) {
            try? session.send(envelope: respEnv)
        }
    }
}
