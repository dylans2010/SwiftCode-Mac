import Foundation

public struct AssistModelOption: Identifiable, Sendable, Codable {
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

public enum AssistCapabilityKind: String, Codable {
    case `extension` = "extension"
    case skill = "skill"
    case tool = "tool"
}

public struct AssistCapability {
    public static let toolIdentifier = "com.swiftcode.assist.capability"

    public static func identifiers(enabled: Bool) -> [String] {
        enabled ? [toolIdentifier] : []
    }
}

public struct AssistCapabilityExecutor {
    @MainActor
    public static func executeIfNeeded(kind: AssistCapabilityKind, name: String, identifiers: [String], payload: [String: String]) {
        guard identifiers.contains(AssistCapability.toolIdentifier) else { return }
        print("[AssistCapabilityExecutor] Executing \(kind.rawValue) '\(name)' with payload: \(payload)")
    }
}
