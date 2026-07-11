import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "SimctlService")

/// Service that coordinates commands to simctl.
public actor SimctlService: Sendable {
    public static let shared = SimctlService()
    private init() {}

    private var simctlPath: String {
        return "/usr/bin/xcrun"
    }

    /// Run a command using the executor.
    public func execute(_ command: SimulatorCommand) async throws -> String {
        let arguments = buildArguments(for: command)

        // Check if xcrun is present on the filesystem
        let fm = FileManager.default
        if !fm.fileExists(atPath: simctlPath) {
            logger.warning("xcrun/simctl developer tools path does not exist on this environment: \(self.simctlPath, privacy: .public). Falling back to virtual operation simulation.")
            throw SimulatorError.missingXcode
        }

        let result = try await SimulatorCommandExecutor.shared.execute(executable: simctlPath, arguments: arguments)
        if result.exitCode != 0 {
            let details = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.error("Command failed: \(command.displayTitle, privacy: .public) with exit code: \(result.exitCode, privacy: .public), details: \(details, privacy: .public)")
            throw SimulatorError.simctlExecutionFailed(details: details)
        }

        return result.stdout
    }

    private func buildArguments(for command: SimulatorCommand) -> [String] {
        var args = ["simctl"]
        switch command {
        case .boot(let udid):
            args.append(contentsOf: ["boot", udid])
        case .shutdown(let udid):
            args.append(contentsOf: ["shutdown", udid])
        case .erase(let udid):
            args.append(contentsOf: ["erase", udid])
        case .delete(let udid):
            args.append(contentsOf: ["delete", udid])
        case .install(let udid, let appPath):
            args.append(contentsOf: ["install", udid, appPath])
        case .launch(let udid, let bundleID, let arguments):
            args.append(contentsOf: ["launch", udid, bundleID])
            args.append(contentsOf: arguments)
        case .terminate(let udid, let bundleID):
            args.append(contentsOf: ["terminate", udid, bundleID])
        case .createDevice(let name, let deviceType, let runtime):
            args.append(contentsOf: ["create", name, deviceType, runtime])
        case .openSimulatorApp:
            // Needs standard AppKit launch
            return []
        }
        return args
    }
}
