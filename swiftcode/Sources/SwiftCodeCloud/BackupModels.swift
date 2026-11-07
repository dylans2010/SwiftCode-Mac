import Foundation

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
        appVersion: String = BackupManifest.defaultAppVersion,
        deviceName: String = ProcessInfo.processInfo.hostName
    ) {
        self.backupID = backupID
        self.createdAt = createdAt
        self.sizeInBytes = sizeInBytes
        self.filename = filename
        self.isCloudStored = isCloudStored
        self.appVersion = appVersion
        self.deviceName = deviceName
    }

    public static var defaultAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

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
