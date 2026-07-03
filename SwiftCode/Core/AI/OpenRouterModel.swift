import Foundation

public struct OpenRouterModel: Identifiable, Sendable, Codable {
    public let id: String
    public let name: String
    public let contextLength: Int
    public let pricing: Pricing

    public struct Pricing: Sendable, Codable {
        public let prompt: String
        public let completion: String
    }
}
