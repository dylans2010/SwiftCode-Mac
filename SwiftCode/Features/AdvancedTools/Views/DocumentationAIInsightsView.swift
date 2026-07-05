import SwiftUI

struct DocumentationAIInsightsView: View {
    @StateObject private var analyzer = DocumentationAnalyzer.shared
    @Environment(\.dismiss) private var dismiss

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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

            if isCode {
                Text(content)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(content)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
