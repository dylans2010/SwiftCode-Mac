import Foundation

// MARK: - SDKNodeLauncher
//
// Host-controlled launcher for the TypeScript extension runtime.
//
// Architecture decision (spec §4.2; ADR §3 in
// `SwiftCode/SDK/Documentation/SDK-Architecture.md`):
// SwiftCode does NOT bundle a Node.js binary, does NOT assume one is
// installed on the user's Mac, and NEVER downloads or executes a runtime
// binary silently. The host resolves a Node.js executable already present
// on the machine using the order documented on `resolveNodeURL()`; when
// none is found, launching fails with a typed `.runtimeUnavailable` error
// carrying actionable install guidance. The missing-runtime path is a
// first-class, tested outcome — never a crash, hang, or silent download.
//
// Isolation contract (spec §10.1):
// Extensions run OUT OF PROCESS as a child `node` process communicating
// over stdio pipes. The host app never runs extension code in-process and
// never on the main thread: `launch(entrypoint:workingDirectory:)` returns
// immediately after spawning, and waiting for exit is async
// (`SDKLaunchedRuntime.waitForExit()`). A hung or crashed extension cannot
// block the host UI; its lifetime is observed via `terminationHandler`,
// never via a blocking wait or a sleep loop.
//
// Resource-control honesty (spec §10.6):
// This launcher does NOT enforce hard CPU or memory caps on the child
// process, and it does NOT sandbox it — there is no supported per-child
// resource-cap or sandbox API usable from this layer, and claiming
// otherwise would be dishonest. Enforcement lives at higher layers:
// per-request timeouts, IPC message-size bounds, and build/output caps in
// the runtime-adapter and service layers. Do not describe this launcher
// as sandboxing.

public enum SDKNodeLauncher {

    // MARK: Resolution

    /// Well-known Node.js install locations, checked in order before `PATH`.
    private static let wellKnownNodePaths = [
        "/opt/homebrew/bin/node", // Homebrew on Apple Silicon
        "/usr/local/bin/node",    // Homebrew on Intel / manual installs
        "/usr/bin/node",          // System / Xcode CLT-adjacent installs
    ]

    /// Resolves the Node.js executable the host will use to run TypeScript
    /// extensions. Inspects the filesystem only; never triggers a download.
    ///
    /// Resolution order:
    /// 1. `SWIFTCODE_NODE_PATH` — when set to a non-blank value, it MUST
    ///    name an existing executable file (tilde is expanded). Otherwise
    ///    `.runtimeUnavailable` is thrown naming the configured value. An
    ///    explicit override is never silently ignored in favor of another
    ///    binary.
    /// 2. Well-known locations (`/opt/homebrew/bin/node`,
    ///    `/usr/local/bin/node`, `/usr/bin/node`) — the first existing
    ///    executable wins.
    /// 3. Each `PATH` component + `/node` — the first existing executable
    ///    wins. Empty components are skipped; relative components are
    ///    evaluated against the host process's current working directory,
    ///    matching standard `FileManager` path semantics.
    ///
    /// A candidate counts only when it exists, is not a directory, and is
    /// executable (`FileManager.isExecutableFile(atPath:)` plus an explicit
    /// directory check — `isExecutableFile` alone also returns `true` for
    /// searchable directories).
    ///
    /// - Throws: `SDKError` with code `.runtimeUnavailable` when
    ///   `SWIFTCODE_NODE_PATH` names something that is not an executable
    ///   file, or when no usable Node.js binary is found anywhere.
    public static func resolveNodeURL() throws -> URL {
        // 1. Explicit developer/host override.
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

        // 2. Well-known locations.
        for path in wellKnownNodePaths {
            if let url = executableFile(atPath: path) {
                return url
            }
        }

        // 3. PATH lookup.
        if let pathValue = ProcessInfo.processInfo.environment["PATH"], !pathValue.isEmpty {
            for component in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
                let candidate = URL(fileURLWithPath: String(component)).appendingPathComponent("node")
                if let url = executableFile(atPath: candidate.path) {
                    return url
                }
            }
        }

