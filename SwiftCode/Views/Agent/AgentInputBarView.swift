import SwiftUI

struct AgentInputBarView: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var text = ""
    @State private var attachments: [AgentAttachment] = []

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(attachments) { attachment in
                            AgentAttachmentChipView(attachment: attachment) {
                                attachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                    .padding(8)
                }
                Divider()
            }

            HStack(alignment: .bottom, spacing: 8) {
                AgentAttachmentPickerView(attachments: $attachments)
                    .padding(.bottom, 8)

                TextEditor(text: $text)
                    .frame(minHeight: 36, maxHeight: 200)
                    .padding(4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                if viewModel.session.turnState == .awaitingModel || viewModel.session.turnState == .executingTools {
                    Button(action: { viewModel.cancelTurn() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.isEmpty && attachments.isEmpty)
                }
            }
            .padding(8)
        }
    }

    private func send() {
        viewModel.sendMessage(text, attachments: attachments)
        text = ""
        attachments = []
    }

}
