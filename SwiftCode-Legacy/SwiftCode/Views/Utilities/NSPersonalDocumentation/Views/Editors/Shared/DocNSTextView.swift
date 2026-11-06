import SwiftUI
import AppKit

public struct DocNSTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true

    public init(text: Binding<String>, isEditable: Bool = true) {
        self._text = text
        self.isEditable = isEditable
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]

        let contentSize = scrollView.contentSize

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true

        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.isEditable = isEditable
        textView.font = .systemFont(ofSize: 13, weight: .regular)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false

        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = true

        textView.textContainerInset = NSSize(width: 12, height: 12)

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            if !selectedRanges.isEmpty {
                textView.selectedRanges = selectedRanges
            }
        }

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DocNSTextView

        init(_ parent: DocNSTextView) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
