import SwiftUI

struct AIChatMessageListView: View {
    let messages: [AIMessage]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.role == .user ? "You" : "Assistant")
                            .font(.caption).bold()
                            .foregroundStyle(.secondary)

                        let blocks = MarkdownParser.shared.parse(message.content)
                        if blocks.isEmpty {
                            Text(message.content)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(10)
                                .background(message.role == .user ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.12))
                                .cornerRadius(8)
                        } else {
                            MarkdownBlockListView(blocks: blocks)
                                .textSelection(.enabled)
                                .padding(10)
                                .background(message.role == .user ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.12))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .padding()
        }
    }
}
