import SwiftUI

struct AgentMessageListView: View {
    let messages: [AgentMessage]
    @Bindable var viewModel: AIAssistantViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if messages.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 60))
                                .foregroundColor(.accentColor)
                            Text("How can I help you today?")
                                .font(.title2)
                                .bold()
                            Text("I can help you write code, debug issues, or manage your project.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding(.top, 100)
                    } else {
                        ForEach(messages) { message in
                            AgentMessageBubbleView(message: message, viewModel: viewModel)
                        }
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}
