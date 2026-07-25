import Foundation
import CloudKit
import os.log

public enum ICloudAccountStatus: String, Codable, Sendable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
}

public final class ICloudKitService: @unchecked Sendable {
    public static let shared = ICloudKitService()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "ICloudKit")

    public var accountStatus: ICloudAccountStatus = .couldNotDetermine
    public var currentAppleAccount: String? = nil

    private let container: CKContainer

    private init() {
        // Initialize private container. If custom container is not configured in entitlements,
        // it gracefully falls back to the default container for the active bundle ID.
        self.container = CKContainer.default()

        Task {
            await checkAccountStatus()
        }
    }

    public func checkAccountStatus() async {
        logger.info("Checking iCloud account status...")
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                self.accountStatus = .available
                // Retrieve active user record name
                if let userId = try? await container.userRecordID() {
                    self.currentAppleAccount = userId.recordName
                } else {
                    self.currentAppleAccount = "iCloud User"
                }
                logger.info("iCloud account is available. User record: \(self.currentAppleAccount ?? "Unknown", privacy: .public)")
            case .noAccount:
                self.accountStatus = .noAccount
                self.currentAppleAccount = nil
                logger.warning("No iCloud account is signed in on this device.")
            case .restricted:
                self.accountStatus = .restricted
                self.currentAppleAccount = nil
                logger.warning("iCloud access is restricted on this device.")
            case .couldNotDetermine:
                self.accountStatus = .couldNotDetermine
                self.currentAppleAccount = nil
                logger.warning("Could not determine iCloud account status.")
            @unknown default:
                self.accountStatus = .couldNotDetermine
                self.currentAppleAccount = nil
            }
        } catch {
            logger.error("Failed to query iCloud account status: \(error.localizedDescription, privacy: .public)")
            self.accountStatus = .couldNotDetermine
            self.currentAppleAccount = nil
        }
    }

    public func getAccountStatus() async -> ICloudAccountStatus {
        await checkAccountStatus()
        return accountStatus
    }

    public func fetchUserRecordID() async throws -> CKRecord.ID {
        try await container.userRecordID()
    }
}
