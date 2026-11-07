import Foundation

public struct SDKCloudModelHistoryEntry: Codable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct SDKCloudModelCompletionRequest: Codable, Sendable {
    public let prompt: String
    public let history: [SDKCloudModelHistoryEntry]
    public let systemPrompt: String?
    public let modelIdentifier: String?

    public init(
        prompt: String,
        history: [SDKCloudModelHistoryEntry] = [],
        systemPrompt: String? = nil,
        modelIdentifier: String? = nil
    ) {
        self.prompt = prompt
        self.history = history
        self.systemPrompt = systemPrompt
        self.modelIdentifier = modelIdentifier
    }
}
