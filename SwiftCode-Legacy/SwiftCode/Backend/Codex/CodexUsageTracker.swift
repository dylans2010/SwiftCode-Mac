import Foundation
import SwiftUI

@MainActor
final class CodexUsageTracker: ObservableObject {
    static let shared = CodexUsageTracker()

    @Published private(set) var estimatedPromptTokens: Int = 0
    @Published private(set) var estimatedCompletionTokens: Int = 0
    @Published private(set) var requestCount: Int = 0
    @Published private(set) var sessionCount: Int = 0

    private init() {}

    var estimatedTotalTokens: Int { estimatedPromptTokens + estimatedCompletionTokens }

    func recordSessionReset() {
        sessionCount += 1
    }

    func record(prompt: String, response: String, tokenUsage: LLMResponse.TokenUsage?, mode: CodexUsageMode) {
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

    private func estimateTokens(in text: String) -> Int {
        max(1, Int((Double(text.count) / 4.0).rounded(.up)))
    }
}
