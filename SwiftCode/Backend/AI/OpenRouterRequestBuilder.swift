import Foundation

public struct OpenRouterRequestBuilder: Sendable {
    public static let shared = OpenRouterRequestBuilder()

    public func build(model: String, messages: [AIMessage]) -> AIAssistantRequest {
        return AIAssistantRequest(model: model, messages: messages)
    }
}
