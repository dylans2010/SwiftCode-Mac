import Foundation

/// The sandboxed terminal's runner (gap closure, specs/ide/
/// gap-closure-windows-artboards.md §8).
///
/// Legacy's terminal is NOT a PTY shell: `TerminalSession.
/// runCommand` runs each command as a fresh `Process` with
/// `/bin/zsh -c <command>`, stdout/stderr piped, cwd `/` by
/// default. Shipping that as an extension-openable shell would
/// ship an unsandboxed shell — so this port does not. The runner
/// below is argv execution, never a shell:
///
/// - no shell is ever spawned (`/usr/bin/env` + argv, so `;`, `|`,
///   `$()`, backticks and friends are rejected before execution,
///   not interpreted);
/// - deny-by-default allowlist (editable by the user) — `git` is
///   restricted to read-only subcommands;
/// - the working directory is confined inside the workspace root;
/// - the environment is scrubbed to PATH / HOME / LANG / TMPDIR;
/// - stdin is the null device; output is capped (1 MB / 10,000
///   lines); a 60s timeout kills the process.
///
/// This is in-process confinement, NOT a macOS Seatbelt sandbox:
/// `YcodeSubprocess` enforces no sandboxing at all, and a true
/// Seatbelt profile (via `sandbox-exec`) is a follow-up decision
/// for Dylan. The window is user-opened only — there is no SDK
/// view and no MCP tool for it, and `sandbox.view` stays
/// unavailable to extensions.
public struct SandboxPolicy: Sendable, Equatable {
    /// The default allowlist. Kept in `UserDefaults` under
    /// `com.ycode.sandbox.allowlist` when the user edits it.
    public static let defaultCommands: [String] = [
        "ls", "pwd", "echo", "date", "uname", "whoami",
        "cat", "head", "tail", "wc", "grep", "find", "du", "df",
        "git", "swift", "xcrun",
    ]
    /// Read-only `git` subcommands (the only ones the allowlist
    /// permits under `git`).
    public static let gitReadOnlySubcommands: Set<String> = [
        "status", "log", "diff", "branch", "remote", "rev-parse",
        "show", "ls-files",
    ]
    public static let defaultTimeoutSeconds: TimeInterval = 60
    public static let maxOutputBytes = 1_048_576
    public static let maxOutputLines = 10_000

    public var allowedCommands: [String]
    public var timeoutSeconds: TimeInterval

    public init(allowedCommands: [String] = SandboxPolicy.defaultCommands,
                timeoutSeconds: TimeInterval = SandboxPolicy.defaultTimeoutSeconds) {
        self.allowedCommands = allowedCommands
        self.timeoutSeconds = timeoutSeconds
    }

    public static func load() -> SandboxPolicy {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: "com.ycode.sandbox.allowlist"), !saved.isEmpty {
            return SandboxPolicy(allowedCommands: saved)
        }
        return SandboxPolicy()
    }

    public func save() {
        UserDefaults.standard.set(allowedCommands, forKey: "com.ycode.sandbox.allowlist")
    }
}

public enum SandboxError: Error, LocalizedError, Equatable {
    case notAllowed(String)
    case metacharacters(String)
    case outsideWorkspace(String)
    case timedOut
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAllowed(let command):
            return "“\(command)” is not on the sandbox allowlist."
        case .metacharacters(let command):
            return "“\(command)” contains shell syntax (such as ; | $() or backticks). This runner never interprets shell syntax — run one command with arguments only."
        case .outsideWorkspace(let path):
            return "The working directory (\(path)) is outside the workspace."
        case .timedOut:
            return "The command timed out and was killed."
        case .launchFailed(let message):
            return "Could not start the command: \(message)"
        }
    }
}

public struct SandboxedCommandResult: Sendable, Equatable {
    public var output: String
    public var exitCode: Int32
    public var truncated: Bool

    public init(output: String, exitCode: Int32, truncated: Bool = false) {
        self.output = output
        self.exitCode = exitCode
        self.truncated = truncated
    }
}

public enum SandboxedCommandRunner {
    /// Characters a shell would interpret. Any of them in the
    /// raw line means the command is rejected outright.
    private static let shellMetacharacters: Set<Character> = [";", "&", "|", "<", ">", "`", "$", "(", ")", "{", "}", "*", "?", "~", "!", "\n", "\r"]

