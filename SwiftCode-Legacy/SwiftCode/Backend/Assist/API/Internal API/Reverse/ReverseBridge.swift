//  ReverseBridge.swift
//  SwiftCode
//
//  Swift-side owner of the Reverse bridge child process.
//
//  Transport contract (see ReverseBridge.mjs in this directory):
//  - One bridge process per request. Swift spawns `node ReverseBridge.mjs
//    --rea-dir <dir>`, writes ONE NDJSON request line to stdin, closes
//    stdin, then reads stdout to EOF. Stdout carries ONLY protocol frames
//    (progress / result / error); the bridge writes diagnostics to stderr.
//  - Frames are bounded (1 MiB each, 8 MiB total stdout). Anything larger,
//    malformed, or off-protocol is a bridge failure, never a success.
//  - No shell is involved anywhere: argv only, via Process.executableURL.
//  - Cancellation terminates the child (SIGTERM, then SIGKILL after a
//    short grace). The bridge forwards SIGTERM to its pinned-CLI child.
//  - Secrets are stripped from the child environment (same fragment list
//    as the SDK node launcher): the bridge has no legitimate need for
//    host API keys, tokens, or passwords.
//
//  FORBIDDEN: this file must never launch, import, or fall back to the
//  Model Context Protocol transport. There is no MCP server, client,
//  import, argv, or fallback anywhere in the Reverse subsystem. The
//  bridge talks to REA's real implementation only: a dynamic import of
//  the pinned rea-agents dist module (direct operations), or the pinned
//  `rea` CLI with `--format json` for `inspect_with_objdump` only
//  (the direct provider does not declare that operation — verified).

import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Outcome of one bridge request: ordered progress frames plus either
/// Evidence or a typed error. Progress frames are collected (the
/// AssistTool protocol has no live-progress channel), and surfaced in
/// the tool result as an ordered trail plus the manager's snapshot.
public struct ReverseBridgeOutcome: Sendable {
    public let progress: [ReverseProgressEvent]
    public let evidence: ReverseEvidence?
    public let error: ReverseError?
    public let stderrTail: String

    public init(progress: [ReverseProgressEvent], evidence: ReverseEvidence?, error: ReverseError?, stderrTail: String) {
        self.progress = progress
        self.evidence = evidence
        self.error = error
        self.stderrTail = stderrTail
    }
}

/// Owns the Node child process that hosts the Reverse bridge script.
/// One process per request; instances are cheap and stateless, which
/// keeps cancellation (kill the process) and crash recovery (next
/// request spawns a fresh process) trivially correct.
public final class ReverseBridge: @unchecked Sendable {
    public static let maxFrameBytes = 1_048_576
    public static let maxStdoutBytes = 8_388_608
    public static let maxStderrBytes = 65_536

    private let lock = NSLock()
    private var running: [String: ProcessBox] = [:]
    private var cancelledIDs: Set<String> = []

    public init() {}

    // MARK: - Public API

    /// One-shot readiness probe: Node + bridge script + REA package.
    public func ping() async -> ReversePingInfo? {
        let request = ReverseBridgeRequest(id: UUID().uuidString, method: "ping", params: nil)
        do {
            let (messages, _) = try await runMessages(request: request, timeoutSeconds: 30)
            return messages.first?.ping
        } catch {
            return nil
        }
    }

    /// Capability discovery. Returns the allow-list with per-operation
    /// availability computed by the bridge (platform, objdump presence).
    public func capabilities() async throws -> [ReverseCapability] {
        let request = ReverseBridgeRequest(id: UUID().uuidString, method: "capabilities", params: nil)
        let (messages, _) = try await runMessages(request: request, timeoutSeconds: 30)
        guard let message = messages.first else {
            throw ReverseError(category: .bridgeFailure, code: "reverse_no_response", message: "Bridge returned no capability frame.", retryable: false)
        }
        if let payload = message.error {
            throw ReverseError.fromBridgePayload(payload)
        }
        return message.capabilities ?? ReverseOperation.allCases.map {
            ReverseCapability(operation: $0, available: false, unavailableReason: "Bridge returned no capability list")
        }
    }

