import SwiftUI

struct AgentAttachmentChipView: View {
    let attachment: AgentAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: attachment.type == .image ? "photo" : "doc")
            Text(attachment.name)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.2))
        .cornerRadius(12)
    }
}