    /// Splits a command line into argv, honouring single and
    /// double quotes. Returns nil on an unbalanced quote.
    public static func tokenize(_ line: String) -> [String]? {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var hasCurrent = false
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
                hasCurrent = true
            } else if ch == "'" || ch == "\"" {
                quote = ch
                hasCurrent = true
            } else if ch.isWhitespace {
                if hasCurrent { tokens.append(current); current = ""; hasCurrent = false }
            } else {
                current.append(ch)
                hasCurrent = true
            }
        }
        if quote != nil { return nil }
        if hasCurrent { tokens.append(current) }
        return tokens
    }

    /// Validates a command line against the policy and returns its
    /// argv, or throws a `SandboxError` explaining the refusal.
    public static func validate(_ line: String, policy: SandboxPolicy) throws -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SandboxError.notAllowed("") }
        if trimmed.contains(where: { shellMetacharacters.contains($0) }) {
            throw SandboxError.metacharacters(trimmed)
        }
        guard let argv = tokenize(trimmed), !argv.isEmpty else {
            throw SandboxError.notAllowed(trimmed)
        }
        let command = argv[0]
        guard policy.allowedCommands.contains(command) else {
            throw SandboxError.notAllowed(command)
        }
        if command == "git" {
            guard argv.count >= 2, SandboxPolicy.gitReadOnlySubcommands.contains(argv[1]) else {
                throw SandboxError.notAllowed("git \(argv.count >= 2 ? argv[1] : "")")
            }
        }
        return argv
    }

    /// Runs `commandLine` (one command + arguments) in
    /// `workingDirectory`, which must sit inside `workspaceRoot`.
    /// The process runs with a scrubbed environment and stdin
    /// from the null device; output is streamed through `onLine`
    /// and capped. Returns the combined output and exit code.
    /// Cancelling the awaiting task terminates the process.
    public static func run(commandLine: String, workingDirectory: URL, workspaceRoot: URL,
                           policy: SandboxPolicy = .load(),
                           onLine: (@Sendable (String) -> Void)? = nil) async throws -> SandboxedCommandResult {
        let argv = try validate(commandLine, policy: policy)
        let cwd = workingDirectory.standardizedFileURL
        let root = workspaceRoot.standardizedFileURL
        guard cwd.path == root.path || cwd.path.hasPrefix(root.path + "/") else {
            throw SandboxError.outsideWorkspace(cwd.path)
        }
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                box.process = process
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = argv
                process.currentDirectoryURL = cwd
                process.standardInput = FileHandle.nullDevice
                // A scrubbed environment: only what a read-only
                // command needs, never the parent's full environment.
                process.environment = [
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                    "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                    "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
                    "TMPDIR": NSTemporaryDirectory(),
                ]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                let output = NSMutableData()
                var lineCount = 0
                var truncated = false
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    // Cap the total output; stop reading past the cap
                    // (the timeout still kills a runaway process).
                    if output.length < SandboxPolicy.maxOutputBytes {
                        let take = min(data.count, SandboxPolicy.maxOutputBytes - output.length)
                        output.append(data.subdata(in: 0..<take))
                        if take < data.count { truncated = true }
                    } else {
                        truncated = true
                    }
                    if let onLine, let text = String(data: data, encoding: .utf8) {
                        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                            lineCount += 1
                            if lineCount <= SandboxPolicy.maxOutputLines { onLine(line) }
                        }
                    }
                }
                let timeout = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + policy.timeoutSeconds, execute: timeout)
                process.terminationHandler = { _ in
                    timeout.cancel()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let text = String(data: output as Data, encoding: .utf8) ?? ""
                    let result = SandboxedCommandResult(output: text, exitCode: process.terminationStatus, truncated: truncated)
                    continuation.resume(returning: result)
                }
                do {
                    try process.run()
                } catch {
                    timeout.cancel()
                    continuation.resume(throwing: SandboxError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            box.process?.terminate()
        }
    }

    /// A box so the cancellation handler can reach the running
    /// process (the runner hides `Process` from callers).
    private final class ProcessBox: @unchecked Sendable {
        var process: Process?
    }
}
