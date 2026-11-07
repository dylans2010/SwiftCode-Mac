import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct CollaborationChatView: View {
    @ObservedObject var manager: CollaborationManager
    @ObservedObject var chat: CollaborationChatManager
    let actorID: String
    @State private var inputText: String = ""
    @State private var selectedChannel: String = "general"

    public init(manager: CollaborationManager, chat: CollaborationChatManager, actorID: String) {
        self.manager = manager
        self.chat = chat
        self.actorID = actorID
    }

    private var channelMessages: [CollaborationChatMessage] {
        chat.messages(for: selectedChannel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ChannelTab(title: "#general", isSelected: selectedChannel == "general") {
                        selectChannel("general")
                    }
                    ChannelTab(title: "#development", isSelected: selectedChannel == "development") {
                        selectChannel("development")
                    }
                    ChannelTab(title: "#prs", isSelected: selectedChannel == "prs") {
                        selectChannel("prs")
                    }
                }
                .padding()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if channelMessages.isEmpty {
                            Text("No messages in #\(selectedChannel) yet.")
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                        ForEach(channelMessages) { message in
                            ChatRow(message: message, isMe: message.authorID == actorID)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: channelMessages.count) {
                    if let lastID = channelMessages.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let lastID = channelMessages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 12) {
                TextField("Message #\(selectedChannel)...", text: $inputText)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .textFieldStyle(.plain)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Team Chat")
        .onAppear { chat.setChannel(selectedChannel) }
    }

    private func selectChannel(_ channelID: String) {
        selectedChannel = channelID
        chat.setChannel(channelID)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chat.sendMessage(text: text, authorID: actorID, channelID: selectedChannel)
        manager.addActivity(actorID: actorID, title: "Chat Message", detail: text, kind: .chat, notify: false)
        inputText = ""
    }
}

struct ChannelTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ChatRow: View {
    let message: CollaborationChatMessage
    let isMe: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isMe {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(Text(String(message.authorID.prefix(1))).font(.caption.bold()).foregroundStyle(.blue))
            } else {
                Spacer()
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if !isMe {
                    Text(message.authorID)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(message.text)
                    .font(.subheadline)
                    .padding(10)
                    .background(isMe ? Color.blue.opacity(0.3) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                if let attachment = message.attachment {
                    switch attachment {
                    case .codeSnippet(let path, let code):
                        Text("\(path): \(code)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    case .fileReference(let path):
                        Label(path, systemImage: "doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(message.timestamp, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if !isMe { Spacer() }
        }
    }
}
