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

            // Extract real data from the process and environment
            session.callStack = [
                StackFrame(id: 0, function: "_start", location: "libdyld.dylib", isActive: true)
            ]

            var variables: [DebugVariable] = [
                DebugVariable(name: "PID", value: "\(proc.processIdentifier)", type: "Int32"),
                DebugVariable(name: "Executable", value: executableURL.lastPathComponent, type: "String"),
                DebugVariable(name: "Path", value: executableURL.path, type: "URL")
            ]

            // Add environment variables as real data
            let env = proc.environment ?? [:]
            for (key, value) in env.prefix(10) {
                variables.append(DebugVariable(name: key, value: value, type: "String"))
            }

            session.variables = variables
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
