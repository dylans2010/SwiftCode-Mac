import Foundation

// MARK: - SDKBuildRequest
//
// Intent to start a build via `build.execute` (spec §11.3).
//
// Deliberate allow-list (architecture doc §2): only target, configuration,
// and destination may be supplied. There are intentionally NO environment,
// settings, or executable fields — `build.execute` is not a shell, and the
// host pins `/usr/bin/xcodebuild`. Unknown/unsupported targets are rejected
// by the host with INVALID_TARGET.

public struct SDKBuildRequest: Codable, Sendable {
    /// Build target (scheme) name. Validated against the project's schemes.
    public let target: String
    /// Build configuration (e.g. "Debug", "Release"). Nil = project default.
    public let configuration: String?
    /// Destination specifier (e.g. "platform=macOS"). Nil = host default.
    public let destination: String?

    public init(target: String, configuration: String? = nil, destination: String? = nil) {
        self.target = target
        self.configuration = configuration
        self.destination = destination
    }
}

// MARK: - SDKBuildOutputKind
//
// Classification of a single streamed build output event.

public enum SDKBuildOutputKind: String, Codable, Sendable {
    /// Standard output from the build process.
    case stdout
    /// Standard error from the build process.
    case stderr
    /// Host-generated lifecycle note (e.g. "build started", "cancelling").
    /// Never raw process output.
    case status
}

// MARK: - SDKBuildOutputEvent
//
// One streamed output event from a running build. Events for a build are
// delivered in emission order over the IPC event channel.

public struct SDKBuildOutputEvent: Codable, Sendable {
    /// Which stream this event came from.
    public let kind: SDKBuildOutputKind
    /// The output text (one logical chunk; may be a partial line).
    public let text: String
    /// Host-side emission time.
    public let timestamp: Date

    public init(kind: SDKBuildOutputKind, text: String, timestamp: Date = Date()) {
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
    }
}

// MARK: - SDKBuildDiagnostic
//
// A single structured compiler/build diagnostic parsed from build output.
// Optional location fields: some diagnostics have no file/line context.

public struct SDKBuildDiagnostic: Codable, Sendable {
    /// Repository-relative file path when the diagnostic has a location.
    public let file: String?
    /// 1-based line number when the diagnostic has a location.
    public let line: Int?
    /// The diagnostic message text.
    public let message: String

    public init(file: String? = nil, line: Int? = nil, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }
}

// MARK: - SDKBuildStatus
//
// Terminal (or in-progress) state of a build. The final state MUST reflect
// the actual build service's terminal result — never "succeeded" merely
// because a process was launched (spec §6.3, §11.3).

public enum SDKBuildStatus: String, Codable, Sendable {
    /// Build is still running; more output events may follow.
    case running
    /// Build finished with exit code 0, a success marker, and zero errors.
    case succeeded
    /// Build finished with a non-zero exit code or parsed errors.
    case failed
    /// Build was cancelled and the underlying process was terminated.
    case cancelled
    /// Build exceeded its time budget and was terminated.
    case timedOut
}

// MARK: - SDKBuildResult
//
// Terminal result of a build (`BuildHandle.wait()` in spec §11.3).
// `correlationId` ties the result to host-side logs and any SDKError raised
// for this build, per the dual-logging model (architecture doc §8).

public struct SDKBuildResult: Codable, Sendable {
    /// Terminal state. Only `succeeded` means the build actually passed.
    public let status: SDKBuildStatus
    /// Process exit code when the build ran to a process exit; nil when the
    /// build never produced one (e.g. cancelled before launch completed).
    public let exitCode: Int?
    /// Wall-clock duration of the build in seconds.
    public let durationSeconds: Double
    /// Number of error diagnostics parsed from the output.
    public let errorCount: Int
    /// Number of warning diagnostics parsed from the output.
    public let warningCount: Int
    /// Structured diagnostics (bounded by the host; see truncation rules).
    public let diagnostics: [SDKBuildDiagnostic]
    /// Correlation ID shared with host logs and related SDK errors.
    public let correlationId: String

    public init(
        status: SDKBuildStatus,
        exitCode: Int? = nil,
        durationSeconds: Double,
        errorCount: Int = 0,
        warningCount: Int = 0,
        diagnostics: [SDKBuildDiagnostic] = [],
        correlationId: String = SDKError.newCorrelationId()
    ) {
        self.status = status
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.diagnostics = diagnostics
        self.correlationId = correlationId
    }
}
