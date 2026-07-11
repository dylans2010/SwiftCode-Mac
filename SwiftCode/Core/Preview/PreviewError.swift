import Foundation

/// Defines error categories for SwiftUI Live Previews.
public enum PreviewError: LocalizedError, Sendable, Identifiable, Hashable {
    public var id: String { errorDescription ?? "unknown_preview_error" }

    case syntaxError(message: String, file: String?, line: Int?)
    case compilationFailed(message: String, logOutput: String)
    case targetUnresolved(reason: String)
    case communicationFailed(reason: String)
    case hostCrash(exitCode: Int32, reason: String)
    case renderTimeout
    case custom(String)

    public var errorDescription: String? {
        switch self {
        case .syntaxError(let message, let file, let line):
            if let file = file, let line = line {
                return "Syntax Error in \(URL(fileURLWithPath: file).lastPathComponent) at line \(line):\n\(message)"
            }
            return "Syntax Error:\n\(message)"
        case .compilationFailed(let message, let logs):
            return "SwiftUI Preview compilation failed:\n\(message)\n\nBuild Log:\n\(logs)"
        case .targetUnresolved(let reason):
            return "Could not resolve a suitable preview target: \(reason)"
        case .communicationFailed(let reason):
            return "Communication with Preview Host application failed: \(reason)"
        case .hostCrash(let exitCode, let reason):
            return "Preview Host crashed (Exit code: \(exitCode)): \(reason)"
        case .renderTimeout:
            return "SwiftUI Previews rendering timed out."
        case .custom(let message):
            return message
        }
    }
}
