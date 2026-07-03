import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    @Bindable var viewModel: EditorViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        let textView = NSTextView()
        textView.autoresizingMask = [.width, .height]
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.delegate = context.coordinator
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView,
              let doc = viewModel.activeDocument else { return }

        if textView.string != doc.content {
            let storage = textView.textStorage
            storage?.beginEditing()
            textView.string = doc.content

            // Apply highlighting
            let fullRange = NSRange(location: 0, length: storage?.length ?? 0)
            storage?.removeAttribute(.foregroundColor, range: fullRange)

            var currentLocation = 0
            for line in viewModel.tokenizedLines {
                for token in line.tokens {
                    let range = NSRange(location: currentLocation, length: token.text.count)
                    if range.location + range.length <= (storage?.length ?? 0) {
                        let color = colorForToken(token.kind)
                        storage?.addAttribute(.foregroundColor, value: color, range: range)
                    }
                    currentLocation += token.text.count
                }
                currentLocation += 1 // for newline
            }
            storage?.endEditing()
        }
    }

    private func colorForToken(_ kind: SyntaxTokenKind) -> NSColor {
        // This should ideally come from themeVM, but for simplicity in this bridge:
        switch kind {
        case .keyword: return .systemPink
        case .string: return .systemOrange
        case .comment: return .systemGreen
        case .number: return .systemPurple
        case .type: return .systemTeal
        case .plain: return .labelColor
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.viewModel.updateContent(textView.string)
        }
    }
}
