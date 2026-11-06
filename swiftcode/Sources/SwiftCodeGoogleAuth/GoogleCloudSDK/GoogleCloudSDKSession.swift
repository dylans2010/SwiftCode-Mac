//
//  GoogleCloudSDKSession.swift
//  SwiftCode
//
//  Native representation of an active Antigravity SDK session.
//
//  Ported from Legacy (Dylan's own code; direct port authorised
//  under MIT):
//    SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKSession.swift
//
//  Adaptation for the destination: the session configuration is
//  `SDKSessionConfiguration` from SwiftCodeAssistant (the
//  destination replacement for Legacy's
//  `GoogleCloudSDKConfiguration` — see AssistSDKModelSelection.swift).
//  All behaviour is otherwise verbatim.

import Foundation
import os

import SwiftCodeAssistant

private let logger = Logger(subsystem: "com.swiftcode.GoogleCloudSDK", category: "GoogleCloudSDKSession")

public final class GoogleCloudSDKSession: Identifiable, Sendable {
    public let id: String
    public let config: SDKSessionConfiguration
    private let bridge: GoogleCloudSDKBridge
    public let conversationId: String?

    public init(id: String, config: SDKSessionConfiguration, bridge: GoogleCloudSDKBridge, conversationId: String? = nil) {
        self.id = id
        self.config = config
        self.bridge = bridge
        self.conversationId = conversationId
    }

    /// Subscribes to events specifically for this session.
    public func subscribeEvents() async -> AsyncStream<GoogleCloudSDKEvent> {
        let stream = await bridge.subscribeEvents()
        let targetId = self.id

        return AsyncStream { continuation in
            let task = Task {
                for await event in stream {
                    switch event {
                    case .agentStarted(let sid, _),
                         .agentProgress(let sid, _, _),
                         .agentCompleted(let sid, _, _, _),
                         .agentFailed(let sid, _),
                         .workerStarted(let sid, _, _, _),
                         .workerProgress(let sid, _, _),
                         .workerCompleted(let sid, _, _),
                         .workerFailed(let sid, _, _):
                        if sid == targetId {
                            continuation.yield(event)
                        }
                    case .toolStarted(let tool):
                        if tool.sessionId == targetId {
                            continuation.yield(event)
                        }
                    case .toolCompleted(let res):
                        if res.sessionId == targetId {
                            continuation.yield(event)
                        }
                    case .toolFailed(_, _, _):
                        // Forward tool failure
                        continuation.yield(event)
                    case .toolProgress:
                        continuation.yield(event)
                    case .runtimeReady, .runtimeStopped, .error:
                        // Global runtime events
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Sends a conversational prompt to the agent and initiates execution.
    public func sendMessage(_ content: String, attachments: [GoogleCloudSDKAttachment] = []) async throws {
        _ = try await bridge.sendMessage(sessionId: self.id, content: content, attachments: attachments)
    }

    /// Cancels in-progress generation or tool execution.
    public func cancel() async throws {
        _ = try await bridge.cancelMessage(sessionId: self.id)
    }

    /// Closes the session and frees memory in the bridge.
    public func close() async throws {
        _ = try await bridge.closeSession(sessionId: self.id)
    }
}
