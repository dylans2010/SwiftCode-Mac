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

    public static let defaults: [OpenRouterModel] = [
        OpenRouterModel(id: "openai/gpt-4o", name: "GPT-4o", description: "OpenAI's most capable model.", contextLength: 128000),
        OpenRouterModel(id: "anthropic/claude-3.5-sonnet", name: "Claude 3.5 Sonnet", description: "Anthropic's latest high-performance model.", contextLength: 200000),
        OpenRouterModel(id: "meta-llama/llama-3.1-405b-instruct", name: "Llama 3.1 405B", description: "Meta's flagship open model.", contextLength: 128000),
        OpenRouterModel(id: "google/gemma-2-9b-it:free", name: "Gemma 2 9B IT (Free)", description: "Google's lightweight, state-of-the-art model.", contextLength: 8192),
        OpenRouterModel(id: "meta-llama/llama-3-8b-instruct:free", name: "Llama 3 8B Instruct (Free)", description: "Meta's highly capable 8B model.", contextLength: 8192),
        OpenRouterModel(id: "mistralai/mistral-7b-instruct:free", name: "Mistral 7B Instruct (Free)", description: "Mistral's high-performance 7B model.", contextLength: 32000),
        OpenRouterModel(id: "qwen/qwen-2-7b-instruct:free", name: "Qwen 2 7B Instruct (Free)", description: "Alibaba's powerful Qwen 2 model.", contextLength: 32000)
    ]
}
