import Foundation

/// Defines Simulator system and toolchain error conditions.
public enum SimulatorError: LocalizedError, Sendable, Identifiable {
    public var id: String { errorDescription ?? "unknown_error" }

    case missingXcode
    case simctlExecutionFailed(details: String)
    case deviceNotAvailable(udid: String)
    case failedToBoot(udid: String, reason: String)
    case failedToShutdown(udid: String, reason: String)
    case appNotFound(bundleID: String)
    case invalidApplicationBundle(path: String, reason: String)
    case failedToInstall(bundleID: String, reason: String)
    case permissionDenied(reason: String)
    case deviceCreationFailed(reason: String)
    case custom(String)

    public var errorDescription: String? {
        switch self {
        case .missingXcode:
            return "Xcode Command Line Tools could not be found. Please ensure Xcode is installed and configured."
        case .simctlExecutionFailed(let details):
            return "simctl failed with error:\n\(details)"
        case .deviceNotAvailable(let udid):
            return "The simulator device with UDID \(udid) is not available."
        case .failedToBoot(let udid, let reason):
            return "Failed to boot simulator (\(udid)): \(reason)"
        case .failedToShutdown(let udid, let reason):
            return "Failed to shutdown simulator (\(udid)): \(reason)"
        case .appNotFound(let bundleID):
            return "The application with bundle identifier \(bundleID) was not found."
        case .invalidApplicationBundle(let path, let reason):
            return "The application bundle at \(path) is invalid: \(reason)"
        case .failedToInstall(let bundleID, let reason):
            return "Failed to install app \(bundleID): \(reason)"
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .deviceCreationFailed(let reason):
            return "Failed to create simulator device: \(reason)"
        case .custom(let message):
            return message
        }
    }
}
