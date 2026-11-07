import Foundation

public struct CommandSpec: Sendable, Hashable {
    public let executableURL: URL
    public let arguments: [String]
    public let timeout: Duration
    public let retryPolicy: RetryPolicy

    public init(
        executableURL: URL,
        arguments: [String],
        timeout: Duration = .seconds(15),
        retryPolicy: RetryPolicy = .standardDefault
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeout = timeout
        self.retryPolicy = retryPolicy
    }
}

public enum RetryPolicy: Sendable, Hashable {
    case none
    case standard(maxRetries: Int, backoffs: [Duration])

    public static let standardDefault = RetryPolicy.standard(
        maxRetries: 2,
        backoffs: [.milliseconds(250), .milliseconds(750)]
    )
}

public enum CommandOutcome: Sendable, Codable, Hashable {
    case success
    case nonZeroExit(code: Int32)
    case timedOut
    case cancelled
    case launchFailed(reason: String)
}

public struct CommandExecutionRecord: Sendable, Identifiable {
    public let id: UUID
    public let command: CommandSpec
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
    public let duration: Duration
    public let startedAt: Date
    public let outcome: CommandOutcome

    public var stdoutString: String {
        String(data: stdout, encoding: .utf8) ?? ""
    }

    public var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }

    public init(
        id: UUID = UUID(),
        command: CommandSpec,
        stdout: Data,
        stderr: Data,
        exitCode: Int32,
        duration: Duration,
        startedAt: Date,
        outcome: CommandOutcome
    ) {
        self.id = id
        self.command = command
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.duration = duration
        self.startedAt = startedAt
        self.outcome = outcome
    }
}
