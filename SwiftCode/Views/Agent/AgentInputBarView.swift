import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AgentInputBarView")

struct AgentInputBarView: View {
    @Bindable var viewModel: AgentViewModel
    @State private var text = ""
    @State private var showingAttachments = false

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(viewModel.attachments) { attachment in
                            AgentAttachmentChipView(attachment: attachment) {
                                viewModel.attachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                Divider()
            }

            HStack(alignment: .center, spacing: 12) {
                Button(action: { showingAttachments = true }) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Add Attachment")

                TextField("Ask the agent anything...", text: $text)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .onSubmit {
                        logger.log("[AgentInputBarView] Return pressed, triggering sendMessage.")
                        sendMessage()
                    }

                Button(action: {
                    logger.log("[AgentInputBarView] Send button clicked, triggering sendMessage.")
                    sendMessage()
                }) {
                    Image(systemName: viewModel.isProcessing ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(text.isEmpty && !viewModel.isProcessing ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty && !viewModel.isProcessing)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .popover(isPresented: $showingAttachments) {
            AgentAttachmentPickerView(attachments: $viewModel.attachments)
                .frame(width: 300, height: 400)
        }
    }

    private func sendMessage() {
        if viewModel.isProcessing {
            logger.log("[AgentInputBarView] Active request is running. Triggering cancel task.")
            viewModel.cancelTask()
        } else {
            guard !text.isEmpty else { return }
            let currentText = text
            text = ""
            logger.log("[AgentInputBarView] Dispatching sendUserMessage task for prompt.")
            Task {
                await viewModel.sendUserMessage(currentText)
            }
        }
    }
}
