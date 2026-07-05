import Foundation

@MainActor
final class OnDeviceAIManager: ObservableObject {
    static let shared = OnDeviceAIManager()

    @Published private(set) var activeSession = OnDeviceSession()
    @Published private(set) var streamedText = ""
    @Published private(set) var isStreaming = false

    private let service = AppleIntelligenceService()
    private var currentTask: Task<Void, Never>?

    private init() {}

    func sendPrompt(_ prompt: String, task: AppleIntelligenceService.TaskType = .textGeneration) async throws -> String {
        activeSession.history.append(AIMessage(role: "user", content: prompt))
        let response = try await service.process(prompt: prompt, task: task, session: activeSession)
        activeSession.history.append(AIMessage(role: "assistant", content: response))
        activeSession.lastUpdated = Date()
        return response
    }

    func streamResponse(for prompt: String, task: AppleIntelligenceService.TaskType = .textGeneration) -> AsyncThrowingStream<String, Error> {
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

    func cancelRequest() {
        currentTask?.cancel()
        isStreaming = false
    }

    func resetSession() {
        cancelRequest()
        activeSession = OnDeviceSession()
        streamedText = ""
    }
}
