import Foundation

enum ProjectOpenError: LocalizedError {
    case pathNotFound
    case bookmarkResolutionFailed
    case corruptedProjectFile
    case timeout
    case unsupportedProjectVersion
    case cancelled
    case underlyingIO(Error)

    var errorDescription: String? {
        switch self {
        case .pathNotFound:
            return "The project folder could not be found."
        case .bookmarkResolutionFailed:
            return "Failed to resolve the security-scoped bookmark for the project."
        case .corruptedProjectFile:
            return "The project metadata file (project.json) is corrupted or missing."
        case .timeout:
            return "The project took too long to load. Please try again."
        case .unsupportedProjectVersion:
            return "This project was created with an unsupported version of SwiftCode."
        case .cancelled:
            return "Project loading was cancelled."
        case .underlyingIO(let error):
            return "An I/O error occurred: \(error.localizedDescription)"
        }
    }
}
