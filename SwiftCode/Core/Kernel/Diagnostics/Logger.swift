import Foundation

public enum KernelError: Error, LocalizedError {
    case serviceNotFound(String)
    case moduleNotFound(String)
    case initializationFailed(String)
    case circularDependencyDetected(String)

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound(let id): return "Service not found: \(id)"
        case .moduleNotFound(let id): return "Module not found: \(id)"
        case .initializationFailed(let msg): return "Initialization failed: \(msg)"
        case .circularDependencyDetected(let id): return "Circular dependency detected: \(id)"
        }
    }
}

/// Simple internal logger for the Kernel until a better one is resolved.
public struct LoggingTool {
    public static func info(_ msg: String) {
        print("[INFO] \(msg)")
    }
    public static func error(_ msg: String) {
        print("[ERROR] \(msg)")
    }
    public static func warn(_ msg: String) {
        print("[WARN] \(msg)")
    }
}
