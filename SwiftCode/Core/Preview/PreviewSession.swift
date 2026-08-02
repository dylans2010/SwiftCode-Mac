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

public struct PreviewSession: Identifiable, Hashable, Codable, Sendable {
    public var id: String { sessionID }
    public let sessionID: String
    public let sourceFilePath: String
    public let targetViewName: String
    public var lastCompiledAt: Date
    public var status: String // Compiling, Ready, Failed, Idle
    public var state: PreviewSessionState
    public var activeNodeHashes: [String: Int] // Node ID -> properties hash for incremental change detection

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
