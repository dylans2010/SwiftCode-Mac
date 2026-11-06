import Foundation
import SwiftData

public actor AIAnalysisManager {
    private let projectID: UUID

    public init(projectID: UUID) {
        self.projectID = projectID
    }

    public enum AnalysisKind: String, Sendable, CaseIterable {
        case dailySummary = "Daily Summary"
        case weeklySummary = "Weekly Summary"
        case missingDocs = "Missing Documentation"
        case duplicateDocs = "Duplicate Ideas Detection"
        case knowledgeGaps = "Knowledge Gaps Analysis"
    }

    public func analyze(kind: AnalysisKind, contextPayload: String) async throws -> String {
        let systemPrompt = "You are a senior documentation and code quality analyzer. Review the following project documents context and generate a professional, constructive \(kind.rawValue) report as a markdown document."

        let fullPrompt = """
        \(systemPrompt)

        === DOCUMENTS CONTEXT ===
        \(contextPayload)
        """

        do {
            let response = try await LLMService.shared.generateResponse(prompt: fullPrompt, useContext: true)
            return response
        } catch {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            return """
            # Analysis Report (\(timestamp))
            - **Status**: Live AI generation encountered an issue (\(error.localizedDescription)).
            - **Recommendation**: Ensure your LLM Provider and API Keys are set in Settings.
            """
        }
    }
}
