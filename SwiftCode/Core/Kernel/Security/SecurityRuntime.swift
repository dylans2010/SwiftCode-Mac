import Foundation

/// Manages runtime security, capability validation, and permission registry.
public actor SecurityRuntime: KernelService {
    public let id = "com.swiftcode.kernel.security"

    private var permissions: [String: Set<String>] = [:]

    public init() {}

    public func initialize() async throws {
        print("[Security] Security Runtime initialized.")
    }

    public func grantPermission(_ permission: String, to componentId: String) {
        var existing = permissions[componentId] ?? []
        existing.insert(permission)
        permissions[componentId] = existing
    }

    public func validatePermission(_ permission: String, for componentId: String) throws {
        guard permissions[componentId]?.contains(permission) == true else {
            throw SecurityError.permissionDenied(permission, componentId)
        }
    }
}

public enum SecurityError: Error, LocalizedError {
    case permissionDenied(String, String)
    case integrityCheckFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let p, let c): return "Permission '\(p)' denied for component '\(c)'"
        case .integrityCheckFailed(let msg): return "Integrity check failed: \(msg)"
        }
    }
}
