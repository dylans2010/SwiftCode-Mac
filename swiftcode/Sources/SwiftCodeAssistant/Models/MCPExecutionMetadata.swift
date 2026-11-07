import Foundation

public struct MCPExecutionMetadata: Codable, Sendable, Identifiable {
    public let id: UUID
    public let serverName: String
    public let toolName: String
    public let arguments: String
    public var output: String
    public var success: Bool
    public var isExecuting: Bool
    public var duration: TimeInterval
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        serverName: String,
        toolName: String,
        arguments: String,
        output: String = "",
        success: Bool = false,
        isExecuting: Bool = true,
        duration: TimeInterval = 0.0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.serverName = serverName
        self.toolName = toolName
        self.arguments = arguments
        self.output = output
        self.success = success
        self.isExecuting = isExecuting
        self.duration = duration
        self.timestamp = timestamp
    }
}
