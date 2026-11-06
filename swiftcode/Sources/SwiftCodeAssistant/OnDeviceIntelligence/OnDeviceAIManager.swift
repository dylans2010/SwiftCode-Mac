// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/On Device Intelligence/OnDeviceAIManager.swift
//   (Legacy commit d51a8f0d)
//
// Session, streaming and cancellation are Legacy's own. The streamed
// text is the real reply from `AppleIntelligenceService` (which routes
// through `FoundationModelsProvider`); the word-by-word pacing with a
// 35 ms delay is presentation pacing of that real reply, not generated
// content. Adaptation: Legacy was `ObservableObject` with `@Published`
// state; the destination uses `@Observable` (see LocalModelManager /
// OfflineModelManager), so this follows that convention.

import Foundation
import Observation

@MainActor
@Observable
public final class OnDeviceAIManager {
    public static let shared = OnDeviceAIManager()

    public private(set) var activeSession = OnDeviceSession()
    public private(set) var streamedText = ""
    public private(set) var isStreaming = false

    private let service = AppleIntelligenceService()
    private var currentTask: Task<Void, Never>?

    private init() {}

    public func sendPrompt(_ prompt: String, task: AppleIntelligenceService.TaskType = .textGeneration) async throws -> String {
        activeSession.history.append(AIMessage(role: .user, content: prompt))
        let response = try await service.process(prompt: prompt, task: task, session: activeSession)
        activeSession.history.append(AIMessage(role: .assistant, content: response))
        activeSession.lastUpdated = Date()
        return response
    }

    public func streamResponse(for prompt: String, task: AppleIntelligenceService.TaskType = .textGeneration) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            currentTask?.cancel()
            currentTask = Task { @MainActor in
                do {
                    self.isStreaming = true
                    self.streamedText = ""
                    let response = try await self.sendPrompt(prompt, task: task)
                    for token in response.split(separator: " ") {
                        try Task.checkCancellation()
                        self.streamedText += (self.streamedText.isEmpty ? "" : " ") + token
                        continuation.yield(self.streamedText)
                        try await Task.sleep(nanoseconds: 35_000_000)
                    }
                    self.isStreaming = false
                    continuation.finish()
                } catch {
                    self.isStreaming = false
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func cancelRequest() {
        currentTask?.cancel()
        isStreaming = false
    }

    public func resetSession() {
        cancelRequest()
        activeSession = OnDeviceSession()
        streamedText = ""
    }
}
