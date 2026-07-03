import Foundation

public actor ProcessRunnerTool {
    public static let shared = ProcessRunnerTool()

    public struct ProcessResult {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
    }

    public func run(executableURL: URL, arguments: [String], environment: [String: String]? = nil, workingDirectory: URL? = nil) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let env = environment {
            process.environment = env
        }
        if let workingDir = workingDirectory {
            process.currentDirectoryURL = workingDir
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutData = try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
        let stderrData = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()

        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    public func runStreaming(executableURL: URL, arguments: [String], environment: [String: String]? = nil, workingDirectory: URL? = nil, onStdout: @escaping @Sendable (String) -> Void, onStderr: @escaping @Sendable (String) -> Void) throws -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let env = environment {
            process.environment = env
        }
        if let workingDir = workingDirectory {
            process.currentDirectoryURL = workingDir
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                onStdout(str)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                onStderr(str)
            }
        }

        try process.run()
        return process
    }
}
