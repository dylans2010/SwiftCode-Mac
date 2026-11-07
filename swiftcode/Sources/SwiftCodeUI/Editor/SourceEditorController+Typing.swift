import AppKit
import SwiftCodeIDECore

@MainActor
final class EditorSyntaxState {
    var document: SyntaxDocument?
    var edits: [(range: NSRange, replacement: String)] = []
    var pendingClosers: Set<Int> = []
    var refineWork: DispatchWorkItem?
    var scopeBlocks: [SyntaxBlock] = []
}

extension SourceEditorController {
    static let syncParseLines = 2_000
    static let syncRefineBudget = 0.008
    static let refineDelay = 0.3

    var syntaxDocument: SyntaxDocument {
        if let d = syntax.document, d.language == language, d.units.count == (textView.string as NSString).length { return d }
        resetSyntax()
        return syntax.document!
    }

    func resetSyntax() {
        syntax.edits = []
        syntax.pendingClosers = []
        syntax.refineWork?.cancel()
        syntax.refineWork = nil
        let doc = SyntaxDocument(text: textView.string, language: language, deferParse: true)
        syntax.document = doc
        if doc.needsRefinement {
            if doc.lineCount <= Self.syncParseLines { doc.refine() } else { scheduleRefine(after: 0) }
        }
        if let storage = textView.textStorage { Theme.apply(doc, to: storage) }
        lastHighlightWasIncremental = false
    }

    func recolorAll() {
        guard let storage = textView.textStorage else { return }
        Theme.apply(syntaxDocument, to: storage)
        updateScopeGuides()
    }

    func noteSyntaxEdit(range: NSRange, replacement: String?) {
        guard let replacement else { return }
        syntax.edits.append((range, replacement))
        syntax.pendingClosers = TypingRules.adjust(syntax.pendingClosers, editing: range, replacementLength: (replacement as NSString).length)
    }

    func rehighlight() {
        let edits = syntax.edits
        syntax.edits = []
        guard Self.incrementalEditing, let doc = syntax.document, doc.language == language, !edits.isEmpty else { return resetSyntax() }
        var dirty: Range<Int>?
        for e in edits {
            let changed = doc.replace(e.range, with: e.replacement)
            dirty = Self.union(dirty.map { Self.carry($0, through: e.range, length: (e.replacement as NSString).length) }, changed)
        }
        guard let storage = textView.textStorage, doc.units.count == storage.length else { return resetSyntax() }
        if doc.needsRefinement {
            if doc.hasParsed && doc.lastRefineDuration < Self.syncRefineBudget {
                if let r = doc.refine() { dirty = Self.union(dirty, r) }
            } else {
                scheduleRefine(after: Self.refineDelay)
            }
        }
        if let dirty { Theme.apply(doc, to: storage, range: dirty) }
        lastHighlightWasIncremental = true
    }

    func scheduleRefine(after delay: TimeInterval) {
        syntax.refineWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refineHighlighting() }
        }
        syntax.refineWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public func refineHighlighting() {
        syntax.refineWork = nil
        guard let doc = syntax.document, let storage = textView.textStorage, doc.units.count == storage.length,
              let r = doc.refine() else { return }
        Theme.apply(doc, to: storage, range: r)
    }

    static func carry(_ r: Range<Int>, through range: NSRange, length: Int) -> Range<Int> {
        let delta = length - range.length
        func map(_ o: Int, _ end: Bool) -> Int {
            if o <= range.location { return o }
            if o >= NSMaxRange(range) { return o + delta }
            return end ? range.location + length : range.location
        }
        return map(r.lowerBound, false)..<max(map(r.lowerBound, false), map(r.upperBound, true))
    }

    static func union(_ a: Range<Int>?, _ b: Range<Int>) -> Range<Int> {
        guard let a else { return b }
        return min(a.lowerBound, b.lowerBound)..<max(a.upperBound, b.upperBound)
    }

    var typingRulesApply: Bool {
        fileURL != nil && textView.isEditable && !textView.hasMarkedText() && textView.multipleRanges.isEmpty
    }

    func typeCharacter(_ s: String) -> Bool {
        guard typingRulesApply, s.utf16.count == 1 else { return false }
        let doc = syntaxDocument
        let sel = textView.selectedRange()
        if sel.length > 0, Placeholders.ranges(in: textView.string).contains(sel) { return false }
        guard let r = TypingRules.insert(s, in: doc, selection: sel, options: Preferences.shared.typingOptions, pendingClosers: syntax.pendingClosers) else { return false }
        if let o = r.steppedOver {
            syntax.pendingClosers.remove(o)
            textView.setSelectedRange(r.edit.selection)
            return true
        }
        textView.typeEdit(r.edit)
        syntax.pendingClosers.formUnion(r.insertedClosers)
        return true
    }

    func didTypeCharacter(_ s: String) {
        guard typingRulesApply, s.utf16.count == 1 else { return }
        let caret = textView.selectedRange()
        guard caret.length == 0,
              let e = TypingRules.reindentAfterTyping(s, in: syntaxDocument, caret: caret.location, options: Preferences.shared.typingOptions) else { return }
        textView.typeEdit(e)
    }

    func typeNewline() -> Bool {
        guard typingRulesApply else { return false }
        textView.typeEdit(TypingRules.newline(in: syntaxDocument, selection: textView.selectedRange(), options: Preferences.shared.typingOptions))
        return true
    }

    func typeTab(backward: Bool) -> Bool {
        guard typingRulesApply else { return false }
        if let e = TypingRules.tab(in: syntaxDocument, selection: textView.selectedRange(), backward: backward, options: Preferences.shared.typingOptions) {
            textView.typeEdit(e)
        }
        return true
    }

    func deleteAutomaticPair() -> Bool {
        guard typingRulesApply,
              let e = TypingRules.deleteBackward(in: syntaxDocument, selection: textView.selectedRange(), pendingClosers: syntax.pendingClosers) else { return false }
        textView.typeEdit(e)
        return true
    }

    func dropClosersOffCaretLine() {
        guard !syntax.pendingClosers.isEmpty, let doc = syntax.document, doc.units.count == (textView.string as NSString).length else { return }
        let line = doc.line(containing: textView.selectedRange().location)
        syntax.pendingClosers = syntax.pendingClosers.filter { $0 <= doc.units.count && doc.line(containing: $0) == line }
    }

    public var pendingAutomaticClosers: Set<Int> { syntax.pendingClosers }

    @objc public func commentSelection(_ sender: Any?) {
        guard let e = TypingRules.toggleComment(in: syntaxDocument, selection: textView.selectedRange()) else { return }
        apply(TextChange(range: e.range, replacement: e.replacement, selection: e.selection), actionName: "Comment Selection")
    }
}

extension SourceTextView {
    func typeEdit(_ e: TypingEdit) {
        if e.range.length > 0 || !e.replacement.isEmpty { insertText(e.replacement, replacementRange: e.range) }
        let len = (string as NSString).length
        let s = NSRange(location: min(e.selection.location, len), length: min(e.selection.length, len - min(e.selection.location, len)))
        setSelectedRange(s)
        scrollRangeToVisible(s)
    }
}
