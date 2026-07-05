import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date
}

enum MessageRole {
    case user
    case assistant
}

@MainActor
final class ChatController: ObservableObject {
    static let shared = ChatController()

    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false

    private let genericErrorMessage = "Something went wrong while generating the response."
    private let unavailableModelMessage = "No AI model available. Add an API key or download an offline model."

    func sendMessage(_ text: String, useContext: Bool) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        appendMessage(role: .user, content: prompt)
        await generateAssistantReply(for: prompt, useContext: useContext)
    }

    func sendAgentMessage(_ text: String, useContext: Bool) async {
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
                appendMessage(role: .assistant, content: genericErrorMessage)
            }
        } catch {
            appendMessage(role: .assistant, content: genericErrorMessage)
        }
    }

    private func appendMessage(role: MessageRole, content: String) {
        messages.append(
            ChatMessage(
                role: role,
                content: content,
                timestamp: Date()
            )
        )
    }
}
