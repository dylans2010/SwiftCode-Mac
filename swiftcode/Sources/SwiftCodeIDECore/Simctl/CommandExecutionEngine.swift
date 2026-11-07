import Foundation
import os

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
        let record = CommandExecutionRecord(
            id: recordID,
            command: spec,
            stdout: Data(),
            stderr: "simctl requires macOS with Xcode installed.".data(using: .utf8) ?? Data(),
            exitCode: -1,
            duration: .zero,
            startedAt: startedAt,
            outcome: .launchFailed(reason: "simctl requires macOS with Xcode installed")
        )
        appendToHistory(record)
        return record
        #else

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
                if case .standard(_, let backoffs) = spec.retryPolicy, currentAttempt - 1 < backoffs.count {
                    let backoff = backoffs[currentAttempt - 1]
                    try? await Task.sleep(for: backoff)
                }
                Logger.process.info("Retrying command: \(spec.executableURL.path) (attempt \(currentAttempt + 1))")
            }

            let attemptRecord = await runSingleProcessExecution(spec: spec, recordID: recordID, startedAt: startedAt)
            lastRecord = attemptRecord

            switch attemptRecord.outcome {
            case .success, .nonZeroExit:
                appendToHistory(attemptRecord)
                return attemptRecord
            case .timedOut, .launchFailed:
                currentAttempt += 1
            case .cancelled:
                appendToHistory(attemptRecord)
                return attemptRecord
            }
        }

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
}
