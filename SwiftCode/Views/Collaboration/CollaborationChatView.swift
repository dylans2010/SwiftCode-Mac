import SwiftUI

@MainActor
public struct CollaborationChatView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String
    @State private var inputText: String = ""
    @State private var selectedChannel: String = "general"

    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

            VStack(spacing: 0) {
                // Channel Picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ChannelTab(title: "#general", isSelected: selectedChannel == "general") {
                            selectedChannel = "general"
                        }
                        ChannelTab(title: "#development", isSelected: selectedChannel == "development") {
                            selectedChannel = "development"
                        }
                        ChannelTab(title: "#prs", isSelected: selectedChannel == "prs") {
                            selectedChannel = "prs"
                        }
                    }
                    .padding()
                }

                // Chat Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(manager.activityLog.filter { $0.kind == .chat }) { msg in
                                ChatRow(activity: msg, isMe: msg.actorID == actorID)
                            }
                        }
                        .padding()
                        .id("Bottom")
                    }
                }

                // Input Area
                HStack(spacing: 12) {
                    TextField("Message #\(selectedChannel)...", text: $inputText)
                        .padding(10)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)

                    Button {
                        manager.addActivity(actorID: actorID, title: "Chat Message", detail: inputText, kind: .chat, notify: false)
                        inputText = ""
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .disabled(inputText.isEmpty)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("Team Chat")
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.05), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
                )
        }
    }
}

struct ChatRow: View {
    let activity: CollaborationActivity
    let isMe: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isMe {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(Text(String(activity.actorID.prefix(1))).font(.caption.bold()).foregroundStyle(.blue))
            } else {
                Spacer()
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if !isMe {
                    Text(activity.actorID)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(activity.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(isMe ? Color.blue.opacity(0.3) : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }

            if !isMe { Spacer() }
        }
    }
}
