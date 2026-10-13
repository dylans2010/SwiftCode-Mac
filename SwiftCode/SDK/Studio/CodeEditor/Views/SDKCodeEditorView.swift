import AppKit // NSScrollView, NSTextView, NSRulerView, NSSavePanel
import Foundation
import SwiftUI
import UniformTypeIdentifiers // UTType for the save panel

// MARK: - SDKCodeEditorView
//
// The editor surface for the Studio code editor's active tab: a real
// AppKit `NSTextView` (typing, selection, and undo all work natively) with
// debounced, off-main-thread syntax highlighting and a live line-number
// gutter.
//
// REAL behaviors, no placeholders:
// - One text system per open tab: the inner representable is keyed by tab
//   ID (`.id(tab.id)`), so switching tabs swaps the whole `NSTextView`
//   instead of splicing strings. Undo history, selection, and the
//   highlight pipeline never leak across documents.
// - Typing flows `NSTextViewDelegate.textDidChange` ->
//   `SDKCodeEditorState.updateText(_:for:)` synchronously on the main
//   actor, so the state's document text is always current.
// - Highlighting is debounced (250 ms) and computed off the main thread
//   (`Task.detached`, the `SDKSyntaxHighlighter` protocol is `Sendable`);
//   tokens are applied back on the main actor as text *attributes* — the
//   string is never replaced — so native typing undo is preserved. Stale
//   results (a newer edit landed mid-computation) are discarded.
// - ⌘S saves the active document: UTF-8 write to `fileURL`, or an
//   `NSSavePanel` for untitled buffers, then `markSaved(tabID:)` clears
//   the dirty flag. Write failures are surfaced honestly (console entry
//   plus alert), never swallowed.
// - Find integration: when a `SDKCodeFindCoordinator` is supplied, this
//   view registers its `SDKCodeEditorFindAdapter` as the coordinator's
//   editor on appear (nil on disappear) and notifies it on every text
//   change, per the contract in `SDKCodeFindCoordinator`.
//
// The highlighter is injected as the `SDKSyntaxHighlighter` protocol only:
// pass the sibling task's `SDKKeywordHighlighter` via
// `init(state:highlighter:...)` once it lands. The default is a trivial
// plain highlighter defined below — deliberately minimal, not a second
// keyword highlighter.

@MainActor
public struct SDKCodeEditorView: View {
    @ObservedObject var state: SDKCodeEditorState

    /// Token source for highlighting. Protocol-typed so the sibling
    /// `SDKKeywordHighlighter` plugs in with no dependency on its file.
    var highlighter: any SDKSyntaxHighlighter

    /// Editor font size in points; always the monospaced system font.
    var fontSize: CGFloat

    /// Shared find coordinator, when the parent composes this view with
    /// `SDKCodeFindBarView`. `nil` keeps the view fully standalone.
    var findCoordinator: SDKCodeFindCoordinator?

    /// Bridges find requests to whichever tab's `NSTextView` is live.
    /// `@StateObject` so it survives tab switches (only the inner
    /// representable is re-keyed per tab).
    @StateObject private var findAdapter = SDKCodeEditorFindAdapter()

    @State private var saveErrorMessage: String = ""
    @State private var showSaveError: Bool = false

    /// Designated initializer: explicit highlighter.
    public init(
        state: SDKCodeEditorState,
        highlighter: any SDKSyntaxHighlighter,
        fontSize: CGFloat = 13,
        findCoordinator: SDKCodeFindCoordinator? = nil
    ) {
        self.state = state
        self.highlighter = highlighter
        self.fontSize = fontSize
        self.findCoordinator = findCoordinator
    }

    /// Convenience initializer: plain (unhighlighted) rendering. Call
    /// sites should prefer the designated initializer with the real
    /// `SDKKeywordHighlighter` once the sibling task lands it. Kept as a
    /// separate initializer (rather than a default parameter value) so
    /// the private fallback type never leaks into public API.
    public init(
        state: SDKCodeEditorState,
        fontSize: CGFloat = 13,
        findCoordinator: SDKCodeFindCoordinator? = nil
    ) {
        self.state = state
        self.highlighter = SDKPlainSyntaxHighlighter()
        self.fontSize = fontSize
        self.findCoordinator = findCoordinator
    }

