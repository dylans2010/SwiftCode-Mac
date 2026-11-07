import Foundation

public enum AssistAPIError: LocalizedError {
    case invalidRoute(String)
    case invalidPayload(String)
    case executionFailed(String)
    case fileSystemError(String)
    case authenticationError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRoute(let route): return "Invalid API Route: \(route)"
        case .invalidPayload(let details): return "Invalid Payload: \(details)"
        case .executionFailed(let error): return "Execution Failed: \(error)"
        case .fileSystemError(let error): return "File System Error: \(error)"
        case .authenticationError(let details): return "Authentication Error: \(details)"
        }
    }
}
