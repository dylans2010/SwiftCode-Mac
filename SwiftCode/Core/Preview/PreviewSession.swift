import Foundation

public enum PreviewSessionState: String, Codable, Sendable {
    case init_state = "INIT"
    case sourceReceived = "SOURCE_RECEIVED"
    case discovering = "DISCOVERING"
    case noCandidates = "NO_CANDIDATES"
    case compiling = "COMPILING"
    case rendering = "RENDERING"
    case rendered = "RENDERED"
    case failedKeepLast = "FAILED_KEEP_LAST"
    case failedNoPrior = "FAILED_NO_PRIOR"
}

/// Structured diagnostic model capturing compilation/validation failures.
public struct PreviewDiagnosticModel: Sendable, Codable, Identifiable, Hashable {
    public var id: UUID { UUID() }
    public let stage: String
    public let subsystem: String
    public let file: String?
    public let line: Int?
    public let severity: String // "error", "warning"
    public let description: String
    public let suggestedFix: String?
    public let rawCompilerOutput: String

    public init(
        stage: String,
        subsystem: String,
        file: String?,
        line: Int?,
        severity: String,
        description: String,
        suggestedFix: String?,
        rawCompilerOutput: String
    ) {
        self.stage = stage
        self.subsystem = subsystem
        self.file = file
        self.line = line
        self.severity = severity
        self.description = description
        self.suggestedFix = suggestedFix
        self.rawCompilerOutput = rawCompilerOutput
    }
}

public struct PreviewSession: Identifiable, Hashable, Codable, Sendable {
    public var id: String { sessionID }
    public let sessionID: String
    public let sourceFilePath: String
    public let targetViewName: String
    public var lastCompiledAt: Date
    public var status: String // Compiling, Ready, Failed, Idle
    public var state: PreviewSessionState
    public var activeNodeHashes: [String: Int] // Node ID -> properties hash for incremental change detection

    // Centralized Build Pipeline Session details
    public var activeProject: String = "None"
    public var activeScheme: String = "None"
    public var buildConfig: String = "Debug"
    public var previewTargets: [PreviewTarget] = []
    public var diagnostics: [PreviewDiagnosticModel] = []
    public var logs: [String] = []
    public var buildResult: String? = nil
    public var compiledProduct: URL? = nil

    public init(
        sessionID: String,
        sourceFilePath: String,
        targetViewName: String,
        lastCompiledAt: Date = Date(),
        status: String = "Idle",
        state: PreviewSessionState = .init_state,
        activeNodeHashes: [String: Int] = [:]
    ) {
        self.sessionID = sessionID
        self.sourceFilePath = sourceFilePath
        self.targetViewName = targetViewName
        self.lastCompiledAt = lastCompiledAt
        self.status = status
        self.state = state
        self.activeNodeHashes = activeNodeHashes
    }

    /// Determines if a specific layout node or property has actually changed
    public func hasNodeChanged(id: String, hash: Int) -> Bool {
        return activeNodeHashes[id] != hash
    }
}
