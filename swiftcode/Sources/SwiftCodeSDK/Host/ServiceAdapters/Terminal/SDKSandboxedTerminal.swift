import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public actor SDKSandboxedTerminal {
    public static let shared = SDKSandboxedTerminal()

    public static let defaultTimeout: TimeInterval = 30
    public static let minTimeout: TimeInterval = 1
    public static let maxTimeout: TimeInterval = 55
    public static let outputByteLimit = 262_144
    public static let maxConcurrentRunsPerExtension = 4
    public static let maxArgumentCount = 256
    public static let maxArgumentBytes = 8_192
    public static let killGrace: TimeInterval = 2

    public static let allowedExecutableNames: Set<String> = [
        "git", "ls", "xcodebuild", "xcrun", "swift", "swiftc",
        "node", "npm", "npx", "python3", "ruby", "make", "cmake",
        "tar", "zip", "unzip", "rsync", "curl", "sed", "awk", "grep",
        "find", "diff", "patch", "codesign", "plutil", "defaults", "ditto",
    ]

    public static let approvedExecutableDirectories: [String] = [
        "/usr/bin", "/bin", "/usr/local/bin", "/opt/homebrew/bin", "/usr/sbin", "/sbin",
    ]

    private var runningCounts: [String: Int] = [:]

    private init() {}

    public func run(caller: SDKCallerIdentity, request: SDKSandboxRunRequest) async throws -> SDKSandboxedResult {
        try await SDKCapabilityBroker.authorize(.terminalSandbox, for: caller)
        let executable = try Self.resolveExecutable(request.command)
        try Self.validateArguments(request.args)
        let timeout = (request.timeout ?? Self.defaultTimeout).clamped(to: Self.minTimeout...Self.maxTimeout)
        let workingDirectory = try Self.resolveWorkingDirectory(request.workingDirectory, scopeRoot: caller.projectRootPath)
        guard (runningCounts[caller.extensionID] ?? 0) < Self.maxConcurrentRunsPerExtension else {
            throw SDKError(code: .resourceLimitExceeded, message: "Too many concurrent sandboxed runs for this extension.")
        }
        runningCounts[caller.extensionID, default: 0] += 1
        defer { runningCounts[caller.extensionID, default: 1] -= 1 }
        return try await Self.execute(
            executable: executable,
            arguments: request.args,
            workingDirectory: workingDirectory,
            projectRoot: caller.projectRootPath,
            timeout: timeout
        )
    }

    static func resolveExecutable(_ command: String) throws -> String {
        guard !command.isEmpty, !command.contains("\0") else {
            throw SDKError(code: .invalidArgument, message: "The command is invalid.")
        }
        if command.contains("/") {
            return try resolveAbsoluteExecutable(command)
        }
        guard command.count <= 64,
              command.unicodeScalars.allSatisfy({ $0.isASCIIAlphanumeric || "._-".contains(Character($0)) }) else {
            throw SDKError(code: .invalidArgument, message: "The command name is invalid.")
        }
        guard allowedExecutableNames.contains(command) else {
            throw SDKError(code: .permissionDenied, message: "The command “\(command)” is not allowed in the sandbox.")
        }
        for directory in approvedExecutableDirectories {
            let path = (directory as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        throw SDKError(code: .serviceUnavailable, message: "The command “\(command)” was not found.")
    }

    private static func resolveAbsoluteExecutable(_ command: String) throws -> String {
        let url = URL(fileURLWithPath: command)
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        let baseName = (resolved as NSString).lastPathComponent
        guard allowedExecutableNames.contains(baseName) else {
            throw SDKError(code: .permissionDenied, message: "The command “\(baseName)” is not allowed in the sandbox.")
        }
        guard approvedExecutableDirectories.contains(where: { resolved == $0 || resolved.hasPrefix($0 + "/") }) else {
            throw SDKError(code: .permissionDenied, message: "The command is outside the approved executable directories.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: resolved) else {
            throw SDKError(code: .invalidArgument, message: "The command is not an executable file.")
        }
        return resolved
    }

    static func validateArguments(_ args: [String]) throws {
        guard args.count <= maxArgumentCount else {
            throw SDKError(code: .invalidArgument, message: "Too many arguments.")
        }
        for arg in args {
            guard arg.utf8.count <= maxArgumentBytes, !arg.contains("\0") else {
                throw SDKError(code: .invalidArgument, message: "An argument is too large.")
            }
        }
    }

    static func resolveWorkingDirectory(_ requested: String?, scopeRoot: String) throws -> String {
        let scope = URL(fileURLWithPath: scopeRoot).resolvingSymlinksInPath().standardizedFileURL.path
        guard let requested, !requested.isEmpty else { return scope }
        let resolved = URL(fileURLWithPath: requested).resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved == scope || resolved.hasPrefix(scope + "/") else {
            throw SDKError(code: .projectOutOfScope, message: "The working directory is outside the approved project.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SDKError(code: .invalidArgument, message: "The working directory does not exist.")
        }
        return resolved
    }

    private static func execute(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        projectRoot: String,
        timeout: TimeInterval
    ) async throws -> SDKSandboxedResult {
        let holder = ProcessHolder()
        return try await withThrowingTaskGroup(of: SDKSandboxedResult.self) { group in
            group.addTask {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
                process.standardInput = FileHandle.nullDevice
                process.environment = [
                    "PATH": approvedExecutableDirectories.joined(separator: ":"),
                    "LANG": "en_US.UTF-8",
                    "LC_ALL": "en_US.UTF-8",
                    "HOME": projectRoot,
                    "TMPDIR": FileManager.default.temporaryDirectory.path,
                ]
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                let stdoutCapture = PipeCapture(limit: outputByteLimit)
                let stderrCapture = PipeCapture(limit: outputByteLimit)
                stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
                    stdoutCapture.append(fh.availableData)
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { fh in
                    stderrCapture.append(fh.availableData)
                }
                await holder.set(process)
                defer { Task { await holder.set(nil) } }
                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    throw SDKError(code: .serviceUnavailable, message: "Could not start the command.", diagnostics: ["underlyingError": error.localizedDescription])
                }
                process.waitUntilExit()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutCapture.append(stdoutPipe.fileHandleForReading.availableData)
                stderrCapture.append(stderrPipe.fileHandleForReading.availableData)
                if await holder.timedOut {
                    throw SDKError(code: .requestTimeout, message: "The sandboxed command timed out.")
                }
                return SDKSandboxedResult(
                    stdout: String(decoding: stdoutCapture.kept, as: UTF8.self),
                    stderr: String(decoding: stderrCapture.kept, as: UTF8.self),
                    exitCode: process.terminationStatus,
                    stdoutTruncated: stdoutCapture.truncated,
                    stderrTruncated: stderrCapture.truncated,
                    stdoutTotalBytes: stdoutCapture.totalBytes,
                    stderrTotalBytes: stderrCapture.totalBytes,
                    byteLimit: outputByteLimit
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                await holder.terminateGracefully(grace: killGrace)
                throw TimeoutSignal()
            }
            do {
                guard let result = try await group.next() else {
                    throw SDKError(code: .serviceUnavailable, message: "The sandboxed run produced no result.")
                }
                group.cancelAll()
                return result
            } catch is TimeoutSignal {
                group.cancelAll()
                throw SDKError(code: .requestTimeout, message: "The sandboxed command timed out.")
            }
        }
    }
}

private actor ProcessHolder {
    private var process: Process?
    private(set) var timedOut = false

    func set(_ process: Process?) {
        self.process = process
    }

    func terminateGracefully(grace: TimeInterval) async {
        timedOut = true
        process?.terminate()
        try? await Task.sleep(for: .seconds(grace))
        if let process, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

private struct TimeoutSignal: Error {}

private final class PipeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private(set) var totalBytes = 0
    private(set) var truncated = false

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        totalBytes += chunk.count
        if data.count >= limit {
            truncated = true
            return
        }
        let remaining = limit - data.count
        if chunk.count <= remaining {
            data.append(chunk)
        } else {
            data.append(chunk.prefix(remaining))
            truncated = true
        }
    }

    var kept: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private extension TimeInterval {
    func clamped(to range: ClosedRange<TimeInterval>) -> TimeInterval {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Unicode.Scalar {
    var isASCIIAlphanumeric: Bool {
        (value >= 48 && value <= 57) || (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
    }
}
