import Foundation

public enum AppError: Error, LocalizedError {
    case fileSystemError(String)
    case gitError(String)
    case buildError(String)
    case aiError(String)
    case securityError(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .fileSystemError(let msg): return "File System Error: \(msg)"
        case .gitError(let msg): return "Git Error: \(msg)"
        case .buildError(let msg): return "Build Error: \(msg)"
        case .aiError(let msg): return "AI Error: \(msg)"
        case .securityError(let msg): return "Security Error: \(msg)"
        case .unknown(let msg): return "Unknown Error: \(msg)"
        }
    }
}
