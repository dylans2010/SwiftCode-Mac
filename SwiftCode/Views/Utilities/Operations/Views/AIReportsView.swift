import SwiftUI

struct AIReportsView: View {
    @State private var ai = AIEngineeringReports.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Engineering Reports")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Generate AI-driven codebase recommendations, dead code warnings, and performance optimizations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        Task {
                            await ai.generateReport()
                        }
                    } label: {
                        Label(ai.isAnalyzing ? "Analyzing..." : "Generate AI Insights", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ai.isAnalyzing)
                }
                .padding(.bottom, 10)

                if ai.isAnalyzing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Analyzing workspace, codebase metrics, and structures...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 100)
                } else if ai.insights.isEmpty {
                    ContentUnavailableView {
                        Label("No AI Insights", systemImage: "sparkles")
                    } description: {
                        Text("Generate insights to scan for duplicate resources, unreferenced structs, large file refactors, and optimization targets.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(ai.insights) { insight in
                        GroupBox {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.title3)
                                    .foregroundStyle(colorForSeverity(insight.severity))
                                    .frame(width: 30, height: 30)
                                    .background(colorForSeverity(insight.severity).opacity(0.12))
                                    .cornerRadius(6)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(insight.title)
                                            .font(.headline)
                                        Spacer()
                                        Text(insight.type.uppercased())
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(insight.message)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    if let impacted = insight.linesOfCodeImpacted {
                                        Text("Impact: ~\(impacted) lines of code optimized")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .padding(6)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            if ai.lastAnalysisDate == nil {
                Task {
                    await ai.generateReport()
                }
            }
        }
    }

    private func colorForSeverity(_ severity: String) -> Color {
        switch severity {
        case "High": return .red
        case "Medium": return .orange
        default: return .blue
        }
    }
}
