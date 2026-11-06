import Foundation

/// Represents a point-in-time backup instance metadata structure.
public struct BackupManifest: Codable, Sendable, Identifiable, Equatable {
    public var id: String { backupID }
    public let backupID: String
    public let createdAt: Date
    public let sizeInBytes: Int64
    public let filename: String
    public let isCloudStored: Bool
    public let appVersion: String
    public let deviceName: String

    public init(
        backupID: String = UUID().uuidString,
        createdAt: Date = Date(),
        sizeInBytes: Int64,
        filename: String,
        isCloudStored: Bool,
        appVersion: String = "1.0.0",
        deviceName: String = Host.current().localizedName ?? "macOS Device"
    ) {
        self.backupID = backupID
        self.createdAt = createdAt
        self.sizeInBytes = sizeInBytes
        self.filename = filename
        self.isCloudStored = isCloudStored
        self.appVersion = appVersion
        self.deviceName = deviceName
    }
}

/// Holds information about individual files included in the snapshot.
public struct BackupEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: String { relativePath }
    public let relativePath: String
    public let fileHash: String
    public let sizeInBytes: Int64

    public init(relativePath: String, fileHash: String, sizeInBytes: Int64) {
        self.relativePath = relativePath
        self.fileHash = fileHash
        self.sizeInBytes = sizeInBytes
    }
}

/// Unified result payload returned upon successful state restoration.
public struct RestoreResult: Codable, Sendable, Equatable {
    public let isSuccess: Bool
    public let restoredFileCount: Int
    public let errorMessage: String?

    public init(isSuccess: Bool, restoredFileCount: Int = 0, errorMessage: String? = nil) {
        self.isSuccess = isSuccess
        self.restoredFileCount = restoredFileCount
        self.errorMessage = errorMessage
    }
}
