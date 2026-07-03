import Foundation

public actor DebugRunnerService {
    public static let shared = DebugRunnerService()

    public func launch(executableURL: URL, onOutput: @escaping @Sendable (String) -> Void) throws -> Process {
        return try ProcessRunnerTool.shared.runStreaming(
            executableURL: executableURL,
            arguments: [],
            onStdout: onOutput,
            onStderr: onOutput
        )
    }
}
