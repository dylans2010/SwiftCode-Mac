import Foundation
import Observation

/// A local process debug session (Legacy `DebugSessionViewModel`'s
/// `DebugSession` / `DebugVariable`, Dylan's own code, ported under MIT).
/// This is the simple launch-and-observe runner: it starts an executable
/// with `Foundation.Process`, streams its output, and records the PID,
/// environment and a one-frame call stack. It is NOT the DAP/LLDB debug
/// session in `SwiftCodeDebug` — that is a different, fuller debugger. The
/// call stack is `[String]` (function names) to avoid colliding with
/// `SwiftCodeDebug.StackFrame`.

public struct DebugVariable: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let value: String
    public let type: String

    public init(name: String, value: String, type: String) {
        self.name = name
        self.value = value
        self.type = type
    }
}

public struct DebugSession: Sendable {
    public enum State: Sendable {
        case running
        case terminated(Int32)
    }

    public let pid: Int32
    public let executableURL: URL
    public var state: State
    public var callStack: [String]
    public var variables: [DebugVariable]

    public init(pid: Int32, executableURL: URL, state: State = .running, callStack: [String] = [], variables: [DebugVariable] = []) {
        self.pid = pid
        self.executableURL = executableURL
        self.state = state
        self.callStack = callStack
        self.variables = variables
    }
}

/// Launches an executable and streams its output (Legacy
/// `DebugSessionViewModel`). The initial variable list is real data: the
/// PID, executable path, and the process environment (first 10 entries).
/// The initial call stack is a single `_start` frame, exactly as Legacy
/// recorded it — a real stack trace needs the DAP debugger, not this runner.
@Observable
@MainActor
public final class DebugSessionViewModel {
    public var activeSession: DebugSession?
    public var consoleOutput = ""
    public var launchError: String?
    private var process: Process?

    public init() {}

    public func startDebugging(executableURL: URL) {
        launchError = nil
        let process = Process()
        process.executableURL = executableURL
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let outputHandle = pipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.consoleOutput += text
            }
        }
        do {
            try process.run()
        } catch {
            launchError = "Failed to launch debugger: \(error.localizedDescription)"
            outputHandle.readabilityHandler = nil
            return
        }
        self.process = process
        var session = DebugSession(pid: process.processIdentifier, executableURL: executableURL)
        session.state = .running
        session.callStack = ["_start"]
        var variables: [DebugVariable] = [
            DebugVariable(name: "PID", value: "\(process.processIdentifier)", type: "Int32"),
            DebugVariable(name: "Executable", value: executableURL.lastPathComponent, type: "String"),
            DebugVariable(name: "Path", value: executableURL.path, type: "URL"),
        ]
        for (key, value) in (process.environment ?? [:]).prefix(10) {
            variables.append(DebugVariable(name: key, value: value, type: "String"))
        }
        session.variables = variables
        activeSession = session
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.activeSession?.state = .terminated(process.terminationStatus)
                self?.process = nil
                outputHandle.readabilityHandler = nil
            }
        }
    }

    public func stop() {
        process?.terminate()
        process = nil
        activeSession = nil
    }
}