    public var body: some View {
        Group {
            if let tab = state.activeTab {
                SDKCodeEditorTextView(
                    document: tab.document,
                    highlighter: highlighter,
                    fontSize: fontSize,
                    findAdapter: findAdapter,
                    onTextChange: { [weak state] newText in
                        state?.updateText(newText, for: tab.id)
                        findCoordinator?.editorTextDidChange()
                    }
                )
                .id(tab.id)
                .accessibilityLabel("Code editor: \(tab.document.displayName)")
            } else {
                editorPlaceholder
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topLeading) {
            // Invisible button existing only to host ⌘S.
            Button("Save") { saveActiveDocument() }
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .disabled(state.activeTab == nil)
        }
        .onAppear {
            if let findCoordinator {
                findCoordinator.editor = findAdapter
            }
        }
        .onDisappear {
            if let findCoordinator, findCoordinator.editor === findAdapter {
                findCoordinator.editor = nil
            }
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    // MARK: - Save (⌘S)

    private func saveActiveDocument() {
        guard let tab = state.activeTab else { return }
        let text = tab.document.text
        if let url = tab.document.fileURL {
            write(text, to: url, displayName: tab.document.displayName, tabID: tab.id)
        } else {
            saveUntitled(text: text, language: tab.document.language, tabID: tab.id)
        }
    }

    /// Untitled buffers go through a real `NSSavePanel`. Cancellation is
    /// not an error — the panel is simply dismissed.
    private func saveUntitled(text: String, language: SDKCodeLanguage, tabID: UUID) {
        let panel = NSSavePanel()
        panel.title = "Save Untitled Document"
        panel.canCreateDirectories = true
        let ext = language.fileExtensions.first ?? "txt"
        panel.nameFieldStringValue = "Untitled.\(ext)"
        if let contentType = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [contentType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(text, to: url, displayName: url.lastPathComponent, tabID: tabID)
        // NOTE: the tab keeps `fileURL == nil` and the "Untitled" title
        // after a save-as — `SDKCodeEditorState` has no API to retarget a
        // document at a new URL. The bytes ARE on disk; the follow-up is a
        // small state API addition, not silent behavior here.
    }

    /// Writes UTF-8 to disk for real, then clears the dirty flag via
    /// `markSaved(tabID:)`. Failures are reported, never swallowed.
    private func write(_ text: String, to url: URL, displayName: String, tabID: UUID) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            state.markSaved(tabID: tabID)
            state.appendConsole(.system("Saved \(displayName)"))
        } catch {
            let message = "Could not save \(displayName): \(error.localizedDescription)"
            state.appendConsole(SDKConsoleEntry(stream: .stderr, text: message))
            saveErrorMessage = message
            showSaveError = true
        }
    }

    // MARK: - Placeholder

    private var editorPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("No File Open")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Open a file to start editing")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No file open")
    }
}

// MARK: - SDKCodeEditorTextView
//
// `NSViewRepresentable` hosting the AppKit text system for ONE document.
// The parent keys this view by tab ID, so `document` only ever changes
// for the same tab (e.g. a programmatic edit through the state) — live
// typing never round-trips through SwiftUI into the text view, and the
// guard in `updateNSView` never clobbers an in-flight edit.

@MainActor
struct SDKCodeEditorTextView: NSViewRepresentable {
    var document: SDKCodeDocument
    var highlighter: any SDKSyntaxHighlighter
    var fontSize: CGFloat
    var findAdapter: SDKCodeEditorFindAdapter
    var onTextChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true

        // Dedicated text system: storage -> layout -> container -> view.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = false
        textContainer.lineBreakMode = .byClipping
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.allowsUndo = true
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = font
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        let ruler = SDKCodeEditorLineNumberRuler(scrollView: scrollView, orientation: .verticalRuler)
        ruler.codeTextView = textView
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true

        let coordinator = context.coordinator
        coordinator.configure(
            textView: textView,
            ruler: ruler,
            highlighter: highlighter,
            language: document.language,
            fontSize: fontSize,
            onTextChange: onTextChange
        )
        findAdapter.textView = textView

        textView.string = document.text
        if let cursor = document.cursorOffset {
            let clamped = min(max(cursor, 0), (document.text as NSString).length)
            textView.selectedRange = NSRange(location: clamped, length: 0)
        }
        coordinator.scheduleHighlight(afterNanoseconds: 50_000_000)
        ruler.needsDisplay = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.highlighter = highlighter
        coordinator.language = document.language
        coordinator.fontSize = fontSize
        coordinator.onTextChange = onTextChange

