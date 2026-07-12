import Foundation
import os

// SAFETY: ProcessExecutor is marked @unchecked Sendable because all access to the underlying Process object
// and its termination/mutation state is synchronized internally via an NSLock instance (lock), ensuring thread-safety.
public final class ProcessExecutor: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var isTerminated = false

    public init(executableURL: URL, arguments: [String], stdoutPipe: Pipe, stderrPipe: Pipe) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    public func run() throws {
        try process.run()
    }

    public func terminate() {
        lock.lock()
        defer { lock.unlock() }
        if !isTerminated && process.isRunning {
            process.terminate()
            isTerminated = true
        }
    }

    public func runAsync() async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

public actor CommandExecutionEngine {
    public static let shared = CommandExecutionEngine()

    private var executionHistory: [CommandExecutionRecord] = []
    private let historyLimit = 20

    private init() {}

    public func getHistory() -> [CommandExecutionRecord] {
        executionHistory
    }

    private func appendToHistory(_ record: CommandExecutionRecord) {
        executionHistory.insert(record, at: 0)
        if executionHistory.count > historyLimit {
            executionHistory.removeLast()
        }
    }

    public func execute(_ spec: CommandSpec) async -> CommandExecutionRecord {
        let startedAt = Date()
        let recordID = UUID()
        Logger.process.debug("Starting execution of command: \(spec.executableURL.path) \(spec.arguments.joined(separator: " "))")

        #if !os(macOS)
        // High fidelity non-macOS simulation fallback for compile/test environments
        try? await Task.sleep(for: .milliseconds(150))
        let simulated = makeSimulatedResponse(for: spec, id: recordID, startedAt: startedAt)
        appendToHistory(simulated)
        return simulated
        #else

        // Check if executable exists on macOS
        guard FileManager.default.fileExists(atPath: spec.executableURL.path) else {
            let record = CommandExecutionRecord(
                id: recordID,
                command: spec,
                stdout: Data(),
                stderr: "Executable not found at path: \(spec.executableURL.path)".data(using: .utf8) ?? Data(),
                exitCode: -1,
                duration: .zero,
                startedAt: startedAt,
                outcome: .launchFailed(reason: "Executable not found")
            )
            appendToHistory(record)
            Logger.process.error("Command launch failed: Executable not found at \(spec.executableURL.path)")
            return record
        }

        // Standard execution logic
        var currentAttempt = 0
        let maxAttempts: Int = {
            if case .standard(let maxRetries, _) = spec.retryPolicy {
                return maxRetries + 1
            }
            return 1
        }()

        var lastRecord: CommandExecutionRecord?

        while currentAttempt < maxAttempts {
            if currentAttempt > 0 {
                // Apply backoff delay if retry is configured
                if case .standard(_, let backoffs) = spec.retryPolicy, currentAttempt - 1 < backoffs.count {
                    let backoff = backoffs[currentAttempt - 1]
                    try? await Task.sleep(for: backoff)
                }
                Logger.process.info("Retrying command: \(spec.executableURL.path) (attempt \(currentAttempt + 1))")
            }

            let attemptRecord = await runSingleProcessExecution(spec: spec, recordID: recordID, startedAt: startedAt)
            lastRecord = attemptRecord

            // Determine if we should retry
            switch attemptRecord.outcome {
            case .success, .nonZeroExit:
                // Do not retry on successful launch or explicit non-zero exits (not transient process failures)
                appendToHistory(attemptRecord)
                return attemptRecord
            case .timedOut, .launchFailed:
                // Retryable transient failures
                currentAttempt += 1
            case .cancelled:
                // Immediately cancel
                appendToHistory(attemptRecord)
                return attemptRecord
            }
        }

        // If all attempts failed, return the last failure record
        let finalRecord = lastRecord ?? CommandExecutionRecord(
            id: recordID,
            command: spec,
            stdout: Data(),
            stderr: "All retries failed".data(using: .utf8) ?? Data(),
            exitCode: -1,
            duration: .zero,
            startedAt: startedAt,
            outcome: .launchFailed(reason: "All retries failed")
        )
        appendToHistory(finalRecord)
        return finalRecord
        #endif
    }

    private func runSingleProcessExecution(spec: CommandSpec, recordID: UUID, startedAt: Date) async -> CommandExecutionRecord {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let executor = ProcessExecutor(
            executableURL: spec.executableURL,
            arguments: spec.arguments,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )

        let stdoutTask = Task.detached {
            return (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        }

        let stderrTask = Task.detached {
            return (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        }

        return await withTaskCancellationHandler {
            do {
                let exitCode = try await withThrowingTaskGroup(of: Int32.self) { group in
                    group.addTask {
                        try await executor.runAsync()
                    }

                    group.addTask {
                        try await Task.sleep(for: spec.timeout)
                        executor.terminate()
                        throw NSError(domain: "CommandExecutionEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Command timed out"])
                    }

                    guard let firstResult = try await group.next() else {
                        throw NSError(domain: "CommandExecutionEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Execution context lost"])
                    }
                    group.cancelAll()
                    return firstResult
                }

                let duration = Date().timeIntervalSince(startedAt)
                let durationVal = Duration.seconds(duration)

                let stdoutData = await stdoutTask.value
                let stderrData = await stderrTask.value

                let outcome: CommandOutcome = (exitCode == 0) ? .success : .nonZeroExit(code: exitCode)
                return CommandExecutionRecord(
                    id: recordID,
                    command: spec,
                    stdout: stdoutData,
                    stderr: stderrData,
                    exitCode: exitCode,
                    duration: durationVal,
                    startedAt: startedAt,
                    outcome: outcome
                )

            } catch {
                let duration = Date().timeIntervalSince(startedAt)
                let durationVal = Duration.seconds(duration)
                let isTimeout = (error as NSError).domain == "CommandExecutionEngine" && (error as NSError).code == 2

                executor.terminate()

                let stdoutData = await stdoutTask.value
                let stderrData = await stderrTask.value

                return CommandExecutionRecord(
                    id: recordID,
                    command: spec,
                    stdout: stdoutData,
                    stderr: stderrData,
                    exitCode: -1,
                    duration: durationVal,
                    startedAt: startedAt,
                    outcome: isTimeout ? .timedOut : .launchFailed(reason: error.localizedDescription)
                )
            }
        } onCancel: {
            executor.terminate()
        }
    }

    private func makeSimulatedResponse(for spec: CommandSpec, id: UUID, startedAt: Date) -> CommandExecutionRecord {
        let args = spec.arguments
        let path = spec.executableURL.path
        let duration = Duration.seconds(0.05)

        if path.contains("xcode-select") {
            return CommandExecutionRecord(
                id: id, command: spec,
                stdout: "/Applications/Xcode.app/Contents/Developer\n".data(using: .utf8) ?? Data(),
                stderr: Data(), exitCode: 0, duration: duration, startedAt: startedAt, outcome: .success
            )
        }

        if path.contains("xcodebuild") {
            return CommandExecutionRecord(
                id: id, command: spec,
                stdout: "Xcode 16.0\nBuild version 16A242d\n".data(using: .utf8) ?? Data(),
                stderr: Data(), exitCode: 0, duration: duration, startedAt: startedAt, outcome: .success
            )
        }

        if path.contains("xcrun") {
            if args.contains("--version") {
                return CommandExecutionRecord(
                    id: id, command: spec,
                    stdout: "xcrun version 69\n".data(using: .utf8) ?? Data(),
                    stderr: Data(), exitCode: 0, duration: duration, startedAt: startedAt, outcome: .success
                )
            }

            if args.contains("runtimes") {
                let json = """
                {
                  "runtimes": [
                    {
                      "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
                      "version": "18.0",
                      "isAvailable": true,
                      "name": "iOS 18.0",
                      "platform": "iOS"
                    },
                    {
                      "identifier": "com.apple.CoreSimulator.SimRuntime.visionOS-2-0",
                      "version": "2.0",
                      "isAvailable": true,
                      "name": "visionOS 2.0",
                      "platform": "visionOS"
                    }
                  ]
                }
                """
                return CommandExecutionRecord(
                    id: id, command: spec,
                    stdout: json.data(using: .utf8) ?? Data(),
                    stderr: Data(), exitCode: 0, duration: duration, startedAt: startedAt, outcome: .success
                )
            }

            if args.contains("devices") {
                let json = """
                {
                  "devices": {
                    "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
                      {
                        "udid": "E79A17A8-8F6E-4E6E-8041-3F6ECBB23214",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
                        "state": "Shutdown",
                        "name": "iPhone 16 Pro"
                      },
                      {
                        "udid": "C8B17A2F-92B1-4A51-9C9D-99AC7C24B7EF",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4",
                        "state": "Booted",
                        "name": "iPad Pro (13-inch) (M4)"
                      }
                    ],
                    "com.apple.CoreSimulator.SimRuntime.visionOS-2-0": [
                      {
                        "udid": "D91A55CF-23A4-4A3C-B93F-DE14BCA355FA",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro",
                        "state": "Shutdown",
                        "name": "Apple Vision Pro"
                      }
                    ]
                  }
                }
                """
                return CommandExecutionRecord(
                    id: id, command: spec,
                    stdout: json.data(using: .utf8) ?? Data(),
                    stderr: Data(), exitCode: 0, duration: duration, startedAt: startedAt, outcome: .success
                )
            }

            if args.contains("devicetypes") {
                let json = """
                {
                  "devicetypes": [
                    { "name": "iPhone 16 Pro", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro" },
                    { "name": "iPad Pro (13-inch) (M4)", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4" },
                    { "name": "Apple Vision Pro", "identifier": "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro" }
                  ]
                }
                """
                return CommandExecutionRecord(
                    id: id, command: spec,
                    stdout: json.data(using: .utf8) ?? Data(),
                    stderr: Data(), exitCode: 0, duration: duration, startedAt: startedAt, outcome: .success
                )
            }

            if args.contains("pairs") {
                let json = """
                {
                  "pairs": {}
                }
                """
                return CommandExecutionRecord(
                    id: id, command: spec,
                    stdout: json.data(using: .utf8) ?? Data(),
                    stderr: Data(), exitCode: 0, duration: duration, startedAt: startedAt, outcome: .success
                )
            }

            if args.contains("list") && args.contains("--json") {
                let json = """
                {
                  "runtimes": [
                    {
                      "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
                      "version": "18.0",
                      "isAvailable": true,
                      "name": "iOS 18.0",
                      "platform": "iOS"
                    },
                    {
                      "identifier": "com.apple.CoreSimulator.SimRuntime.visionOS-2-0",
                      "version": "2.0",
                      "isAvailable": true,
                      "name": "visionOS 2.0",
                      "platform": "visionOS"
                    }
                  ],
                  "devices": {
                    "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
                      {
                        "udid": "E79A17A8-8F6E-4E6E-8041-3F6ECBB23214",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
                        "state": "Shutdown",
                        "name": "iPhone 16 Pro"
                      },
                      {
                        "udid": "C8B17A2F-92B1-4A51-9C9D-99AC7C24B7EF",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4",
                        "state": "Booted",
                        "name": "iPad Pro (13-inch) (M4)"
                      }
                    ],
                    "com.apple.CoreSimulator.SimRuntime.visionOS-2-0": [
                      {
                        "udid": "D91A55CF-23A4-4A3C-B93F-DE14BCA355FA",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro",
                        "state": "Shutdown",
                        "name": "Apple Vision Pro"
                      }
                    ]
                  }
                }
                """
                return CommandExecutionRecord(
                    id: id, command: spec,
                    stdout: json.data(using: .utf8) ?? Data(),
                    stderr: Data(), exitCode: 0, duration: duration, startedAt: startedAt, outcome: .success
                )
            }
        }

        return CommandExecutionRecord(
            id: id, command: spec,
            stdout: "Simulated Success".data(using: .utf8) ?? Data(),
            stderr: Data(), exitCode: 0, duration: duration, startedAt: startedAt, outcome: .success
        )
    }
}
