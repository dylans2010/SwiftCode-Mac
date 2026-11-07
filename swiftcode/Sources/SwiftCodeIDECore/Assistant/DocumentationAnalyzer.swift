import Foundation
import Observation
import SwiftCodeAssistant

public struct AIInsightResults: Sendable, Equatable {
    public let overview: String
    public let integrationOpportunities: String
    public let suggestedCode: String
    public let potentialImprovements: String

    public init(overview: String, integrationOpportunities: String, suggestedCode: String, potentialImprovements: String) {
        self.overview = overview
        self.integrationOpportunities = integrationOpportunities
        self.suggestedCode = suggestedCode
        self.potentialImprovements = potentialImprovements
    }
}

@Observable
@MainActor
public final class DocumentationAnalyzer {
    public var isAnalyzing = false
    public var results: AIInsightResults?
    public var error: String?

    private let provider: AssistantProvider
    private let model: String?

    public init(provider: AssistantProvider, model: String? = nil) {
        self.provider = provider
        self.model = model
    }

    public func analyze(url: URL, documentationContent: String? = nil, workspaceURL: URL? = nil) async {
        isAnalyzing = true
        error = nil
        results = nil

        do {
            let documentationSummary: String
            if let documentationContent {
                documentationSummary = documentationContent
            } else {
                documentationSummary = try await extractDocumentationContent(from: url)
            }

            let projectContext = scanProjectContext(workspaceURL: workspaceURL)

            let analysis = try await requestAIAnalysis(docSummary: documentationSummary, projectContext: projectContext)

            self.results = analysis
        } catch {
            self.error = error.localizedDescription
        }

        isAnalyzing = false
    }

    private func extractDocumentationContent(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DocumentationAnalyzerError.fetchFailed("HTTP \(http.statusCode) fetching \(url.absoluteString)")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw DocumentationAnalyzerError.fetchFailed("Documentation page at \(url.absoluteString) is not readable text.")
        }
        let text = ReleaseNotesFormatter.plainText(from: html)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentationAnalyzerError.fetchFailed("Documentation page at \(url.absoluteString) has no readable text.")
        }
        return text
    }

    private func scanProjectContext(workspaceURL: URL?) -> String {
        guard let projectDir = workspaceURL else {
            return "No active project found."
        }

        let fm = FileManager.default
        var context = "Project Name: \(projectDir.lastPathComponent)\n"

        if let enumerator = fm.enumerator(at: projectDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            var swiftFileCount = 0
            var imports = Set<String>()

            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "swift" {
                    swiftFileCount += 1
                    if let content = try? String(contentsOf: fileURL) {
                        let lines = content.components(separatedBy: .newlines)
                        for line in lines where line.hasPrefix("import ") {
                            imports.insert(line.trimmingCharacters(in: .whitespaces))
                        }
                    }
                }
                if swiftFileCount > 50 { break }
            }

            context += "Total Swift files: \(swiftFileCount)\n"
            context += "Frameworks used: \(imports.joined(separator: ", "))\n"
        }

        return context
    }

    private func requestAIAnalysis(docSummary: String, projectContext: String) async throws -> AIInsightResults {
        let systemPrompt = """
        You are an AI Documentation Analyst. Your task is to analyze Apple Developer Documentation and suggest how it can be integrated into the user's current project.
        Provide your response in exactly four sections: Overview, Integration Opportunities, Suggested Code Implementation, and Potential Improvements.
        Use Markdown formatting.
        """

        let userPrompt = """
        Documentation Summary:
        \(docSummary)

        Project Context:
        \(projectContext)

        Analyze how the documented API could integrate into the user's codebase.
        """

        let request = ChatRequest(
            model: model,
            instructions: systemPrompt,
            messages: [ChatMessage(.user, userPrompt)]
        )

        var text = ""
        for try await event in provider.send(request) {
            if case .text(let chunk) = event {
                text += chunk
            }
        }
        return Self.parseAIResponse(text)
    }

    static func parseAIResponse(_ text: String) -> AIInsightResults {
        let sections = ["Overview", "Integration Opportunities", "Suggested Code Implementation", "Potential Improvements"]
        var results: [String: String] = [:]

        var currentSection = ""
        var currentContent = ""

        for line in text.components(separatedBy: .newlines) {
            var foundSection = false
            for section in sections {
                if line.lowercased().contains(section.lowercased()) && (line.hasPrefix("#") || line.hasPrefix("**")) {
                    if !currentSection.isEmpty {
                        results[currentSection] = currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    currentSection = section
                    currentContent = ""
                    foundSection = true
                    break
                }
            }
            if !foundSection {
                currentContent += line + "\n"
            }
        }

        if !currentSection.isEmpty {
            results[currentSection] = currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return AIInsightResults(
            overview: results["Overview"] ?? "No overview provided.",
            integrationOpportunities: results["Integration Opportunities"] ?? "No integration opportunities identified.",
            suggestedCode: results["Suggested Code Implementation"] ?? "No code snippets suggested.",
            potentialImprovements: results["Potential Improvements"] ?? "No improvements suggested."
        )
    }
}

public enum DocumentationAnalyzerError: LocalizedError {
    case fetchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fetchFailed(let message):
            return message
        }
    }
}
