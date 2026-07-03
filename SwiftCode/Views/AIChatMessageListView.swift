import SwiftUI

struct AIChatMessageListView: View {
    let messages: [AIMessage]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.role == .user ? "You" : "Assistant")
                            .font(.caption).bold()
                        Text(message.content)
                            .padding(8)
                            .background(message.role == .user ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
    }
}
