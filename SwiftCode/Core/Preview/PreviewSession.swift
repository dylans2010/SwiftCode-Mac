import Foundation

public struct PreviewSession: Identifiable, Hashable, Codable, Sendable {
    public var id: String { sessionID }
    public let sessionID: String
    public let sourceFilePath: String
    public let targetViewName: String
    public var lastCompiledAt: Date
    public var status: String // Compiling, Ready, Failed, Idle
    public var activeNodeHashes: [String: Int] // Node ID -> properties hash for incremental change detection

    public init(
        sessionID: String,
        sourceFilePath: String,
        targetViewName: String,
        lastCompiledAt: Date = Date(),
        status: String = "Idle",
        activeNodeHashes: [String: Int] = [:]
    ) {
        self.sessionID = sessionID
        self.sourceFilePath = sourceFilePath
        self.targetViewName = targetViewName
        self.lastCompiledAt = lastCompiledAt
        self.status = status
        self.activeNodeHashes = activeNodeHashes
    }

    /// Determines if a specific layout node or property has actually changed
    public func hasNodeChanged(id: String, hash: Int) -> Bool {
        return activeNodeHashes[id] != hash
    }
}
