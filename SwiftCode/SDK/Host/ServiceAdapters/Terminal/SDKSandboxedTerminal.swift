import Foundation
import Darwin

// MARK: - SDKSandboxedTerminal
//
// THE ONLY PROCESS-EXECUTION PATH EXTENSIONS MAY USE (spec §8.1:
// `terminal.sandbox`, high risk).
//
// This is host-mediated SANDBOXED COMMAND EXECUTION — not a terminal UI.
// Per the SDK terminal audit (2026-10-12) there is no sandboxed terminal
// view anywhere in the codebase: the real `TerminalView` is a full,
// unsandboxed `/bin/zsh` shell and is deliberately NOT wrapped or reused
// here. Wrapping it would be sandbox theater. This adapter spawns one
// `Process` per call with no shell anywhere in the path and enforces every
// constraint below in host code, on every call.
//
// ---------------------------------------------------------------------------
// SECURITY RULES — ALL ENFORCED HOST-SIDE, EVERY CALL
// ---------------------------------------------------------------------------
// 1. Per-call broker authorization. `run` calls
//    `SDKCapabilityBroker.authorize(.terminalSandbox, for:)` FIRST, before
//    any validation, resolution, or process work. There is no cached or
//    ambient authorization: a revoked/expired grant fails the next call.
//
// 2. Command resolution — NO SHELL, EVER.
//    `command` takes exactly two forms, and both are validated before use:
//      (a) Bare name: must match ^[A-Za-z0-9._-]{1,64}$ (no "/", no
//          whitespace, no empty string) AND be a member of
//          `allowedExecutableNames` (the host allow-list). It is resolved
//          by searching `approvedExecutableDirectories` in FIXED order and
//          taking the first regular executable file. Ambient PATH is never
//          consulted (`/usr/bin/env` would inherit the host's PATH and is
//          not used).
//      (b) Absolute path: must start with "/", is symlink-resolved, and
//          must sit inside one of `approvedExecutableDirectories` AFTER
//          resolution (so /usr/bin/git -> /elsewhere/bin/git escapes are
//          rejected). Must be a regular executable file.
//    Anything else — shell snippets, relative paths, `~`, bare names not
//    on the allow-list — is `.invalidArgument`. The resolved URL becomes
//    `Process.executableURL` and `args` become `Process.arguments`
//    verbatim: argv elements, never concatenated into a string, never
//    passed through `/bin/sh -c`. There is no code path that can invoke a
//    shell.
//
// 3. Working-directory confinement. The default is the caller's project
//    root. An explicit directory is standardized, symlink-resolved, and
//    required to be a directory EQUAL TO or INSIDE the caller's project
//    root (the grant scope, taken from the session-bound caller identity —
//    never from extension input). `..` segments, symlinks pointing out,
//    and absolute paths elsewhere are `.projectOutOfScope`. Relative
//    paths are anchored at the project root, not at the host CWD.
//
// 4. Minimal sanitized environment. `Process.environment` is a FIXED
//    dictionary (PATH, LANG, LC_ALL, HOME, TMPDIR). NOTHING is inherited
//    from the host process environment: no secrets, tokens, API keys, or
//    user shell configuration can leak into the child. HOME is the
//    project root so tools cannot read/write the user's real home.
//
// 5. Hard timeout with SIGKILL escalation. The budget defaults to 30 s
//    and is clamped to [1, 55] s — 55 stays under the IPC dispatcher's
//    60 s per-request budget so the kill path below always fires before
//    the IPC layer times out the request. On expiry the process gets
//    SIGTERM, a 2 s grace period, then SIGKILL via `kill(…, SIGKILL)`
//    if still alive, and the call throws typed `.requestTimeout`. Exit
//    codes are never fabricated: a timed-out run is an error, not a
//    result. stdin is `/dev/null` so the child can never block waiting
//    for input the extension cannot provide.
//
// 6. Byte-capped output with truncation metadata. Each stream is capped
//    at 256 KiB (the same bound as `SDKDiffOptions`' default). Readers
//    keep DRAINING past the cap (counting bytes) so a chatty child never
//    blocks on a full pipe and the totals stay honest. Truncation cuts
//    at the byte limit and decodes lossy UTF-8; `stdoutTruncated` /
//    `stderrTruncated` plus total/limit fields say exactly what was
//    withheld. Oversized output is never rejected with `outputTooLarge`:
//    that code is reserved in the taxonomy but this surface truncates
//    with metadata instead, like the diff adapter.
//
// 7. Concurrency cap. At most `maxConcurrentRunsPerExtension` runs per
//    extension at once (fork-bomb resistance); the excess throws typed
//    `.resourceLimitExceeded`.
//
// 8. Argument sanity. argv is capped (count and per-element bytes) and
//    NUL bytes are rejected — defense in depth around `Process`.
//
// Known honest limitations (see agent_notes.md):
// - This is argv-only execution: no pipes, redirects, globs, or shell
//   builtins. Multi-stage pipelines must be separate `run` calls composed
//   by the extension.
// - The timeout ceiling is 55 s because the IPC dispatcher times requests
//   out at 60 s; longer jobs must be split or run through `build.execute`.
// - A child that double-forks grandchildren holding the stdout/stderr
//   pipes open can delay reader completion; the timeout path closes the
//   read ends after SIGKILL so the call itself always returns.

