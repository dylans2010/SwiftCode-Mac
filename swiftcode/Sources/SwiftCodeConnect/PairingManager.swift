import Foundation
import os.log

public struct PendingPairingRequest: Identifiable, Sendable {
    public let id: UUID
    public let deviceID: String
    public let deviceName: String
    public let deviceModel: String
    public let clientVersion: String
    public let verificationCode: String
    public let timestamp: Date

    public init(id: UUID = UUID(), deviceID: String, deviceName: String, deviceModel: String, clientVersion: String, verificationCode: String, timestamp: Date = Date()) {
        self.id = id
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.clientVersion = clientVersion
        self.verificationCode = verificationCode
        self.timestamp = timestamp
    }
}

@Observable
@MainActor
public final class PairingManager: @unchecked Sendable {
    public static let shared = PairingManager()

    public private(set) var activePairingRequest: PendingPairingRequest?
    private var pairingContinuation: CheckedContinuation<Bool, Never>?
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "PairingManager")

    private init() {}

    public func requestPairing(_ request: PendingPairingRequest) async -> Bool {
        if let existing = pairingContinuation {
            existing.resume(returning: false)
            pairingContinuation = nil
        }

        self.activePairingRequest = request
        logger.info("New pairing request received from \(request.deviceName) (\(request.deviceModel))")

        return await withCheckedContinuation { continuation in
            self.pairingContinuation = continuation
        }
    }

    public func approvePairing() {
        guard let request = activePairingRequest else { return }

        let trusted = TrustedDevice(
            id: request.deviceID,
            name: request.deviceName,
            model: request.deviceModel,
            pairingDate: Date(),
            lastConnection: Date(),
            sessionToken: UUID().uuidString,
            permissions: ConnectPermission.allCases,
            isRevoked: false
        )

        TrustStore.shared.registerDevice(trusted)
        logger.info("Pairing approved for \(request.deviceName)")

        pairingContinuation?.resume(returning: true)
        pairingContinuation = nil
        activePairingRequest = nil
    }

    public func declinePairing() {
        guard let request = activePairingRequest else { return }
        logger.info("Pairing declined for \(request.deviceName)")

        pairingContinuation?.resume(returning: false)
        pairingContinuation = nil
        activePairingRequest = nil
    }
}
