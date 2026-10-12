import Foundation

// MARK: - SDKBuildService
//
// Host-managed build service behind the `build.execute` SDK capability
// (spec §8.6, §11.3).
//
// SECURITY POSTURE (by construction, not by convention):
// - The executable is PINNED to `/usr/bin/xcodebuild`. There is no field,
//   preference, or code path that can change it.
// - `SDKBuildRequest` is a typed allow-list: target, configuration,
//   destination. It has no environment, build-setting, argument, or
//   executable fields, so a caller cannot inject any of those.
// - The environment handed to the build is the host process's own
//   environment (`ProcessInfo.processInfo.environment`). No
//   caller-supplied variables are accepted or forwarded.
// - The argument vector is exactly: the resolver's `-project`/`-workspace`
//   pair, `-scheme`, `-configuration`, `-destination`, and the `build`
//   action. No free-form arguments exist.
// - The build runs with `currentDirectoryURL` set to the caller's
//   authorized project root; the capability broker already scoped the
//   caller to that root before `run` is reached.
// - Cancellation is genuine: the service retains the `Process` handle and
//   `cancel()` calls `terminate()` on it.
//
// TRUTHFUL TERMINAL STATE (spec §6.3, §11.3): a build is never reported
// `.succeeded` merely because the process launched. The result is computed
// from the real termination status plus the parsed diagnostics.

