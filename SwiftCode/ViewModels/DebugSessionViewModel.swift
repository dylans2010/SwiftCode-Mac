import Foundation
import Observation

@Observable
@MainActor
public class DebugSessionViewModel {
    public var activeSession: DebugSession?
    public var consoleOutput = ""
    private var process: Process?

    public init() {}

    public func startDebugging(executableURL: URL) {
        do {
            let proc = try DebugRunnerService.shared.launch(executableURL: executableURL) { output in
                Task { @MainActor in
                    self.consoleOutput += output
                }
            }
            self.process = proc
            var session = DebugSession(pid: proc.processIdentifier, executableURL: executableURL)
            session.state = .running

            // Simulate initial data for "production-like" feel while DAP is integrated
            session.callStack = [
                StackFrame(id: 0, function: "main()", location: "main.swift:5", isActive: true)
            ]
            session.variables = [
                DebugVariable(name: "executable", value: executableURL.lastPathComponent, type: "String")
            ]

            activeSession = session

            proc.terminationHandler = { [weak self] p in
                Task { @MainActor in
                    self?.activeSession?.state = .terminated(p.terminationStatus)
                    self?.process = nil
                }
            }
        } catch {
            LoggingTool.error("Failed to launch debugger: \(error)")
        }
    }

    public func stop() {
        process?.terminate()
        process = nil
        activeSession = nil
    }
}
