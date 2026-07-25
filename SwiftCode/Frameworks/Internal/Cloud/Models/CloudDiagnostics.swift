import Foundation

public struct CloudDiagnostics: Codable, Sendable {
    public let isOnline: Bool
    public let activeProvider: CloudProviderType
    public let lastSuccessfulSync: Date?
    public let lastFailedSync: Date?
    public let pendingUploads: Int
    public let pendingDownloads: Int
    public let syncErrorCount: Int
    public let connectionLatencyMs: Double

    public init(isOnline: Bool, activeProvider: CloudProviderType, lastSuccessfulSync: Date?, lastFailedSync: Date?, pendingUploads: Int, pendingDownloads: Int, syncErrorCount: Int, connectionLatencyMs: Double) {
        self.isOnline = isOnline
        self.activeProvider = activeProvider
        self.lastSuccessfulSync = lastSuccessfulSync
        self.lastFailedSync = lastFailedSync
        self.pendingUploads = pendingUploads
        self.pendingDownloads = pendingDownloads
        self.syncErrorCount = syncErrorCount
        self.connectionLatencyMs = connectionLatencyMs
    }
}
