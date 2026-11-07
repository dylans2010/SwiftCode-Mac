import Foundation

public struct SDKSandboxRunRequest: Codable, Sendable {
    public let command: String
    public let args: [String]
    public let workingDirectory: String?

    public let timeout: Double?

    public init(
        command: String,
        args: [String] = [],
        workingDirectory: String? = nil,
        timeout: Double? = nil
    ) {
        self.command = command
        self.args = args
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
    }
}

public struct SDKSandboxedResult: Codable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let stdoutTotalBytes: Int
    public let stderrTotalBytes: Int
    public let byteLimit: Int

    public init(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        stdoutTruncated: Bool = false,
        stderrTruncated: Bool = false,
        stdoutTotalBytes: Int,
        stderrTotalBytes: Int,
        byteLimit: Int
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.stdoutTruncated = stdoutTruncated
        self.stderrTruncated = stderrTruncated
        self.stdoutTotalBytes = stdoutTotalBytes
        self.stderrTotalBytes = stderrTotalBytes
        self.byteLimit = byteLimit
    }
}