    /// Runs one analysis operation through the bridge. `requestID` is
    /// the correlation/cancellation handle: the caller keeps it and
    /// passes it to `cancel(_:)` to terminate this exact operation.
    public func analyze(
        operation: ReverseOperation,
        targetPath: String,
        objdumpOperation: ReverseObjdumpOperation?,
        symbol: String?,
        task: String,
        timeoutSeconds: TimeInterval,
        requestID: String
    ) async throws -> ReverseBridgeOutcome {
        let request = ReverseBridgeRequest(
            id: requestID,
            method: "analyze",
            params: ReverseBridgeParams(
                operation: operation.rawValue,
                targetPath: targetPath,
                objdumpOperation: objdumpOperation?.rawValue,
                symbol: symbol,
                task: task,
                followDebugLinks: false
            )
        )
        return try await run(request: request, timeoutSeconds: timeoutSeconds)
    }

    /// Terminates the in-flight bridge process for `requestID`, if any.
    /// Best-effort: the process may already have exited. The cancelled
    /// mark is recorded only when a live process exists, so late
    /// cancels cannot accumulate stale entries.
    public func cancel(requestID: String) {
        let box = lock.withLock { () -> ProcessBox? in
            let b = running[requestID]
            if b != nil {
                cancelledIDs.insert(requestID)
            }
            return b
        }
        box?.process?.terminate()
        // Escalate to SIGKILL if the child ignores SIGTERM. The
        // @Sendable closure captures only the Sendable box.
        if let box {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                guard let process = box.process, process.isRunning else { return }
                #if canImport(Darwin)
                kill(process.processIdentifier, SIGKILL)
                #endif
            }
        }
    }

    /// Whether `requestID` was cancelled via `cancel(_:)`.
    public func wasCancelled(_ requestID: String) -> Bool {
        lock.withLock {
            cancelledIDs.contains(requestID)
        }
    }

    // MARK: - Resolution

    /// Locates the bridge script. Order: explicit settings override,
    /// `SWIFTCODE_REVERSE_BRIDGE_PATH` env, app-bundle resource
    /// (Copy Bundle Resources phase), Application Support copy.
    /// Returns nil when no script file exists — a typed unavailable
    /// error, never a silent fallback.
    /// Reads the override from UserDefaults directly (not via
    /// `AppSettings`, which is `@MainActor`-isolated and this type is
    /// not): the keys are the same `assist.*` keys AppSettings owns.
    public static func resolveBridgeURL() -> URL? {
        let fm = FileManager.default
        let candidates: [String?] = [
            nonEmpty(UserDefaults.standard.string(forKey: "assist.reverseBridgePath")),
            nonEmpty(ProcessInfo.processInfo.environment["SWIFTCODE_REVERSE_BRIDGE_PATH"]),
        ]
        for candidate in candidates {
            if let candidate {
                let expanded = (candidate as NSString).expandingTildeInPath
                if fm.isReadableFile(atPath: expanded) {
                    return URL(fileURLWithPath: expanded)
                }
            }
        }
        if let resource = Bundle.main.url(forResource: "ReverseBridge", withExtension: "mjs") {
            return resource
        }
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let url = support.appendingPathComponent("SwiftCode/Reverse/ReverseBridge.mjs")
            if fm.isReadableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Locates the pinned `rea-agents` package directory. Order: explicit
    /// settings override, `SWIFTCODE_REVERSE_REA_DIR` env, `node_modules`
    /// next to the bridge script, Application Support copy. The directory
    /// must contain `package.json` with version == pinned version.
    public static func resolveREADirectory(bridgeURL: URL?) -> URL? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let override = nonEmpty(UserDefaults.standard.string(forKey: "assist.reverseReaDir")) {
            candidates.append((override as NSString).expandingTildeInPath)
        }
        if let env = nonEmpty(ProcessInfo.processInfo.environment["SWIFTCODE_REVERSE_REA_DIR"]) {
            candidates.append((env as NSString).expandingTildeInPath)
        }
        if let bridgeURL {
            candidates.append(bridgeURL.deletingLastPathComponent().appendingPathComponent("node_modules/rea-agents").path)
        }
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(support.appendingPathComponent("SwiftCode/Reverse/node_modules/rea-agents").path)
        }
        for candidate in candidates {
            let packageURL = URL(fileURLWithPath: candidate).appendingPathComponent("package.json")
            guard let data = try? Data(contentsOf: packageURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String, name == ReverseBridgeProtocol.reaPackageName,
                  let version = json["version"] as? String, version == ReverseBridgeProtocol.pinnedREAVersion
            else { continue }
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    /// Resolves a Node.js executable without downloading anything.
    /// Mirrors the SDK node launcher's order: `SWIFTCODE_NODE_PATH`
    /// override, well-known locations, then PATH.
    public static func resolveNodeURL() -> URL? {
        let fm = FileManager.default
        func executable(at path: String) -> URL? {
            let expanded = (path as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue,
                  fm.isExecutableFile(atPath: expanded) else { return nil }
            return URL(fileURLWithPath: expanded)
        }
        if let override = nonEmpty(ProcessInfo.processInfo.environment["SWIFTCODE_NODE_PATH"]),
           let url = executable(at: override) {
            return url
        }
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] {
            if let url = executable(at: path) { return url }
        }
        if let pathValue = ProcessInfo.processInfo.environment["PATH"] {
            for component in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
                if let url = executable(at: "\(component)/node") { return url }
            }
        }
        return nil
    }

    /// Node major version for a resolved Node binary, e.g. 24 for v24.20.0.
    /// Runs `node --version` (argv only, no shell). Nil when it cannot be determined.
    public static func nodeMajorVersion(for nodeURL: URL) -> Int? {
        let process = Process()
        process.executableURL = nodeURL
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "")
        let major = text.split(separator: ".").first.flatMap { Int($0) }
        return major
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    /// Host environment with secret-bearing variables stripped. The bridge
    /// child never receives API keys, tokens, passwords, or client secrets.
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

    // MARK: - Process execution

    private struct RawOutcome {
        let stdout: Data
        let stderr: String
        let exitCode: Int32
        let timedOut: Bool
    }

    /// Runs one request and returns the parsed protocol frames plus the
    /// bridge stderr tail. Shared by analyze / ping / capabilities.
    private func runMessages(request: ReverseBridgeRequest, timeoutSeconds: TimeInterval) async throws -> ([ReverseBridgeMessage], String) {
        // Clear this request's cancelled mark on exit (success or throw)
        // so the set stays bounded to genuinely in-flight requests.
        defer {
            lock.withLock {
                _ = cancelledIDs.remove(request.id)
            }
        }
        guard let bridgeURL = Self.resolveBridgeURL() else {
            throw ReverseError.unavailable(
                "Reverse bridge script (ReverseBridge.mjs) was not found.",
                remediation: "Set the bridge path in Settings → Assist → Reverse, or reinstall SwiftCode so the bundled bridge resource is present. Reverse is unavailable until then."
            )
        }
        guard let reaDir = Self.resolveREADirectory(bridgeURL: bridgeURL) else {
            throw ReverseError.unavailable(
                "The pinned REA package (\(ReverseBridgeProtocol.reaPackageName)@\(ReverseBridgeProtocol.pinnedREAVersion)) was not found.",
                remediation: "Set the REA directory in Settings → Assist → Reverse to a folder containing rea-agents@\(ReverseBridgeProtocol.pinnedREAVersion) (package.json version must match). SwiftCode never downloads or installs it automatically."
            )
        }
        guard let nodeURL = Self.resolveNodeURL() else {
            throw ReverseError.unavailable(
                "Node.js was not found.",
                remediation: "Install Node.js 22, 24, or 26 (REA 6.5.0 engines) from nodejs.org or Homebrew, or set SWIFTCODE_NODE_PATH to a Node binary."
            )
        }
        // Probe on a detached task: `node --version` blocks until exit
        // and must never run on the caller's executor (often MainActor).
        let major = await Task.detached { Self.nodeMajorVersion(for: nodeURL) }.value
        if let major, !ReverseBridgeProtocol.supportedNodeMajors.contains(major) {
            throw ReverseError.unavailable(
                "Node.js v\(major) is not supported by REA \(ReverseBridgeProtocol.pinnedREAVersion).",
                remediation: "Use Node.js 22, 24, or 26."
            )
        }

        let encoder = JSONEncoder()
        let requestData: Data
        do {
            requestData = try encoder.encode(request)
        } catch {
            throw ReverseError(category: .bridgeFailure, code: "reverse_encode_failed", message: "Failed to encode bridge request: \(error.localizedDescription)", retryable: false)
        }

        let raw = try await spawn(
            requestID: request.id,
            nodeURL: nodeURL,
            bridgeURL: bridgeURL,
            reaDir: reaDir,
            requestData: requestData,
            timeoutSeconds: timeoutSeconds
        )

        if raw.timedOut {
            throw ReverseError(category: .timeout, code: "reverse_timeout", message: "Reverse operation timed out after \(Int(timeoutSeconds))s and the bridge process was terminated.", retryable: true, remediation: "Retry with a smaller target, or raise the timeout in Settings → Assist → Reverse.")
        }
        if wasCancelled(request.id) {
            throw ReverseError(category: .cancelled, code: "reverse_cancelled", message: "Reverse operation was cancelled.", retryable: false)
        }

        // Parse stdout frames: every line must be one protocol frame.
        let text = String(decoding: raw.stdout, as: UTF8.self)
        var messages: [ReverseBridgeMessage] = []
        let decoder = JSONDecoder()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let lineData = Data(line.utf8)
            guard lineData.count <= Self.maxFrameBytes else {
                throw ReverseError(category: .bridgeFailure, code: "reverse_frame_too_large", message: "Bridge frame exceeded the 1 MiB limit.", retryable: false)
            }
            guard let message = try? decoder.decode(ReverseBridgeMessage.self, from: lineData) else {
                throw ReverseError(
                    category: .bridgeFailure, code: "reverse_malformed_frame",
                    message: "Bridge sent a malformed protocol frame.",
                    retryable: false,
                    remediation: "Bridge stderr: \(raw.stderr.prefix(500))"
                )
            }
            guard message.version == ReverseBridgeProtocol.version else {
                throw ReverseError(category: .bridgeFailure, code: "reverse_version_mismatch", message: "Bridge protocol version mismatch (got \(message.version), expected \(ReverseBridgeProtocol.version)).", retryable: false)
            }
            guard message.id == request.id else {
                throw ReverseError(category: .bridgeFailure, code: "reverse_correlation_mismatch", message: "Bridge response correlation ID does not match the request.", retryable: false)
            }
            guard ["progress", "result", "error"].contains(message.type) else {
                throw ReverseError(category: .bridgeFailure, code: "reverse_unknown_frame", message: "Bridge sent an unknown frame type '\(message.type)'.", retryable: false)
            }
            messages.append(message)
        }

        if messages.isEmpty {
            throw ReverseError(
                category: .bridgeFailure, code: "reverse_no_response",
                message: "Bridge exited (code \(raw.exitCode)) without sending a protocol frame.",
                retryable: false,
                remediation: "Bridge stderr: \(raw.stderr.prefix(500))"
            )
        }
        return (messages, raw.stderr)
    }

    /// Runs one analysis operation: folds the bridge frames into an
    /// outcome (ordered progress trail + Evidence or typed error).
    private func run(request: ReverseBridgeRequest, timeoutSeconds: TimeInterval) async throws -> ReverseBridgeOutcome {
        let (messages, stderr) = try await runMessages(request: request, timeoutSeconds: timeoutSeconds)
        var progress: [ReverseProgressEvent] = []
        var evidence: ReverseEvidence?
        var bridgeError: ReverseError?
        for message in messages {
            switch message.type {
            case "progress":
                if let event = message.progress { progress.append(event) }
            case "result":
                evidence = message.evidence
            case "error":
                if let payload = message.error { bridgeError = ReverseError.fromBridgePayload(payload) }
            default:
                break
            }
        }
        if let bridgeError {
            // A partial-evidence error still surfaces the evidence upstream.
            return ReverseBridgeOutcome(progress: progress, evidence: bridgeError.partialEvidence, error: bridgeError, stderrTail: stderr)
        }
        guard let evidence else {
            throw ReverseError(category: .bridgeFailure, code: "reverse_missing_evidence", message: "Bridge completed without returning Evidence or an error.", retryable: false, remediation: "Bridge stderr: \(stderr.prefix(500))")
        }
        return ReverseBridgeOutcome(progress: progress, evidence: evidence, error: nil, stderrTail: stderr)
    }

    private func spawn(
        requestID: String,
        nodeURL: URL,
        bridgeURL: URL,
        reaDir: URL,
        requestData: Data,
        timeoutSeconds: TimeInterval
    ) async throws -> RawOutcome {
        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [bridgeURL.path, "--rea-dir", reaDir.path]
        process.environment = Self.sanitizedEnvironment()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Sendable holder: @Sendable closures (timeout, cancellation)
        // capture only this box, never the non-Sendable Process.
        let box = ProcessBox(process)

        lock.withLock {
            running[requestID] = box
        }
        defer {
            lock.withLock {
                _ = running.removeValue(forKey: requestID)
            }
        }

        do {
            try process.run()
        } catch {
            throw ReverseError(category: .bridgeFailure, code: "reverse_launch_failed", message: "Failed to launch the Reverse bridge: \(error.localizedDescription)", retryable: false)
        }

        // Drain both pipes via readability handlers so a chatty child
        // can never deadlock on a full pipe. Bounded: keep only tails.
        let stdoutBox = BoundedDataBox(limit: Self.maxStdoutBytes + 1)
        let stderrBox = BoundedDataBox(limit: Self.maxStderrBytes)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stdoutBox.append(chunk) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stderrBox.append(chunk) }
        }
        // Write the single request line, then close stdin (the bridge
        // reads stdin to EOF, then executes).
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: requestData + Data([0x0A]))
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            process.terminate()
            throw ReverseError(category: .bridgeFailure, code: "reverse_write_failed", message: "Failed to write to the Reverse bridge: \(error.localizedDescription)", retryable: false)
        }

        // Timeout: terminate the child if it outlives the budget.
        // Fires exactly once; harmless no-op when already exited.
        let timedOutBox = FlagBox()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) {
            guard let proc = box.process, proc.isRunning else { return }
            timedOutBox.set(true)
            proc.terminate()
        }

        // Wait via terminationHandler + continuation (no blocked thread,
        // no non-Sendable capture in a detached task). Task cancellation
        // terminates the child; the continuation then resumes with the
        // real termination status.
        let exitCode: Int32
        do {
            exitCode = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                    let gate = FlagBox()
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
            } onCancel: {
                box.process?.terminate()
            }
        } catch is CancellationError {
            // withTaskCancellationHandler already terminated the child;
            // report cancellation, not the raw CancellationError.
            throw ReverseError(category: .cancelled, code: "reverse_cancelled", message: "Reverse operation was cancelled.", retryable: false)
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        // Drain any bytes that arrived after the last handler invocation.
        let stdoutTail = stdoutPipe.fileHandleForReading.availableData
        if !stdoutTail.isEmpty { stdoutBox.append(stdoutTail) }
        let stderrTail = stderrPipe.fileHandleForReading.availableData
        if !stderrTail.isEmpty { stderrBox.append(stderrTail) }
        let stdoutData = stdoutBox.data
        if stdoutData.count > Self.maxStdoutBytes {
            throw ReverseError(category: .bridgeFailure, code: "reverse_output_too_large", message: "Bridge stdout exceeded the 8 MiB total limit.", retryable: false)
        }
        let stderrText = String(decoding: stderrBox.data, as: UTF8.self)
        return RawOutcome(stdout: stdoutData, stderr: stderrText, exitCode: exitCode, timedOut: timedOutBox.value)
    }
}

// MARK: - Small thread-safe boxes

private final class BoundedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var buffer = Data()
    init(limit: Int) { self.limit = limit }
    func append(_ data: Data) {
        lock.withLock {
            buffer.append(data)
            if buffer.count > limit {
                buffer = buffer.suffix(limit)
            }
        }
    }
    var data: Data {
        lock.withLock { buffer }
    }
}

private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set(_ value: Bool) {
        lock.withLock { flag = value }
    }
    var value: Bool {
        lock.withLock { flag }
    }
    /// Returns true to the single first caller; false afterwards.
    /// Guards a CheckedContinuation against double-resume races.
    func claim() -> Bool {
        lock.withLock {
            guard !flag else { return false }
            flag = true
            return true
        }
    }
}

/// Sendable holder for a `Process` (which is not itself Sendable).
/// @Sendable closures capture only this box; the process is reached
/// through the lock-guarded accessor.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    init(_ process: Process) { _process = process }
    var process: Process? {
        lock.withLock { _process }
    }
}
