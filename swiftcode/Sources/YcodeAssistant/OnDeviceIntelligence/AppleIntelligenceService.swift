import Foundation

public final class AppleIntelligenceService: Sendable {
    public enum TaskType: String, Sendable, Codable, CaseIterable {
        case textGeneration
        case summarization
        case rewriting
        case codeAssist
    }

    private let provider = FoundationModelsProvider()

    public init() {}

    public func process(prompt: String, task: TaskType, session: OnDeviceSession) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var messages: [ChatMessage] = session.history.map { message in
            switch message.role {
            case .user: ChatMessage(.user, message.content)
            case .assistant: ChatMessage(.assistant, message.content)
            case .system: ChatMessage(.system, message.content)
            }
        }
        messages.append(ChatMessage(.user, trimmed))
        let request = ChatRequest(
            model: FoundationModelsProvider.modelID,
            instructions: Self.instructions(for: task),
            messages: messages
        )
        var response = ""
        for try await event in provider.send(request) {
            if case let .text(text) = event {
                response += text
            }
        }
        return response
    }

    private static func instructions(for task: TaskType) -> String {
        switch task {
        case .textGeneration:
            return ""
        case .summarization:
            return "Summarize the following text concisely, keeping only the key points."
        case .rewriting:
            return "Rewrite the following text more clearly, preserving its meaning."
        case .codeAssist:
            return "You are a coding assistant. Inspect the relevant files and dependencies the user describes, propose the requested code changes, and say how to validate them with targeted build or test commands."
        }
    }
}
