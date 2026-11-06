import Foundation
import SwiftCodeBuild

// MARK: - SDKBuildService
//
// Ported from Legacy `SwiftCode/SDK/Host/ServiceAdapters/Build/SDKBuildService.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Runs extension builds through the host's managed build service.
// Process execution delegates to SwiftCodeBuild's `XcodebuildEngine` —
// never a raw `Process` here — while Legacy's semantics are kept:
// typed allow-list request, host environment only, working directory
// confined to the caller's project root, one build per extension,
// bounded streams, and a truthful terminal result decided by
// `SDKBuildOutputParser.didSucceed` (exit 0 AND `** BUILD SUCCEEDED **`
// AND zero parsed errors).
//
// DEVIATIONS from Legacy (recorded in the slice spec draft):
// - SwiftCodeBuild's default command is `["/usr/bin/xcrun", "xcodebuild"]`;
//   Legacy pinned `/usr/bin/xcodebuild`. Same tool, different launcher.
// - Legacy located the project via the app's
//   `AssistXcodeProjectResolver` and resolved the scheme with
//   `xcodebuild -list` (explicit scheme, else first scheme, else bundle
//   name). The scheme half now exists in SwiftCode (Wave 16, Slice D):
//   `XcodeSchemeDiscovery` (SwiftCodeBuild) resolves the scheme in
//   Legacy's precedence order — explicit-when-known, first listed,
//   first `.xcscheme` file, else the requested target / container
//   name — and the resolution (including the fallback reason) is
//   logged. The container half is still resolved from the project
//   root (`.xcworkspace` > `.xcodeproj` > `Package.swift`); the
//   resolver's `locate(relativePath:)` and pbxproj introspection
//   (`groupID`, `sourcesBuildPhaseID`) belong to the MCP project
//   tools, not to this service.

public actor SDKBuildService {
    public static let shared = SDKBuildService()

    /// Maximum streamed events per build.
    public static let maxStreamedEvents = 20_000
    /// Maximum retained build output (4 MiB).
    public static let maxRetainedOutputBytes = 4 * 1024 * 1024
    /// Maximum diagnostics in the terminal result.
    public static let maxResultDiagnostics = 50
    /// Maximum build time (30 minutes).
    public static let buildTimeout: TimeInterval = 1_800

    private let engine: any BuildEngine
    private var activeHandles: [String: SDKBuildHandle] = [:]
    /// Resolves the scheme to build (Wave 16: `XcodeSchemeDiscovery`).
    /// Injectable so tests can stub discovery; the default runs the
    /// real `xcodebuild -list` leg on macOS and the file leg anywhere.
    private let schemeDiscovery: XcodeSchemeDiscovery

    public init(engine: any BuildEngine = XcodebuildEngine(), schemeDiscovery: XcodeSchemeDiscovery = XcodeSchemeDiscovery()) {
        self.engine = engine
        self.schemeDiscovery = schemeDiscovery
    }

    /// Starts a build for `caller`. Authorizes `.buildExecute` first.
    /// Throws `.invalidArgument` for a malformed request,
    /// `.invalidTarget` when no buildable container is found, and
    /// `.resourceLimitExceeded` when the extension already has a build
    /// running. Returns a handle for streaming events and waiting.
    public func run(caller: SDKCallerIdentity, request: SDKBuildRequest) async throws -> SDKBuildHandle {
        try await SDKCapabilityBroker.authorize(.buildExecute, for: caller)
        guard activeHandles[caller.extensionID] == nil else {
            throw SDKError(code: .resourceLimitExceeded, message: "A build is already running for this extension.")
        }
        let validated = try validate(request)
        let container = try resolveContainer(projectRoot: caller.projectRootPath)
        let resolvedScheme = await schemeDiscovery.resolveScheme(explicit: validated.target, container: container)
        if let reason = resolvedScheme.reason {
            SDKLog.info("SDKBuildService: scheme '\(resolvedScheme.scheme)' (\(resolvedScheme.source.rawValue)): \(reason)")
        }
        let buildRequest = BuildRequest(
            container: container,
            scheme: resolvedScheme.scheme,
            configuration: validated.configuration,
            destination: validated.destination
        )
        let operation = engine.start(buildRequest)
        let handle = SDKBuildHandle(callerExtensionID: caller.extensionID, operation: operation)
        activeHandles[caller.extensionID] = handle
        Task {
            await drive(handle: handle, operation: operation)
            await removeHandle(for: caller.extensionID, handle: handle)
        }
        return handle
    }

    // MARK: - Private

    private func removeHandle(for extensionID: String, handle: SDKBuildHandle) {
        if activeHandles[extensionID] === handle {
            activeHandles.removeValue(forKey: extensionID)
        }
    }

    private struct ValidatedRequest {
        let target: String
        let configuration: String?
        let destination: String
    }

    private func validate(_ request: SDKBuildRequest) throws -> ValidatedRequest {
        let target = request.target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, target.count <= 256, !target.contains("\0") else {
            throw SDKError(code: .invalidArgument, message: "The build target is invalid.")
        }
        if let configuration = request.configuration {
            guard configuration == "Debug" || configuration == "Release" else {
                throw SDKError(code: .invalidArgument, message: "The build configuration must be Debug or Release.")
            }
        }
        let destination = request.destination ?? "platform=macOS"
        guard destination.count <= 256, !destination.contains("\0") else {
            throw SDKError(code: .invalidArgument, message: "The build destination is invalid.")
        }
        return ValidatedRequest(target: target, configuration: request.configuration, destination: destination)
    }

    private func resolveContainer(projectRoot: String) throws -> BuildRequest.Container {
        let root = URL(fileURLWithPath: projectRoot)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        // Prefer a workspace, then a project, then a Swift package.
        if let workspace = names.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return .workspace(root.appendingPathComponent(workspace).path)
        }
        if let project = names.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return .project(root.appendingPathComponent(project).path)
        }
        if names.contains("Package.swift") {
            return .package(root.path)
        }
        throw SDKError(
            code: .invalidTarget,
            message: "No buildable project, workspace, or package was found in the project.",
            suggestion: "Open a project containing an .xcodeproj, .xcworkspace, or Package.swift file."
        )
    }

    private func drive(handle: SDKBuildHandle, operation: BuildOperation) async {
        let startedAt = Date()
        var retainedOutput = ""
        var retainedBytes = 0
        var streamedEvents = 0
        var engineResult: SwiftCodeBuild.BuildResult?
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(Self.buildTimeout))
            await handle.markTimedOut()
            operation.cancel()
        }
        defer { timeoutTask.cancel() }
        for await event in operation.events {
            switch event {
            case .output(let line):
                guard streamedEvents < Self.maxStreamedEvents else { continue }
                streamedEvents += 1
                let lineBytes = line.utf8.count + 1
                if retainedBytes + lineBytes <= Self.maxRetainedOutputBytes {
                    retainedOutput += line + "\n"
                    retainedBytes += lineBytes
                }
                await handle.emit(.init(kind: .stdout, text: line))
            case .issue(let diagnostic):
                guard streamedEvents < Self.maxStreamedEvents else { continue }
                streamedEvents += 1
                let text = "\(diagnostic.location.map { "\($0.file):\($0.line): " } ?? "")\(diagnostic.message)"
                await handle.emit(.init(kind: .stderr, text: text))
            case .activity(let text):
                await handle.emit(.init(kind: .status, text: text))
            case .planning, .progress:
                break
            case .finished(let result):
                engineResult = result
            }
        }
        let result = engineResult ?? SwiftCodeBuild.BuildResult(status: .cancelled, exitCode: -1, issues: [])
        let parsed = SDKBuildOutputParser.parse(retainedOutput, maxDiagnostics: Self.maxResultDiagnostics)
        let timedOut = await handle.isTimedOut
        let status: SDKBuildStatus
        switch result.status {
        case .cancelled:
            status = timedOut ? .timedOut : .cancelled
        case .succeeded, .failed:
            status = SDKBuildOutputParser.didSucceed(output: retainedOutput, exitCode: result.exitCode, parsed: parsed)
                ? .succeeded : .failed
        }
        let duration = Date().timeIntervalSince(startedAt)
        await handle.finish(with: SDKBuildResult(
            status: status,
            exitCode: Int(result.exitCode),
            durationSeconds: duration,
            errorCount: parsed.errorCount,
            warningCount: parsed.warningCount,
            diagnostics: parsed.diagnostics,
            correlationId: await handle.correlationId
        ))
    }
}

