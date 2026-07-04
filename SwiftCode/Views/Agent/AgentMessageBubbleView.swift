import SwiftUI

struct AgentMessageBubbleView: View {
    let message: AgentMessage
    @Bindable var viewModel: AgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: message.role == .user ? "person.circle.fill" : "cpu.fill")
                    .font(.title3)
                    .foregroundColor(message.role == .user ? .accentColor : .secondary)

                Text(message.role == .user ? "You" : "SwiftCode Agent")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Text(Date().formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<message.content.count, id: \.self) { index in
                    contentView(message.content[index])
                }
            }
            .padding(12)
            .background(message.role == .user ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .id(message.id)
    }

    @ViewBuilder
    private func contentView(_ content: AgentMessageContent) -> some View {
        switch content {
        case .text(let text):
            Text(MarkdownRenderer.shared.render(text))
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
                    .background(Color.black.opacity(0.05))
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
}