        guard let textView = coordinator.textView else { return }

        // External change only: typing already pushed this same string
        // into the state, so a difference here means someone else edited
        // the document (and the tab switch itself is handled by `.id`).
        if textView.string != document.text {
            let savedSelection = textView.selectedRange
            textView.string = document.text
            let clamped = min(savedSelection.location, (textView.string as NSString).length)
            textView.selectedRange = NSRange(location: clamped, length: 0)
            coordinator.scheduleHighlight(afterNanoseconds: 50_000_000)
        }

        if (textView.font?.pointSize ?? 0) != fontSize {
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            textView.font = font
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
            coordinator.scheduleHighlight(afterNanoseconds: 50_000_000)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    /// `NSTextViewDelegate`: forwards edits to the state and drives the
    /// debounced highlight pipeline. All mutable state is main-actor
    /// confined; only the pure `highlight(_:language:)` call leaves the
    /// main actor, following the codebase's `Task.detached` +
    /// `MainActor.run` idiom (see `SDKCodeFileNavigatorView`).
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        weak var ruler: SDKCodeEditorLineNumberRuler?
        var highlighter: any SDKSyntaxHighlighter = SDKPlainSyntaxHighlighter()
        var language: SDKCodeLanguage = .plaintext
        var fontSize: CGFloat = 13
        var onTextChange: (String) -> Void = { _ in }

        private var highlightTask: Task<Void, Never>?

        func configure(
            textView: NSTextView,
            ruler: SDKCodeEditorLineNumberRuler,
            highlighter: any SDKSyntaxHighlighter,
            language: SDKCodeLanguage,
            fontSize: CGFloat,
            onTextChange: @escaping (String) -> Void
        ) {
            self.textView = textView
            self.ruler = ruler
            self.highlighter = highlighter
            self.language = language
            self.fontSize = fontSize
            self.onTextChange = onTextChange
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let changed = notification.object as? NSTextView,
                  changed === textView else { return }
            onTextChange(changed.string)
            ruler?.needsDisplay = true
            scheduleHighlight()
        }

        // MARK: Highlight pipeline

        /// Debounces highlight recomputation (250 ms default keeps typing
        /// smooth; the initial paint uses a shorter delay). The previous
        /// pending pass is cancelled. Inputs are snapshotted on the main
        /// actor up front so the detached closure captures only `Sendable`
        /// values; staleness is re-checked after the off-main computation
        /// before anything is applied.
        func scheduleHighlight(afterNanoseconds delay: UInt64 = 250_000_000) {
            highlightTask?.cancel()
            let highlighter = self.highlighter
            let language = self.language
            let fontSize = self.fontSize
            let text = self.textView?.string ?? ""
            highlightTask = Task.detached { [highlighter, language, fontSize, text] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                // Pure token computation off the main thread.
                let tokens = highlighter.highlight(text, language: language)
                await MainActor.run { [weak self] in
                    guard let self,
                          let textView = self.textView,
                          !Task.isCancelled,
                          textView.string == text
                    else { return } // stale: a newer edit landed mid-computation
                    self.apply(tokens: tokens, fontSize: fontSize, to: textView)
                }
            }
        }

        /// Applies token colors as text attributes on the main thread. The
        /// string itself is never replaced, so native typing undo keeps
        /// working. Out-of-range tokens (a highlighter bug) are skipped,
        /// never trapped on.
        private func apply(tokens: [SDKToken], fontSize: CGFloat, to textView: NSTextView) {
            guard let storage = textView.textStorage, storage.length > 0 else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            storage.beginEditing()
            storage.addAttribute(.font, value: font, range: fullRange)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            for token in tokens where token.kind != .plain {
                let range = NSRange(location: token.range.lowerBound, length: token.length)
                guard range.location >= 0, range.upperBound <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: Self.color(for: token.kind), range: range)
            }
            storage.endEditing()
            ruler?.needsDisplay = true
        }

        private static func color(for kind: SDKTokenKind) -> NSColor {
            // Dynamic system colors: correct in light and dark appearance.
            switch kind {
            case .keyword: return .systemPink
            case .string: return .systemOrange
            case .comment: return .systemGreen
            case .number: return .systemPurple
            case .typeName: return .systemTeal
            case .plain: return .labelColor
            }
        }
    }
}

