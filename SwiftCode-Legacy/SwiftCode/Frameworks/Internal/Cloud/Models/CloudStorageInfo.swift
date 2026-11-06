import Foundation

public struct CloudStorageInfo: Codable, Sendable, Equatable {
    public let usedBytes: Int64
    public let limitBytes: Int64
    public let activeBuckets: [String]

    public var usagePercentage: Double {
        guard limitBytes > 0 else { return 0.0 }
        return Double(usedBytes) / Double(limitBytes) * 100.0
    }

    public init(usedBytes: Int64 = 0, limitBytes: Int64 = 5 * 1024 * 1024 * 1024, activeBuckets: [String] = []) { // Default 5GB
        self.usedBytes = usedBytes
        self.limitBytes = limitBytes
        self.activeBuckets = activeBuckets
    }
}