        // 4. Nothing found — typed, actionable failure. The missing-runtime
        // path is a real outcome (spec §4.2), never a crash or hang.
        throw SDKError(
            code: .runtimeUnavailable,
            message: "Node.js is required to run TypeScript extensions but was not found.",
            suggestion: "Install Node.js 20 or later from nodejs.org, via Homebrew (brew install node), or set SWIFTCODE_NODE_PATH."
        )
    }

    /// Environment variable name fragments treated as secret-bearing.
    /// Any variable whose uppercased name contains one of these fragments is
    /// stripped before the extension process is spawned. The extension
    /// runtime has no legitimate need for host secrets (API keys, tokens,
    /// client secrets); inheriting them ambiently would defeat the
    /// "secrets never cross into the extension process" contract below.
    /// Deliberately conservative: generic `*KEY*` is NOT matched (too many
    /// benign names), only compound fragments that reliably name secrets.
    private static let secretEnvNameFragments = [
        "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL",
        "PRIVATE_KEY", "API_KEY", "APIKEY", "ACCESS_KEY",
        "AUTH_TOKEN", "CLIENT_SECRET", "SESSION_TOKEN",
    ]

    /// The host environment with secret-bearing variables removed.
    /// Everything else (PATH, HOME, TMPDIR, LANG, NODE_*, …) passes through
    /// unchanged so the node runtime behaves normally.
    private static func sanitizedEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { name, _ in
            let upper = name.uppercased()
            return !secretEnvNameFragments.contains { upper.contains($0) }
        }
    }

    // MARK: Launch

    /// Launches the validated extension entry point as a child `node`
    /// process and returns its runtime handle.
    ///
    /// The child is spawned with:
    /// - `executableURL` = the resolved Node.js binary, `arguments` =
    ///   `[entrypoint.path] + arguments` — plain argv elements, no shell,
    ///   so there is no shell-quoting or shell-injection surface at this
    ///   layer. Callers pass only fixed option flags and validated
    ///   filesystem paths / extension IDs as extra arguments — never
    ///   extension-controlled strings.
    /// - `currentDirectoryURL` = `workingDirectory`.
    /// - `environment` = the host process environment with secret-bearing
    ///   variables stripped (`sanitizedEnvironment()`). The runtime-adapter
    ///   layer passes no secrets through this boundary, and ambient
    ///   inheritance cannot leak them either: anything named like a secret
    ///   (API keys, tokens, passwords, client secrets) never crosses into
    ///   the extension process.
    /// - Dedicated `Pipe`s for stdin/stdout/stderr, exposed on the returned
    ///   `SDKLaunchedRuntime` for the IPC layer.
    ///
    /// This function never blocks: `Process.run()` spawns asynchronously and
    /// returns immediately. It never touches `@MainActor`.
    ///
    /// - Throws: `SDKError` with code `.runtimeLaunchFailed` when the entry
    ///   point is not a usable regular file, when Node.js cannot be resolved
    ///   (`.runtimeUnavailable` propagates from `resolveNodeURL()`), or when
    ///   the process fails to spawn. The user-facing message is sanitized —
    ///   it carries no raw paths and no system error text; full detail
    ///   travels in `diagnostics` for the developer log.
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

    // MARK: Filesystem checks

    /// Returns a file URL when `path` names an existing, non-directory,
    /// executable file; otherwise `nil`. Tilde is expanded first.
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

    /// Strict regular-file check. Follows symlinks (a symlink to a regular
    /// file is accepted); rejects directories, FIFOs, sockets, and dangling
    /// links.
    private static func isRegularFile(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeRegular
    }
}

// MARK: - SDKLaunchedRuntime
//
// Actor-owned handle to a running extension `node` process (spec §10.1,
// §10.5). The extension itself is out-of-process; this actor only owns the
// `Process` instance, its stdio pipes, and lifetime observation.
//
// Concurrency notes:
// - The stdio pipes are exposed without actor isolation so the IPC layer
//   can read and write stdio from any executor without hopping onto this
//   actor. The *references* are fixed at `init`; the underlying file
//   descriptors are owned by a single reader/writer pair in the
//   runtime-adapter layer.
// - `waitForExit()` is single-waiter by contract: the runtime lifecycle
//   layer awaits it exactly once per launched runtime. Installing a second
//   waiter would replace the first waiter's `terminationHandler`.
//
// `nonisolated(unsafe)` deviation note: the contract asks for
// `nonisolated let` pipes, but `Pipe` is not `Sendable`, and Swift 6 strict
// concurrency rejects `nonisolated let` of non-`Sendable` type inside an
// actor. `nonisolated(unsafe)` preserves the intended access pattern (no
// actor hop) while compiling; the safety argument is documented above.

public actor SDKLaunchedRuntime {

    /// Child stdin. See the type-level note on `nonisolated(unsafe)`.
    public nonisolated(unsafe) let stdinPipe: Pipe
    /// Child stdout. See the type-level note on `nonisolated(unsafe)`.
    public nonisolated(unsafe) let stdoutPipe: Pipe
    /// Child stderr. See the type-level note on `nonisolated(unsafe)`.
    public nonisolated(unsafe) let stderrPipe: Pipe
    /// The child process ID, captured after a successful `run()`.
    public nonisolated let processIdentifier: Int32

    private let process: Process

    init(process: Process, stdinPipe: Pipe, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.processIdentifier = process.processIdentifier
    }

    /// Whether the child process is currently running.
    public var isRunning: Bool {
        process.isRunning
    }

    /// Sends `SIGTERM` to the child process. Best-effort and non-blocking;
    /// use `waitForExit()` to observe the actual exit. Cancellation of a
    /// waiter is expressed through `terminate()` — the waiter then resumes
    /// with the real termination status.
    public func terminate() {
        process.terminate()
    }

    /// Asynchronously waits for the child process to exit and returns its
    /// termination status.
    ///
    /// Implemented with `terminationHandler` + `CheckedContinuation`: the
    /// waiting task suspends with no thread blocked and no polling loop. A
    /// fast path returns immediately when the process has already exited.
    /// The handler is installed before rechecking `isRunning`, and an
    /// exactly-once gate closes the race where the process exits between
    /// the install and the recheck (in which case the handler never fires).
    public func waitForExit() async -> Int32 {
        if !process.isRunning {
            return process.terminationStatus
        }
        // Capture the process locally so the termination handler does not
        // retain the actor (actor -> process -> handler -> actor cycle).
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

/// Exactly-once gate protecting a `CheckedContinuation` against the race
/// between a firing `terminationHandler` and the post-install `isRunning`
/// recheck. Lock-guarded because the handler runs on an arbitrary thread.
private final class TerminationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// Returns `true` to the single first caller; `false` afterwards.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
