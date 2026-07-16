import SwiftUI

struct AgentMessageBubbleView: View {
    let message: AgentMessage
    @Bindable var viewModel: AgentViewModel
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Author identity and timestamp
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: message.role == .user ? "person.crop.circle.fill" : "sparkles")
                    .font(.title3)
                    .foregroundColor(message.role == .user ? .accentColor : .orange)

                Text(message.role == .user ? "You" : (viewModel.mode == .chat ? "SwiftCode Assistant" : "SwiftCode Agent"))
                    .font(.subheadline)
                    .bold()

                Spacer()

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            // Content container
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<message.content.count, id: \.self) { index in
                    contentView(message.content[index])
                }
            }
            .padding(14)
            .background(
                message.role == .user
                ? Color.accentColor.opacity(0.08)
                : Color(NSColor.controlBackgroundColor).opacity(0.85)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        message.role == .user
                        ? Color.accentColor.opacity(0.2)
                        : Color.secondary.opacity(0.15),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
            // Hover actions overlay
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    HStack(spacing: 6) {
                        Button(action: copyToClipboard) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Copy Message Content")

                        Button(action: deleteMessage) {
                            Image(systemName: "trash.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Delete Message")
                    }
                    .padding(6)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .id(message.id)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
        // Native Context Menu
        .contextMenu {
            Button("Copy Message") {
                copyToClipboard()
            }
            Button("Copy as Markdown") {
                copyAsMarkdown()
            }
            Divider()
            Button("Delete", role: .destructive) {
                deleteMessage()
            }
        }
    }

    @ViewBuilder
    private func contentView(_ content: AgentMessageContent) -> some View {
        switch content {
        case .text(let text):
            MarkdownBlockListView(blocks: MarkdownRenderer.shared.parse(text))
                .textSelection(.enabled)
        case .image(let data, _):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400)
                    .cornerRadius(8)
                    .shadow(radius: 2)
            }
        case .toolCall(let call):
            AgentToolCallSummaryView(name: call.name, arguments: call.arguments)
        case .toolResult(let result):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: result.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text("Tool Result")
                        .font(.caption)
                        .bold()
                }
                .foregroundColor(result.isError ? .red : .green)

                Text(result.content)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(4)
            }
        case .pendingQuestion(let question):
            AskUserPromptView(question: question, viewModel: viewModel)
        case .pendingQuestionSet(let set):
            QuestionsHandleView(questionSet: set, viewModel: viewModel)
        case .checklistUpdate:
            EmptyView()
        }
    }

    private func extractRawText() -> String {
        return message.content.compactMap { content -> String? in
            switch content {
            case .text(let t): return t
            case .toolResult(let r): return "[Tool Result] \(r.content)"
            default: return nil
            }
        }.joined(separator: "\n")
    }

    private func copyToClipboard() {
        let text = extractRawText()
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
    }

    private func copyAsMarkdown() {
        let text = extractRawText()
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("```markdown\n\(text)\n```", forType: .string)
    }

    private func deleteMessage() {
        withAnimation {
            viewModel.session.messages.removeAll { $0.id == message.id }
        }
    }
}
