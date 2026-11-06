// Ported from Legacy `SwiftCode/Views/Gists/Components/MarkdownToolbar.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim except `.liquidGlass(...)` -> thinMaterial (see Adaptive notes).
// Self-contained markdown formatting toolbar (bold/italic/strikethrough/quote/link/
// code/list + attach + mention). applyFormat appends at the end — that is Legacy
// behaviour (selection-aware editing needs NSTextView access; preserved as-is).
// Wiring: GistBrowserView's file editor (SwiftCodeUI/SourceControl) — place above
// the editor, binding the file text; onAttachFile/onMention are host-owned.
// (GistBrowserView's header claims this was already rebuilt; it was not — no
// formatting controls exist in it.)

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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        // Basic implementation, ideally it would handle selection if we had access to the underlying NSTextView
        text += prefix + suffix
    }
}
