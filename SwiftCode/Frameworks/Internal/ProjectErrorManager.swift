import Foundation

public final class ProjectErrorManager: Sendable {
    public static let shared = ProjectErrorManager()
    private init() {}

    public enum ProjectError: LocalizedError {
        case manifestMissing
        case corruptedPackage(String)
        case invalidFormat(String)
        case versionIncompatible(Int, Int)
        case securityFailure(String)
        case ioError(Error)

        public var errorDescription: String? {
            switch self {
            case .manifestMissing: return "The project manifest is missing."
            case .corruptedPackage(let msg): return "The project package is corrupted: \(msg)"
            case .invalidFormat(let msg): return "Invalid file format: \(msg)"
            case .versionIncompatible(let current, let required): return "Version mismatch: project requires version \(required), but only \(current) is supported."
            case .securityFailure(let msg): return "Security verification failed: \(msg)"
            case .ioError(let error): return "File system error: \(error.localizedDescription)"
            }
        }
    }

    public func logError(_ error: Error) {
        print("[ProjectErrorManager] Error: \(error.localizedDescription)")
    }
}