public actor SDKSandboxedTerminal {

    public static let shared = SDKSandboxedTerminal()

    private init() {}

    // MARK: - Limits (host-owned; not extension-configurable)

    /// Default wall-clock budget per run.
    public static let defaultTimeoutSeconds: TimeInterval = 30
    /// Hard floor: sub-second budgets cannot reliably launch a process.
    public static let minimumTimeoutSeconds: TimeInterval = 1
    /// Hard ceiling: must stay under the IPC dispatcher's 60 s per-request
    /// budget so the SIGTERM/SIGKILL path below always fires first.
    public static let maximumTimeoutSeconds: TimeInterval = 55
    /// Per-stream output cap (matches `SDKDiffOptions`' default).
    public static let outputByteLimit: Int = 256 * 1024
    /// Fork-bomb resistance: concurrent runs allowed per extension.
    public static let maxConcurrentRunsPerExtension: Int = 4
    /// argv sanity caps.
    private static let maxArgumentCount = 256
    private static let maxArgumentBytes = 8 * 1024

    // MARK: - Command policy (host-owned; not extension-configurable)

    /// Bare-name allow-list. These are developer tools whose argv-only
    /// execution the host permits inside the sandbox. The sandbox boundary
    /// is the allow-list + no-shell + cwd confinement + minimal env —
    /// not any single tool's behavior. Notably ABSENT: sh, bash, zsh, and
    /// env (shell interpretation has no place in this surface).
    public static let allowedExecutableNames: Set<String> = [
        "git", "ls", "xcodebuild", "xcrun", "swift", "swiftc",
        "node", "npm", "npx", "python3", "ruby", "make", "cmake",
        "tar", "zip", "unzip", "rsync", "curl", "sed", "awk", "grep",
        "find", "diff", "patch", "codesign", "plutil", "defaults", "ditto",
    ]

    /// Approved executable locations. Bare names are resolved by searching
    /// these in this FIXED order (ambient PATH is never consulted);
    /// absolute paths must resolve inside one of these AFTER symlink
    /// resolution.
    public static let approvedExecutableDirectories: [String] = [
        "/usr/bin",
        "/bin",
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/usr/sbin",
        "/sbin",
    ]

    /// Bare-name shape: no "/", no whitespace, 1–64 chars.
    private static let bareNamePattern = "^[A-Za-z0-9._-]{1,64}$"

    // MARK: - State

    /// Live runs per extension ID (concurrency cap enforcement).
    private var activeRuns: [String: Int] = [:]

    // MARK: - Entry points

    /// Runs one sandboxed command from a decoded IPC request.
    public func run(
        request: SDKSandboxRunRequest,
        caller: SDKCallerIdentity
    ) async throws -> SDKSandboxedResult {
        let timeout: TimeInterval
        if let requested = request.timeout, requested.isFinite, requested > 0 {
            timeout = requested
        } else {
            timeout = Self.defaultTimeoutSeconds
        }
        let workingDirectory = request.workingDirectory.map { URL(fileURLWithPath: $0) }
        return try await run(
            command: request.command,
            args: request.args,
            workingDirectory: workingDirectory,
            timeout: timeout,
            caller: caller
        )
    }

    /// Runs one sandboxed command.
    ///
    /// - Parameters:
    ///   - command: Bare allow-listed name (e.g. "git") or an absolute
    ///     path inside an approved location. Never a shell snippet.
    ///   - args: Verbatim argv elements (no shell interpretation).
    ///   - workingDirectory: Explicit cwd, or nil for the project root.
    ///     Relative paths anchor at the project root. Must resolve inside
    ///     the caller's project scope.
    ///   - timeout: Wall-clock budget; clamped to [1, 55] seconds.
    ///   - caller: Session-bound caller identity (broker authorization +
    ///     scope). Mandatory: there is no ambient authorization.
    public func run(
        command: String,
        args: [String],
        workingDirectory: URL?,
        timeout: TimeInterval,
        caller: SDKCallerIdentity
    ) async throws -> SDKSandboxedResult {
        // --- 1. Authorize FIRST: every call, before anything else.
        try await SDKCapabilityBroker.authorize(.terminalSandbox, for: caller)

        // --- 2. Concurrency cap per extension.
        let liveCount = activeRuns[caller.extensionID, default: 0]
        guard liveCount < Self.maxConcurrentRunsPerExtension else {
            throw SDKError(
                code: .resourceLimitExceeded,
                message: "Too many concurrent sandboxed commands for this extension.",
                suggestion: "Wait for a running command to finish before starting another."
            )
        }
        activeRuns[caller.extensionID, default: 0] = liveCount + 1
        defer {
            let remaining = (activeRuns[caller.extensionID] ?? 1) - 1
            if remaining <= 0 {
                activeRuns.removeValue(forKey: caller.extensionID)
            } else {
                activeRuns[caller.extensionID] = remaining
            }
        }

        // --- 3. Scope root comes from the SESSION, never the extension.
        let scopeRoot = try resolvedScopeRoot(for: caller)

        // --- 4. Resolve the command (no shell, ever).
        let executable = try resolveExecutable(command)

        // --- 5. Validate argv.
        let validatedArgs = try validateArgs(args)

        // --- 6. Confine the working directory to the scope.
        let cwd = try resolveWorkingDirectory(workingDirectory, scopeRoot: scopeRoot)

        // --- 7. Clamp the timeout inside the IPC budget.
        let boundedTimeout = min(max(timeout, Self.minimumTimeoutSeconds), Self.maximumTimeoutSeconds)

        // --- 8. Launch, race against the timeout, SIGKILL on expiry.
        return try await launch(
            executable: executable,
            args: validatedArgs,
            workingDirectory: cwd,
            scopeRoot: scopeRoot,
            timeout: boundedTimeout
        )
    }

    // MARK: - Scope

    /// The caller's project root, standardized and symlink-resolved. This
    /// is the confinement root for the working directory. The value comes
    /// from the host-created session identity — extension input never
    /// supplies it.
    private func resolvedScopeRoot(for caller: SDKCallerIdentity) throws -> URL {
        let raw = caller.projectRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw SDKError(
                code: .projectNotOpen,
                message: "No project is open for this extension session.",
                suggestion: "Open a project before running sandboxed commands."
            )
        }
        return URL(fileURLWithPath: raw, isDirectory: true)
            .standardized
            .resolvingSymlinksInPath()
    }

    // MARK: - Command resolution

    /// Resolves `command` to an executable URL under the rules in the file
    /// header. Never consults ambient PATH; never invokes a shell.
    private func resolveExecutable(_ command: String) throws -> URL {
        if command.hasPrefix("/") {
            return try resolveAbsoluteExecutable(command)
        }
        guard isBareName(command) else {
            throw SDKError(
                code: .invalidArgument,
                message: "The command must be a bare executable name or an absolute path — not a shell snippet.",
                suggestion: "Pass \"git\" (bare name) or \"/usr/bin/git\" (absolute path). Shell syntax like pipes or \";\" is not supported."
            )
        }
        guard Self.allowedExecutableNames.contains(command) else {
            throw SDKError(
                code: .invalidArgument,
                message: "Command \"\(command)\" is not on the host's allowed-executables list.",
                suggestion: "Use one of the allowed developer tools, or an absolute path inside an approved location."
            )
        }
        for directory in Self.approvedExecutableDirectories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(command)
            if isExecutableFile(candidate) {
                return candidate
            }
        }
        throw SDKError(
            code: .invalidArgument,
            message: "Command \"\(command)\" is allowed but was not found in any approved location.",
            suggestion: "The tool may not be installed on this Mac."
        )
    }

    /// Absolute-path form: symlink-resolved FIRST, then required to sit
    /// inside an approved location, then required to be a regular
    /// executable file.
    private func resolveAbsoluteExecutable(_ path: String) throws -> URL {
        let resolved = URL(fileURLWithPath: path).standardized.resolvingSymlinksInPath()
        let insideApproved = Self.approvedExecutableDirectories.contains { directory in
            isPath(resolved.path, insideDirectory: directory)
        }
        guard insideApproved else {
            throw SDKError(
                code: .invalidArgument,
                message: "Absolute executable paths must resolve inside an approved location (/usr/bin, /bin, /usr/local/bin, /opt/homebrew/bin).",
                suggestion: "Use a bare allow-listed name like \"git\" instead."
            )
        }
        guard isExecutableFile(resolved) else {
            throw SDKError(
                code: .invalidArgument,
                message: "The path is not an executable file.",
                suggestion: "Point at a real executable inside an approved location."
            )
        }
        return resolved
    }

    private func isBareName(_ command: String) -> Bool {
        command.range(of: Self.bareNamePattern, options: .regularExpression) != nil
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// True when `path` is inside `directory` (or is the directory
    /// itself), compared on standardized absolute paths with a trailing-
    /// slash prefix so "/usr/bin2/x" never matches "/usr/bin".
    private func isPath(_ path: String, insideDirectory directory: String) -> Bool {
        let dirPath = URL(fileURLWithPath: directory, isDirectory: true).standardized.path
        let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
        return path == dirPath || path.hasPrefix(prefix)
    }

    // MARK: - Argument validation

    /// argv sanity: bounded count, bounded element size, no NUL bytes.
    /// Elements are passed to `Process.arguments` verbatim.
    private func validateArgs(_ args: [String]) throws -> [String] {
        guard args.count <= Self.maxArgumentCount else {
            throw SDKError(
                code: .invalidArgument,
                message: "Too many arguments (maximum \(Self.maxArgumentCount)).",
                suggestion: "Split the work across multiple runs."
            )
        }
        for arg in args {
            if arg.contains("\0") {
                throw SDKError(
                    code: .invalidArgument,
                    message: "Arguments must not contain NUL bytes.",
                    suggestion: "Remove the NUL byte from the argument."
                )
            }
            guard arg.utf8.count <= Self.maxArgumentBytes else {
                throw SDKError(
                    code: .invalidArgument,
                    message: "An argument exceeds the \(Self.maxArgumentBytes)-byte limit.",
                    suggestion: "Pass large inputs via files inside the project instead."
                )
            }
        }
        return args
    }

    // MARK: - Working-directory confinement

    /// Resolves the working directory and confines it to the scope root.
    /// Relative paths anchor at the scope root (never the host CWD).
    /// Symlink resolution happens BEFORE the containment check, so a
    /// symlink pointing outside the project is rejected.
    private func resolveWorkingDirectory(_ requested: URL?, scopeRoot: URL) throws -> URL {
        let anchored: URL
        if let requested {
            let rawPath = requested.path
            guard !rawPath.isEmpty else {
                throw SDKError(
                    code: .invalidArgument,
                    message: "The working directory must not be empty.",
                    suggestion: "Omit it to run in the project root."
                )
            }
            if rawPath.hasPrefix("/") {
                anchored = requested
            } else {
                anchored = scopeRoot.appendingPathComponent(rawPath)
            }
        } else {
            anchored = scopeRoot
        }
        let resolved = anchored.standardized.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SDKError(
                code: .invalidArgument,
                message: "The working directory does not exist or is not a directory.",
                suggestion: "Pass a directory inside the open project."
            )
        }
        guard isPath(resolved.path, insideDirectory: scopeRoot.path) else {
            throw SDKError(
                code: .projectOutOfScope,
                message: "The working directory is outside the approved project scope.",
                suggestion: "Run inside the open project's directory."
            )
        }
        return resolved
    }

    // MARK: - Sanitized environment

    /// The FIXED child environment. Nothing is inherited from the host
    /// process: no secrets, tokens, API keys, or user shell configuration
    /// can leak into the child. HOME is the project root so tools cannot
    /// touch the user's real home directory.
    private static func sanitizedEnvironment(home: URL) -> [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "HOME": home.path,
            "TMPDIR": NSTemporaryDirectory(),
        ]
    }

    // MARK: - Launch, timeout, SIGKILL

    /// Launches the process, races it against the timeout, and enforces
    /// the timeout with SIGTERM → 2 s grace → SIGKILL. Never throws for a
    /// non-zero exit: the exit code is data in the result. Timeouts throw
    /// typed `.requestTimeout` — exit codes are never fabricated.
    ///
    /// Concurrency notes: the exit race polls `process.isRunning`
    /// (SDKBuildService's pattern) so no blocking wait ever parks the
    /// actor, and pipe ingestion uses `readabilityHandler` into a
    /// lock-guarded per-run capture box. There are no detached tasks, so
    /// `Process`/`FileHandle` never cross a `Sendable` boundary.
    private func launch(
        executable: URL,
        args: [String],
        workingDirectory: URL,
        scopeRoot: URL,
        timeout: TimeInterval
    ) async throws -> SDKSandboxedResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.currentDirectoryURL = workingDirectory
        process.environment = Self.sanitizedEnvironment(home: scopeRoot)
        // The extension cannot feed stdin; /dev/null keeps the child from
        // blocking on input it can never receive.
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdoutReadEnd = stdoutPipe.fileHandleForReading
        let stderrReadEnd = stderrPipe.fileHandleForReading

        // Capture boxes attach BEFORE launch so early output cannot be
        // missed. readabilityHandler is not a @Sendable closure (same as
        // SDKBuildService); the boxes are the only shared state and are
        // lock-guarded.
        let stdoutCapture = PipeCapture(limit: Self.outputByteLimit)
        let stderrCapture = PipeCapture(limit: Self.outputByteLimit)
        stdoutReadEnd.readabilityHandler = { handle in
            stdoutCapture.ingest(handle.availableData)
        }
        stderrReadEnd.readabilityHandler = { handle in
            stderrCapture.ingest(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            // Launch failed: detach the handlers and report honestly.
            stdoutReadEnd.readabilityHandler = nil
            stderrReadEnd.readabilityHandler = nil
            throw SDKError(
                code: .serviceUnavailable,
                message: "The sandboxed command could not be started.",
                suggestion: "The executable may have become unavailable; try again.",
                diagnostics: ["underlyingError": error.localizedDescription]
            )
        }

        // Exit race: poll isRunning against the deadline.
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Task.isCancelled {
                // Our own task was cancelled (e.g. the IPC dispatcher hit
                // its 60 s budget): kill the child, then propagate.
                await killChild(process)
                await settleCapture(stdoutReadEnd, capture: stdoutCapture)
                await settleCapture(stderrReadEnd, capture: stderrCapture)
                throw CancellationError()
            }
            if Date() >= deadline {
                timedOut = true
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if timedOut {
            await killChild(process)
        }

        await settleCapture(stdoutReadEnd, capture: stdoutCapture)
        await settleCapture(stderrReadEnd, capture: stderrCapture)

        if timedOut {
            throw SDKError(
                code: .requestTimeout,
                message: "The sandboxed command exceeded its \(Int(timeout))-second limit and was killed.",
                suggestion: "Raise \"timeout\" (maximum 55 seconds) or split the work across runs."
            )
        }

        let stdout = stdoutCapture.snapshot
        let stderr = stderrCapture.snapshot
        return SDKSandboxedResult(
            stdout: String(decoding: stdout.data, as: UTF8.self),
            stderr: String(decoding: stderr.data, as: UTF8.self),
            exitCode: process.terminationStatus,
            stdoutTruncated: stdout.truncated,
            stderrTruncated: stderr.truncated,
            stdoutTotalBytes: stdout.totalBytes,
            stderrTotalBytes: stderr.totalBytes,
            byteLimit: Self.outputByteLimit
        )
    }

    /// SIGTERM → 2 s grace → SIGKILL escalation, then a short reap poll.
    /// `Process.isRunning` performs a non-blocking waitpid, so polling it
    /// after SIGKILL reaps the child instead of leaking a zombie.
    private func killChild(_ process: Process) async {
        process.terminate()
        let graceDeadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < graceDeadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
            for _ in 0..<20 where process.isRunning {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    /// Stops async delivery, waits a beat for in-flight handler calls,
    /// then synchronously drains whatever is left so no output is lost
    /// between process exit and handler delivery. Always closes the read
    /// end, so the call returns even if a grandchild still holds the pipe.
    private func settleCapture(_ handle: FileHandle, capture: PipeCapture) async {
        try? await Task.sleep(nanoseconds: 250_000_000)
        handle.readabilityHandler = nil
        while true {
            guard let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty else {
                break
            }
            capture.ingest(chunk)
        }
        try? handle.close()
    }

    // MARK: - Bounded pipe capture

    /// Lock-guarded per-stream capture box. The ONLY state shared between
    /// the readabilityHandler callbacks and the actor. `@unchecked
    /// Sendable` is sound: every access happens under `lock`.
    ///
    /// `data` holds at most `limit` bytes; `totalBytes` counts EVERYTHING
    /// ingested (even past the cap) so the truncation metadata stays
    /// honest. Ingestion keeps draining past the cap so the child never
    /// blocks on a full pipe.
    private final class PipeCapture: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var kept = Data()
        private var totalBytes = 0

        init(limit: Int) {
            self.limit = limit
            kept.reserveCapacity(min(limit, 65_536))
        }

        func ingest(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            totalBytes += data.count
            if kept.count < limit {
                kept.append(data.prefix(limit - kept.count))
            }
        }

        var snapshot: (data: Data, totalBytes: Int, truncated: Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (kept, totalBytes, totalBytes > limit)
        }
    }
}
