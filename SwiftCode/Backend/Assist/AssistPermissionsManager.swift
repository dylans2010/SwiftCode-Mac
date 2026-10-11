import Foundation

public final class AssistPermissionsManager: @unchecked Sendable, AssistPermissionsManagerProtocol {
    private var allowedPaths: Set<String> = []
    private var blockedPaths: Set<String> = []
    public var requiresApproval: Bool = false
    public var isApproved: Bool = true
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

    public func authorizeOperation(_ operation: String) -> Bool {
        let op = operation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let meta = AssistToolRouter.shared.metadata(for: op)
        let isHighRisk = meta.riskLevel >= .potentiallyDestructive || meta.riskLevel == .externalSideEffect

        let destructiveToolIds: Set<String> = [
            "file_delete", "dir_delete", "directory_delete", "delete_file", "delete_directory",
            "use_mcp", "use_composio"
        ]
        let tokens = op.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let destructiveKeywords: Set<String> = ["delete", "remove", "rm", "drop", "truncate", "destroy", "wipe"]

        let isDestructive = destructiveToolIds.contains(op) || tokens.contains(where: { destructiveKeywords.contains($0) }) || isHighRisk
        if isDestructive {
            if requiresApproval {
                return isApproved
            }
        }
        return true
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
