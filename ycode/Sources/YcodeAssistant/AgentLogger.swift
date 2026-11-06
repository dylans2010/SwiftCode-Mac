// Adapted from SwiftCode-Legacy SwiftCode/Core/AI/Agent/AgentLogger.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
// Adaptation note: SwiftUI import dropped (unused); the log model is Foundation/Observation only.
import Foundation
import Observation

public struct ToolLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let toolName: String
    public let arguments: [String: any Sendable]
    public let source: ToolSource
    public let timestamp: Date

    public init(id: UUID = UUID(), toolName: String, arguments: [String: any Sendable], source: ToolSource, timestamp: Date = Date()) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.source = source
        self.timestamp = timestamp
    }
}

@Observable
@MainActor
public final class AgentLogger {
    public static let shared = AgentLogger()

    public var toolLogs: [ToolLogEntry] = []

    private init() {}

    public func logToolExecution(name: String, arguments: [String: any Sendable], source: ToolSource) {
        let entry = ToolLogEntry(toolName: name, arguments: arguments, source: source)
        self.toolLogs.append(entry)
    }
}
