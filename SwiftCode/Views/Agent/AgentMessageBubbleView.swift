import SwiftUI

struct AgentMessageBubbleView: View {
    let message: AgentMessage
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.role == .user ? "person.circle.fill" : "cpu.fill")
                .font(.title2)
                .foregroundColor(message.role == .user ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(message.role == .user ? "You" : "Agent")
                    .font(.headline)

                ForEach(0..<message.content.count, id: \.self) { index in
                    contentView(message.content[index])
                }
            }
        }
        .id(message.id)
    }

    @ViewBuilder
    private func contentView(_ content: AgentMessageContent) -> some View {
        switch content {
        case .text(let text):
            MarkdownRenderer(markdown: text)
        case .image(let data, _):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400)
                    .cornerRadius(8)
            }
        case .toolCall(let call):
            AgentToolCallSummaryView(name: call.name, arguments: call.arguments)
        case .toolResult(let result):
            Text(result.isError ? "Error: \(result.content)" : "Result: \(result.content)")
                .font(.footnote)
                .foregroundColor(result.isError ? .red : .secondary)
        case .pendingQuestion(let question):
            AskUserPromptView(question: question, viewModel: viewModel)
        case .pendingQuestionSet(let set):
            QuestionsHandleView(questionSet: set, viewModel: viewModel)
        case .checklistUpdate:
            EmptyView()
        }
    }
}
