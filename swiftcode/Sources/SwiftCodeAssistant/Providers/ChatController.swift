import Foundation

public enum MessageRole: String, Sendable, Codable {
    case user
    case assistant
}

@MainActor
public final class ChatController: ObservableObject {
    public static let shared = ChatController()

    @Published public var messages: [ChatMessage] = []
    @Published public var isGenerating = false

    private let unavailableModelMessage = "No AI model available. Add an API key or download an offline model."

    public init() {}

    public func sendMessage(_ text: String, useContext: Bool) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        appendMessage(role: .user, content: prompt)
        await generateAssistantReply(for: prompt, useContext: useContext)
    }

    public func sendAgentMessage(_ text: String, useContext: Bool) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        appendMessage(role: .user, content: prompt)
        await generateAssistantReply(for: prompt, useContext: useContext)
    }

    private func generateAssistantReply(for prompt: String, useContext: Bool) async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let response = try await CodexModelRouter().routePrompt(prompt, useContext: useContext)
            let normalizedResponse = LLMService.shared.sanitizeResponse(response, relativeTo: prompt)

            if normalizedResponse.isEmpty {
                appendMessage(role: .assistant, content: "I couldn't generate a meaningful response. Please try rephrasing your request.")
            } else {
                appendMessage(role: .assistant, content: normalizedResponse)
            }
        } catch let error as LLMError {
            switch error {
            case .missingOfflineDefaultModel, .offlineFallbackUnavailable:
                appendMessage(role: .assistant, content: unavailableModelMessage)
            default:
                appendMessage(role: .assistant, content: "Request failed: \(error.localizedDescription)")
            }
        } catch {
            appendMessage(role: .assistant, content: "Request failed: \(error.localizedDescription)")
        }
    }

    private func appendMessage(role: ChatRole, content: String) {
        messages.append(ChatMessage(role, content))
    }
}
