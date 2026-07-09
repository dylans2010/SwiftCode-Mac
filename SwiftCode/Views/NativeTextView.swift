import SwiftUI
import AppKit

struct NativeTextView: NSViewRepresentable {
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
        guard let textView = nsView.documentView as? NSTextView else { return }

        guard let doc = viewModel.activeDocument else {
            textView.string = ""
            return
        }

        if textView.string != doc.content {
            let selectedRange = textView.selectedRange()
            textView.string = doc.content

            // Restore selection if it's within bounds
            if selectedRange.location + selectedRange.length <= textView.string.count {
                textView.setSelectedRange(selectedRange)
            }
            context.coordinator.lastTokenizedLines = nil // Force re-highlight
            applyHighlighting(textView, coordinator: context.coordinator)
        } else if !viewModel.tokenizedLines.isEmpty {
            // Apply highlighting even if text didn't change (e.g. tokens arrived later)
            applyHighlighting(textView, coordinator: context.coordinator)
        }
    }

    private func applyHighlighting(_ textView: NSTextView, coordinator: Coordinator) {
        // PERFORMANCE: Check if we already applied these tokens
        if let last = coordinator.lastTokenizedLines, last == viewModel.tokenizedLines {
            return
        }

        guard let storage = textView.textStorage else { return }

        // SAFETY: Only apply highlighting if tokens are available and not stale
        guard !viewModel.tokenizedLines.isEmpty else {
            storage.beginEditing()
            storage.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
            coordinator.lastTokenizedLines = []
            return
        }

        storage.beginEditing()
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.foregroundColor, range: fullRange)

        var currentLocation = 0
        for line in viewModel.tokenizedLines {
            for token in line.tokens {
                let range = NSRange(location: currentLocation, length: token.text.count)
                // SAFETY: Ensure we don't go out of bounds of the current text storage
                if range.location + range.length <= storage.length {
                    let color = colorForToken(token.kind)
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                }
                currentLocation += token.text.count

                // SAFETY: Stop if we've reached the end of the storage
                if currentLocation >= storage.length { break }
            }
            currentLocation += 1 // for newline

            // SAFETY: Stop if we've reached the end of the storage to avoid processing stale/extra tokens
            if currentLocation >= storage.length { break }
        }
        storage.endEditing()
        coordinator.lastTokenizedLines = viewModel.tokenizedLines
    }

    private func colorForToken(_ kind: SyntaxTokenKind) -> NSColor {
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
        var parent: NativeTextView
        var lastTokenizedLines: [TokenizedLine]?

        init(_ parent: NativeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.viewModel.updateContent(textView.string)
        }
    }
}
