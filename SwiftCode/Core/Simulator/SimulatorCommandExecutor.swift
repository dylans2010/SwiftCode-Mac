import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "SimulatorCommandExecutor")

/// Actor that executes raw shell commands for simctl on a background context.
public actor SimulatorCommandExecutor: Sendable {
    public static let shared = SimulatorCommandExecutor()
    private init() {}

    /// Executes a given command with arguments, returning the exit code, stdout, and stderr.
    public func execute(executable: String, arguments: [String]) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let exeURL = URL(fileURLWithPath: executable)
        logger.info("Executing: \(executable) with arguments: \(arguments.joined(separator: " "), privacy: .public)")

        do {
            let result = try await ProcessRunnerTool.shared.run(
                executableURL: exeURL,
                arguments: arguments
            )
            return (result.exitCode, result.stdout, result.stderr)
        } catch {
            logger.error("Failed to run execution process: \(error.localizedDescription, privacy: .public)")
            throw SimulatorError.simctlExecutionFailed(details: error.localizedDescription)
        }
    }
}
