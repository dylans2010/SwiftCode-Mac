import Foundation
import YcodeSyntax

public struct EditorSelection: Equatable, Hashable, Sendable {
    public var anchor: Int
    public var head: Int

    public init(anchor: Int, head: Int) {
        self.anchor = anchor
        self.head = head
    }

    public init(caret: Int) { self.init(anchor: caret, head: caret) }

    public init(_ r: NSRange) { self.init(anchor: r.location, head: r.location + r.length) }

    public var range: Range<Int> { min(anchor, head)..<max(anchor, head) }
    public var nsRange: NSRange { NSRange(location: range.lowerBound, length: range.count) }
    public var isEmpty: Bool { anchor == head }
}

public final class EditorBuffer {
    public let document: SyntaxDocument
    public private(set) var revision = 0
    public private(set) var textRevision = 0
    public private(set) var selection = EditorSelection(caret: 0)
    public private(set) var markedText = ""
    public private(set) var markedCursor = 0
    public var isReadOnly = false
    public var typingOptions: TypingOptions
    public var onTextChange: ((NSRange, String) -> Void)?

    public private(set) var pendingClosers: Set<Int> = []
    var goalX: CGFloat?

    private struct Edit {
        var location: Int
        var removed: [UInt16]
        var inserted: [UInt16]
    }

    private struct Group {
        var edits: [Edit]
        var selectionBefore: EditorSelection
        var selectionAfter: EditorSelection
        var stateBefore: Int
        var stateAfter: Int
    }

    enum EditKind: Equatable { case typing, deleteBackward, deleteForward, other }

    private var undoStack: [Group] = []
    private var redoStack: [Group] = []
    private var openKind: EditKind?
    private var state = 0
    private var nextState = 1
    private var savedState: Int? = 0
    public var undoLimit = 10_000

    public static let parserLineLimit = 20_000

    public init(text: String, language: SyntaxLanguage, typingOptions: TypingOptions = TypingOptions(), deferParse: Bool = true) {
        var lines = 1
        if language == .swift { for u in text.utf8 where u == 10 { lines += 1 } }
        document = SyntaxDocument(text: text, language: language, usesParser: lines <= Self.parserLineLimit, deferParse: deferParse)
        self.typingOptions = typingOptions
    }

