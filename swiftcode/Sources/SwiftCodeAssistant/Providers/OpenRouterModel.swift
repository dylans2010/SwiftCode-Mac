import Foundation

// Ported verbatim from Legacy `SwiftCode/Core/AI/OpenRouterModel.swift` (22 lines),
// made public: `OpenRouterService.fetchModels()` returns `[OpenRouterModel]` and
// call sites live in SwiftCodeUI / swiftcode-ide, and
// `SettingsViewModel.availableModels` / `OpenRouterAssistProvider.fetchModels()`
// already reference the type. Decodes directly from the /models JSON
// (`id`, `name`, `description`; `contextLength`/`pricing` are optional and
// absent keys decode as nil).

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
