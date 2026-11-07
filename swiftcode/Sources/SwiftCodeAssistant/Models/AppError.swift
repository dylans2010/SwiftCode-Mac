import Foundation

public enum AppError: Error, LocalizedError, Sendable {
    case aiError(String)

    public var errorDescription: String? {
        switch self {
        case .aiError(let msg): return msg
        }
    }
}
