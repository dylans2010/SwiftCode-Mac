// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Features/AdvancedTools/Views/DocumentationAIInsightsView.swift
//
// Adapted for SwiftCode: production's `DocumentationAnalyzer`
// (`SwiftCodeIDECore/Assistant/DocumentationAnalyzer.swift`) has
// no `.shared` — it is built with an injected `AssistantProvider`
// and model, and it is `@Observable`, not `ObservableObject`.
// The analyzer is therefore injected (W1 wires the presenter;
// see DISPOSITIONS.md) instead of `DocumentationAnalyzer.shared`.
// `AIInsightResults`, `MarkdownBlockListView`, `MarkdownParser`
// and `.liquidGlass` all already exist in the destination.

import SwiftCodeIDECore
import SwiftUI

public struct DocumentationAIInsightsView: View {
    /// Injected: production's `DocumentationAnalyzer` has no `.shared`.
    public let analyzer: DocumentationAnalyzer
    @Environment(\.dismiss) private var dismiss

    public init(analyzer: DocumentationAnalyzer) {
        self.analyzer = analyzer
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if analyzer.isAnalyzing {
                        loadingState
                    } else if let error = analyzer.error {
                        errorState(error)
                    } else if let results = analyzer.results {
                        insightsContent(results)
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 50)
            ProgressView()
                .scaleEffect(1.5)
            Text("Analyzing Documentation...")
                .font(.headline)
            Text("Comparing APIs with your project context to find integration opportunities.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.red)
            Text("Analysis Failed")
                .font(.title3.bold())
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                // Retry logic if needed, currently analyzer holds state
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 50)
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("No Insights Yet")
                .font(.title3.bold())
            Text("Tap the 'AI Insights' button in the Documentation Browser to start the analysis.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 50)
        .frame(maxWidth: .infinity)
    }

    private func insightsContent(_ results: AIInsightResults) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            insightSection(title: "Overview", icon: "info.circle", content: results.overview)
            insightSection(title: "Integration Opportunities", icon: "lightbulb", content: results.integrationOpportunities)
            insightSection(title: "Suggested Code Implementation", icon: "curlybraces", content: results.suggestedCode, isCode: true)
            insightSection(title: "Potential Improvements", icon: "arrow.up.circle", content: results.potentialImprovements)
        }
    }

    private func insightSection(title: String, icon: String, content: String, isCode: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .liquidGlass(style: .subtle, cornerRadius: 8)

            if isCode {
                Text(content)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                MarkdownBlockListView(blocks: MarkdownParser.shared.parse(content))
            }
        }
    }
}
