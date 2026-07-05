import Foundation
import NaturalLanguage

final class AppleIntelligenceService {
    enum TaskType: String, Codable, CaseIterable {
        case textGeneration
        case summarization
        case rewriting
        case codeAssist
    }

    func process(prompt: String, task: TaskType, session: OnDeviceSession) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        switch task {
        case .summarization:
            return summarize(trimmed)
        case .rewriting:
            return rewrite(trimmed)
        case .codeAssist:
            return codeAssist(trimmed, history: session.history)
        case .textGeneration:
            return generate(trimmed, history: session.history)
        }
    }

    private func summarize(_ text: String) -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return sentences.prefix(3).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    private func rewrite(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return text.split(separator: "\n").map { "• " + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }

    private func codeAssist(_ text: String, history: [AIMessage]) -> String {
        let context = history.suffix(4).map(\.content).joined(separator: "\n")
        return "Suggested implementation plan:\n1. Inspect relevant files and dependencies.\n2. Apply the requested code changes with permission-safe file edits.\n3. Validate with targeted build/test commands.\n\nContext:\n\(context)\n\nPrompt:\n\(text)"
    }

    private func generate(_ text: String, history: [AIMessage]) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage?.rawValue ?? "und"
        let context = history.suffix(2).map(\.content).joined(separator: "\n")
        return "On-device response (\(language)):\n\(text)\n\nRecent context:\n\(context)"
    }
}
