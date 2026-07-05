import SwiftUI

struct DeploymentLogLine: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let isError: Bool
}

struct DeploymentLogsView: View {
    let logs: [DeploymentLogLine]
    @State private var analysis: String?
    @State private var isAnalyzing = false
    @State private var showAnalysis = false

    var body: some View {
        VStack(spacing: 12) {
            logContainer

            HStack {
                Button {
                    analyzeLogs()
                } label: {
                    HStack {
                        if isAnalyzing {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "brain.head.profile")
                        }
                        Text("Analyze Logs")
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(8)
                }
                .disabled(logs.isEmpty || isAnalyzing)

                Spacer()

                if analysis != nil {
                    Button {
                        showAnalysis = true
                    } label: {
                        Label("View Analysis", systemImage: "doc.text.magnifyingglass")
                            .font(.caption.bold())
                    }
                }
            }
        }
        .sheet(isPresented: $showAnalysis) {
            AnalysisResultView(analysis: analysis ?? "")
        }
    }

    private var logContainer: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logs) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(line.timestamp, style: .time)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)

                            Text(line.message)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(line.isError ? .red : .primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .id(line.id)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
            .onChange(of: logs.count) {
                if let last = logs.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func analyzeLogs() {
        isAnalyzing = true
        analysis = nil

        let logText = logs.map { "[\($0.timestamp.formatted())] \($0.isError ? "ERROR: " : "")\($0.message)" }.joined(separator: "\n")

        let prompt = """
        You are a deployment expert. Analyze the following deployment logs and explain what happened.
        If there's an error, explain WHY it failed and how to fix it.
        Format your response using Markdown.

        LOGS:
        \(logText)
        """

        Task {
            do {
                var fullResponse = ""
                try await LLMService.shared.streamChat(
                    messages: [AIMessage(role: "user", content: prompt)],
                    model: AppSettings.shared.selectedModel,
                    systemPrompt: "You are an AI assistant helping a developer debug deployment issues."
                ) { token in
                    await MainActor.run {
                        fullResponse += token
                    }
                }

                await MainActor.run {
                    self.analysis = fullResponse
                    self.isAnalyzing = false
                    self.showAnalysis = true
                }
            } catch {
                await MainActor.run {
                    self.analysis = "Failed to analyze logs: \(error.localizedDescription)"
                    self.isAnalyzing = false
                    self.showAnalysis = true
                }
            }
        }
    }
}

// MARK: - Analysis Result View

struct AnalysisResultView: View {
    let analysis: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(parseMarkdown(analysis))
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.07))
            .navigationTitle("AI Log Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func parseMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full))) ?? AttributedString(text)
    }
}

#Preview {
    DeploymentLogsView(logs: [
        DeploymentLogLine(timestamp: Date(), message: "Preparing Repository...", isError: false),
        DeploymentLogLine(timestamp: Date(), message: "Pushing Code To GitHub...", isError: false),
        DeploymentLogLine(timestamp: Date(), message: "Failed to push: Remote Rejected", isError: true)
    ])
    .frame(height: 300)
    .padding()
}
