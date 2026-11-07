import Foundation

public enum SDKNodeLauncher {

    private static let wellKnownNodePaths = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        "/usr/bin/node",
    ]

    public static func resolveNodeURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["SWIFTCODE_NODE_PATH"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let url = executableFile(atPath: override) else {
                throw SDKError(
                    code: .runtimeUnavailable,
                    message: "SWIFTCODE_NODE_PATH points to '\(override)', which is not an existing executable file.",
                    suggestion: "Point SWIFTCODE_NODE_PATH at a Node.js 20 or later binary, or unset it to let SwiftCode search the standard locations."
                )
            }
            return url
        }

        for path in wellKnownNodePaths {
            if let url = executableFile(atPath: path) {
                return url
            }
        }

        if let pathValue = ProcessInfo.processInfo.environment["PATH"], !pathValue.isEmpty {
            for component in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
                let candidate = URL(fileURLWithPath: String(component)).appendingPathComponent("node")
                if let url = executableFile(atPath: candidate.path) {
                    return url
                }
            }
        }

        throw SDKError(
            code: .runtimeUnavailable,
            message: "Node.js is required to run TypeScript extensions but was not found.",
            suggestion: "Install Node.js 20 or later from nodejs.org, via Homebrew (brew install node), or set SWIFTCODE_NODE_PATH."
        )
    }

    private static let secretEnvNameFragments = [
        "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL",
        "PRIVATE_KEY", "API_KEY", "APIKEY", "ACCESS_KEY",
        "AUTH_TOKEN", "CLIENT_SECRET", "SESSION_TOKEN",
    ]

    private static func sanitizedEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { name, _ in
            let upper = name.uppercased()
            return !secretEnvNameFragments.contains { upper.contains($0) }
        }
    }

    public static func launch(
        entrypoint: URL,
        workingDirectory: URL,
        arguments: [String] = []
    ) throws -> SDKLaunchedRuntime {
        guard entrypoint.isFileURL else {
            throw SDKError(
                code: .runtimeLaunchFailed,
                message: "The extension entry point is not a file URL.",
                suggestion: "The extension package failed validation; reinstall the extension.",
                diagnostics: ["entrypoint": entrypoint.absoluteString]
            )
        }
        guard isRegularFile(at: entrypoint) else {
            throw SDKError(
                code: .runtimeLaunchFailed,
                message: "The extension entry point is missing or is not a file.",
                suggestion: "Reinstall the extension; its declared entry point could not be found.",
                diagnostics: ["entrypoint": entrypoint.path]
            )
        }

        let nodeURL = try resolveNodeURL()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [entrypoint.path] + arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = sanitizedEnvironment()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw SDKError(
                code: .runtimeLaunchFailed,
                message: "The extension runtime failed to start for '\(entrypoint.lastPathComponent)'.",
                suggestion: "Verify the Node.js installation and that the extension entry point is readable, then try again.",
                diagnostics: [
                    "nodePath": nodeURL.path,
                    "entrypoint": entrypoint.path,
                    "workingDirectory": workingDirectory.path,
                    "underlyingError": String(describing: error),
                ]
            )
        }

        return SDKLaunchedRuntime(
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )
    }

    private static func executableFile(atPath path: String) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: expanded) else {
            return nil
        }
        return URL(fileURLWithPath: expanded)
    }

    private static func isRegularFile(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeRegular
    }
}

public actor SDKLaunchedRuntime {

    public nonisolated(unsafe) let stdinPipe: Pipe
    public nonisolated(unsafe) let stdoutPipe: Pipe
    public nonisolated(unsafe) let stderrPipe: Pipe
    public nonisolated let processIdentifier: Int32

    private let process: Process

    init(process: Process, stdinPipe: Pipe, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.processIdentifier = process.processIdentifier
    }

    public var isRunning: Bool {
        process.isRunning
    }

    public func terminate() {
        process.terminate()
    }

    public func waitForExit() async -> Int32 {
        if !process.isRunning {
            return process.terminationStatus
        }
        let process = self.process
        return await withCheckedContinuation { continuation in
            let gate = TerminationGate()
            process.terminationHandler = { finished in
                finished.terminationHandler = nil
                if gate.claim() {
                    continuation.resume(returning: finished.terminationStatus)
                }
            }
            if !process.isRunning, gate.claim() {
                process.terminationHandler = nil
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }
}

private final class TerminationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
