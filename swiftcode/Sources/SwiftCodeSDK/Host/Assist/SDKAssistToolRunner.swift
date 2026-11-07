import Foundation

public protocol SDKAssistToolRunning: Sendable {
    func liveAllowedToolIDs(for extensionID: String) async -> Set<String>?

    func runTool(session: SDKAssistSession, call: SDKAssistToolCall) async throws -> SDKAssistToolResult
}
