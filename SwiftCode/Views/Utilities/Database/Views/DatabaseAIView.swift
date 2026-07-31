import SwiftUI

struct DatabaseAIView: View {
    @State private var prompt = "Create a database architecture for a messaging app."
    @State private var response = ""
    @State private var isGenerating = false
    @State private var copiedText = false

    var body: some View {
        HStack(spacing: 0) {
            // Prompts sidebar
            VStack(alignment: .leading, spacing: 12) {
                Text("Suggested Prompts")
                    .font(.headline)

                Group {
                    PromptSuggestionButton(title: "User Authentication Schema", text: "Create user authentication database with secure tokens and session tracking.") { prompt = $0 }
                    PromptSuggestionButton(title: "E-Commerce System", text: "Design a relational e-commerce schema with orders, products, order items, and customers.") { prompt = $0 }
                    PromptSuggestionButton(title: "Normalization Suggestions", text: "Suggest normal forms and best-practice normalization schemas for blogging platforms.") { prompt = $0 }
                    PromptSuggestionButton(title: "Generate SwiftData Models", text: "Generate complete production-ready SwiftData models matching user tables.") { prompt = $0 }
                }

                Spacer()
            }
            .frame(width: 220)
            .padding()
            .background(Color.secondary.opacity(0.04))

            Divider()

            // Interaction terminal
            VStack(spacing: 0) {
                ScrollView {
                    if isGenerating {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Senior Database Architect is thinking...")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    } else if !response.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Architect Output")
                                    .font(.headline)
                                Spacer()
                                Button(action: copyToClipboard) {
                                    Label(copiedText ? "Copied" : "Copy Output", systemImage: copiedText ? "checkmark" : "doc.on.doc")
                                }
                            }

                            ScrollView {
                                Text(response)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.purple.opacity(0.06))
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                    } else {
                        ContentUnavailableView("Ask AI Co-Pilot", systemImage: "sparkles", description: Text("Let senior AI co-pilot model complete database architectures, normalization schemes, indexing, and model files."))
                    }
                }

                Divider()

                // Prompt input bar
                HStack {
                    TextField("Ask AI co-pilot anything about databases...", text: $prompt)
                        .textFieldStyle(.roundedBorder)

                    Button("Generate") {
                        generateArchitecture()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(prompt.isEmpty || isGenerating)
                }
                .padding()
            }
        }
    }

    private func generateArchitecture() {
        isGenerating = true
        response = ""
        copiedText = false

        Task {
            do {
                response = try await DatabaseAIService.shared.generateDatabaseArchitecture(prompt: prompt)
            } catch {
                response = "Failed: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(response, forType: .string)
        copiedText = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedText = false
        }
    }
}

struct PromptSuggestionButton: View {
    let title: String
    let text: String
    let action: (String) -> Void

    var body: some View {
        Button(action: { action(text) }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.bold())
                Text(text)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
