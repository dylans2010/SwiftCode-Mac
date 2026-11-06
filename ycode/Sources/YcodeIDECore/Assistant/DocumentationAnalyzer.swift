import Foundation
import Observation

/// The four sections an AI documentation analysis returns.
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

/// Analyzes Apple Developer Documentation against the user's project
/// (ported from Legacy's `DocumentationAnalyzer`, honestly reworked).
///
/// Legacy's version had a fake at its core: `extractDocumentationContent`
/// returned a canned string ("Documentation for X. This API provides
/// methods...") instead of reading the page, and `requestAIAnalysis`
/// called `LLMService` with a hardcoded `gpt-4-turbo` model. This version
/// does the real thing:
/// - the page is fetched over the network and stripped to text (via
///   `ReleaseNotesFormatter.plainText`, the same HTML-to-text pass the
///   update notes use); a fetch failure is an error, not invented text.
/// - the project is scanned from an explicit workspace URL (Legacy read
///   `ProjectSessionStore.shared.activeProject`, which does not exist in
///   Ycode) — up to 50 Swift files, collecting their `import` lines.
/// - the analysis runs through an injected `AssistantProvider` with an
///   explicit model (the caller picks the provider the user selected in
///   Assist; no model is hardcoded here).
///
/// The caller is the Documentation Browser's AI Co-Pilot tab (Wave 19);
/// this file is the engine, not the view.
@Observable
@MainActor
public final class DocumentationAnalyzer {
    public var isAnalyzing = false
    public var results: AIInsightResults?
    public var error: String?

    private let provider: AssistantProvider
    private let model: String?

    /// - Parameters:
    ///   - provider: the assistant provider to run the analysis with
    ///     (e.g. `CodingAssistantServices.shared.provider(kind)`).
    ///   - model: the model id to request, or nil for the provider's default.
    public init(provider: AssistantProvider, model: String? = nil) {
        self.provider = provider
        self.model = model
    }

    public func analyze(url: URL, documentationContent: String? = nil, workspaceURL: URL? = nil) async {
        isAnalyzing = true
        error = nil
        results = nil

        do {
            // Step 1 & 2: Capture URL and extract relevant documentation content
            let documentationSummary: String
            if let documentationContent {
                documentationSummary = documentationContent
            } else {
                documentationSummary = try await extractDocumentationContent(from: url)
            }

            // Step 3: Scan the user's project codebase
            let projectContext = scanProjectContext(workspaceURL: workspaceURL)

            // Step 4: Send both to the selected assistant provider
            let analysis = try await requestAIAnalysis(docSummary: documentationSummary, projectContext: projectContext)

            self.results = analysis
        } catch {
            self.error = error.localizedDescription
        }

        isAnalyzing = false
    }

    /// Fetches the documentation page and strips it to readable text.
    /// Throws on network failure or an empty page — never invents content.
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

        // Use an enumerator to find Swift files and gather some context
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

    /// Splits a model reply into the four expected sections (Legacy's
    /// naive heading-based parser, unchanged in behaviour). Static so
    /// tests can cover it without a provider.
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
