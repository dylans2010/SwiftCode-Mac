import Foundation

public struct AssistModelOption: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let displayName: String
    public let provider: String

    public static let swiftCodeBalanced = AssistModelOption(
        id: "swiftcode-balanced",
        displayName: "SwiftCode Balanced",
        provider: "OpenRouter"
    )

    public static let gpt4o = AssistModelOption(
        id: "openai/gpt-4o",
        displayName: "GPT-4o",
        provider: "OpenRouter"
    )

    public static let claude35Sonnet = AssistModelOption(
        id: "anthropic/claude-3.5-sonnet",
        displayName: "Claude 3.5 Sonnet",
        provider: "OpenRouter"
    )

    public static let all: [AssistModelOption] = [
        .swiftCodeBalanced,
        .gpt4o,
        .claude35Sonnet
    ]
}
