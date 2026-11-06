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
                                .liquidGlass(
                                    style: message.role == .user ? .prominent : .standard,
                                    cornerRadius: 10,
                                    tint: message.role == .user ? .accentColor : nil
                                )
                        } else {
                            MarkdownBlockListView(blocks: blocks)
                                .textSelection(.enabled)
                                .padding(10)
                                .liquidGlass(
                                    style: message.role == .user ? .prominent : .standard,
                                    cornerRadius: 10,
                                    tint: message.role == .user ? .accentColor : nil
                                )
                        }
                    }
                }
            }
            .padding()
        }
    }
}
