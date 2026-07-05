import Foundation
import SwiftUI

struct AIInsightResults {
    let overview: String
    let integrationOpportunities: String
    let suggestedCode: String
    let potentialImprovements: String
}

@MainActor
final class DocumentationAnalyzer: ObservableObject {
    static let shared = DocumentationAnalyzer()
    private init() {}

    @Published var isAnalyzing = false
    @Published var results: AIInsightResults?
    @Published var error: String?

    func analyze(url: URL, documentationContent: String? = nil) async {
        isAnalyzing = true
        error = nil
        results = nil

        do {
            // Step 1 & 2: Capture URL and Extract relevant documentation content
            let documentationSummary: String
            if let documentationContent = documentationContent {
                documentationSummary = documentationContent
            } else {
                documentationSummary = try await extractDocumentationContent(from: url)
            }

            // Step 3: Scan the user’s project codebase
            let projectContext = try await scanProjectContext()

            // Step 4: Send both to LLMService
            let analysis = try await requestAIAnalysis(docSummary: documentationSummary, projectContext: projectContext)

            self.results = analysis
        } catch {
            self.error = error.localizedDescription
        }

        isAnalyzing = false
    }

    private func extractDocumentationContent(from url: URL) async throws -> String {
        // In a real app, this would scrape the page or use a documentation API.
        // For this implementation, we'll use the URL to infer the topic.
        let topic = url.lastPathComponent.capitalized
        return "Documentation for \(topic). This API provides methods and properties for building user interfaces and handling data in \(topic) framework."
    }

    private func scanProjectContext() async throws -> String {
        guard let project = ProjectManager.shared.activeProject else {
            return "No active project found."
        }

        let fm = FileManager.default
        let projectDir = project.directoryURL

        var context = "Project Name: \(project.name)\n"

        // Use an enumerator to find Swift files and gather some context
        if let enumerator = fm.enumerator(at: projectDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            var swiftFileCount = 0
            var imports = Set<String>()

            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "swift" {
                    swiftFileCount += 1
                    if let content = try? String(contentsOf: fileURL) {
                        let lines = content.components(separatedBy: .newlines)
                        for line in lines where line.hasPrefix("import ") {
                            imports.insert(line.trimmingCharacters(in: .whitespaces))
                        }
                    }
                }
                if swiftFileCount > 50 { break } // Limit scan
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

        let messages = [
            AIMessage(role: "user", content: userPrompt)
        ]

        let response = try await LLMService.shared.sendChatRequest(
            model: "gpt-4-turbo", // Defaulting to a high-quality model if available
            messages: messages,
            key: nil // Uses stored key
        )

        return parseAIResponse(response.completionText)
    }

    private func parseAIResponse(_ text: String) -> AIInsightResults {
        // Naive parsing based on expected sections
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
