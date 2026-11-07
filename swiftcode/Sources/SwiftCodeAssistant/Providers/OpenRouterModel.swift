import Foundation

public struct OpenRouterModel: Identifiable, Sendable, Codable {
    public let id: String
    public let name: String
    public let description: String
    public let contextLength: Int?
    public let pricing: Pricing?

    public struct Pricing: Sendable, Codable {
        public let prompt: String?
        public let completion: String?
    }

    public init(id: String, name: String, description: String, contextLength: Int? = 128000, pricing: Pricing? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.contextLength = contextLength
        self.pricing = pricing
    }
}
