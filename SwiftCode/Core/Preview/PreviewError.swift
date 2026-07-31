import Foundation

public enum PreviewError: LocalizedError, Sendable {
    case compilationError(details: String)
    case renderingCrash(details: String)
    case hostTimeout(details: String)
    case parsingFailed(details: String)
    case xcodeProjectNotLoaded
    case scanFailed(message: String)
    case resolveFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .compilationError(let details):
            return "SwiftUI Previews compilation failed: \(details)"
        case .renderingCrash(let details):
            return "The Preview rendering host crashed: \(details)"
        case .hostTimeout(let details):
            return "Timed out waiting for connection from Preview Host: \(details)"
        case .parsingFailed(let details):
            return "Failed to parse SwiftUI source previews: \(details)"
        case .xcodeProjectNotLoaded:
            return "No active workspace or Xcode project is currently loaded."
        case .scanFailed(let message):
            return "File system scanner failed: \(message)"
        case .resolveFailed(let message):
            return "Target resolver failed: \(message)"
        }
    }
}
