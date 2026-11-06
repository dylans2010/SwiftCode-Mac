// Adapted from SwiftCode-Legacy SwiftCode/Core/Simulator/SimulatorCommandExecutor.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation
import os

public actor SimulatorCommandExecutor {
    private let logger = Logger(subsystem: "com.swiftcode.simulator", category: "CommandExecutor")
    public init() {}

    public struct ExecutionResult: Sendable {
        public let exitCode: Int32
        public let output: String
        public let errorOutput: String
        public let duration: TimeInterval
    }

    public func execute(_ command: SimulatorCommand) async throws -> ExecutionResult {
        logger.info("[BEGIN] Executing command '\(command.name)': \(command.executable) \(command.arguments.joined(separator: " "))")
        let startTime = Date()

        // Safely check if the target executable exists
        let fm = FileManager.default
        let hasExecutable = fm.fileExists(atPath: command.executable)

        guard hasExecutable else {
            // Never fabricate success output for a missing tool: simctl
            // requires macOS with Xcode installed. (Legacy returned canned
            // Xcode/simctl output here; that fiction is removed in this port.)
            logger.error("[FAILED] Executable not found at '\(command.executable)'")
            throw SimulatorError.executionFailed(
                command: command.name, exitCode: -1,
                output: "Executable not found at '\(command.executable)'. simctl requires macOS with Xcode installed.")
        }

        // Native command execution using Process & Pipe safely (no force unwraps)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            // Asynchronous timeout control using modern task group
            let exitCode = try await withThrowingTaskGroup(of: Int32.self) { group in
                group.addTask {
                    process.waitUntilExit()
                    return process.terminationStatus
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(command.timeout * 1_000_000_000))
                    if process.isRunning {
                        process.terminate()
                    }
                    throw SimulatorError.bootTimeout(udid: command.name)
                }

                guard let result = try await group.next() else {
                    process.terminate()
                    throw SimulatorError.simctlFailed(reason: "Execution context lost")
                }
                group.cancelAll()
                return result
            }

            // Capture stdout/stderr safely (no force unwraps, handles empty cases gracefully)
            let outputData: Data
            if let data = try? outputPipe.fileHandleForReading.readToEnd() {
                outputData = data
            } else {
                outputData = Data()
            }

            let errorData: Data
            if let data = try? errorPipe.fileHandleForReading.readToEnd() {
                errorData = data
            } else {
                errorData = Data()
            }

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            let duration = Date().timeIntervalSince(startTime)

            logger.info("[END] Command '\(command.name)' exited with \(exitCode) in \(duration)s")
            return ExecutionResult(exitCode: exitCode, output: output, errorOutput: errorOutput, duration: duration)

        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.error("[FAILED] Command '\(command.name)' failed after \(duration)s: \(error.localizedDescription)")
            throw SimulatorError.simctlFailed(reason: error.localizedDescription)
        }
    }
}