// MARK: - SDKCodeEditorLineNumberRuler
//
// Native `NSRulerView` gutter showing 1-based line numbers. The scroll view
// keeps the ruler's coordinate space synchronized with the document, so
// numbers scroll with the text for free — no manual frame syncing. Only
// the visible glyph range is drawn, and wrapped continuation fragments are
// skipped (only paragraph starts are numbered), so long files stay cheap.

@MainActor
final class SDKCodeEditorLineNumberRuler: NSRulerView {
    weak var codeTextView: NSTextView?

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 48
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = codeTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = scrollView else { return }

        (textView.backgroundColor ?? .textBackgroundColor).setFill()
        rect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.width - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let lineHeight = font.ascender - font.descender + font.leading

        let nsString = textView.string as NSString
        let visibleRect = scrollView.contentView.documentVisibleRect

        guard nsString.length > 0 else {
            let y = visibleRect.minY + textView.textContainerInset.height
            drawLineNumber(1, atY: y, lineHeight: lineHeight, attributes: attributes)
            return
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else { return }

        // 1-based number of the first visible line: count the lines before
        // its first character. (If that fragment is a wrapped continuation
        // it is skipped below without incrementing, so numbering stays
        // exact.)
        let firstCharRange = layoutManager.characterRange(
            forGlyphRange: NSRange(location: glyphRange.location, length: 0),
            actualGlyphRange: nil
        )
        var lineNumber = 1
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: firstCharRange.location),
            options: .byLines
        ) { _, _, _, _ in lineNumber += 1 }

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [self] _, usedRect, _, fragmentGlyphRange, _ in
            let charRange = layoutManager.characterRange(
                forGlyphRange: fragmentGlyphRange,
                actualGlyphRange: nil
            )
            let paragraphRange = nsString.paragraphRange(
                for: NSRange(location: charRange.location, length: 0)
            )
            guard charRange.location == paragraphRange.location else { return }
            drawLineNumber(lineNumber, atY: usedRect.minY, lineHeight: usedRect.height, attributes: attributes)
            lineNumber += 1
        }
    }

    private func drawLineNumber(
        _ number: Int,
        atY y: CGFloat,
        lineHeight: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let label = "\(number)" as NSString
        let size = label.size(withAttributes: attributes)
        let x = bounds.width - size.width - 8
        let centeredY = y + max(0, (lineHeight - size.height) / 2)
        label.draw(at: NSPoint(x: x, y: centeredY), withAttributes: attributes)
    }
}

// MARK: - SDKCodeEditorFindAdapter
//
// `SDKCodeFindableEditor` bridge from the find coordinator to whichever
// tab's `NSTextView` is currently live. Owned by `SDKCodeEditorView` as a
// `@StateObject`; the representable points it at the fresh text view on
// every `makeNSView` (i.e. every tab switch). Out-of-bounds ranges are
// ignored rather than trapping, per the protocol contract.

@MainActor
final class SDKCodeEditorFindAdapter: SDKCodeFindableEditor, ObservableObject {
    weak var textView: NSTextView?

    var findableText: String {
        textView?.string ?? ""
    }

    func selectFindRange(_ range: Range<Int>) {
        guard let textView else { return }
        let length = (textView.string as NSString).length
        guard range.lowerBound >= 0,
              range.lowerBound <= range.upperBound,
              range.upperBound <= length else { return }
        let nsRange = NSRange(location: range.lowerBound, length: range.upperBound - range.lowerBound)
        textView.selectedRange = nsRange
        textView.scrollRangeToVisible(nsRange)
        _ = textView.window?.makeFirstResponder(textView)
    }
}

// MARK: - SDKPlainSyntaxHighlighter
//
// Trivial `SDKSyntaxHighlighter` emitting no tokens — everything renders
// in the default text color. The editor's fallback default ONLY until the
// sibling task's `SDKKeywordHighlighter` lands and call sites pass it
// explicitly. Deliberately minimal: this must not grow into a second
// keyword highlighter.

struct SDKPlainSyntaxHighlighter: SDKSyntaxHighlighter {
    func highlight(_ text: String, language: SDKCodeLanguage) -> [SDKToken] {
        []
    }
}
