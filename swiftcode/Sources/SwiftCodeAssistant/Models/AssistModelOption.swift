// STAGED PORT — SwiftCode-Legacy `SwiftCode/Models/AssistModelOption.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeAssistant (`swiftcode/Sources/SwiftCodeAssistant/Models/AssistModelOption.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Static curated model catalogue (swiftCodeBalanced/gpt4o/claude35Sonnet/geminiFlash/deepseekChat/direct-*)
//   - 'swiftcode-balanced' alias in resolve() (mapped to anthropic/claude-3.5-sonnet)
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES: none found by static scan (SwiftUI/Foundation/Apple-framework names excluded).
// WIRING / REGISTRATION: None (library type) — consumed by Assist session/agent code and, for tool-adjacent types, by SwiftCodeMCP.

import Foundation

public struct AssistModelOption: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let displayName: String
    public let provider: String

    public static let swiftCodeBalanced = AssistModelOption(
        id: "anthropic/claude-3.5-sonnet",
        displayName: "SwiftCode Balanced (Claude 3.5 Sonnet)",
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

    public static let gpt4oMini = AssistModelOption(
        id: "openai/gpt-4o-mini",
        displayName: "GPT-4o Mini",
        provider: "OpenRouter"
    )

    public static let claude35Haiku = AssistModelOption(
        id: "anthropic/claude-3.5-haiku",
        displayName: "Claude 3.5 Haiku",
        provider: "OpenRouter"
    )

    public static let geminiFlash = AssistModelOption(
        id: "google/gemini-2.0-flash-001",
        displayName: "Gemini 2.0 Flash",
        provider: "OpenRouter"
    )

    public static let deepseekChat = AssistModelOption(
        id: "deepseek/deepseek-chat",
        displayName: "DeepSeek V3",
        provider: "OpenRouter"
    )

    public static let appleFoundation = AssistModelOption(
        id: "AFM 3 Core",
        displayName: "Apple Foundation Models (On-Device)",
        provider: "Apple"
    )

    public static let directOpenAI4o = AssistModelOption(
        id: "gpt-4o",
        displayName: "GPT-4o (Direct OpenAI)",
        provider: "OpenAI"
    )

    public static let directClaude35Sonnet = AssistModelOption(
        id: "claude-3-5-sonnet-20241022",
        displayName: "Claude 3.5 Sonnet (Direct Anthropic)",
        provider: "Anthropic"
    )

    public static let directGeminiFlash = AssistModelOption(
        id: "gemini-2.0-flash",
        displayName: "Gemini 2.0 Flash (Direct Google)",
        provider: "Google"
    )

    public static let all: [AssistModelOption] = [
        .swiftCodeBalanced,
        .gpt4o,
        .claude35Sonnet,
        .gpt4oMini,
        .claude35Haiku,
        .geminiFlash,
        .deepseekChat,
        .appleFoundation,
        .directOpenAI4o,
        .directClaude35Sonnet,
        .directGeminiFlash
    ]

    public static func resolve(id: String) -> String {
        if id == "swiftcode-balanced" {
            return "anthropic/claude-3.5-sonnet"
        }
        return id
    }
}
