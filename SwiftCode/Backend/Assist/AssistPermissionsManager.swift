import Foundation

public final class AssistPermissionsManager: @unchecked Sendable, AssistPermissionsManagerProtocol {
    private var allowedPaths: Set<String> = []
    private var blockedPaths: Set<String> = []
    public var requiresApproval: Bool = false
    public var isApproved: Bool = true
    private let lock = NSLock()

    public static let isolatedScriptsDirectory = "/tmp/swiftcode/scripts"

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

        // Ensure the isolated scripts directory exists
        try? FileManager.default.createDirectory(atPath: Self.isolatedScriptsDirectory, withIntermediateDirectories: true)
    }

    public func isAutopilotActive() -> Bool {
        let modeRaw = UserDefaults.standard.string(forKey: "com.swiftcode.assist.executionMode") ?? ExecutionMode.autopilot.rawValue
        return modeRaw.lowercased() == ExecutionMode.autopilot.rawValue
    }

    public func isPathAllowed(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Always allow the isolated scripts directory
        if path.hasPrefix(Self.isolatedScriptsDirectory) {
            return true
        }

        // In Autopilot mode, bypass sandbox path restrictions outside of critical OS system kernels
        if isAutopilotActive() {
            if path.contains("..") { return false }
            if path.hasPrefix("/System/") || path.hasPrefix("/sbin/") { return false }
            return true
        }

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
        // When Assist is on Autopilot, BYPASS the permissions COMPLETELY at a system level (SwiftCode, not macOS)
        if isAutopilotActive() {
            return true
        }

        let op = operation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let meta = AssistToolRouter.metadata(for: op)
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
