import CryptoKit
import Darwin
import Foundation

// MARK: - SDKCodeBuildRunner
//
// Executes `SDKBuildRunRequest`s for real and streams stdout/stderr into
// the editor console LIVE, line by line, via
// `SDKCodeEditorState.appendConsole(_:)` — never buffered to the end.
//
// Execution mapping (no simulated builds, ever):
// - `.xcodebuildSwift`     → `SDKBuildService.shared`, the app's REAL
//                            managed xcodebuild runner (the same service
//                            the `build.execute` capability path uses).
//                            This runner never shells out to xcodebuild
//                            itself.
// - `.typescriptExtension` → `npm run build` via `Process`, working
//                            directory = the project root (real tsc build).
// - `.nodeScript`          → `node <entry>` via `Process`, working
//                            directory = the project root.
//
// AUTHORIZATION (xcodebuild path): `SDKBuildService.run` gates every call
// through `SDKCapabilityBroker` on `.buildExecute`. The Studio editor is
// host-owned UI — not an extension — so it presents a fixed host identity
// (`hostExtensionID` / `hostPackageDigest`), which also keeps the
// service's one-build-per-extension slot from colliding with extension
// builds. There is deliberately NO silent self-approval: if the user has
// not granted `build.execute` to the Studio editor for this project root,
// the broker denies and the runner reports the denial verbatim
// (code + message + suggestion) in the console. Grant-approval UX for the
// editor identity is a separate task; this runner never fabricates
// grants.
//
// TERMINAL TRUTHFULNESS (spec §6.3): success/failure is reported ONLY
// from the real terminal state — the managed handle's `wait()` result,
// or the local `Process` termination status/reason. A successful launch
// is never reported as a successful build.
//
// CANCELLATION: `cancel(taskID:)` terminates the underlying build handle
// or process for real. Managed builds go through `SDKBuildHandle.cancel()`
// (SIGTERM on the retained process). Local processes get SIGTERM, then
// SIGKILL after `cancelGraceNanoseconds` when they ignore it. The
// supervising path observes the exit and reports `.cancelled`; the
// process the runner launched is never left alive.

