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
            context.coordinator.lastHighlightedContent = nil
            context.coordinator.lastHighlightedLanguage = nil
            return
        }

        // 1. Sync string contents if mismatched
        if textView.string != doc.content {
            let selectedRange = textView.selectedRange()
            textView.string = doc.content

            // Restore selection if it's within bounds
            if selectedRange.location + selectedRange.length <= textView.string.count {
                textView.setSelectedRange(selectedRange)
            }
        }

        // 2. PERFORMANCE: Only highlight if content or language actually mutated!
        // This avoids spawning tasks on selection changes, focus gains, or cursor moves.
        guard doc.content != context.coordinator.lastHighlightedContent ||
              doc.language != context.coordinator.lastHighlightedLanguage else {
            return
        }

        context.coordinator.lastHighlightedContent = doc.content
        context.coordinator.lastHighlightedLanguage = doc.language

        // 3. PERFORMANCE: Cancel any outstanding previous highlighting task
        context.coordinator.activeHighlightTask?.cancel()

        // 4. Asynchronously apply modern high-fidelity highlighting
        context.coordinator.activeHighlightTask = Task {
            let highlighted = await CodeRenderEngine.shared.parseAndHighlight(doc.content, language: doc.language)

            // Check for cancellation before scheduling UI updates on Main Actor
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard doc.id == viewModel.activeDocument?.id else { return }
                guard let storage = textView.textStorage, storage.string == doc.content else { return }

                storage.beginEditing()

                // Cleansing: Remove existing attributes to prevent style leaks/ghosting
                let fullRange = NSRange(location: 0, length: storage.length)
                storage.removeAttribute(.foregroundColor, range: fullRange)

                // Safely apply attributes without resetting text storage
                let attributedString = highlighted.attributedString
                attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { attributes, range, _ in
                    if range.location + range.length <= storage.length {
                        storage.addAttributes(attributes, range: range)
                    }
                }

                storage.endEditing()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextView
        var activeHighlightTask: Task<Void, Never>?
        var lastHighlightedContent: String?
        var lastHighlightedLanguage: SourceLanguage?

        init(_ parent: NativeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.viewModel.updateContent(textView.string)
        }
    }
}
