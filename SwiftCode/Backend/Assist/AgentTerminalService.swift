import Foundation
import os

// MARK: - Assist v3 Structured Terminal Models

public struct TerminalExecutionResult: Codable, Sendable {
    public let command: String
    public let workingDirectory: String
    public let stdout: String
    public let stderr: String
    public let exitCode: Int
    public let duration: TimeInterval
    public let diagnostics: [BuildDiagnostic]

    public var isSuccess: Bool {
        return exitCode == 0
    }

    public var combinedOutput: String {
        if stderr.isEmpty { return stdout }
        if stdout.isEmpty { return stderr }
        return stdout + "\n" + stderr
    }

    public init(
        command: String,
        workingDirectory: String,
        stdout: String,
        stderr: String,
        exitCode: Int,
        duration: TimeInterval,
        diagnostics: [BuildDiagnostic] = []
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.duration = duration
        self.diagnostics = diagnostics
    }
}

// MARK: - Thread-safe Output Collector Actor
private actor OutputCollector {
    private(set) var stdout: String = ""
    private(set) var stderr: String = ""

    func appendStdout(_ text: String) {
        stdout += text
    }

    func appendStderr(_ text: String) {
        stderr += text
    }

    func getOutputs() -> (stdout: String, stderr: String) {
        return (stdout, stderr)
    }
}

// MARK: - Agent Terminal Service

@MainActor
public final class AgentTerminalService: Sendable {
    public static let shared = AgentTerminalService()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AgentTerminalService")

    public var activeProcess: Process?
    public var isRunning: Bool = false
    public var liveOutput: String = ""

    private var pendingOutputBuffer = ""
    private var flushTask: Task<Void, Never>?

    private init() {}

    private func scheduleOutputFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            flushTask = nil
            if !pendingOutputBuffer.isEmpty {
                let chunk = pendingOutputBuffer
                pendingOutputBuffer = ""
                AssistManager.shared.appendTerminalOutput(chunk)
            }
        }
    }

    /// Discovers developer directory for Xcode tools to prevent command line tools xcode-select errors.
    public func resolveDeveloperDirectory() -> String {
        return AssistVerificationPipeline.shared.resolveDeveloperDir()
    }

    /// Executes an arbitrary shell command with live streaming, environment isolation, and duration tracking.
    public func execute(
        command: String,
        workingDirectory: URL,
        timeoutSeconds: TimeInterval = 300,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> TerminalExecutionResult {
        let startTime = Date()

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = workingDirectory

        let devDir = resolveDeveloperDirectory()
        var env = ProcessInfo.processInfo.environment
        env["DEVELOPER_DIR"] = devDir
        env["PATH"] = (env["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(devDir)/usr/bin"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.activeProcess = process
        self.isRunning = true
        self.liveOutput = ""

        let collector = OutputCollector()

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                Task {
                    await collector.appendStdout(text)
                    await MainActor.run {
                        self?.pendingOutputBuffer += text
                        self?.scheduleOutputFlush()
                        onOutput?(text)
                    }
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                Task {
                    await collector.appendStderr(text)
                    await MainActor.run {
                        self?.pendingOutputBuffer += text
                        self?.scheduleOutputFlush()
                        onOutput?(text)
                    }
                }
            }
        }

        logger.info("Launching terminal command: '\(command)' in \(workingDirectory.path)")

        do {
            try process.run()
        } catch {
            self.isRunning = false
            self.activeProcess = nil
            throw error
        }

        let runTask = Task {
            process.waitUntilExit()
        }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            if process.isRunning {
                process.terminate()
            }
        }

        await runTask.value
        timeoutTask.cancel()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if !pendingOutputBuffer.isEmpty {
            let chunk = pendingOutputBuffer
            pendingOutputBuffer = ""
            AssistManager.shared.appendTerminalOutput(chunk)
        }
        flushTask?.cancel()
        flushTask = nil

        let exitCode = Int(process.terminationStatus)
        let duration = Date().timeIntervalSince(startTime)

        self.isRunning = false
        self.activeProcess = nil

        let outputs = await collector.getOutputs()
        let finalStdout = outputs.stdout
        let finalStderr = outputs.stderr

        // Parse diagnostics
        let combined = finalStdout + "\n" + finalStderr
        var diagnostics: [BuildDiagnostic] = []
        for line in combined.components(separatedBy: .newlines) {
            if let diag = BuildLogLineParser.shared.parse(line) {
                diagnostics.append(diag)
            }
        }

        logger.info("Terminal command finished with exit code \(exitCode) in \(String(format: "%.2f", duration))s")

        return TerminalExecutionResult(
            command: command,
            workingDirectory: workingDirectory.path,
            stdout: finalStdout,
            stderr: finalStderr,
            exitCode: exitCode,
            duration: duration,
            diagnostics: diagnostics
        )
        #else
        return TerminalExecutionResult(
            command: command,
            workingDirectory: workingDirectory.path,
            stdout: "",
            stderr: "Terminal execution only supported on macOS",
            exitCode: 1,
            duration: 0
        )
        #endif
    }

    public func cancel() {
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
            logger.info("Cancelled running terminal process.")
        }
        self.isRunning = false
        self.activeProcess = nil
    }
}