public actor SDKCodeBuildRunner {
    public static let shared = SDKCodeBuildRunner()

    /// Host-owned identity the Studio editor presents to the managed build
    /// service. Distinct from every extension ID, so the service's
    /// one-build-per-extension slot never collides with extension builds.
    public static let hostExtensionID = "studio.editor"

    /// Stable digest for the host identity. The host has no installable
    /// package, so this is the SHA-256 of a fixed marker string — it only
    /// needs to be STABLE so a user-approved grant's digest binding
    /// (`grant.packageDigest == caller.packageDigest`) keeps matching.
    public static let hostPackageDigest: String = {
        let digest = SHA256.hash(data: Data("swiftcode.sdk.studio.editor".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }()

    /// Pinned executable lookup for local (npm/node) runs. The command
    /// itself is still explicit (`npm`, `node`); `env` only resolves PATH.
    private static let envExecutablePath = "/usr/bin/env"

    /// Grace period between SIGTERM and SIGKILL when cancelling a local
    /// (npm/node) process that ignores termination.
    private static let cancelGraceNanoseconds: UInt64 = 3_000_000_000

    private enum ActiveEntry {
        case managedBuild(SDKBuildHandle)
        case localProcess(LocalProcessSession)
    }

    private var active: [UUID: ActiveEntry] = [:]

    public init() {}

    // MARK: - Public API

    /// Executes `request` for real, streaming output lines into
    /// `editorState` as they arrive. Does not return until the run reaches
    /// a terminal state (or the request fails to start); the caller keeps
    /// `request.taskID` and uses `cancel(taskID:)` to stop it early.
    public func run(_ request: SDKBuildRunRequest, into editorState: SDKCodeEditorState) async {
        guard active[request.taskID] == nil else {
            await emit(.system("Build/run ignored: task \(request.taskID.uuidString) is already in flight."), to: editorState)
            return
        }
        switch request.kind {
        case .xcodebuildSwift:
            await runManagedBuild(request, into: editorState)
        case .typescriptExtension, .nodeScript:
            await runLocalProcess(request, into: editorState)
        }
    }

    /// Genuine cancellation: terminates the underlying build handle or
    /// process for `taskID`. The in-flight `run` observes the exit and
    /// reports `.cancelled`. A no-op for unknown or already-finished tasks.
    public func cancel(taskID: UUID) async {
        guard let entry = active[taskID] else { return }
        switch entry {
        case .managedBuild(let handle):
            await handle.cancel()
        case .localProcess(let session):
            await session.requestCancel()
        }
    }

    /// Whether `taskID` currently has a run in flight.
    public func isRunning(taskID: UUID) -> Bool {
        active[taskID] != nil
    }

    // MARK: - Managed xcodebuild path

    private func runManagedBuild(_ request: SDKBuildRunRequest, into editorState: SDKCodeEditorState) async {
        let taskID = request.taskID
        let scheme = request.schemeOrEntry?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An empty target is intentional: the service falls back to its
        // scheme resolver (first `xcodebuild -list` scheme, else the
        // project bundle name) and reports the resolved scheme itself.
        let sdkRequest = SDKBuildRequest(target: scheme)
        let caller = SDKCallerIdentity(
            extensionID: Self.hostExtensionID,
            packageDigest: Self.hostPackageDigest,
            projectRootPath: request.projectRoot.path,
            apiKey: nil
        )
        await emit(
            .system("Build requested (xcodebuild) — project: \(request.projectRoot.lastPathComponent), scheme: \(scheme.isEmpty ? "<auto-detect>" : "\"\(scheme)\"")"),
            to: editorState
        )

        let handle: SDKBuildHandle
        do {
            handle = try await SDKBuildService.shared.run(request: sdkRequest, caller: caller)
        } catch let sdkError as SDKError {
            var text = "Build could not start [\(sdkError.code.rawValue)]: \(sdkError.message)"
            if let suggestion = sdkError.suggestion, !suggestion.isEmpty {
                text += " \(suggestion)"
            }
            await emit(.system(text), to: editorState)
            return
        } catch {
            await emit(.system("Build could not start: \(error.localizedDescription)"), to: editorState)
            return
        }
        active[taskID] = .managedBuild(handle)

        // Stream to completion BEFORE wait(): the handle finishes its
        // stream (with a final summary event) as part of reaching its
        // terminal state, so draining first guarantees every output line
        // lands in the console before the terminal line is emitted.
        // wait() then returns the cached result immediately.
        for await event in await handle.events() {
            await emit(consoleEntry(for: event), to: editorState)
        }
        let result: SDKBuildResult
        do {
            result = try await handle.wait()
        } catch {
            active[taskID] = nil
            await emit(.system("Build result unavailable: \(error.localizedDescription)"), to: editorState)
            return
        }
        active[taskID] = nil
        await emit(terminalEntry(for: result), to: editorState)
    }

    private func consoleEntry(for event: SDKBuildOutputEvent) -> SDKConsoleEntry {
        switch event.kind {
        case .stdout: return .stdout(event.text)
        case .stderr: return .stderr(event.text)
        case .status: return .system(event.text)
        }
    }

    /// Truthful terminal line, computed ONLY from the managed service's
    /// real result — never from the fact that the process launched.
    private func terminalEntry(for result: SDKBuildResult) -> SDKConsoleEntry {
        let duration = String(format: "%.1f", result.durationSeconds)
        switch result.status {
        case .succeeded:
            return .system("Build succeeded in \(duration)s.")
        case .failed:
            let exit = result.exitCode.map(String.init) ?? "?"
            return .system("Build failed (exit \(exit), \(result.errorCount) error(s), \(result.warningCount) warning(s), \(duration)s).")
        case .cancelled:
            return .system("Build cancelled.")
        case .timedOut:
            return .system("Build timed out after 30 minutes.")
        case .running:
            return .system("Build ended in an unexpected state (still marked running).")
        }
    }

    // MARK: - Local process path (npm / node)

    private func runLocalProcess(_ request: SDKBuildRunRequest, into editorState: SDKCodeEditorState) async {
        let taskID = request.taskID
        let root = request.projectRoot

        let arguments: [String]
        let label: String
        switch request.kind {
        case .typescriptExtension:
            arguments = ["npm", "run", "build"]
            label = "npm run build"
        case .nodeScript:
            guard let raw = request.schemeOrEntry?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                await emit(.system("Run failed: no script path provided."), to: editorState)
                return
            }
            guard let scriptURL = Self.scriptURL(for: raw, under: root) else {
                await emit(.system("Run failed: script path \"\(raw)\" escapes the project root."), to: editorState)
                return
            }
            arguments = ["node", scriptURL.path]
            label = "node \(raw)"
        case .xcodebuildSwift:
            return // Unreachable: dispatched to runManagedBuild above.
        }

        let startedAt = Date()
        await emit(.system("\(label) — started in \(root.lastPathComponent)"), to: editorState)

        let session: LocalProcessSession
        do {
            session = LocalProcessSession(
                executable: URL(fileURLWithPath: Self.envExecutablePath),
                arguments: arguments,
                workingDirectory: root
            ) { [weak self] entry in
                guard let self else { return }
                Task { await self.emit(entry, to: editorState) }
            }
            try await session.launch()
        } catch {
            await emit(.system("\(label) — could not start: \(error.localizedDescription)"), to: editorState)
            return
        }
        active[taskID] = .localProcess(session)

        let outcome = await session.waitForExit()
        active[taskID] = nil

        let duration = String(format: "%.1f", Date().timeIntervalSince(startedAt))
        if outcome.cancelled {
            await emit(.system("\(label) — cancelled."), to: editorState)
        } else if outcome.reason == .exit, outcome.exitCode == 0 {
            await emit(.system("\(label) — finished successfully (exit 0, \(duration)s)."), to: editorState)
        } else if outcome.reason == .exit {
            await emit(.system("\(label) — failed with exit code \(outcome.exitCode) (\(duration)s)."), to: editorState)
        } else {
            await emit(.system("\(label) — terminated by signal \(outcome.exitCode) (\(duration)s)."), to: editorState)
        }
    }

    /// Resolves a script entry to a URL, refusing anything that escapes
    /// the project root. Absolute entries are treated as relative (a path
    /// component, not a filesystem root), so they stay inside the root.
    private static func scriptURL(for entry: String, under root: URL) -> URL? {
        let base = root.standardized
        let candidate = base.appendingPathComponent(entry).standardized
        let basePath = base.path
        guard candidate.path == basePath || candidate.path.hasPrefix(basePath + "/") else {
            return nil
        }
        return candidate
    }

    // MARK: - Console sink

    private func emit(_ entry: SDKConsoleEntry, to editorState: SDKCodeEditorState) async {
        await editorState.appendConsole(entry)
    }

    // MARK: - LocalProcessSession

    /// One locally-launched process (npm/node): owns the `Process`, its
    /// pipes, and line-buffered ingestion. Output lines are delivered to
    /// `onLine` LIVE as they arrive. An actor so the pipe handlers (which
    /// fire on arbitrary queues) can only mutate state through isolation.
    private actor LocalProcessSession {
        typealias LineSink = @Sendable (SDKConsoleEntry) -> Void

        private let process: Process
        private let stdoutHandle: FileHandle
        private let stderrHandle: FileHandle
        private let onLine: LineSink

        private var stdoutRemainder = ""
        private var stderrRemainder = ""
        private var cancelRequested = false
        private var finished = false

        init(
            executable: URL,
            arguments: [String],
            workingDirectory: URL,
            onLine: @escaping LineSink
        ) {
            self.onLine = onLine
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            // Host environment only — same posture as the managed build
            // service: nothing caller-supplied is forwarded.
            process.environment = ProcessInfo.processInfo.environment
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            self.process = process
            self.stdoutHandle = stdoutPipe.fileHandleForReading
            self.stderrHandle = stderrPipe.fileHandleForReading
        }

        /// Attaches line-buffered readers, then launches. Throws when the
        /// process cannot start; a failed launch is reported by the caller,
        /// never as a successful run.
        func launch() throws {
            // Attach readers before launch so early output cannot be missed.
            stdoutHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self else { return }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    Task { await self.ingest(data: data, stream: .stdout) }
                }
            }
            stderrHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self else { return }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    Task { await self.ingest(data: data, stream: .stderr) }
                }
            }
            do {
                try process.run()
            } catch {
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                throw error
            }
        }

        /// Genuine cancellation: SIGTERM on the launched process, escalated
        /// to SIGKILL after the grace window when it ignores termination.
        /// No-op when the process already exited — `cancelRequested` is
        /// only set while the process is actually running, so a natural
        /// exit is never misreported as a cancellation.
        func requestCancel() {
            guard !finished, process.isRunning else { return }
            cancelRequested = true
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            process.terminate()
            // Escalate on the actor (not the raw pid): checking the retained
            // `Process` avoids any pid-reuse hazard in the grace window.
            Task.detached { [weak self] in
                try? await Task.sleep(nanoseconds: SDKCodeBuildRunner.cancelGraceNanoseconds)
                guard let self else { return }
                let target = await self.killEscalationTarget()
                if let pid = target {
                    kill(pid, SIGKILL)
                }
            }
        }

        /// The pid to SIGKILL, or `nil` when escalation is unnecessary (the
        /// process already exited or was never cancel-requested).
        private func killEscalationTarget() -> pid_t? {
            guard cancelRequested, !finished, process.isRunning else { return nil }
            return process.processIdentifier
        }

        /// Waits for process exit, settles and drains the pipes so no
        /// output is lost, then reports the REAL termination state.
        func waitForExit() async -> LocalProcessOutcome {
            while process.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            // Settle: give in-flight handler deliveries a beat to land,
            // then detach and synchronously drain anything they never
            // consumed. The drain (not the sleep) is the guarantee.
            try? await Task.sleep(nanoseconds: 200_000_000)
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            drain(stdoutHandle, stream: .stdout)
            drain(stderrHandle, stream: .stderr)
            flushRemainder(stream: .stdout)
            flushRemainder(stream: .stderr)
            finished = true
            try? stdoutHandle.close()
            try? stderrHandle.close()
            return LocalProcessOutcome(
                exitCode: process.terminationStatus,
                reason: process.terminationReason,
                cancelled: cancelRequested
            )
        }

        /// Reads whatever the handlers never consumed. The writers are dead
        /// at this point, so this returns at EOF immediately.
        private func drain(_ handle: FileHandle, stream: SDKConsoleStream) {
            let data = handle.readDataToEndOfFile()
            if !data.isEmpty {
                ingest(data: data, stream: stream)
            }
        }

        private func ingest(data: Data, stream: SDKConsoleStream) {
            guard !finished else { return }
            let text = String(decoding: data, as: UTF8.self)
            guard !text.isEmpty else { return }
            switch stream {
            case .stdout:
                stdoutRemainder += text
                for line in takeCompleteLines(stream: .stdout) {
                    onLine(.stdout(line))
                }
            case .stderr:
                stderrRemainder += text
                for line in takeCompleteLines(stream: .stderr) {
                    onLine(.stderr(line))
                }
            case .system:
                break
            }
        }

        private func takeCompleteLines(stream: SDKConsoleStream) -> [String] {
            switch stream {
            case .stdout:
                var parts = stdoutRemainder.components(separatedBy: "\n")
                stdoutRemainder = parts.removeLast()
                return parts
            case .stderr:
                var parts = stderrRemainder.components(separatedBy: "\n")
                stderrRemainder = parts.removeLast()
                return parts
            case .system:
                return []
            }
        }

        private func flushRemainder(stream: SDKConsoleStream) {
            switch stream {
            case .stdout:
                if !stdoutRemainder.isEmpty {
                    onLine(.stdout(stdoutRemainder))
                    stdoutRemainder = ""
                }
            case .stderr:
                if !stderrRemainder.isEmpty {
                    onLine(.stderr(stderrRemainder))
                    stderrRemainder = ""
                }
            case .system:
                break
            }
        }
    }

    // MARK: - LocalProcessOutcome

    /// The real terminal state of a local process: exit code, how it
    /// terminated, and whether the runner cancelled it.
    private struct LocalProcessOutcome: Sendable {
        let exitCode: Int32
        let reason: Process.TerminationReason
        let cancelled: Bool
    }
}