public actor SDKBuildService {
    public static let shared = SDKBuildService()

    // MARK: - Limits

    /// Maximum streamed output events per build. Beyond this, events are
    /// counted and dropped, and the result carries a truncation diagnostic.
    /// `fileprivate` so the handle in this file can enforce the same limits.
    fileprivate static let maxStreamedEvents = 20_000
    /// Maximum retained full-output bytes for final parsing (4 MiB). Beyond
    /// this, bytes are counted but no longer stored.
    fileprivate static let maxRetainedOutputBytes = 4 * 1024 * 1024
    /// Maximum structured diagnostics attached to the result.
    fileprivate static let maxResultDiagnostics = 50
    /// Build wall-clock budget. Exceeded -> terminate -> `.timedOut`.
    fileprivate static let buildTimeoutSeconds: TimeInterval = 1800
    /// Pinned build executable. Never a user preference, never configurable.
    fileprivate static let xcodebuildPath = "/usr/bin/xcodebuild"

    /// Running builds keyed by extension ID. At most one per extension.
    private var activeBuilds: [String: SDKBuildHandle] = [:]

    private init() {}

    // MARK: - run

    /// Starts a managed build for the calling extension. Returns the handle
    /// only after the build process has actually launched.
    public func run(request: SDKBuildRequest, caller: SDKCallerIdentity) async throws -> SDKBuildHandle {
        // 1. Authorization gate — every call, before anything else.
        try await SDKCapabilityBroker.authorize(.buildExecute, for: caller)
        let extensionID = caller.extensionID

        // 2. One running build per extension.
        if activeBuilds[extensionID] != nil {
            throw SDKError(
                code: .resourceLimitExceeded,
                message: "This extension already has a build running.",
                suggestion: "Wait for the running build's wait() to return, or cancel() it, before starting another build."
            )
        }

        // 3. Resolve the user's project. The resolver only looks inside the
        //    caller's authorized project root — never SwiftCode's own bundle.
        let projectRoot = URL(fileURLWithPath: caller.projectRootPath)
        guard let located = AssistXcodeProjectResolver.locate(in: projectRoot) else {
            throw SDKError(
                code: .invalidTarget,
                message: "No Xcode project or workspace was found in the approved project folder.",
                suggestion: "Run the build from a folder containing a .xcodeproj or .xcworkspace file."
            )
        }

        // 4. Scheme: an explicit non-blank target wins; a blank target falls
        //    back to the resolver (first `xcodebuild -list` scheme, else the
        //    project bundle name).
        let trimmedTarget = request.target.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitScheme: String? = trimmedTarget.isEmpty ? nil : trimmedTarget
        if let explicitScheme, explicitScheme.count > 128 {
            throw SDKError(
                code: .invalidArgument,
                message: "The build target name is too long (maximum 128 characters)."
            )
        }
        let resolvedScheme = await AssistXcodeProjectResolver.resolveScheme(for: located, explicit: explicitScheme)
        let scheme = resolvedScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty, scheme.count <= 128 else {
            throw SDKError(
                code: .invalidTarget,
                message: "Could not determine a build scheme for this project.",
                suggestion: "Pass an explicit target (scheme) name in the build request."
            )
        }

        // 5. Configuration allow-list.
        let configuration: String
        if let rawConfiguration = request.configuration {
            let normalized = rawConfiguration.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized == "Debug" || normalized == "Release" else {
                throw SDKError(
                    code: .invalidArgument,
                    message: "Unsupported build configuration '\(rawConfiguration)'. Only \"Debug\" and \"Release\" are allowed."
                )
            }
            configuration = normalized
        } else {
            configuration = "Debug"
        }

        // 6. Destination sanity bound (full allow-listing is future hardening;
        //    see agent_notes.md).
        let destination: String
        if let rawDestination = request.destination {
            guard !rawDestination.isEmpty, rawDestination.count <= 256, !rawDestination.unicodeScalars.contains("\0") else {
                throw SDKError(
                    code: .invalidArgument,
                    message: "The destination specifier is invalid."
                )
            }
            destination = rawDestination
        } else {
            destination = "platform=macOS"
        }

        // 7. Create the handle, launch, then register it. Registration happens
        //    only after a successful launch: a launch failure throws and the
        //    handle never enters the active map.
        let handleID = UUID().uuidString
        let correlationId = SDKError.newCorrelationId()
        let handle = SDKBuildHandle(
            id: handleID,
            correlationId: correlationId,
            scheme: scheme,
            configuration: configuration,
            destination: destination,
            projectArguments: located.xcodebuildArgs,
            workingDirectory: projectRoot,
            onTerminal: { finishedID in
                Task {
                    await SDKBuildService.shared.noteTerminated(extensionID: extensionID, handleID: finishedID)
                }
            }
        )
        try await handle.start()
        activeBuilds[extensionID] = handle
        return handle
    }

    /// Removes a build from the active map once it reaches a terminal state.
    /// Only removes when the finishing handle is the currently registered
    /// one, so a stale completion can never evict a newer build.
    func noteTerminated(extensionID: String, handleID: String) {
        if activeBuilds[extensionID]?.id == handleID {
            activeBuilds.removeValue(forKey: extensionID)
        }
    }
}

// MARK: - SDKBuildHandle
//
// Handle for one managed build. Owns the retained `Process` (which is what
// makes `cancel()` genuine), the line-buffered output stream, the timeout
// watchdog, and the terminal-result computation.
//
// The stream is single-consumer: `events()` returns the same underlying
// stream on every call.

