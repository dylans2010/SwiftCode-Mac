//
//  GoogleCloudSDKSession.swift
//  SwiftCode
//
//  Native representation of an active Antigravity SDK session.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.GoogleCloudSDK", category: "GoogleCloudSDKSession")

public final class GoogleCloudSDKSession: Identifiable, Sendable {
    public let id: String
    public let config: GoogleCloudSDKConfiguration
    private let bridge: GoogleCloudSDKBridge
    public let conversationId: String?

    public init(id: String, config: GoogleCloudSDKConfiguration, bridge: GoogleCloudSDKBridge, conversationId: String? = nil) {
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
                    if Task.isCancelled { break }

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
                    case .toolProgress(let sid, _, _, _, _):
                        if sid == targetId {
                            continuation.yield(event)
                        }
                    case .toolFailed(let sid, _, _, _):
                        if sid == targetId {
                            continuation.yield(event)
                        }
                    case .runtimeStopped:
                        continuation.yield(event)
                        continuation.finish()
                        return
                    case .runtimeReady, .error:
                        // Global events
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

    /// Sends a conversational prompt to the agent and initiates execution with cooperative cancellation.
    public func sendMessage(_ content: String, attachments: [GoogleCloudSDKAttachment] = []) async throws {
        try await withTaskCancellationHandler {
            _ = try await bridge.sendMessage(sessionId: self.id, content: content, attachments: attachments)
        } onCancel: {
            Task { [weak self] in
                guard let self = self else { return }
                try? await self.cancel()
            }
        }
    }

    /// Cancels in-progress generation or tool execution.
    public func cancel() async throws {
        do {
            _ = try await bridge.cancelMessage(sessionId: self.id)
        } catch {
            logger.warning("Failed to cancel message for session \(self.id): \(error.localizedDescription)")
            throw error
        }
    }

    /// Closes the session and frees memory in the bridge.
    public func close() async throws {
        do {
            _ = try await bridge.closeSession(sessionId: self.id)
        } catch {
            logger.warning("Failed to close session \(self.id): \(error.localizedDescription)")
            throw error
        }
    }
}
