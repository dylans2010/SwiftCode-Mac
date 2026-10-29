import Foundation

// MARK: - Resource limits (security controls, not tuning knobs)
//
// These bounds are enforced in PackageService, RPC, and HostManager.
// Raising them needs a reason in Docs/Extensions-v2.md, not a quiet edit.
public enum ExtV2ResourceLimits {
    /// Largest VSIX accepted (200 MB). Larger packages are rejected before
    /// any extraction, so a decompression bomb cannot start expanding.
    public static let maxVSIXBytes: Int = 200 * 1024 * 1024
    /// Largest total extracted size (1 GB) across all entries.
    public static let maxExtractedBytes: Int = 1024 * 1024 * 1024
    /// Largest number of entries in one archive.
    public static let maxArchiveEntries: Int = 10_000
    /// Largest single IPC message (1 MB). Larger messages are dropped and
    /// the host is faulted, not truncated and misinterpreted.
    public static let maxIPCMessageBytes: Int = 1024 * 1024
    /// How long a host activation or a single command may run.
    public static let hostActivationTimeout: TimeInterval = 30
    public static let hostCommandTimeout: TimeInterval = 60
    /// How long a registry request may take before it is a user-visible error.
    public static let registryTimeout: TimeInterval = 30
    /// Crash-restart backoff: a host that crashes this many times in a row
    /// is left stopped until the user retries it manually.
    public static let maxConsecutiveHostCrashes: Int = 3
}
