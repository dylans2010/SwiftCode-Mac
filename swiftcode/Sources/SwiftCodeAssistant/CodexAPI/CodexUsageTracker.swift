import Foundation
import Observation

/// Tracks Codex usage for the app-owned key's limits (ported from
/// Legacy's `CodexUsageTracker`).
///
/// When the API returns real token usage those numbers are used; otherwise
/// tokens are estimated at 4 characters per token (Legacy's estimate,
/// labelled as an estimate — it is a fallback, not a measurement). In
/// restricted (app-owned key) mode the running totals are capped at
/// 200,000 tokens, matching the manager's enforcement limit.
@Observable
@MainActor
public final class CodexUsageTracker {
    public static let shared = CodexUsageTracker()

    public private(set) var estimatedPromptTokens: Int = 0
    public private(set) var estimatedCompletionTokens: Int = 0
    public private(set) var requestCount: Int = 0
    public private(set) var sessionCount: Int = 0

    public init() {}

    public var estimatedTotalTokens: Int { estimatedPromptTokens + estimatedCompletionTokens }

    public func recordSessionReset() {
        sessionCount += 1
    }

    public func record(prompt: String, response: String, tokenUsage: CodexLLMResponse.TokenUsage?, mode: CodexUsageMode) {
        requestCount += 1
        if let tokenUsage {
            estimatedPromptTokens += tokenUsage.promptTokens
            estimatedCompletionTokens += tokenUsage.completionTokens
        } else {
            estimatedPromptTokens += estimateTokens(in: prompt)
            estimatedCompletionTokens += estimateTokens(in: response)
        }

        if mode == .restrictedAppControlled {
            estimatedPromptTokens = min(estimatedPromptTokens, 200_000)
            estimatedCompletionTokens = min(estimatedCompletionTokens, 200_000)
        }
    }

    public func resetCounts() {
        estimatedPromptTokens = 0
        estimatedCompletionTokens = 0
        requestCount = 0
    }

    private func estimateTokens(in text: String) -> Int {
        max(1, Int((Double(text.count) / 4.0).rounded(.up)))
    }
}
