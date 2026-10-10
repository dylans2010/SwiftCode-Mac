//
//  GoogleCloudSDKEvent.swift
//  SwiftCode
//
//  Strongly-typed stream events emitted by the Antigravity runtime.
//

import Foundation

public struct GoogleCloudSDKUsage: Codable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int = 0, completionTokens: Int = 0, totalTokens: Int = 0) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public enum GoogleCloudSDKEvent: Sendable {
    case runtimeReady(version: String, pid: Int32)
    case agentStarted(sessionId: String, prompt: String?)
    case agentProgress(sessionId: String, delta: String?, thoughtDelta: String?)
    case agentCompleted(sessionId: String, response: String, stopReason: String?, usage: GoogleCloudSDKUsage?)
    case agentFailed(sessionId: String, error: String)
    case toolStarted(tool: GoogleCloudSDKToolEvent)
    case toolProgress(sessionId: String, toolId: String, message: String, outputChunk: String? = nil, callId: String? = nil)
    case toolCompleted(result: GoogleCloudSDKToolResult)
    case toolFailed(sessionId: String, toolId: String, toolName: String, error: String)
    case workerStarted(sessionId: String, workerId: String, name: String, args: String)
    case workerProgress(sessionId: String, workerId: String, progress: String)
    case workerCompleted(sessionId: String, workerId: String, result: String)
    case workerFailed(sessionId: String, workerId: String, error: String)
    case runtimeStopped
    case error(message: String)

    /// Returns the target session ID if this event is session-scoped.
    public var targetSessionId: String? {
        switch self {
        case .agentStarted(let sid, _),
             .agentProgress(let sid, _, _),
             .agentCompleted(let sid, _, _, _),
             .agentFailed(let sid, _),
             .workerStarted(let sid, _, _, _),
             .workerProgress(let sid, _, _),
             .workerCompleted(let sid, _, _),
             .workerFailed(let sid, _, _):
            return sid
        case .toolStarted(let tool):
            return tool.sessionId
        case .toolCompleted(let res):
            return res.sessionId
        case .toolProgress(let sid, _, _, _, _):
            return sid
        case .toolFailed(let sid, _, _, _):
            return sid
        case .runtimeReady, .runtimeStopped, .error:
            return nil
        }
    }
}
