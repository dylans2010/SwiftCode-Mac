import Foundation

/// The result of a finished process: exit code plus captured output.
public struct DeviceConnectProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

/// Why a process could not run.
public enum DeviceConnectProcessError: Error, LocalizedError, Sendable {
    case executableNotFound(URL)
    case launchFailed(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let url):
            return "Executable not found: \(url.path)"
        case .launchFailed(let url, let error):
            return "Failed to launch \(url.path): \(error.localizedDescription)"
        }
    }
}

/// The process runner for DeviceConnectKit, ported from Legacy
/// (`SwiftCode/Views/Build/DeviceConnectKit/Core/ProcessRunner.swift`
/// + the `ProcessRunnerTool` it delegated to, which lives outside
/// this slice).
///
/// Legacy's `ProcessRunnerTool` is not in this slice, so this file
/// implements the three operations the commands need directly on
/// `Foundation.Process`:
/// - `run`: capture stdout/stderr to end of file;
/// - `runStreamingAsync`: forward lines live, resolve to exit-code 0;
/// - `runStreaming`: forward lines live, hand the caller the
///   `Process` to terminate (syslog streaming).
///
/// The commands invoke real developer tools (`/usr/bin/xcodebuild`,
/// `/usr/bin/xcrun`, `/usr/bin/security`, `/usr/bin/sw_vers`,
/// `/usr/bin/swift`, `/usr/bin/xcode-select`). On a machine without
/// them `run` throws `.executableNotFound` — the failure is honest,
/// never a fabricated result.
public struct DeviceConnectProcessRunner: Sendable {
    public static let shared = DeviceConnectProcessRunner()

    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) async throws -> DeviceConnectProcessResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.runSync(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            )
        }.value
    }

    public func runStreamingAsync(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> Bool {
        let running = try startStreaming(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            onStdout: onStdout,
            onStderr: onStderr
        )
        let process = running.process
        // Poll for exit: the readability handlers deliver lines as
        // they arrive. The buffers are flushed explicitly after the
        // loop so no trailing partial line is lost to a race with
        // the termination handler.
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                return false
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        running.flush()
        return process.terminationStatus == 0
    }

    public func runStreaming(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) throws -> Process {
        return try startStreaming(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            onStdout: onStdout,
            onStderr: onStderr
        ).process
    }

    // MARK: - Private

    private static func runSync(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> DeviceConnectProcessResult {
        let process = try makeProcess(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Both pipes are drained on background queues while the
        // process runs: reading one to EOF first could deadlock if
        // the other fills its buffer.
        let group = DispatchGroup()
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try process.run()
        } catch {
            throw DeviceConnectProcessError.launchFailed(executableURL, error)
        }
        process.waitUntilExit()
        group.wait()

        return DeviceConnectProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutBox.data, as: UTF8.self),
            stderr: String(decoding: stderrBox.data, as: UTF8.self)
        )
    }

    private func startStreaming(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) throws -> (process: Process, flush: () -> Void) {
        let process = try Self.makeProcess(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutLines = LineBuffer(onLine: onStdout)
        let stderrLines = LineBuffer(onLine: onStderr)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stdoutLines.append(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stderrLines.append(data) }
        }
        // `flush` is handed to a @Sendable termination handler, so the
        // non-Sendable pipe file handles are carried in a Sendable box.
        let handles = StreamHandles(stdout: stdoutPipe.fileHandleForReading, stderr: stderrPipe.fileHandleForReading)
        let flush: @Sendable () -> Void = {
            handles.detach()
            stdoutLines.flush()
            stderrLines.flush()
        }
        // Flush any partial trailing line once the process is gone.
        // `terminationHandler` runs after the pipes close, so no
        // line is lost.
        process.terminationHandler = { _ in flush() }

        do {
            try process.run()
        } catch {
            throw DeviceConnectProcessError.launchFailed(executableURL, error)
        }
        return (process, flush)
    }

    private static func makeProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> Process {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw DeviceConnectProcessError.executableNotFound(executableURL)
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        return process
    }
}

/// The two pipe read handles for a streaming run, boxed so the flush
/// closure can be `@Sendable` (Foundation's `FileHandle` is not).
private final class StreamHandles: @unchecked Sendable {
    private let stdout: FileHandle
    private let stderr: FileHandle

    init(stdout: FileHandle, stderr: FileHandle) {
        self.stdout = stdout
        self.stderr = stderr
    }

    func detach() {
        stdout.readabilityHandler = nil
        stderr.readabilityHandler = nil
    }
}

/// A locked `Data` box for the synchronous drain in `runSync`.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()

    var data: Data {
        get { lock.withLock { _data } }
        set { lock.withLock { _data = newValue } }
    }
}

/// Buffers pipe bytes into complete lines, delivering each line once
/// its newline arrives. The remainder is delivered by `flush()`.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        var lines: [String] = []
        lock.withLock {
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                let lineData = pending[..<newline]
                pending.removeSubrange(...newline)
                lines.append(String(decoding: lineData, as: UTF8.self))
            }
        }
        for line in lines { onLine(line) }
    }

    func flush() {
        var remainder: String?
        lock.withLock {
            if !pending.isEmpty {
                remainder = String(decoding: pending, as: UTF8.self)
                pending.removeAll()
            }
        }
        if let remainder { onLine(remainder) }
    }
}
