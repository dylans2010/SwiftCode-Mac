import Foundation

public struct OpenRouterRequestBuilder: Sendable {
    public static let shared = OpenRouterRequestBuilder()

    public func build(model: String, messages: [AIMessage]) -> AIAssistantRequest {
        return AIAssistantRequest(model: model, messages: messages)
    }

    public func buildAgentRequest(model: String, messages: [AgentMessage], tools: [[String: any Sendable]]?) -> [String: any Sendable] {
        var body: [String: any Sendable] = [
            "model": model,
            "messages": messages.map { encodeMessage($0) },
            "stream": true
        ]
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools
        }
        return body
    }

    private func encodeMessage(_ message: AgentMessage) -> [String: any Sendable] {
        var dict: [String: any Sendable] = ["role": message.role.rawValue]

        let contents: [[String: any Sendable]] = message.content.compactMap { content in
            switch content {
            case .text(let text):
                return ["type": "text", "text": text]
            case .image(let data, let mimeType):
                let base64 = data.base64EncodedString()
                return [
                    "type": "image_url",
                    "image_url": ["url": "data:\(mimeType);base64,\(base64)"]
                ]
            case .toolCall(let _):
                return nil
            case .toolResult(let _):
                return nil
            case .pendingQuestion, .pendingQuestionSet, .checklistUpdate:
                return nil
            }
        }

        if !contents.isEmpty {
            dict["content"] = contents
        }

        for content in message.content {
            if case .toolCall(let call) = content {
                var toolCalls = dict["tool_calls"] as? [[String: any Sendable]] ?? []
                toolCalls.append([
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": call.arguments
                    ]
                ])
                dict["tool_calls"] = toolCalls
            } else if case .toolResult(let result) = content {
                dict["role"] = "tool"
                dict["tool_call_id"] = result.toolCallId
                dict["content"] = result.content
            }
        }

        return dict
    }
}
