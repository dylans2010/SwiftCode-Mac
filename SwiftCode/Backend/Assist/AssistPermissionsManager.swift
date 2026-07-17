import Foundation

// Thread-safe permissions manager synchronized with NSLock
public final class AssistPermissionsManager: @unchecked Sendable, AssistPermissionsManagerProtocol {
    private var allowedPaths: Set<String> = []
    private var blockedPaths: Set<String> = []
    private var requiresApproval: Bool = false
    private let lock = NSLock()

    public init() {
        // Initialize with default safe paths if needed
    }

    public func isPathAllowed(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // Simple implementation for now
        if blockedPaths.contains(path) { return false }
        // In a real app, check if it's within the project directory
        return true
    }

    public func authorizeOperation(_ operation: String) -> Bool {
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
