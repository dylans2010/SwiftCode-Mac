import SwiftUI

struct AgentMessageListView: View {
    let messages: [AgentMessage]
    @Bindable var viewModel: AgentViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    if messages.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                                .frame(height: 60)
                            Image(systemName: "sparkles")
                                .font(.system(size: 64))
                                .foregroundColor(.accentColor)
                                .symbolEffect(.pulse, options: .repeating)

                            Text("Welcome to SwiftCode AI")
                                .font(.title)
                                .bold()

                            Text(viewModel.mode == .chat ?
                                 "Ask anything about the project. Full read-only code awareness is active with automatic indexing." :
                                 "Let's write code, run terminal tasks, or complete autonomous engineering projects together.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                .font(.body)

                            // Nice Feature Tags
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Complete workspace semantic search context.")
                                }
                                HStack(spacing: 10) {
                                    Image(systemName: "lock.shield.fill")
                                        .foregroundColor(.green)
                                    Text("Native Apple secure foundation model support.")
                                }
                                if viewModel.mode == .agent {
                                    HStack(spacing: 10) {
                                        Image(systemName: "terminal.fill")
                                            .foregroundColor(.purple)
                                        Text("Autonomous file operations & tools execution.")
                                    }
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color.secondary.opacity(0.06))
                            .cornerRadius(12)
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(messages) { message in
                            AgentMessageBubbleView(message: message, viewModel: viewModel)
                        }
                    }

                    // Pulsating typing / processing indicator
                    if viewModel.isProcessing {
                        HStack(spacing: 8) {
                            Image(systemName: "cpu.fill")
                                .foregroundColor(.accentColor)
                                .symbolEffect(.bounce, options: .repeating)

                            Text(viewModel.session.turnState == .executingTools ? "Executing autonomous tools..." : "Thinking...")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .transition(.opacity)
                        .id("typing-indicator")
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isProcessing) {
                scrollToBottom(proxy: proxy)
            }
            // Smart observation: scroll to bottom if the last message text updates (streaming)
            .onChange(of: messages.last?.content.description) {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if viewModel.isProcessing {
                proxy.scrollTo("typing-indicator", anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
