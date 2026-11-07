import SwiftUI
import Foundation

@MainActor
final class AISuggestionEngine: ObservableObject {
    static let shared = AISuggestionEngine()

    @Published var ghostText: String = ""
    @Published var isLoading: Bool = false

    private var pendingTask: Task<Void, Never>?
    private let debounceNanos: UInt64 = 600_000_000

    private init() {}

    func requestCompletion(
        prefix: String,
        suffix: String,
        fileName: String,
        model: String? = nil
    ) {
        pendingTask?.cancel()
        ghostText = ""

        guard !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pendingTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }

            isLoading = true
            defer { isLoading = false }

            let resolvedModel = model ?? AppSettings.shared.selectedModel
            let contextLines = prefix.components(separatedBy: "\n").suffix(30).joined(separator: "\n")
            let prompt = buildPrompt(prefix: contextLines, suffix: suffix, fileName: fileName)

            do {
                let response = try await LLMService.shared.sendChatRequest(
                    model: resolvedModel,
                    messages: [AIMessage(role: .system, content: completionSystemPrompt), AIMessage(role: .user, content: prompt)]
                )
                let result = response.completionText
                guard !Task.isCancelled else { return }
                ghostText = cleanCompletion(result, prefix: prefix)
            } catch {
                ghostText = ""
            }
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        ghostText = ""
        isLoading = false
    }

    func acceptSuggestion() -> String {
        let accepted = ghostText
        ghostText = ""
        return accepted
    }

    private func buildPrompt(prefix: String, suffix: String, fileName: String) -> String {
        """
        Complete the following Swift code in \(fileName). \
        Return ONLY the completion text (no explanation, no markdown fences). \
        Keep it short (1–5 lines max).

        <prefix>
        \(prefix)
        </prefix>
        <suffix>
        \(suffix.prefix(200))
        </suffix>
        """
    }

    private var completionSystemPrompt: String {
        """
        You are an expert Swift code completion engine. \
        Given a code prefix and suffix, return only the missing code that fits naturally between them. \
        Do not include any explanation, markdown, or code fences. \
        Output only raw Swift code.
        """
    }

    private func cleanCompletion(_ raw: String, prefix: String) -> String {
        var result = raw
            .replacingOccurrences(of: "```swift", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .newlines)

        if let lastLine = prefix.components(separatedBy: "\n").last?.trimmingCharacters(in: .whitespaces),
           !lastLine.isEmpty,
           result.hasPrefix(lastLine) {
            result = String(result.dropFirst(lastLine.count))
                .trimmingCharacters(in: .newlines)
        }

        return result
    }
}
