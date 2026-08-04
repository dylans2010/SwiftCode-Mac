import SwiftUI

struct AIReportsView: View {
    @State private var ai = AIEngineeringReports.shared
    @State private var assistant = AIEngineeringAssistant.shared
    @State private var selectedSubTab: String = "Interactive Assistant"
    @State private var userQuestion: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header and Segmentation Tab
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Engineering Assistant")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Evaluate codebase metrics, analyze dependency graphs, and resolve diagnostics using AI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Picker("", selection: $selectedSubTab) {
                    Text("Interactive Assistant").tag("Interactive Assistant")
                    Text("Static Engineering Scan").tag("Static Engineering Scan")
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(16)

            Divider()

            if selectedSubTab == "Interactive Assistant" {
                interactiveAssistantView()
            } else {
                staticScanReportsView()
            }
        }
    }

    @ViewBuilder
    private func interactiveAssistantView() -> some View {
        VStack(spacing: 0) {
            // Conversational Scroll
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(assistant.conversation) { msg in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: msg.isUser ? "person.circle.fill" : "sparkles")
                                    .font(.title3)
                                    .foregroundStyle(msg.isUser ? .blue : .purple)
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(msg.isUser ? "You" : "SwiftCode Assistant")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)

                                    Text(msg.text)
                                        .font(.subheadline)
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .background(msg.isUser ? Color.blue.opacity(0.12) : Color.primary.opacity(0.04))
                                        .cornerRadius(8)
                                }
                                Spacer()
                            }
                            .id(msg.id)
                        }

                        if assistant.isAnalyzing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Analyzing project workspace files...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 34)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: assistant.conversation.count) { _, _ in
                    if let last = assistant.conversation.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Recommended questions list
            VStack(alignment: .leading, spacing: 6) {
                Text("Recommended Questions:")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Why are builds slower?") {
                        assistant.askQuestion("Why are builds slower?")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Find duplicate code.") {
                        assistant.askQuestion("Find duplicate code.")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Optimize storage.") {
                        assistant.askQuestion("Optimize storage.")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Explain diagnostics.") {
                        assistant.askQuestion("Explain diagnostics.")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Question Input field
            HStack(spacing: 12) {
                TextField("Ask about packages, duplicates, slow builds, diagnostics...", text: $userQuestion, onCommit: sendQuestion)
                    .textFieldStyle(.plain)
                    .font(.subheadline)

                Button {
                    sendQuestion()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(userQuestion.isEmpty || assistant.isAnalyzing)
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func staticScanReportsView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Static AI Engineering Reports")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task {
                            await ai.generateReport()
                        }
                    } label: {
                        Label(ai.isAnalyzing ? "Analyzing..." : "Regenerate Reports", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ai.isAnalyzing)
                }

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
            .padding(20)
        }
        .onAppear {
            if ai.lastAnalysisDate == nil {
                Task {
                    await ai.generateReport()
                }
            }
        }
    }

    private func sendQuestion() {
        let q = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        assistant.askQuestion(q)
        userQuestion = ""
    }

    private func colorForSeverity(_ severity: String) -> Color {
        switch severity {
        case "High": return .red
        case "Medium": return .orange
        default: return .blue
        }
    }
}
