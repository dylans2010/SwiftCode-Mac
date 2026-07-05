import SwiftUI

struct MarkdownToolbar: View {
    @Binding var text: String
    var onAttachFile: () -> Void
    var onMention: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                toolbarButton(icon: "bold", action: { applyFormat("**", "**") })
                toolbarButton(icon: "italic", action: { applyFormat("_", "_") })
                toolbarButton(icon: "strikethrough", action: { applyFormat("~~", "~~") })
                toolbarButton(icon: "quote.opening", action: { applyFormat("> ", "") })
                toolbarButton(icon: "link", action: { applyFormat("[", "](url)") })
                toolbarButton(icon: "curlybraces", action: { applyFormat("```\n", "\n```") })
                toolbarButton(icon: "list.bullet", action: { applyFormat("- ", "") })
                toolbarButton(icon: "list.number", action: { applyFormat("1. ", "") })

                Divider().frame(height: 20)

                toolbarButton(icon: "paperclip", action: onAttachFile)
                toolbarButton(icon: "at", action: onMention)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.white.opacity(0.05))
    }

    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func applyFormat(_ prefix: String, _ suffix: String) {
        // Basic implementation, ideally it would handle selection if we had access to the underlying UITextView
        text += prefix + suffix
    }
}
