import Foundation

public struct SandboxPolicy: Sendable, Equatable {
    public static let defaultCommands: [String] = [
        "ls", "pwd", "echo", "date", "uname", "whoami",
        "cat", "head", "tail", "wc", "grep", "find", "du", "df",
        "git", "swift", "xcrun",
    ]
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
        if let saved = defaults.stringArray(forKey: "com.swiftcode.sandbox.allowlist"), !saved.isEmpty {
            return SandboxPolicy(allowedCommands: saved)
        }
        return SandboxPolicy()
    }

    public func save() {
        UserDefaults.standard.set(allowedCommands, forKey: "com.swiftcode.sandbox.allowlist")
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
    private static let shellMetacharacters: Set<Character> = [";", "&", "|", "<", ">", "`", "$", "(", ")", "{", "}", "*", "?", "~", "!", "\n", "\r"]

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
                process.environment = [
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                    "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                    "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
                    "TMPDIR": NSTemporaryDirectory(),
                ]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                let capture = SandboxedOutputCapture()
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    capture.lock.lock(); defer { capture.lock.unlock() }
                    if capture.output.length < SandboxPolicy.maxOutputBytes {
                        let take = min(data.count, SandboxPolicy.maxOutputBytes - capture.output.length)
                        capture.output.append(data.subdata(in: 0..<take))
                        if take < data.count { capture.truncated = true }
                    } else {
                        capture.truncated = true
                    }
                    if let onLine, let text = String(data: data, encoding: .utf8) {
                        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                            capture.lineCount += 1
                            if capture.lineCount <= SandboxPolicy.maxOutputLines { onLine(line) }
                        }
                    }
                }
                let timeout = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + policy.timeoutSeconds, execute: timeout)
                let timeoutBox = WorkItemBox(timeout)
                process.terminationHandler = { _ in
                    timeoutBox.item.cancel()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let (text, truncated) = capture.lock.withLock {
                        (String(data: capture.output as Data, encoding: .utf8) ?? "", capture.truncated)
                    }
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

    private final class ProcessBox: @unchecked Sendable {
        var process: Process?
    }
}

private final class SandboxedOutputCapture: @unchecked Sendable {
    let lock = NSLock()
    let output = NSMutableData()
    var lineCount = 0
    var truncated = false
}

private final class WorkItemBox: @unchecked Sendable {
    let item: DispatchWorkItem
    init(_ item: DispatchWorkItem) { self.item = item }
}
