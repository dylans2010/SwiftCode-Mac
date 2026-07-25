import Foundation

public struct SyncMetrics: Codable, Sendable {
    public let bytesUploaded: UInt64
    public let bytesDownloaded: UInt64
    public let uploadCount: UInt32
    public let downloadCount: UInt32
    public let conflictCount: UInt32
    public let failureCount: UInt32

    public init(bytesUploaded: UInt64, bytesDownloaded: UInt64, uploadCount: UInt32, downloadCount: UInt32, conflictCount: UInt32, failureCount: UInt32) {
        self.bytesUploaded = bytesUploaded
        self.bytesDownloaded = bytesDownloaded
        self.uploadCount = uploadCount
        self.downloadCount = downloadCount
        self.conflictCount = conflictCount
        self.failureCount = failureCount
    }
}

public protocol CloudStatistics: AnyObject, Sendable {
    func getMetrics() async -> SyncMetrics
    func incrementUpload(bytes: UInt64) async
    func incrementDownload(bytes: UInt64) async
    func incrementConflict() async
    func incrementFailure() async
    func reset() async
}