    public var text: String { document.text }
    public var length: Int { document.units.count }
    public var lineCount: Int { document.lineCount }
    public var language: SyntaxLanguage { document.language }
    public var caret: Int { selection.head }
    public var caretLine: Int { document.line(containing: selection.head) }
    public var caretColumn: Int { selection.head - document.lineStart(caretLine) }
    public var hasMarkedText: Bool { !markedText.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var isDirty: Bool { savedState != state }
    public var selectedText: String { string(selection.range) }

    public func string(_ r: Range<Int>) -> String {
        String(decoding: document.units[max(0, r.lowerBound)..<min(length, r.upperBound)], as: UTF16.self)
    }

    public func markSaved() {
        savedState = state
        touch()
    }

    func normalized(_ offset: Int) -> Int {
        let o = min(max(offset, 0), length)
        let u = document.units
        if o > 0, o < u.count, u[o - 1] == 13, u[o] == 10 { return o - 1 }
        return o
    }

    public func setSelection(_ s: EditorSelection) {
        let c = EditorSelection(anchor: normalized(s.anchor), head: normalized(s.head))
        if c != selection { openKind = nil }
        selection = c
        goalX = nil
        dropClosersOffCaretLine()
        touch()
    }

    public func setCaret(_ offset: Int) { setSelection(EditorSelection(caret: offset)) }

    public func extendSelection(to offset: Int) {
        setSelection(EditorSelection(anchor: selection.anchor, head: offset))
    }

    public func selectAll() { setSelection(EditorSelection(anchor: 0, head: length)) }

    private func touch() { revision &+= 1 }

    func apply(_ range: NSRange, _ replacement: String, selection after: EditorSelection, kind: EditKind) {
        guard !isReadOnly else { return }
        let loc = min(max(range.location, 0), length)
        let len = min(max(range.length, 0), length - loc)
        let removed = Array(document.units[loc..<(loc + len)])
        let inserted = Array(replacement.utf16)
        if removed == inserted, after == selection { return }
        let before = selection
        pendingClosers = TypingRules.adjust(pendingClosers, editing: NSRange(location: loc, length: len), replacementLength: inserted.count)
        document.replace(NSRange(location: loc, length: len), with: replacement)
        let edit = Edit(location: loc, removed: removed, inserted: inserted)
        redoStack.removeAll()
        let newState = nextState
        nextState += 1
        if kind != .other, openKind == kind, var last = undoStack.popLast() {
            last.edits.append(edit)
            last.selectionAfter = EditorSelection(anchor: normalized(after.anchor), head: normalized(after.head))
            last.stateAfter = newState
            undoStack.append(last)
        } else {
            undoStack.append(Group(edits: [edit], selectionBefore: before,
                                   selectionAfter: EditorSelection(anchor: normalized(after.anchor), head: normalized(after.head)),
                                   stateBefore: state, stateAfter: newState))
            if undoStack.count > undoLimit { undoStack.removeFirst() }
        }
        state = newState
        openKind = kind == .other ? nil : kind
        selection = EditorSelection(anchor: normalized(after.anchor), head: normalized(after.head))
        goalX = nil
        textChanged(NSRange(location: loc, length: len), replacement)
    }

    private func textChanged(_ range: NSRange, _ replacement: String) {
        textRevision &+= 1
        touch()
        onTextChange?(range, replacement)
    }

    public func replace(_ range: NSRange, with replacement: String, selection after: EditorSelection? = nil) {
        apply(range, replacement, selection: after ?? EditorSelection(caret: range.location + replacement.utf16.count), kind: .other)
    }

    public func replaceAll(_ edits: [(range: NSRange, replacement: String)], selection after: EditorSelection? = nil) {
        guard !isReadOnly, !edits.isEmpty else { return }
        let before = selection
        var made: [Edit] = []
        made.reserveCapacity(edits.count)
        pendingClosers = []
        let stateBefore = state
        let newState = nextState
        nextState += 1
        state = newState
        for e in edits.sorted(by: { $0.range.location > $1.range.location }) {
            let loc = min(max(e.range.location, 0), length)
            let len = min(max(e.range.length, 0), length - loc)
            let r = NSRange(location: loc, length: len)
            made.append(Edit(location: loc, removed: Array(document.units[loc..<(loc + len)]), inserted: Array(e.replacement.utf16)))
            document.replace(r, with: e.replacement)
            textChanged(r, e.replacement)
        }
        let c = after ?? EditorSelection(caret: selection.head)
        let end = EditorSelection(anchor: normalized(c.anchor), head: normalized(c.head))
        redoStack.removeAll()
        undoStack.append(Group(edits: made, selectionBefore: before, selectionAfter: end, stateBefore: stateBefore, stateAfter: newState))
        openKind = nil
        selection = end
        goalX = nil
        touch()
    }

    private var typingRulesApply: Bool { !hasMarkedText }

    private func type(_ e: TypingEdit) {
        apply(e.range, e.replacement, selection: EditorSelection(e.selection), kind: .typing)
    }

    public func insertText(_ s: String) {
        guard !isReadOnly, !s.isEmpty else { return }
        clearMarkedText()
        let startsOver = !selection.isEmpty
        if startsOver { openKind = nil }
        if s == "\n" || s == "\r" || s == "\r\n" { newline(); return }
        if s.utf16.count == 1 {
            if let r = TypingRules.insert(s, in: document, selection: selection.nsRange, options: typingOptions, pendingClosers: pendingClosers) {
                if let o = r.steppedOver {
                    pendingClosers.remove(o)
                    selection = EditorSelection(r.edit.selection)
                    goalX = nil
                    touch()
                } else {
                    type(r.edit)
                    pendingClosers.formUnion(r.insertedClosers)
                }
            } else {
                insertPlain(s)
            }
            if selection.isEmpty, let e = TypingRules.reindentAfterTyping(s, in: document, caret: selection.head, options: typingOptions) {
                type(e)
            }
            return
        }
        insertPlain(s)
    }

    private func insertPlain(_ s: String) {
        let r = selection.nsRange
        apply(r, s, selection: EditorSelection(caret: r.location + s.utf16.count), kind: .typing)
    }

    public func newline() {
        guard !isReadOnly else { return }
        clearMarkedText()
        if !selection.isEmpty { openKind = nil }
        type(TypingRules.newline(in: document, selection: selection.nsRange, options: typingOptions))
        openKind = nil
    }

    public func tab(backward: Bool) {
        guard !isReadOnly else { return }
        clearMarkedText()
        if let e = TypingRules.tab(in: document, selection: selection.nsRange, backward: backward, options: typingOptions) {
            if selection.isEmpty { type(e) } else { apply(e.range, e.replacement, selection: EditorSelection(e.selection), kind: .other) }
        }
    }

    public func toggleComment() {
        guard !isReadOnly, let e = TypingRules.toggleComment(in: document, selection: selection.nsRange) else { return }
        apply(e.range, e.replacement, selection: EditorSelection(e.selection), kind: .other)
    }

    public func paste(_ s: String) {
        guard !isReadOnly, !s.isEmpty else { return }
        clearMarkedText()
        openKind = nil
        let text = s.utf8.contains(13) ? s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") : s
        let r = selection.nsRange
        apply(r, text, selection: EditorSelection(caret: r.location + text.utf16.count), kind: .other)
    }

    public func copyText() -> String? { selection.isEmpty ? nil : selectedText }

    public func cutText() -> String? {
        guard !isReadOnly, !selection.isEmpty else { return nil }
        let t = selectedText
        deleteSelection()
        return t
    }

    public func deleteSelection() {
        guard !selection.isEmpty else { return }
        let r = selection.nsRange
        apply(r, "", selection: EditorSelection(caret: r.location), kind: .other)
    }

    public func deleteBackward(_ unit: EditorMovement = .character) {
        guard !isReadOnly else { return }
        clearMarkedText()
        if !selection.isEmpty { deleteSelection(); return }
        if unit == .character, let e = TypingRules.deleteBackward(in: document, selection: selection.nsRange, pendingClosers: pendingClosers) {
            apply(e.range, e.replacement, selection: EditorSelection(e.selection), kind: .deleteBackward)
            return
        }
        let to = target(of: unit, from: selection.head, forward: false)
        guard to < selection.head else { return }
        apply(NSRange(location: to, length: selection.head - to), "", selection: EditorSelection(caret: to), kind: .deleteBackward)
    }

    public func deleteForward(_ unit: EditorMovement = .character) {
        guard !isReadOnly else { return }
        clearMarkedText()
        if !selection.isEmpty { deleteSelection(); return }
        let to = target(of: unit, from: selection.head, forward: true)
        guard to > selection.head else { return }
        apply(NSRange(location: selection.head, length: to - selection.head), "", selection: EditorSelection(caret: selection.head), kind: .deleteForward)
    }

    public func setMarkedText(_ s: String, cursor: Int) {
        guard !isReadOnly else { return }
        if !s.isEmpty, markedText.isEmpty, !selection.isEmpty { deleteSelection() }
        markedText = s
        markedCursor = min(max(cursor, 0), s.count)
        touch()
    }

    private func clearMarkedText() {
        guard hasMarkedText else { return }
        markedText = ""
        markedCursor = 0
        touch()
    }

    public func breakUndoGroup() { openKind = nil }

    public func undo() {
        guard !isReadOnly else { return }
        clearMarkedText()
        guard let g = undoStack.popLast() else { return }
        state = g.stateBefore
        for e in g.edits.reversed() {
            let replacement = String(decoding: e.removed, as: UTF16.self)
            let r = NSRange(location: e.location, length: e.inserted.count)
            document.replace(r, with: replacement)
            pendingClosers = []
            textChanged(r, replacement)
        }
        redoStack.append(g)
        openKind = nil
        selection = g.selectionBefore
        goalX = nil
        touch()
    }

    public func redo() {
        guard !isReadOnly else { return }
        clearMarkedText()
        guard let g = redoStack.popLast() else { return }
        state = g.stateAfter
        for e in g.edits {
            let replacement = String(decoding: e.inserted, as: UTF16.self)
            let r = NSRange(location: e.location, length: e.removed.count)
            document.replace(r, with: replacement)
            pendingClosers = []
            textChanged(r, replacement)
        }
        undoStack.append(g)
        openKind = nil
        selection = g.selectionAfter
        goalX = nil
        touch()
    }

    private func dropClosersOffCaretLine() {
        guard !pendingClosers.isEmpty else { return }
        let line = document.line(containing: selection.head)
        pendingClosers = pendingClosers.filter { $0 <= length && document.line(containing: $0) == line }
    }

    @discardableResult
    public func refineHighlighting() -> Bool {
        guard document.needsRefinement, document.refine() != nil else { return false }
        touch()
        return true
    }
}