public actor SDKBuildHandle {
    public nonisolated let id: String
    public nonisolated let correlationId: String

    private let scheme: String
    private let configuration: String
    private let destination: String
    private let projectArguments: [String]
    private let workingDirectory: URL
    private let onTerminal: @Sendable (String) -> Void

    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stream: AsyncStream<SDKBuildOutputEvent>?
    private var continuation: AsyncStream<SDKBuildOutputEvent>.Continuation?
    private var runTask: Task<SDKBuildResult, Never>?
    private var cachedResult: SDKBuildResult?
    private var startedAt: Date?
    private var cancelRequested = false
    private var didTimeOut = false
    private var finished = false

    private var stdoutRemainder = ""
    private var stderrRemainder = ""
    private var eventCount = 0
    private var droppedEventCount = 0
    private var outputText = ""
    private var outputByteCount = 0
    private var outputTextTruncated = false

    init(
        id: String,
        correlationId: String,
        scheme: String,
        configuration: String,
        destination: String,
        projectArguments: [String],
        workingDirectory: URL,
        onTerminal: @escaping @Sendable (String) -> Void
    ) {
        self.id = id
        self.correlationId = correlationId
        self.scheme = scheme
        self.configuration = configuration
        self.destination = destination
        self.projectArguments = projectArguments
        self.workingDirectory = workingDirectory
        self.onTerminal = onTerminal
    }

    // MARK: - Launch

    /// Launches the build process. Throws when the toolchain is missing or
    /// the process cannot start; a failed launch is terminal (`.failed`) and
    /// `wait()` still returns a result.
    func start() async throws {
        guard FileManager.default.fileExists(atPath: SDKBuildService.xcodebuildPath) else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The Xcode build tools are not installed on this Mac.",
                suggestion: "Install Xcode or the Xcode command-line tools, then try again.",
                correlationId: correlationId
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: SDKBuildService.xcodebuildPath)
        process.arguments = projectArguments + [
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", destination,
            "build",
        ]
        process.currentDirectoryURL = workingDirectory
        // Host environment only. The request type has no environment fields;
        // nothing caller-supplied is accepted or forwarded here.
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let (stream, continuation) = AsyncStream<SDKBuildOutputEvent>.makeStream()
        self.stream = stream
        self.continuation = continuation
        self.startedAt = Date()

        // Attach readers before launch so early output cannot be missed.
        let stdoutFH = stdoutPipe.fileHandleForReading
        let stderrFH = stderrPipe.fileHandleForReading
        self.stdoutHandle = stdoutFH
        self.stderrHandle = stderrFH
        stdoutFH.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                Task { await self.ingest(data: data, kind: .stdout) }
            }
        }
        stderrFH.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                Task { await self.ingest(data: data, kind: .stderr) }
            }
        }

        do {
            try process.run()
        } catch {
            stdoutFH.readabilityHandler = nil
            stderrFH.readabilityHandler = nil
            let sdkError = SDKError(
                code: .serviceUnavailable,
                message: "The build process could not be started.",
                suggestion: "Check that the Xcode command-line tools are installed and functional.",
                diagnostics: ["underlyingError": error.localizedDescription],
                correlationId: correlationId
            )
            // Terminal immediately: a build that never launched is `.failed`,
            // never `.succeeded`, and wait() still returns a result.
            let result = SDKBuildResult(
                status: .failed,
                exitCode: nil,
                durationSeconds: 0,
                diagnostics: [SDKBuildDiagnostic(message: "Build failed to start: \(sdkError.message)")],
                correlationId: correlationId
            )
            self.cachedResult = result
            self.finished = true
            continuation.finish()
            throw sdkError
        }

        self.process = process
        emitStatus("Build started: xcodebuild -scheme \"\(scheme)\" -configuration \(configuration) -destination \"\(destination)\" [\(correlationId)]")
        self.runTask = Task { await self.supervise() }
    }

    // MARK: - Handle API

    /// The live output stream. Single-consumer; returns the same underlying
    /// stream on every call.
    public func events() -> AsyncStream<SDKBuildOutputEvent> {
        if let stream { return stream }
        return AsyncStream { $0.finish() }
    }

    /// Waits for the terminal result. Idempotent: repeated calls return the
    /// cached result without re-running anything.
    public func wait() async throws -> SDKBuildResult {
        if let cachedResult { return cachedResult }
        guard let runTask else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The build did not start.",
                correlationId: correlationId
            )
        }
        let result = await runTask.value
        cachedResult = result
        return result
    }

    /// Genuine cancellation: terminates the retained build process. `wait()`
    /// then returns a result with status `.cancelled`. A no-op when the
    /// build already reached a terminal state.
    public func cancel() async {
        guard !finished else { return }
        cancelRequested = true
        emitStatus("Cancelling build…")
        // The supervising task observes the exit and completes the build as
        // `.cancelled`.
        process?.terminate()
    }

    // MARK: - Supervision

    /// Waits for process exit or the timeout budget, whichever comes first,
    /// then settles the pipes and computes the truthful terminal result.
    private func supervise() async -> SDKBuildResult {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.waitForExit() }
            group.addTask { await self.enforceTimeout() }
            // First finisher wins; the loser is cancelled.
            _ = await group.next()
            group.cancelAll()
        }
        await settlePipes()
        let result = makeResult()
        finish(with: result)
        return result
    }

    private func waitForExit() async {
        while let process = self.process, process.isRunning {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Terminates the build when it exceeds the wall-clock budget.
    private func enforceTimeout() async {
        try? await Task.sleep(nanoseconds: UInt64(SDKBuildService.buildTimeoutSeconds) * 1_000_000_000)
        if Task.isCancelled { return }
        guard let process = self.process, process.isRunning else { return }
        self.didTimeOut = true
        emitStatus("Build timed out after 30 minutes; terminating.")
        process.terminate()
        // Grace window for SIGTERM before the blocking wait.
        for _ in 0..<50 {
            if !process.isRunning { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        process.waitUntilExit()
    }

    // MARK: - Output ingestion

    /// Gives in-flight readability-handler deliveries a moment to land, then
    /// detaches the handlers and synchronously drains anything they never
    /// consumed, so no output is lost. The settle sleep is a heuristic; the
    /// final drain is the guarantee.
    private func settlePipes() async {
        try? await Task.sleep(nanoseconds: 250_000_000)
        if let handle = stdoutHandle {
            handle.readabilityHandler = nil
            drain(handle, kind: .stdout)
            try? handle.close()
        }
        stdoutHandle = nil
        if let handle = stderrHandle {
            handle.readabilityHandler = nil
            drain(handle, kind: .stderr)
            try? handle.close()
        }
        stderrHandle = nil
        flushRemainder(kind: .stdout)
        flushRemainder(kind: .stderr)
    }

    /// Reads whatever the handlers never consumed. The writers are dead at
    /// this point, so this returns at EOF immediately.
    private func drain(_ handle: FileHandle, kind: SDKBuildOutputKind) {
        let data = handle.readDataToEndOfFile()
        if !data.isEmpty {
            ingest(data: data, kind: kind)
        }
    }

    private func ingest(data: Data, kind: SDKBuildOutputKind) {
        guard !finished else { return }
        let text = String(decoding: data, as: UTF8.self)
        guard !text.isEmpty else { return }

        // Retained full text for final parsing (bounded).
        outputByteCount += data.count
        if !outputTextTruncated {
            let used = outputText.utf8.count
            if used < SDKBuildService.maxRetainedOutputBytes {
                let remaining = SDKBuildService.maxRetainedOutputBytes - used
                if text.utf8.count <= remaining {
                    outputText += text
                } else {
                    var kept = text
                    while kept.utf8.count > remaining { kept.removeLast() }
                    outputText += kept
                    outputTextTruncated = true
                }
            } else {
                outputTextTruncated = true
            }
        }

        // Line-buffered streaming.
        switch kind {
        case .stdout:
            stdoutRemainder += text
            emitCompleteLines(kind: .stdout)
        case .stderr:
            stderrRemainder += text
            emitCompleteLines(kind: .stderr)
        case .status:
            emitEvent(kind: .status, text: text)
        }
    }

    private func emitCompleteLines(kind: SDKBuildOutputKind) {
        switch kind {
        case .stdout:
            var parts = stdoutRemainder.components(separatedBy: "\n")
            stdoutRemainder = parts.removeLast()
            for part in parts { emitEvent(kind: .stdout, text: part) }
        case .stderr:
            var parts = stderrRemainder.components(separatedBy: "\n")
            stderrRemainder = parts.removeLast()
            for part in parts { emitEvent(kind: .stderr, text: part) }
        case .status:
            break
        }
    }

    private func flushRemainder(kind: SDKBuildOutputKind) {
        switch kind {
        case .stdout:
            if !stdoutRemainder.isEmpty {
                emitEvent(kind: .stdout, text: stdoutRemainder)
                stdoutRemainder = ""
            }
        case .stderr:
            if !stderrRemainder.isEmpty {
                emitEvent(kind: .stderr, text: stderrRemainder)
                stderrRemainder = ""
            }
        case .status:
            break
        }
    }

    private func emitEvent(kind: SDKBuildOutputKind, text: String) {
        guard !finished else { return }
        // Lifecycle notes always get through, even past the event cap, so the
        // terminal state is never dropped from the stream.
        if kind != .status {
            guard eventCount < SDKBuildService.maxStreamedEvents else {
                droppedEventCount += 1
                return
            }
            eventCount += 1
        }
        continuation?.yield(SDKBuildOutputEvent(kind: kind, text: text))
    }

    private func emitStatus(_ text: String) {
        emitEvent(kind: .status, text: text)
    }

    // MARK: - Terminal result

    /// Computes the truthful terminal state: never `.succeeded` from launch
    /// alone — success requires the parser's verdict on the real exit code
    /// and the parsed error count.
    private func makeResult() -> SDKBuildResult {
        let terminationCode: Int32? = process?.terminationStatus
        let parsed = SDKBuildOutputParser.parse(outputText, maxDiagnostics: SDKBuildService.maxResultDiagnostics)
        var diagnostics = parsed.errors
        if droppedEventCount > 0 || outputTextTruncated {
            var reasons: [String] = []
            if droppedEventCount > 0 {
                reasons.append("\(droppedEventCount) streamed event(s) dropped after the \(SDKBuildService.maxStreamedEvents)-event cap")
            }
            if outputTextTruncated {
                reasons.append("retained output text truncated at \(SDKBuildService.maxRetainedOutputBytes) bytes (\(outputByteCount) bytes total)")
            }
            diagnostics.append(SDKBuildDiagnostic(
                message: "Build output was truncated (" + reasons.joined(separator: "; ") + "). Parsed diagnostics cover the retained output only."
            ))
        }

        let status: SDKBuildStatus
        if cancelRequested {
            status = .cancelled
        } else if didTimeOut {
            status = .timedOut
        } else if let terminationCode,
                  SDKBuildOutputParser.didSucceed(exitCode: terminationCode, output: outputText, errorCount: parsed.errorCount) {
            status = .succeeded
        } else {
            status = .failed
        }

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        return SDKBuildResult(
            status: status,
            exitCode: terminationCode.map { Int($0) },
            durationSeconds: duration,
            errorCount: parsed.errorCount,
            warningCount: parsed.warningCount,
            diagnostics: diagnostics,
            correlationId: correlationId
        )
    }

    private func finish(with result: SDKBuildResult) {
        guard !finished else { return }
        finished = true
        cachedResult = result

        let summary: String = switch result.status {
        case .succeeded:
            "Build finished: succeeded."
        case .failed:
            "Build finished: failed (exit code \(result.exitCode.map { String($0) } ?? "unknown"), \(result.errorCount) error(s), \(result.warningCount) warning(s))."
        case .cancelled:
            "Build finished: cancelled."
        case .timedOut:
            "Build finished: timed out after 30 minutes."
        case .running:
            "Build finished."
        }
        continuation?.yield(SDKBuildOutputEvent(kind: .status, text: summary))
        continuation?.finish()
        try? stdoutHandle?.close()
        try? stderrHandle?.close()
        stdoutHandle = nil
        stderrHandle = nil
        process = nil

        // Terminal state reached: release the per-extension slot.
        onTerminal(id)
    }
}
