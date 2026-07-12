import Foundation

public struct PreviewSession: Identifiable, Hashable, Codable, Sendable {
    public var id: String { sessionID }
    public let sessionID: String
    public let sourceFilePath: String
    public let targetViewName: String
    public var lastCompiledAt: Date
    public var status: String // Compiling, Ready, Failed, Idle

    public init(sessionID: String, sourceFilePath: String, targetViewName: String, lastCompiledAt: Date = Date(), status: String = "Idle") {
        self.sessionID = sessionID
        self.sourceFilePath = sourceFilePath
        self.targetViewName = targetViewName
        self.lastCompiledAt = lastCompiledAt
        self.status = status
    }
}
