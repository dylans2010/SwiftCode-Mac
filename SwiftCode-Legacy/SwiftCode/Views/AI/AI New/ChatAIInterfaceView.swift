import SwiftUI

struct ChatAIInterfaceView: View {
    @StateObject private var controller = ChatController.shared
    @State private var input = ""
    @State private var useContext = true
    @State private var showSlashCommands = false

    private let commands = ["/summarize", "/explain", "/fix", "/plan"]

    var body: some View {
        VStack(spacing: 18) {
            header
            messagesPanel
            composer
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            AssistantSectionHeader(
                eyebrow: "Chat mode",
                title: "Ask for code help naturally",
                subtitle: "The assistant now avoids echoing your prompt and focuses on concise, useful output."
            )
            Spacer()
            Toggle("Context", isOn: $useContext)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(20)
        .assistantGlassCard()
    }

    private var messagesPanel: some View {
        VStack(spacing: 12) {
            if controller.messages.isEmpty {
                ContentUnavailableView(
                    "Start a Conversation",
                    systemImage: "wand.and.stars",
                    description: Text("Ask about your codebase, request a refactor, or generate a plan.")
                )
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(controller.messages) { message in
                                ChatMessageBubble(message: message)
                                    .id(message.id)
                            }

                            if controller.isGenerating {
                                TypingIndicatorBubble()
                            }
                        }
                        .padding(2)
                    }
                    .onChange(of: controller.messages.count) { _, _ in
                        if let last = controller.messages.last {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minHeight: 320)
        .assistantGlassCard()
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showSlashCommands {
                SlashCommandList(commands: commands) { command in
                    input = command + " "
                    showSlashCommands = false
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message the AI assistant", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(16)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
                    .onChange(of: input) { _, newValue in
                        showSlashCommands = newValue.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
                    }

                Button {
                    Task { await sendMessage() }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(AssistantPrimaryButtonStyle())
                .frame(maxWidth: 140)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.isGenerating)
            }
        }
        .padding(20)
        .assistantGlassCard()
    }

    private func sendMessage() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        input = ""
        showSlashCommands = false
        await controller.sendMessage(prompt, useContext: useContext)
    }
}
