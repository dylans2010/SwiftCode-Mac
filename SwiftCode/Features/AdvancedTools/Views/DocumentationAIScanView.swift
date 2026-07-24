import SwiftUI

struct LocalChatMsg: Identifiable, Sendable, Hashable {
    let id = UUID()
    let isUser: Bool
    let content: String
    let timestamp = Date()
}

@MainActor
struct DocumentationAIScanView: View {
    let documentTitle: String
    let scannedContent: String

    @State private var chatHistory: [LocalChatMsg] = []
    @State private var questionText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    @State private var isScanning = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isScanning {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.bottom, 8)
                        Text("Scanning Page Content...")
                            .font(.headline)
                        Text("Extracting text references, framework signatures, and indexing layout for the AI Scanned Document Assistant...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        // Chat History / Initial Prompt
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 16) {
                                    if chatHistory.isEmpty {
                                        VStack(spacing: 12) {
                                            Spacer().frame(height: 40)
                                            Image(systemName: "apple.intelligence")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.orange)
                                            Text("Ask me anything about \(documentTitle)")
                                                .font(.title3.bold())
                                            Text("I have scanned and indexed the entire document. Ask about its parameters, platform support, code samples, or how to integrate it into your project.")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, 40)
                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity)
                                    } else {
                                        ForEach(chatHistory) { msg in
                                            HStack(alignment: .top, spacing: 12) {
                                                ZStack {
                                                    Circle()
                                                        .fill(msg.isUser ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                                                        .frame(width: 30, height: 30)
                                                    Image(systemName: msg.isUser ? "person.fill" : "sparkles")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(msg.isUser ? .blue : .orange)
                                                }

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(msg.isUser ? "You" : "Apple Expert AI")
                                                        .font(.caption.bold())
                                                        .foregroundStyle(.secondary)

                                                    if msg.isUser {
                                                        Text(msg.content)
                                                            .font(.body)
                                                            .textSelection(.enabled)
                                                            .lineSpacing(4)
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                    } else {
                                                        MarkdownBlockListView(blocks: MarkdownParser.shared.parse(msg.content))
                                                    }
                                                }
                                            }
                                            .padding(12)
                                            .background(msg.isUser ? Color.blue.opacity(0.04) : Color.orange.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                            .id(msg.id)
                                        }
                                    }

                            if isProcessing {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Analyzing document and writing answer...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("processing")
                            }

                            if let error = errorMessage {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: chatHistory.count) { _, _ in
                        if let last = chatHistory.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isProcessing) { _, newValue in
                        if newValue {
                            withAnimation {
                                proxy.scrollTo("processing", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input Bar
                HStack(spacing: 12) {
                    TextField("Ask anything about this document...", text: $questionText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .onSubmit {
                            askQuestion()
                        }
                        .disabled(isProcessing)

                    Button(action: askQuestion) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing ? .secondary : .orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                }
                .padding(14)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        }
        .navigationTitle("Document Scan Analyst")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation {
                    isScanning = false
                }
            }
        }
        }
        .frame(width: 650, height: 500)
    }

    private func askQuestion() {
        let question = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty && !isProcessing else { return }

        questionText = ""
        errorMessage = nil
        chatHistory.append(LocalChatMsg(isUser: true, content: question))
        isProcessing = true

        let systemPrompt = """
You are a world-class senior iOS and macOS software engineer and an absolute expert in Swift, SwiftUI, Combine, and Foundation APIs. Below is the scanned documentation of a specific component/webpage. The user has questions about this documentation. Analyze the scanned documentation carefully, and answer their questions with complete clarity, providing fully-commented, premium production-ready Swift code examples, and direct answers to any technical queries. Here is the scanned document:

[START SCANNED DOCUMENT]
\(scannedContent)
[END SCANNED DOCUMENT]

Answer the user's questions based on this document and your expert Apple SDK knowledge.
"""

        let prompt = "\(systemPrompt)\n\nUser Question:\n\(question)"

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                isProcessing = false
                chatHistory.append(LocalChatMsg(isUser: false, content: response))
            } catch {
                isProcessing = false
                errorMessage = "AI Request Failed: \(error.localizedDescription)"
            }
        }
    }
}
