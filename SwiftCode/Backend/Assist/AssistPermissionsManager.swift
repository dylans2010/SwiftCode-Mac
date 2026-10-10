import Foundation

public final class AssistPermissionsManager: @unchecked Sendable, AssistPermissionsManagerProtocol {
    private var allowedPaths: Set<String> = []
    private var blockedPaths: Set<String> = []
    private var requiresApproval: Bool = false
    private let lock = NSLock()

    public init() {
        blockedPaths.insert("/System")
        blockedPaths.insert("/usr")
        blockedPaths.insert("/bin")
        blockedPaths.insert("/sbin")
        blockedPaths.insert("/etc")
        blockedPaths.insert("/var")
        blockedPaths.insert("/Library")
        blockedPaths.insert("/private")
        blockedPaths.insert("/dev")
        blockedPaths.insert("/tmp")
    }

    public func isPathAllowed(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if blockedPaths.contains(path) { return false }
        if path.contains("..") { return false }
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/bin/") || path.hasPrefix("/sbin/") { return false }
        if path.hasPrefix("/etc/") || path.hasPrefix("/var/") || path.hasPrefix("/Library/") || path.hasPrefix("/private/") { return false }
        if !allowedPaths.isEmpty {
            return allowedPaths.contains(path)
        }
        return true
    }

    /// Tool ids that permanently delete data. These are matched exactly (a
    /// substring match used to deny e.g. "use_terminal" and "code_format"
    /// because they contain "rm").
    public static let approvalRequiredOperations: Set<String> = ["file_delete", "dir_delete"]

    /// Returns true when the operation may run without asking the user.
    /// Returns false when it needs explicit approval; callers then route it
    /// through the approval UI rather than failing outright.
    public func authorizeOperation(_ operation: String) -> Bool {
        let normalized = operation.lowercased().replacingOccurrences(of: "-", with: "_")
        lock.lock()
        let autoApprove = !requiresApproval
        lock.unlock()
        if Self.approvalRequiredOperations.contains(normalized) {
            return false
        }
        // `use_terminal` has its own per-command approval inside the tool.
        return autoApprove || !normalized.contains("delete")
    }

    /// Requires approval for every operation whose id mentions deletion, in
    /// addition to the always-gated destructive tools.
    public func setRequiresApproval(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        requiresApproval = value
    }

    public func blockPath(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        blockedPaths.insert(path)
    }

    public func allowPath(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        allowedPaths.insert(path)
    }
}
