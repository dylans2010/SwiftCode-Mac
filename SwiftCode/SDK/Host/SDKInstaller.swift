import Foundation
import os.log

// MARK: - SDKInstaller
//
// Real installer for the `@swiftcode/sdk` npm package (spec §5, "Studio
// first-launch SDK installer").
//
// What it does:
//   - Runs `npm install <url> --prefix <dir>` through a real Swift
//     `Process`, streaming live stdout/stderr lines to the caller.
//   - Never reports success unless `<prefix>/node_modules/@swiftcode/sdk/`
//     `package.json` resolves AND parses with a non-empty `version`.
//     A non-zero npm exit, a missing package.json, or an unparseable
//     version is reported as failure carrying the REAL npm output —
//     never a fake "installed".
//   - Idempotent: `inspect(prefix:)` classifies an existing install as
//     `.ok` / `.missing` / `.versionMismatch` / `.corrupt`, and the
//     install path uses that to skip, install, or repair.
//   - Fallback: if GitHub is unreachable, installs from an app-bundled
//     SDK copy (parameter or Bundle.main resource) and says so honestly
//     via `InstallResult.usedFallback`.
//
// Testability: the npm executable, the reachability probe, the prefix,
// and the fallback source are all injectable via `InstallOptions`, so
// tests can point at a stub home directory and a stub `npm` script.
//
// macOS 15, Swift 6. Verification and remaining release gates are
// documented in SDK/Documentation/Release-Readiness.md.

public enum SDKInstaller {

    // MARK: - Configuration

    /// The npm package installed.
    public static let packageName = "@swiftcode/sdk"

    /// Pinned remote distribution. The exact archive is probed and verified;
    /// unavailable or incomplete remote releases fall back to the bundled SDK.
    public static let downloadURL = URL(string: "https://raw.githubusercontent.com/dylans2010/SwiftCode-Mac/sdk-v1.0.0/SwiftCode/SDK/Distribution/swiftcode-sdk-1.0.0.tgz")!

    /// The version the pinned tarball is expected to contain.
    public static let expectedVersion = "1.0.0"

