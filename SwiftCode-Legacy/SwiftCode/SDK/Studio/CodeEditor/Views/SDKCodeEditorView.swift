import AppKit // NSScrollView, NSTextView, NSRulerView, NSSavePanel
import Foundation
import SwiftUI
import UniformTypeIdentifiers // UTType for the save panel

// MARK: - SDKCodeEditorView
//
// The editor surface for the Studio code editor's active tab: a real
// AppKit `NSTextView` (typing, selection, and undo all work natively) with
// debounced, off-main-thread syntax highlighting, a live line-number
// gutter, line/column navigation, Save-As retargeting, and external
// modification conflict resolution.

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

    /// Convenience initializer: plain (unhighlighted) rendering.
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
                VStack(spacing: 0) {
                    if tab.document.hasExternalModification {
                        externalModificationBanner(for: tab)
                        Divider()
                    }
                    SDKCodeEditorTextView(
                        tabID: tab.id,
                        document: tab.document,
                        highlighter: highlighter,
                        fontSize: fontSize,
                        findAdapter: findAdapter,
                        navigationTarget: state.requestedNavigationTarget?.tabID == tab.id ? state.requestedNavigationTarget : nil,
                        onClearNavigationTarget: { [weak state] in
                            state?.clearNavigationTarget()
                        },
                        onTextChange: { [weak state] newText in
                            state?.updateText(newText, for: tab.id)
                            findCoordinator?.editorTextDidChange()
                        }
                    )
                    .id(tab.id)
                    .accessibilityLabel("Code editor: \(tab.document.displayName)")
                }
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
            state.checkExternalModifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.checkExternalModifications()
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

    // MARK: - External Modification Banner

    private func externalModificationBanner(for tab: SDKCodeEditorTab) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("“\(tab.document.displayName)” was modified on disk outside the editor while you have unsaved changes.")
                .font(.caption)
            Spacer()
            Button("Reload from Disk") {
                try? state.reloadTabFromDisk(tab.id)
            }
            .controlSize(.small)
            Button("Keep Mine") {
                state.dismissExternalModification(for: tab.id)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlass(style: .subtle, cornerRadius: 8, tint: .orange)
        .padding(6)
    }

    // MARK: - Save (⌘S)

    private func saveActiveDocument() {
        guard let tab = state.activeTab else { return }
        let text = tab.document.text
        if let url = tab.document.fileURL {
            write(text, to: url, displayName: tab.document.displayName, tabID: tab.id, isUntitledSaveAs: false)
        } else {
            saveUntitled(text: text, language: tab.document.language, tabID: tab.id)
        }
    }

    /// Untitled buffers go through a real `NSSavePanel` and retarget the
    /// tab to the newly saved URL.
    private func saveUntitled(text: String, language: SDKCodeLanguage, tabID: UUID) {
        let panel = NSSavePanel()
        panel.title = "Save Untitled Document"
        panel.canCreateDirectories = true
        if let rootURL = state.projectRootURL {
            panel.directoryURL = rootURL
        }
        let ext = language.fileExtensions.first ?? "txt"
        panel.nameFieldStringValue = "Untitled.\(ext)"
        if let contentType = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [contentType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(text, to: url, displayName: url.lastPathComponent, tabID: tabID, isUntitledSaveAs: true)
    }

    /// Writes UTF-8 to disk for real, then clears the dirty flag via
    /// `markSaved(tabID:)` or `retargetTab(_:to:)`. Failures are reported, never swallowed.
    private func write(_ text: String, to url: URL, displayName: String, tabID: UUID, isUntitledSaveAs: Bool) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            if isUntitledSaveAs {
                state.retargetTab(tabID, to: url)
            } else {
                state.markSaved(tabID: tabID)
            }
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
            Text("Open a file from the navigator or create a new tab to start editing")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No file open")
    }
}

// MARK: - SDKCodeEditorTextView

@MainActor
struct SDKCodeEditorTextView: NSViewRepresentable {
    var tabID: UUID
    var document: SDKCodeDocument
    var highlighter: any SDKSyntaxHighlighter
    var fontSize: CGFloat
    var findAdapter: SDKCodeEditorFindAdapter
    var navigationTarget: SDKCodeNavigationTarget?
    var onClearNavigationTarget: () -> Void
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
        if let target = navigationTarget {
            applyNavigationTarget(target, to: textView)
            DispatchQueue.main.async {
                onClearNavigationTarget()
            }
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

        if textView.string != document.text {
            let savedSelection = textView.selectedRange
            textView.string = document.text
            let clamped = min(document.cursorOffset ?? savedSelection.location, (textView.string as NSString).length)
            textView.selectedRange = NSRange(location: max(0, clamped), length: 0)
            coordinator.scheduleHighlight(afterNanoseconds: 50_000_000)
        }

        if let target = navigationTarget {
            applyNavigationTarget(target, to: textView)
            DispatchQueue.main.async {
                onClearNavigationTarget()
            }
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

    private func applyNavigationTarget(_ target: SDKCodeNavigationTarget, to textView: NSTextView) {
        let nsString = textView.string as NSString
        guard nsString.length > 0 else { return }
        let targetLine = max(1, target.line)
        var currentLine = 1
        var lineRange = NSRange(location: 0, length: 0)
        var index = 0
        while index < nsString.length {
            let range = nsString.lineRange(for: NSRange(location: index, length: 0))
            lineRange = range
            if currentLine == targetLine {
                break
            }
            currentLine += 1
            index = NSMaxRange(range)
        }
        let colOffset = max(0, (target.column ?? 1) - 1)
        let targetLoc = min(lineRange.location + colOffset, NSMaxRange(lineRange))
        let selectionLength = min(max(0, NSMaxRange(lineRange) - targetLoc), nsString.length - targetLoc)
        let nsRange = NSRange(location: targetLoc, length: selectionLength > 1 ? selectionLength - 1 : 0)
        textView.selectedRange = nsRange
        textView.scrollRangeToVisible(nsRange)
        _ = textView.window?.makeFirstResponder(textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

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

        func scheduleHighlight(afterNanoseconds delay: UInt64 = 250_000_000) {
            highlightTask?.cancel()
            let highlighter = self.highlighter
            let language = self.language
            let fontSize = self.fontSize
            let text = self.textView?.string ?? ""
            highlightTask = Task.detached { [highlighter, language, fontSize, text] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                let tokens = highlighter.highlight(text, language: language)
                await MainActor.run { [weak self] in
                    guard let self,
                          let textView = self.textView,
                          !Task.isCancelled,
                          textView.string == text
                    else { return }
                    self.apply(tokens: tokens, fontSize: fontSize, to: textView)
                }
            }
        }

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

struct SDKPlainSyntaxHighlighter: SDKSyntaxHighlighter {
    func highlight(_ text: String, language: SDKCodeLanguage) -> [SDKToken] {
        []
    }
}
