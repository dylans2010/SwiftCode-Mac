import Foundation

public struct CodeSuggestion: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let filePath: String?
}

public enum CodeSuggestionCategory: String, CaseIterable {
    case improvements = "Improvements"
    case featureIdeas = "Feature Ideas"
    case cleanupSuggestions = "Cleanup Suggestions"
    case architectureAdvice = "Architecture Advice"
}

extension Notification.Name {
    public static let codeSuggestionsReady = Notification.Name("codeSuggestionsReady")
}

@MainActor
public final class CodeSuggestionsML: ObservableObject {
    public static let shared = CodeSuggestionsML()

    @Published public var groupedSuggestions: [CodeSuggestionCategory: [CodeSuggestion]] = [:]
    @Published public var isAnalyzing = false

    public init() {}

    public func analyze(directory: URL) {
        guard !isAnalyzing else { return }
        isAnalyzing = true

        Task.detached(priority: .utility) {
            let report = await self.generateSuggestions(for: directory)
            await MainActor.run {
                self.groupedSuggestions = report
                self.isAnalyzing = false
                NotificationCenter.default.post(name: .codeSuggestionsReady, object: directory)
            }
        }
    }

    private func generateSuggestions(for directory: URL) async -> [CodeSuggestionCategory: [CodeSuggestion]] {

        var imports: [String: Int] = [:]
        var totalFunctions = 0
        var todoFiles: [String] = []
        var longFiles: [String] = []
        var repeatedLines: [String: Int] = [:]

        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return [:]
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let content = try? String(contentsOf: fileURL) else { continue }
            let lines = content.components(separatedBy: .newlines)

            if lines.count > 350 { longFiles.append(fileURL.lastPathComponent) }
            if content.localizedCaseInsensitiveContains("TODO") { todoFiles.append(fileURL.lastPathComponent) }

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("import ") {
                    imports[trimmed, default: 0] += 1
                }
                if trimmed.contains("func ") {
                    totalFunctions += 1
                }
                if trimmed.count > 24 {
                    repeatedLines[trimmed, default: 0] += 1
                }
            }
        }

        var result: [CodeSuggestionCategory: [CodeSuggestion]] = [:]

        if totalFunctions > 80 {
            result[.improvements, default: []].append(.init(
                title: "Consider module split",
                detail: "Detected \(totalFunctions) functions. Splitting large files into focused feature modules may improve maintainability.",
                filePath: nil
            ))
        }

        if let heavyImport = imports.max(by: { $0.value < $1.value }) {
            result[.architectureAdvice, default: []].append(.init(
                title: "Review dependency usage",
                detail: "\(heavyImport.key) appears in \(heavyImport.value) files. Consider wrapping shared behavior behind lightweight adapters.",
                filePath: nil
            ))
        }

        for file in longFiles.prefix(3) {
            result[.cleanupSuggestions, default: []].append(.init(
                title: "Large file detected",
                detail: "This file appears long and may benefit from extraction into smaller components.",
                filePath: file
            ))
        }

        for file in todoFiles.prefix(3) {
            result[.featureIdeas, default: []].append(.init(
                title: "Promote TODO to tracked task",
                detail: "Convert TODO comments into backlog items to keep roadmap visibility high.",
                filePath: file
            ))
        }

        if let repetition = repeatedLines.first(where: { $0.value >= 5 }) {
            result[.improvements, default: []].append(.init(
                title: "Repeated pattern found",
                detail: "A repeated code pattern appears \(repetition.value)x. Consider extracting helper utilities or view modifiers.",
                filePath: nil
            ))
        }

        if result.isEmpty {
            result[.architectureAdvice] = [
                .init(
                    title: "Codebase looks healthy",
                    detail: "No obvious inefficiencies were detected. Continue with periodic analysis as the project grows.",
                    filePath: nil
                )
            ]
        }

        return result
    }
}
