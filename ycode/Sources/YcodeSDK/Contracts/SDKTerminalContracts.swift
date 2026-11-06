import Foundation

// MARK: - SDKSandboxRunRequest
//
// Intent to run one sandboxed command via `terminal.sandbox`
// (spec §8.1, §11.x — host-mediated sandboxed execution).
//
// This is NOT a terminal view and carries no UI surface: the request asks
// the host to spawn a single process under the sandbox rules enforced by
// `SDKSandboxedTerminal`. Deliberate allow-list: only command, args,
// workingDirectory, and timeout may be supplied. There are intentionally NO
// environment, shell, executable-search-path, stdin-content, or signal
// fields — the host pins the environment, forbids shell interpretation,
// resolves the executable itself, and owns the lifecycle.

public struct SDKSandboxRunRequest: Codable, Sendable {
    /// Executable to run: either a bare name from the host allow-list
    /// (e.g. "git") or an absolute path inside an approved location
    /// (e.g. "/usr/bin/git"). Never a shell snippet.
    public let command: String
    /// Verbatim argv elements. Passed to the process directly — never
    /// concatenated into a shell string.
    public let args: [String]
    /// Working directory for the process, as a path string. Relative paths
    /// are anchored at the caller's project root. Must resolve inside the
    /// caller's approved project scope; nil = the project root.
    public let workingDirectory: String?
    /// Wall-clock budget in seconds. Nil = host default. Clamped by the
    /// host to [1, 55] seconds; expiry SIGTERMs then SIGKILLs the process.

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

    // Tolerant decoding: `args`, `workingDirectory`, and `timeout` are
    // optional on the wire; absence means host defaults. A present-but-
    // wrongly-typed field still fails decoding (→ `.invalidArgument`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
    }
}

// MARK: - SDKSandboxedResult
//
// Terminal result of one sandboxed run. Output is ALWAYS byte-bounded:
// `stdoutTruncated`/`stderrTruncated` plus `stdoutTotalBytes`/
// `stderrTotalBytes`/`byteLimit` describe exactly how much was withheld.
// Oversized output is truncated with metadata — never silently cut, and
// never rejected with `outputTooLarge` (same convention as the
// source-control diff adapter: truncation metadata is the specified
// behavior, so that error code stays unused by this surface).

public struct SDKSandboxedResult: Codable, Sendable {
    /// Captured standard output (lossy UTF-8 decode, byte-capped).
    public let stdout: String
    /// Captured standard error (lossy UTF-8 decode, byte-capped).
    public let stderr: String
    /// Real process exit code (`Process.terminationStatus`). Never
    /// fabricated: timeouts throw `.requestTimeout` instead of inventing
    /// an exit code.
    public let exitCode: Int32
    /// True when stdout was cut at the byte limit.
    public let stdoutTruncated: Bool
    /// True when stderr was cut at the byte limit.
    public let stderrTruncated: Bool
    /// Full, untruncated stdout byte size (may exceed `byteLimit`).
    public let stdoutTotalBytes: Int
    /// Full, untruncated stderr byte size (may exceed `byteLimit`).
    public let stderrTotalBytes: Int
    /// The per-stream byte limit that was applied.
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