// MARK: - SDKBuildHandle

/// A running build: streams output events and resolves to a truthful
/// terminal result. `wait()` is idempotent and cached; `cancel()`
/// terminates the underlying build. Possession of the handle IS the
/// authorization for `build.wait` / `build.cancel` — handles are never
/// shared across extensions (the dispatcher enforces that).
public final actor SDKBuildHandle {
    public let id = UUID()
    public let correlationId = SDKError.newCorrelationId()
    public let callerExtensionID: String

    private let operation: BuildOperation
    private let stream: AsyncStream<SDKBuildOutputEvent>
    private let continuation: AsyncStream<SDKBuildOutputEvent>.Continuation
    private var result: SDKBuildResult?
    private var waiters: [CheckedContinuation<SDKBuildResult, Never>] = []
    private var timedOut = false

    public init(callerExtensionID: String, operation: BuildOperation) {
        self.callerExtensionID = callerExtensionID
        self.operation = operation
        var storedContinuation: AsyncStream<SDKBuildOutputEvent>.Continuation!
        self.stream = AsyncStream { storedContinuation = $0 }
        self.continuation = storedContinuation
    }

    /// The output event stream. Single-consumer, like Legacy.
    public var events: AsyncStream<SDKBuildOutputEvent> { stream }

    public var isTimedOut: Bool { timedOut }

    public func markTimedOut() {
        timedOut = true
    }

    fileprivate func emit(_ event: SDKBuildOutputEvent) {
        continuation.yield(event)
    }

    /// Waits for the terminal result. Idempotent: every caller gets
    /// the same cached result.
    public func wait() async -> SDKBuildResult {
        if let result { return result }
        return await withCheckedContinuation { (continuation: CheckedContinuation<SDKBuildResult, Never>) in
            waiters.append(continuation)
        }
    }

    /// Cancels the underlying build.
    public func cancel() {
        operation.cancel()
    }

    fileprivate func finish(with result: SDKBuildResult) {
        guard self.result == nil else { return }
        self.result = result
        continuation.finish()
        for waiter in waiters { waiter.resume(returning: result) }
        waiters = []
    }
}
