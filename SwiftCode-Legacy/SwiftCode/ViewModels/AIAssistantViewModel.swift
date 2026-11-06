import Foundation
import Observation

@Observable
@MainActor
public class AIAssistantViewModel {
    public var conversation = AIConversation()
    public var isSending = false
    public var currentStreamingMessage = ""

    public init() {}

    public func sendMessage(_ text: String, model: String) async {
        let userMsg = AIMessage(role: .user, content: text)
        conversation.messages.append(userMsg)
        isSending = true
        currentStreamingMessage = ""

        let assistantMsgPlaceholder = AIMessage(role: .assistant, content: "", modelUsed: model)
        conversation.messages.append(assistantMsgPlaceholder)
        let assistantIdx = conversation.messages.count - 1

        do {
            let request = AIAssistantRequest(model: model, messages: conversation.messages.dropLast())
            let stream = try await OpenRouterClient.shared.streamChatCompletion(request: request)

            for try await chunk in stream {
                currentStreamingMessage += chunk
                conversation.messages[assistantIdx].content = currentStreamingMessage
            }
        } catch {
            LoggingTool.error("AI error: \(error)")
            conversation.messages[assistantIdx].content = "Failed to generate response: \(error.localizedDescription)"
        }

        isSending = false
    }
}
