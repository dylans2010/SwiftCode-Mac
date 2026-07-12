import SwiftUI

struct SearchDocumentationView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var urlInput = ""
    @State private var summaryResponse = ""
    @State private var isSummarizing = false
    @State private var summaryTitle = "Documentation Summary"

    private var parsedBlocks: [MarkdownBlock] {
        MarkdownRenderer.shared.parse(summaryResponse)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top control bar
                VStack(alignment: .leading, spacing: 12) {
                    Text("Web Link & Documentation Summarizer")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Paste any GitHub repository link, generic documentation page, or developer guide below. The default AI model will analyze and summarize its contents with comprehensive markdown formatting, structural tables, and code snippets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)
                            TextField("Paste GitHub repository or documentation link here (e.g., https://github.com/...),", text: $urlInput)
                                .textFieldStyle(.plain)
                                .onSubmit {
                                    startSummarization()
                                }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                        Button(action: startSummarization) {
                            if isSummarizing {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .padding(.horizontal, 8)
                            } else {
                                Label("Summarize", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(isSummarizing || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    HStack {
                        Image(systemName: "cpu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Powered by selected model: \(settings.selectedModel.isEmpty ? "meta-llama/llama-3-70b-instruct" : settings.selectedModel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial)

                Divider()

                // Summarization Content Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if summaryResponse.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text("No Summary Generated Yet")
                                    .font(.title3.bold())
                                Text("Paste a link and click 'Summarize' above to receive a highly detailed summary including markdown lists, tables, and usage blocks.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 400)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                        } else {
                            // Render summarized content using MarkdownBlockListView
                            MarkdownBlockListView(blocks: parsedBlocks)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Footer toolbar
                if !summaryResponse.isEmpty {
                    HStack {
                        Button("Clear Summary") {
                            summaryResponse = ""
                            urlInput = ""
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button("Copy Summary Markdown") {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(summaryResponse, forType: .string)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }
            .navigationTitle("Link Summarizer")
        }
    }

    private func startSummarization() {
        let link = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }

        isSummarizing = true
        summaryResponse = ""

        let systemPrompt = """
        You are an advanced documentation analyst and software engineering assistant.
        The user has provided a link: \(link).
        Your goal is to write a highly descriptive, comprehensive summary of the provided web documentation or GitHub repository link.
        Your output MUST be structured using beautiful, clean Markdown. You must include:
        1. An H1 title for the resource.
        2. A concise introduction section.
        3. A detailed table outlining key highlights, components, APIs, or files, with descriptive columns.
        4. Structured headings (H2/H3) explaining major architectural concepts.
        5. Bulleted lists of advantages, use cases, or setup steps.
        6. A standard code block showing sample usage or installation commands.
        7. A blockquote summarizing the overall utility.
        Avoid returning conversational fluff or preambles before or after the markdown. Output ONLY the beautiful formatted markdown blocks.
        """

        let messages = [
            AIMessage(role: .user, content: "Please summarize the documentation or repository at link: \(link)")
        ]

        let model = settings.selectedModel.isEmpty ? "meta-llama/llama-3-70b-instruct" : settings.selectedModel

        Task {
            do {
                try await OpenRouterService.shared.streamChat(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt
                ) { token in
                    await MainActor.run {
                        summaryResponse += token
                    }
                }
                await MainActor.run {
                    isSummarizing = false
                }
            } catch {
                await MainActor.run {
                    summaryResponse = "# Summarization Failed\n\nCould not analyze the link. Error: \(error.localizedDescription)"
                    isSummarizing = false
                }
            }
        }
    }
}
