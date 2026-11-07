import Foundation

public enum SimulatorError: LocalizedError, Sendable {
    case xcrunNotAvailable
    case simctlFailed(reason: String)
    case deviceNotAvailable(udid: String)
    case bootTimeout(udid: String)
    case invalidApplicationBundle(path: String, reason: String)
    case appLaunchFailed(bundleID: String, reason: String)
    case executionFailed(command: String, exitCode: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .xcrunNotAvailable:
            return "Xcode Command Line Tools or 'xcrun' were not found. Please ensure Xcode is installed and configured."
        case .simctlFailed(let reason):
            return "simctl utility failed: \(reason)"
        case .deviceNotAvailable(let udid):
            return "The simulator device with UDID \(udid) is not available or does not exist."
        case .bootTimeout(let udid):
            return "The simulator device \(udid) timed out while booting."
        case .invalidApplicationBundle(let path, let reason):
            return "Invalid application bundle at '\(path)': \(reason)"
        case .appLaunchFailed(let bundleID, let reason):
            return "Failed to launch application '\(bundleID)': \(reason)"
        case .executionFailed(let command, let exitCode, let output):
            return "Command '\(command)' failed with exit code \(exitCode). Output:\n\(output)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .xcrunNotAvailable:
            return "Open Terminal and run 'xcode-select --install', or specify the active Xcode path in system preferences."
        case .simctlFailed:
            return "Try restarting the macOS core simulator services or rebooting your computer."
        case .deviceNotAvailable:
            return "Select a different simulator device or create a new one using the Simulator Creation wizard."
        case .bootTimeout:
            return "Shutdown the simulator and try erasing its contents and settings before booting again."
        case .invalidApplicationBundle:
            return "Ensure you are deploying a valid iOS/watchOS/tvOS/visionOS simulator-compatible build (.app)."
        case .appLaunchFailed:
            return "Verify that the app is properly installed and that the simulator is fully booted."
        case .executionFailed:
            return "Inspect the simulator console logs for detailed crash reports or system diagnostic warnings."
        }
    }
}
