import Foundation
import Network
import os.log

public struct TrustedDevice: Codable, Identifiable, Sendable {
    public let id: String // deviceID
    public var name: String
    public var model: String
    public var pairingDate: Date
    public var lastConnection: Date
    public var sessionToken: String
    public var permissions: [ConnectPermission]
    public var isRevoked: Bool

    public init(id: String, name: String, model: String, pairingDate: Date = Date(), lastConnection: Date = Date(), sessionToken: String = UUID().uuidString, permissions: [ConnectPermission] = ConnectPermission.allCases, isRevoked: Bool = false) {
        self.id = id
        self.name = name
        self.model = model
        self.pairingDate = pairingDate
        self.lastConnection = lastConnection
        self.sessionToken = sessionToken
        self.permissions = permissions
        self.isRevoked = isRevoked
    }
}

@Observable
@MainActor
public final class TrustStore: @unchecked Sendable {
    public static let shared = TrustStore()

    private static let keychainKey = "com.swiftcode.connect.trusted_devices"
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "TrustStore")

    public private(set) var trustedDevices: [TrustedDevice] = []

    private init() {
        loadTrustedDevices()
    }

    public func loadTrustedDevices() {
        if let jsonString = KeychainService.shared.get(forKey: Self.keychainKey),
           let data = jsonString.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let devices = try? decoder.decode([TrustedDevice].self, from: data) {
                self.trustedDevices = devices
                return
            }
        }
        self.trustedDevices = []
    }

    private func saveTrustedDevices() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(trustedDevices),
           let jsonString = String(data: data, encoding: .utf8) {
            KeychainService.shared.set(jsonString, forKey: Self.keychainKey)
        }
    }

    public func isTrusted(deviceID: String) -> Bool {
        guard let device = trustedDevices.first(where: { $0.id == deviceID }) else { return false }
        return !device.isRevoked
    }

    public func getDevice(deviceID: String) -> TrustedDevice? {
        trustedDevices.first(where: { $0.id == deviceID })
    }

    public func registerDevice(_ device: TrustedDevice) {
        if let index = trustedDevices.firstIndex(where: { $0.id == device.id }) {
            trustedDevices[index] = device
        } else {
            trustedDevices.append(device)
        }
        saveTrustedDevices()
        logger.info("Registered/updated trusted device: \(device.name) (\(device.id))")
    }

    public func updateLastConnection(deviceID: String) {
        if let index = trustedDevices.firstIndex(where: { $0.id == deviceID }) {
            trustedDevices[index].lastConnection = Date()
            saveTrustedDevices()
        }
    }

    public func revokeDevice(deviceID: String) {
        if let index = trustedDevices.firstIndex(where: { $0.id == deviceID }) {
            trustedDevices[index].isRevoked = true
            saveTrustedDevices()
            logger.info("Revoked trust for device: \(deviceID)")
        }
    }

    public func deleteDevice(deviceID: String) {
        trustedDevices.removeAll(where: { $0.id == deviceID })
        saveTrustedDevices()
        logger.info("Deleted trusted device: \(deviceID)")
    }

    public func updatePermissions(deviceID: String, permissions: [ConnectPermission]) {
        if let index = trustedDevices.firstIndex(where: { $0.id == deviceID }) {
            trustedDevices[index].permissions = permissions
            saveTrustedDevices()
        }
    }
}
