import Foundation

public enum ExtV2ResourceLimits {
    public static let maxVSIXBytes: Int = 200 * 1024 * 1024
    public static let maxExtractedBytes: Int = 1024 * 1024 * 1024
    public static let maxArchiveEntries: Int = 10_000
    public static let maxIPCMessageBytes: Int = 1024 * 1024
    public static let hostActivationTimeout: TimeInterval = 30
    public static let hostCommandTimeout: TimeInterval = 60
    public static let registryTimeout: TimeInterval = 30
    public static let maxConsecutiveHostCrashes: Int = 3
}
