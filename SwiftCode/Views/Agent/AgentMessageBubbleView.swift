import SwiftUI

struct AgentMessageBubbleView: View {
    let message: AgentMessage
    @Bindable var viewModel: AgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                if message.role == .user {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                } else {
                    Image(systemName: message.role == .system ? "terminal.fill" : "sparkles")
                        .font(.system(size: 18))
                        .foregroundColor(message.role == .system ? .secondary : .purple)
                }

                Text(message.role == .user ? "You" : (message.role == .system ? "System" : "SwiftCode AI"))
                    .font(.subheadline)
                    .fontWeight(.bold)

                Spacer()

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            // Content Bubble
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<message.content.count, id: \.self) { index in
                    contentView(message.content[index])
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(bubbleBackgroundColor)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .id(message.id)
    }

    private var bubbleBackgroundColor: Color {
        if message.role == .user {
            return Color.accentColor.opacity(0.08)
        } else if message.role == .system {
            return Color.secondary.opacity(0.06)
        } else {
            return Color(NSColor.controlBackgroundColor).opacity(0.7)
        }
    }

    @ViewBuilder
    private func contentView(_ content: AgentMessageContent) -> some View {
        switch content {
        case .text(let text):
            MarkdownBlockListView(blocks: MarkdownParser.shared.parse(text))
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: result.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Tool Execution Result")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(result.isError ? .red : .green)

                ScrollView(.horizontal) {
                    Text(result.content)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(10)
                }
                .background(Color.black.opacity(0.15))
                .cornerRadius(6)
            }
            .padding(.top, 4)
        case .pendingQuestion(let question):
            AskUserPromptView(question: question, viewModel: viewModel)
        case .pendingQuestionSet(let set):
            QuestionsHandleView(questionSet: set, viewModel: viewModel)
        case .checklistUpdate:
            EmptyView()
        }
    }
}
