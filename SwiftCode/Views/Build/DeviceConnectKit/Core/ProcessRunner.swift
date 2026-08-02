import Foundation

public struct ProcessRunner {
    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) async throws -> ProcessRunnerTool.ProcessResult {
        return try await ProcessRunnerTool.shared.run(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
    }

    public func runStreaming(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) throws -> Process {
        return try ProcessRunnerTool.shared.runStreaming(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            onStdout: onStdout,
            onStderr: onStderr
        )
    }
}
