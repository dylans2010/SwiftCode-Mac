import Foundation
import Darwin

public actor SDKSandboxedTerminal {

    public static let shared = SDKSandboxedTerminal()

    private init() {}

    public static let defaultTimeoutSeconds: TimeInterval = 30
    public static let minimumTimeoutSeconds: TimeInterval = 1
    public static let maximumTimeoutSeconds: TimeInterval = 55
    public static let outputByteLimit: Int = 256 * 1024
    public static let maxConcurrentRunsPerExtension: Int = 4
    private static let maxArgumentCount = 256
    private static let maxArgumentBytes = 8 * 1024

    public static let allowedExecutableNames: Set<String> = [
        "git", "ls", "xcodebuild", "xcrun", "swift", "swiftc",
        "node", "npm", "npx", "python3", "ruby", "make", "cmake",
        "tar", "zip", "unzip", "rsync", "curl", "sed", "awk", "grep",
        "find", "diff", "patch", "codesign", "plutil", "defaults", "ditto",
    ]

    public static let approvedExecutableDirectories: [String] = [
        "/usr/bin",
        "/bin",
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/usr/sbin",
        "/sbin",
    ]

    private static let bareNamePattern = "^[A-Za-z0-9._-]{1,64}$"

    private var activeRuns: [String: Int] = [:]

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

    public func run(
        command: String,
        args: [String],
        workingDirectory: URL?,
        timeout: TimeInterval,
        caller: SDKCallerIdentity
    ) async throws -> SDKSandboxedResult {
        try await SDKCapabilityBroker.authorize(.terminalSandbox, for: caller)

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

        let scopeRoot = try resolvedScopeRoot(for: caller)

        let executable = try resolveExecutable(command)

        let validatedArgs = try validateArgs(args)

        let cwd = try resolveWorkingDirectory(workingDirectory, scopeRoot: scopeRoot)

        let boundedTimeout = min(max(timeout, Self.minimumTimeoutSeconds), Self.maximumTimeoutSeconds)

        return try await launch(
            executable: executable,
            args: validatedArgs,
            workingDirectory: cwd,
            scopeRoot: scopeRoot,
            timeout: boundedTimeout
        )
    }

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

    private func isPath(_ path: String, insideDirectory directory: String) -> Bool {
        let dirPath = URL(fileURLWithPath: directory, isDirectory: true).standardized.path
        let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
        return path == dirPath || path.hasPrefix(prefix)
    }

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

    private static func sanitizedEnvironment(home: URL) -> [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "HOME": home.path,
            "TMPDIR": NSTemporaryDirectory(),
        ]
    }

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
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdoutReadEnd = stdoutPipe.fileHandleForReading
        let stderrReadEnd = stderrPipe.fileHandleForReading

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
            stdoutReadEnd.readabilityHandler = nil
            stderrReadEnd.readabilityHandler = nil
            throw SDKError(
                code: .serviceUnavailable,
                message: "The sandboxed command could not be started.",
                suggestion: "The executable may have become unavailable; try again.",
                diagnostics: ["underlyingError": error.localizedDescription]
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Task.isCancelled {
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
