import SwiftUI

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

            HStack(alignment: .bottom, spacing: 12) {
                Button(action: { showingAttachments = true }) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Add Attachment")

                TextField("Ask the agent anything...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...10)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: viewModel.isProcessing ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(text.isEmpty && !viewModel.isProcessing ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty && !viewModel.isProcessing)
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
            viewModel.cancelTask()
        } else {
            guard !text.isEmpty else { return }
            let currentText = text
            text = ""
            Task {
                await viewModel.sendUserMessage(currentText)
            }
        }
    }
}