    /// Default install location: `~/.swiftcode/sdk`. Overridable per
    /// call (and per test) via `InstallOptions.prefix`.
    public static var defaultPrefix: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swiftcode/sdk", isDirectory: true)
    }

    private static let logger = Logger(
        subsystem: "com.swiftcode.app",
        category: "SDKInstaller"
    )

    // MARK: - Inspection

    /// Classification of whatever currently lives at `prefix`.
    public enum Inspection: Sendable, Equatable {
        /// A usable install: package.json resolves, names the right
        /// package, and carries the expected version.
        case ok(version: String)
        /// Nothing installed at this prefix.
        case missing
        /// package.json resolves and parses, but the version differs
        /// from `expectedVersion`.
        case versionMismatch(actual: String)
        /// Something is there but it is not a usable install
        /// (unreadable file, invalid JSON, wrong package, no version).
        case corrupt(reason: String)
    }

    /// Inspects the install state at `prefix` (default
    /// `~/.swiftcode/sdk`). Pure file-system read — no network, no
    /// subprocess. The install path uses this to decide between
    /// skip / install / repair.
    public static func inspect(
        prefix: URL? = nil,
        expectedVersion: String = SDKInstaller.expectedVersion
    ) -> Inspection {
        let root = prefix ?? defaultPrefix
        let packageJSON = root
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent(packageName, isDirectory: true)
            .appendingPathComponent("package.json")

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: packageJSON.path) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: packageJSON) else {
            return .corrupt(reason: "package.json exists at \(packageJSON.path) but could not be read.")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .corrupt(reason: "package.json at \(packageJSON.path) is not valid JSON.")
        }
        if (json["name"] as? String) != packageName {
            return .corrupt(reason: "package.json at \(packageJSON.path) must name '\(packageName)'.")
        }
        guard
            let version = (json["version"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !version.isEmpty
        else {
            return .corrupt(reason: "package.json at \(packageJSON.path) has no usable \"version\" field.")
        }
        if version != expectedVersion {
            return .versionMismatch(actual: version)
        }
        let packageRoot = packageJSON.deletingLastPathComponent()
        for entry in ["dist/index.js", "dist/index.d.ts", "dist/assist.js", "dist/assistUI.js"] {
            guard fileManager.fileExists(atPath: packageRoot.appendingPathComponent(entry).path) else {
                return .corrupt(reason: "SDK entry point \(entry) is missing at \(packageRoot.path).")
            }
        }
        return .ok(version: version)
    }

    // MARK: - Install

    /// One streamed line of installer output.
    public struct LogLine: Sendable, Equatable {
        public enum Stream: String, Sendable {
            case stdout
            case stderr
        }
        public var stream: Stream
        public var text: String

        public init(stream: Stream, text: String) {
            self.stream = stream
            self.text = text
        }
    }

    /// Options for `install(_:onLine:)`. Every external dependency is
    /// injectable so tests can stub the home directory, the npm binary,
    /// and the reachability probe.
    public struct InstallOptions: Sendable {
        /// npm `--prefix`. Defaults to `~/.swiftcode/sdk`.
        public var prefix: URL = SDKInstaller.defaultPrefix
        /// Remote tarball installed when GitHub is reachable.
        public var downloadURL: URL = SDKInstaller.downloadURL
        /// Version the verified install must carry.
        public var expectedVersion: String = SDKInstaller.expectedVersion
        /// Fallback source used when GitHub is unreachable: a local
        /// `.tgz` or directory that `npm install` accepts. `nil` means
        /// auto-detect from the app bundle.
        public var bundledFallbackURL: URL? = nil
        /// Explicit npm binary. `nil` means resolve from known locations
        /// plus `PATH` (see `resolveNPMExecutable()`).
        public var npmExecutable: URL? = nil
        /// Reachability check for the download URL. `nil` means a real
        /// `URLSession` HEAD probe.
        public var reachabilityProbe: (@Sendable (URL) async -> Bool)? = nil
        /// Maximum seconds for one `npm install` invocation. Exceeding
        /// it terminates the process and reports a real timeout error.
        /// `nil` disables the timeout.
        public var timeout: TimeInterval? = 600

        public init() {}
    }

    /// The outcome of `install(_:onLine:)`. `success` is true ONLY when
    /// the post-install verification (`inspect`) returned `.ok`.
    /// `usedFallback` is true ONLY when the verified install came from
    /// the bundled fallback source rather than GitHub.
    public struct InstallResult: Sendable, Equatable {
        public var success: Bool
        public var installedVersion: String?
        public var usedFallback: Bool
        public var message: String
        /// Full npm transcript (each entry prefixed `[stdout]`/`[stderr]`).
        /// On failure this carries the real error text.
        public var log: [String]
    }

    /// Errors that abort the install before npm can even run.
    public enum InstallerError: Error, LocalizedError, Sendable {
        case npmNotFound(searchedPaths: [String])
        case installTimedOut(seconds: TimeInterval)
        case internalError(String)

        public var errorDescription: String? {
            switch self {
            case .npmNotFound(let searchedPaths):
                return "npm was not found. Searched: \(searchedPaths.joined(separator: ", ")). Install Node.js (https://nodejs.org) and try again."
            case .installTimedOut(let seconds):
                return "npm install timed out after \(Int(seconds)) seconds and was terminated."
            case .internalError(let detail):
                return "Installer internal error: \(detail)"
            }
        }
    }

    /// Runs the install. Idempotent: an already-`.ok` prefix short-
    /// circuits to success without spawning npm. Streams every stdout/
    /// stderr line to `onLine` as it arrives.
    public static func install(
        options: InstallOptions = InstallOptions(),
        onLine: @escaping @Sendable (LogLine) -> Void = { _ in }
    ) async -> InstallResult {
        let transcript = TranscriptCollector()
        let record: @Sendable (LogLine) -> Void = { line in
            transcript.append("[\(line.stream.rawValue)] \(line.text)")
            onLine(line)
        }

        // 1. Idempotent short-circuit / repair decision.
        switch inspect(prefix: options.prefix, expectedVersion: options.expectedVersion) {
        case .ok(let version):
            logger.info("SDKInstaller: already installed (\(version)) at \(options.prefix.path, privacy: .public) — skipping npm.")
            return InstallResult(
                success: true,
                installedVersion: version,
                usedFallback: false,
                message: "SwiftCode SDK \(version) is already installed at \(options.prefix.path).",
                log: []
            )
        case .missing:
            logger.info("SDKInstaller: no install at \(options.prefix.path, privacy: .public) — installing.")
        case .versionMismatch(let actual):
            logger.info("SDKInstaller: version mismatch (found \(actual, privacy: .public), expected \(options.expectedVersion, privacy: .public)) — repairing.")
        case .corrupt(let reason):
            logger.info("SDKInstaller: corrupt install (\(reason, privacy: .public)) — repairing.")
        }

        // 2. Locate npm.
        let npm: URL
        do {
            npm = try options.npmExecutable ?? resolveNPMExecutable()
        } catch {
            let message = error.localizedDescription
            logger.error("SDKInstaller: \(message, privacy: .public)")
            return InstallResult(success: false, installedVersion: nil, usedFallback: false, message: message, log: transcript.lines)
        }

        // 3. Decide the source: GitHub when reachable, else the bundled
        //    fallback — but only when it actually exists on disk.
        let probe: @Sendable (URL) async -> Bool =
            options.reachabilityProbe ?? { await defaultReachabilityProbe($0) }
        let githubReachable = await probe(options.downloadURL)
        let fallbackURL = options.bundledFallbackURL ?? defaultBundledFallbackURL()
        let fallbackExists = fallbackURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        var usedFallback = false
        var installExitedSuccessfully = false
        var attemptErrors: [String] = []

        if githubReachable {
            record(LogLine(stream: .stdout, text: "Downloading SwiftCode SDK from GitHub…"))
            do {
                let exitCode = try await runNPM(
                    npm,
                    source: options.downloadURL.absoluteString,
                    prefix: options.prefix,
                    timeout: options.timeout,
                    onLine: record
                )
                installExitedSuccessfully = exitCode == 0
                if exitCode != 0 {
                    attemptErrors.append("npm install from GitHub exited with code \(exitCode).")
                }
            } catch {
                attemptErrors.append("npm install from GitHub failed: \(error.localizedDescription)")
            }
            if installExitedSuccessfully {
                switch inspect(prefix: options.prefix, expectedVersion: options.expectedVersion) {
                case .ok:
                    break
                case .missing:
                    installExitedSuccessfully = false
                    attemptErrors.append("The remote package is missing after installation.")
                case .corrupt(let reason):
                    installExitedSuccessfully = false
                    attemptErrors.append("The remote package failed verification: \(reason)")
                case .versionMismatch(let actual):
                    installExitedSuccessfully = false
                    attemptErrors.append("The remote package version \(actual) does not match \(options.expectedVersion).")
                }
            }
            // A failed download or incomplete package falls through to the
            // bundled release, including stale archives sharing a version.
            if !attemptErrors.isEmpty, fallbackExists, let fallbackURL {
                usedFallback = true
                attemptErrors.append("Retrying with the SDK copy bundled with SwiftCode.")
                record(LogLine(stream: .stdout, text: "GitHub install failed — installing from the bundled SDK copy…"))
                do {
                    let exitCode = try await runNPM(
                        npm,
                        source: fallbackURL.path,
                        prefix: options.prefix,
                        timeout: options.timeout,
                        onLine: record
                    )
                    installExitedSuccessfully = exitCode == 0
                    if exitCode != 0 {
                        attemptErrors.append("npm install from the bundled copy exited with code \(exitCode).")
                    }
                } catch {
                    attemptErrors.append("npm install from the bundled copy failed: \(error.localizedDescription)")
                }
            }
        } else if fallbackExists, let fallbackURL {
            usedFallback = true
            record(LogLine(stream: .stdout, text: "GitHub is unreachable — installing from the SDK copy bundled with SwiftCode…"))
            logger.info("SDKInstaller: GitHub unreachable; using bundled fallback at \(fallbackURL.path, privacy: .public).")
            do {
                let exitCode = try await runNPM(
                    npm,
                    source: fallbackURL.path,
                    prefix: options.prefix,
                    timeout: options.timeout,
                    onLine: record
                )
                installExitedSuccessfully = exitCode == 0
                if exitCode != 0 {
                    attemptErrors.append("npm install from the bundled copy exited with code \(exitCode).")
                }
            } catch {
                attemptErrors.append("npm install from the bundled copy failed: \(error.localizedDescription)")
            }
        } else {
            let message = "GitHub is unreachable and no bundled SDK copy was found in the app, so the SDK cannot be installed right now. Check your network connection and try again."
            logger.error("SDKInstaller: \(message, privacy: .public)")
            return InstallResult(success: false, installedVersion: nil, usedFallback: false, message: message, log: transcript.lines)
        }

        guard installExitedSuccessfully else {
            return InstallResult(success: false, installedVersion: nil, usedFallback: usedFallback,
                message: (attemptErrors + transcript.lastLines(12)).joined(separator: "\n"), log: transcript.lines)
        }

        // 4. Verify: resolve package.json and require a non-empty version.
        //    Success is reported ONLY here.
        switch inspect(prefix: options.prefix, expectedVersion: options.expectedVersion) {
        case .ok(let version):
            let sourceDescription = usedFallback
                ? "the SDK copy bundled with SwiftCode (remote download unavailable)"
                : "GitHub"
            let message = "SwiftCode SDK \(version) installed at \(options.prefix.path) from \(sourceDescription)."
            logger.info("SDKInstaller: \(message, privacy: .public)")
            return InstallResult(
                success: true,
                installedVersion: version,
                usedFallback: usedFallback,
                message: message,
                log: transcript.lines
            )
        case .missing, .corrupt, .versionMismatch:
            let detail: String
            switch inspect(prefix: options.prefix, expectedVersion: options.expectedVersion) {
            case .missing:
                detail = "npm finished but node_modules/@swiftcode/sdk/package.json is still missing at \(options.prefix.path)."
            case .corrupt(let reason):
                detail = "npm finished but the install is corrupt: \(reason)"
            case .versionMismatch(let actual):
                detail = "npm installed version \(actual), which does not match the expected \(options.expectedVersion)."
            case .ok:
                detail = "unexpected verification state"
            }
            let attempts = attemptErrors.isEmpty ? "" : " " + attemptErrors.joined(separator: " ")
            let tail = transcript.lastLines(12).joined(separator: "\n")
            let message = "Installation failed: \(detail)\(attempts)\n\nnpm output (last lines):\n\(tail)"
            logger.error("SDKInstaller: installation failed — \(detail, privacy: .public)")
            return InstallResult(success: false, installedVersion: nil, usedFallback: false, message: message, log: transcript.lines)
        }
    }

    // MARK: - npm resolution

    /// Resolves the npm binary from well-known install locations plus
    /// every directory on `PATH`. Throws `InstallerError.npmNotFound`
    /// with the real searched paths when nothing is executable.
    static func resolveNPMExecutable() throws -> URL {
        let fileManager = FileManager.default
        var candidates: [String] = [
            "/opt/homebrew/bin/npm",
            "/usr/local/bin/npm",
            "/opt/local/bin/npm",
        ]
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: pathEnv.split(separator: ":").map { "\($0)/npm" })
        }
        var searched: [String] = []
        var seen = Set<String>()
        for path in candidates {
            guard seen.insert(path).inserted else { continue }
            searched.append(path)
            if fileManager.isExecutableFile(atPath: path) {
                logger.debug("SDKInstaller: using npm at \(path, privacy: .public)")
                return URL(fileURLWithPath: path)
            }
        }
        throw InstallerError.npmNotFound(searchedPaths: searched)
    }

    // MARK: - Reachability

    /// Real reachability probe: a HEAD request to raw.githubusercontent.com.
    /// Only a successful response for the exact archive is usable.
    static func defaultReachabilityProbe(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200..<300).contains(http.statusCode)
            }
            return false
        } catch {
            logger.info("SDKInstaller: GitHub reachability probe failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The app-bundled SDK copy, when one is shipped inside the app
    /// bundle by Distribution/bundle-sdk.sh; absence is reported honestly.
    static func defaultBundledFallbackURL() -> URL? {
        let currentDir = FileManager.default.currentDirectoryPath
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("SwiftCodeSDK/Distribution/swiftcode-sdk-1.0.0.tgz"),
            Bundle.main.resourceURL?.appendingPathComponent("SwiftCode/SDK/Distribution/swiftcode-sdk-1.0.0.tgz"),
            Bundle.main.url(forResource: "swiftcode-sdk-1.0.0", withExtension: "tgz"),
            URL(fileURLWithPath: "\(currentDir)/SwiftCode/SDK/Distribution/swiftcode-sdk-1.0.0.tgz"),
            URL(fileURLWithPath: "\(currentDir)/SDK/Distribution/swiftcode-sdk-1.0.0.tgz")
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Explicit developer override first; otherwise use the shipped toolkit.
    static func resolveCLIURL() -> URL? {
        if let path = UserDefaults.standard.string(forKey: "com.swiftcode.sdk.cliPath"),
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue ? url : nil
        }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("SwiftCodeSDK/TypeScript/cli/swiftcode.mjs"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Process

    /// Runs `npm install <source> --prefix <prefix>`, streaming live
    /// output. Returns npm's exit code. Throws on timeout (after
    /// terminating the process) or when the process cannot start.
    static func runNPM(
        _ npm: URL,
        source: String,
        prefix: URL,
        timeout: TimeInterval?,
        onLine: @escaping @Sendable (LogLine) -> Void
    ) async throws -> Int32 {
        try await runProcess(
            executable: npm,
            arguments: ["install", source, "--prefix", prefix.path, "--ignore-scripts", "--no-audit", "--no-fund"],
            timeout: timeout,
            onLine: onLine
        )
    }

    /// Minimal honest `Process` wrapper: live line streaming, stdin
    /// closed (npm can never block on a prompt), optional timeout that
    /// terminates the process.
    static func runProcess(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval?,
        onLine: @escaping @Sendable (LogLine) -> Void
    ) async throws -> Int32 {
        let handle = ProcessHandle()
        return try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                var environment = ProcessInfo.processInfo.environment
                // npm commonly uses /usr/bin/env node; GUI launches have a
                // minimal PATH even when npm was found in Homebrew.
                environment["PATH"] = executable.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
                process.environment = environment
                // Closed stdin: a spawned installer must never block
                // waiting for interactive input.
                process.standardInput = FileHandle.nullDevice
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let collector = OutputCollector(onLine: onLine)
                stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
                    collector.append(fh.availableData, stream: .stdout)
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { fh in
                    collector.append(fh.availableData, stream: .stderr)
                }

                await handle.set(process)
                do {
                    try process.run()
                } catch {
                    await handle.set(nil)
                    throw error
                }
                process.waitUntilExit()
                // Drain anything written between the last handler
                // callback and process exit, then flush partial lines.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                collector.append(stdoutPipe.fileHandleForReading.availableData, stream: .stdout)
                collector.append(stderrPipe.fileHandleForReading.availableData, stream: .stderr)
                collector.flush()
                await handle.set(nil)
                return process.terminationStatus
            }
            if let timeout {
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    await handle.terminate()
                    throw InstallerError.installTimedOut(seconds: timeout)
                }
            }
            guard let result = try await group.next() else {
                throw InstallerError.internalError("installer subprocess produced no result")
            }
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Private helpers

/// Thread-safe line splitter: pipe chunks arrive on arbitrary threads;
/// complete `\n`-terminated lines are forwarded, partial tails are held
/// until `flush()`.
private final class OutputCollector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.swiftcode.sdkinstaller.output")
    private var pending: [SDKInstaller.LogLine.Stream: String] = [
        .stdout: "",
        .stderr: "",
    ]
    private let onLine: @Sendable (SDKInstaller.LogLine) -> Void

    init(onLine: @escaping @Sendable (SDKInstaller.LogLine) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data, stream: SDKInstaller.LogLine.Stream) {
        guard !data.isEmpty else { return }
        let chunk = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        guard !chunk.isEmpty else { return }
        queue.sync {
            var text = pending[stream, default: ""] + chunk
            while let newline = text.firstIndex(of: "\n") {
                let line = String(text[..<newline])
                onLine(SDKInstaller.LogLine(stream: stream, text: line))
                text = String(text[text.index(after: newline)...])
            }
            pending[stream] = text
        }
    }

    func flush() {
        queue.sync {
            for (stream, rest) in pending {
                let trimmed = rest.trimmingCharacters(in: .newlines)
                if !trimmed.isEmpty {
                    onLine(SDKInstaller.LogLine(stream: stream, text: trimmed))
                }
            }
            pending = [.stdout: "", .stderr: ""]
        }
    }
}

/// Thread-safe transcript of everything the installer streamed.
private final class TranscriptCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ entry: String) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func lastLines(_ count: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.suffix(count))
    }
}

/// Lets the timeout task terminate a running `Process` without
/// breaking Swift 6 actor isolation.
private actor ProcessHandle {
    private var process: Process?

    func set(_ process: Process?) {
        self.process = process
    }

    func terminate() {
        process?.terminate()
        process = nil
    }
}
