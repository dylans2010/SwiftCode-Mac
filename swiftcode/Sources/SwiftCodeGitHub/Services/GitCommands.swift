import Foundation

public enum GitCommandsError: LocalizedError, Sendable {
    case missingRemote
    case pushFailed(String)
    case pullFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingRemote:
            return "No GitHub repository is linked to this project. Please set a repository URL in the GitHub settings."
        case .pushFailed(let reason):
            return "Push Failed: \(reason)"
        case .pullFailed(let reason):
            return "Pull Failed: \(reason)"
        }
    }
}
