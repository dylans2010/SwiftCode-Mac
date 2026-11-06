// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Local Building/Connectivity/TrustStore.swift
// Adapted for SwiftCode: Legacy KeychainService replaced by SwiftCodeAssistant's SecretStore (same Keychain-backed store Wave 12 uses).

import Foundation
import Network
import os.log

import SwiftCodeAssistant

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

    /// SecretStore account holding the trusted-devices JSON. Legacy kept
    /// this in Legacy's own KeychainService; SwiftCode uses SwiftCodeAssistant's
    /// SecretStore (Keychain on macOS), which is the same store Wave 12's
    /// cloud code uses.
    private static let storeAccount = "swiftcode.connect.trusted-devices"
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "TrustStore")

    public private(set) var trustedDevices: [TrustedDevice] = []

    private init() {
        loadTrustedDevices()
    }

    public func loadTrustedDevices() {
        let store = defaultSecretStore()
        if let devices = store.readJSON([TrustedDevice].self, Self.storeAccount) {
            self.trustedDevices = devices
            return
        }
        self.trustedDevices = []
    }

    private func saveTrustedDevices() {
        let store = defaultSecretStore()
        try? store.writeJSON(trustedDevices, for: Self.storeAccount)
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
