import Foundation
import Observation
import YcodeEditorKit
import YcodeIDECore
import YcodeSyntax

public struct EditorLineIssue: Equatable, Sendable {
    public var isError: Bool
    public var message: String
    public init(isError: Bool, message: String) {
        self.isError = isError
        self.message = message
    }
}

public enum SaveAlert: Equatable, Identifiable, Sendable {
    case conflict(path: String, change: EditorDocument.DiskChange)
    case failed(path: String, message: String)

    public var id: String {
        switch self {
        case .conflict(let p, _): "conflict " + p
        case .failed(let p, let m): "failed " + p + m
        }
    }

    public var title: String {
        switch self {
        case .conflict(let p, .modified): "“\((p as NSString).lastPathComponent)” changed on disk"
        case .conflict(let p, .deleted): "“\((p as NSString).lastPathComponent)” was deleted"
        case .failed(let p, _): "Could not save “\((p as NSString).lastPathComponent)”"
        }
    }

    public var message: String {
        switch self {
        case .conflict(_, .modified): "Another program changed the file since it was opened here. Your edits have not been written."
        case .conflict(_, .deleted): "The file no longer exists on disk. Your edits have not been written."
        case .failed(_, let m): "\(m) Your edits are still in the editor."
        }
    }
}

extension WorkspaceShellModel {
    public var hasUnsavedChanges: Bool { !editedPaths.isEmpty }

    func showFile(_ path: String) {
        if showStructured(path) { previewCanvasFocusChanged(); return }
        if let d = openDocuments[path] {
            editor = d
            document = SourceDocument(path: path, language: d.buffer.language, lines: [])
        } else {
            let opened = EditorDocument.open(path: path, typingOptions: Preferences.shared.typingOptions)
            if let d = opened.document {
                openDocuments[path] = d
                d.buffer.onTextChange = { [weak self, weak d] _, _ in
                    guard let self, let d else { return }
                    self.documentChanged(d)
                }
                editor = d
                document = SourceDocument(path: path, language: d.buffer.language, lines: [])
                restoreRecoveredText(d)
                if d.readOnlyReason == nil { session.language?.open(URL(fileURLWithPath: path), text: d.buffer.text) }
            } else {
                editor = nil
                document = SourceDocument(path: path, language: SyntaxLanguage(fileName: (path as NSString).lastPathComponent), lines: [],
                                          message: opened.message)
            }
        }
        findBar.documentChanged(to: editor)
        syncEditorIssues()
        sourceControl.noteText(of: path)
        previewCanvasFocusChanged()
    }

    func documentChanged(_ d: EditorDocument) {
        syncEdited(d)
        if d === editor { sourceControl.noteText(of: d.path) }
        session.noteFileEdited(d.path)
        if d === editor { findBar.textChanged() }
        scheduleRecoveryCopy()
        scheduleLanguageUpdate(d)
        previewCanvasEdited(d)
    }

    public func startLanguageService() {
        guard languageStart == nil else { return }
        languageStart = Task { [weak self] in
            guard let self else { return }
            await self.session.startLanguageService()
            guard let language = self.session.language else { return }
            for d in self.openDocuments.values where d.readOnlyReason == nil {
                language.open(URL(fileURLWithPath: d.path), text: d.buffer.text)
            }
        }
    }

    public func stopLanguageService() {
        for t in languageUpdates.values { t.cancel() }
        languageUpdates = [:]
        languageStart?.cancel()
        guard let language = session.language else { return }
        Task { await language.stop() }
    }

    private func scheduleLanguageUpdate(_ d: EditorDocument) {
        guard session.language != nil else { return }
        let path = d.path
        languageUpdates[path]?.cancel()
        languageUpdates[path] = Task { [weak self, weak d] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self, let d else { return }
            self.languageUpdates[path] = nil
            self.session.language?.change(URL(fileURLWithPath: path), text: d.buffer.text)
        }
    }

    private func restoreRecoveredText(_ d: EditorDocument) {
        guard d.readOnlyReason == nil, let e = recovery.entry(for: d.path) else { return }
        guard e.text != d.buffer.text else {
            recovery.discard(path: d.path)
            return
        }
        d.restore(text: e.text)
        d.buffer.breakUndoGroup()
        syncEdited(d)
        recoveredPaths.insert(d.path)
    }

    private func scheduleRecoveryCopy() {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.writeRecoveryCopies()
        }
    }

    public func writeRecoveryCopies() {
        for d in openDocuments.values {
            if d.isDirty {
                recovery.keep(path: d.path, baseHash: d.stamp?.contentHash ?? 0, text: d.buffer.text)
            } else {
                recovery.discard(path: d.path)
            }
        }
    }

    public func discardRecoveredText() {
        guard let d = editor else { return }
        recoveredPaths.remove(d.path)
        recovery.discard(path: d.path)
        _ = d.reloadFromDisk()
        syncEdited(d)
    }

    public func discardAllRecoveryCopies() {
        recoveryTask?.cancel()
        for p in editedPaths { recovery.discard(path: p) }
    }

    func syncEdited(_ d: EditorDocument) {
        if d.isDirty {
            if !editedPaths.contains(d.path) { editedPaths.insert(d.path) }
        } else if editedPaths.contains(d.path) {
            editedPaths.remove(d.path)
        }
    }

    public var editedDocumentNames: [String] { editedPaths.sorted().map { ($0 as NSString).lastPathComponent } }

    @discardableResult
    public func saveCurrent() -> Bool {
        guard let d = editor else { return true }
        return save(d, overwrite: false)
    }

    private func save(_ d: EditorDocument, overwrite: Bool) -> Bool {
        let r = d.save(overwrite: overwrite)
        syncEdited(d)
        switch r {
        case .saved:
            recovery.discard(path: d.path)
            recoveredPaths.remove(d.path)
            sourceControl.refresh()
            session.language?.saved(URL(fileURLWithPath: d.path))
            return true
        case .conflict(let c):
            saveAlert = .conflict(path: d.path, change: c)
            return false
        case .failed(let m):
            saveAlert = .failed(path: d.path, message: m)
            return false
        }
    }

    @discardableResult
    public func saveAll() -> Bool {
        for p in editedPaths.sorted() {
            guard let d = openDocuments[p] else { continue }
            if !save(d, overwrite: false) {
                return false
            }
        }
        return true
    }

    func saveAllBeforeBuilding() -> Bool { saveAll() }

    public func overwriteOnConflict() {
        guard case .conflict(let path, _)? = saveAlert, let d = openDocuments[path] else { return }
        saveAlert = nil
        _ = save(d, overwrite: true)
    }

    public func revertToSaved() {
        guard let d = editor else { return }
        if !d.reloadFromDisk() {
            saveAlert = .failed(path: d.path, message: "The file can't be read as text.")
        } else {
            recovery.discard(path: d.path)
            recoveredPaths.remove(d.path)
        }
        syncEdited(d)
    }

    public func closeCurrentDocument(discard: Bool = false) {
        guard let path = document?.path else { return }
        if let d = editor, d.isDirty, !discard {
            closeDocumentPrompt = true
            return
        }
        if editor?.isDirty == true { recovery.discard(path: path) }
        editedPaths.remove(path)
        recoveredPaths.remove(path)
        openDocuments[path] = nil
        languageUpdates.removeValue(forKey: path)?.cancel()
        session.language?.close(URL(fileURLWithPath: path))
        editor = nil
        document = nil
        structuredEditor = nil
        findBar.documentChanged(to: nil)
        syncEditorIssues()
        sourceControl.noteText(of: nil)
        previewCanvasFocusChanged()
    }

    public func checkOpenFilesOnDisk() {
        for d in openDocuments.values {
            if d.checkDisk() == .modified, !d.isDirty {
                _ = d.reloadFromDisk()
                syncEdited(d)
            }
        }
    }

    public func reloadFromDisk() {
        guard let d = editor else { return }
        _ = d.reloadFromDisk()
        syncEdited(d)
    }

    public func keepEditorVersion() {
        guard let d = editor else { return }
        d.keepBufferOverDisk()
        syncEdited(d)
    }

    public func preferencesChanged() {
        let options = Preferences.shared.typingOptions
        for d in openDocuments.values { d.buffer.typingOptions = options }
    }

    func performEditing(_ c: ShellCommand) {
        switch c {
        case .save: saveCurrent()
        case .saveAll: saveAll()
        case .closeDocument: closeCurrentDocument()
        case .revertToSaved: revertToSaved()
        case .find: showFindBar(replace: false)
        case .findAndReplace: showFindBar(replace: true)
        case .findNext: findBar.step(forward: true)
        case .findPrevious: findBar.step(forward: false)
        case .useSelectionForFind:
            if let b = editor?.buffer, !b.selection.isEmpty {
                findBar.query = b.selectedText
                findBar.refresh()
            }
        case .jumpToLine: isJumpToLineShown = true
        case .commentSelection: editor?.buffer.toggleComment()
        case .shiftLeft: shift(right: false)
        case .shiftRight: shift(right: true)
        case .moveLineUp: moveLines(up: true)
        case .moveLineDown: moveLines(up: false)
        default: break
        }
    }

    func showFindBar(replace: Bool) {
        findBar.isShown = true
        findBar.showsReplace = replace
        if let b = editor?.buffer, !b.selection.isEmpty, !b.selectedText.contains("\n") { findBar.query = b.selectedText }
        findBar.refresh()
        findBar.focusCount += 1
    }

    private func apply(_ change: TextChange?) {
        guard let change, let b = editor?.buffer else { return }
        b.replace(change.range, with: change.replacement, selection: EditorSelection(change.selection))
    }

    private func shift(right: Bool) {
        guard let b = editor?.buffer else { return }
        let o = b.typingOptions.indent
        let unit = o.usesTabs ? "\t" : String(repeating: " ", count: o.indentWidth)
        apply(TextCommands.shift(in: b.text, selection: b.selection.nsRange, right: right, unit: unit, indentWidth: o.indentWidth))
    }

    private func moveLines(up: Bool) {
        guard let b = editor?.buffer else { return }
        apply(TextCommands.moveLines(in: b.text, selection: b.selection.nsRange, up: up))
    }

    public func focusEditor() { editorFocusCount += 1 }

    @discardableResult
    public func jumpToLine(_ text: String) -> Bool {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", maxSplits: 1)
        guard let b = editor?.buffer, let first = parts.first, let line = Int(first), line > 0 else { return false }
        b.selectLine(number: line)
        if parts.count == 2, let col = Int(parts[1]), col > 0 {
            let r = b.document.lineRange(b.caretLine)
            b.setCaret(min(r.lowerBound + col - 1, r.upperBound))
        }
        isJumpToLineShown = false
        let caret = b.caret
        open(document?.path ?? "", line: b.caretLine + 1)
        b.setCaret(caret)
        return true
    }
}

@MainActor
@Observable
public final class EditorFindBar {
    public var isShown = false {
        didSet { if oldValue != isShown, !isShown { showMatchesOff() } }
    }
    public var showsReplace = false
    public var query = ""
    public var replacement = ""
    public var options = WorkspaceSearch.Options()
    public private(set) var matches: [NSRange] = []
    public private(set) var current: Int?
    public internal(set) var focusCount = 0
    @ObservationIgnored private weak var editor: EditorDocument?
    @ObservationIgnored private var find = EditorFind()
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init() {}

    public var countText: String {
        guard !query.isEmpty else { return "" }
        guard let current, !matches.isEmpty else { return "No matches" }
        return "\(current + 1) of \(matches.count)"
    }

    func documentChanged(to d: EditorDocument?) {
        editor = d
        if isShown { refresh() } else { matches = []; current = nil }
    }

    private func showMatchesOff() {
        matches = []
        current = nil
        pending?.cancel()
    }

    func textChanged() {
        guard isShown else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.search(selectingCurrent: false)
        }
    }

    public func refresh() { search(selectingCurrent: true) }

    private func search(selectingCurrent: Bool) {
        guard let b = editor?.buffer else {
            matches = []
            current = nil
            return
        }
        find.query = query
        find.replacement = replacement
        find.options = options
        find.update(text: b.text, from: b.selection.range.lowerBound)
        if matches != find.matches { matches = find.matches }
        if current != find.current { current = find.current }
        if selectingCurrent { selectCurrent() }
    }

    private func selectCurrent() {
        guard let r = find.currentRange, let b = editor?.buffer else { return }
        b.setSelection(EditorSelection(r))
    }

    public func step(forward: Bool) {
        if !isShown { isShown = true }
        guard let b = editor?.buffer else { return }
        if query != find.query || matches.isEmpty { search(selectingCurrent: false) }
        if let r = find.currentRange, EditorSelection(r) == b.selection {
            find.step(forward)
        } else if !forward, !matches.isEmpty {
            let at = b.selection.range.lowerBound
            find.update(text: b.text, from: at)
            find.step(false)
        } else {
            find.update(text: b.text, from: b.selection.range.upperBound)
        }
        matches = find.matches
        current = find.current
        selectCurrent()
    }

    public func replaceCurrent() {
        guard let b = editor?.buffer, !b.isReadOnly else { return }
        find.replacement = replacement
        if find.query != query || find.options != options { search(selectingCurrent: true) }
        guard let r = find.currentRange else { return }
        let text = find.replacementText(in: b.text, range: r)
        b.replace(r, with: text)
        find.update(text: b.text, from: r.location + text.utf16.count)
        matches = find.matches
        current = find.current
        selectCurrent()
    }

    @discardableResult
    public func replaceAll() -> Int {
        guard let d = editor, !d.buffer.isReadOnly else { return 0 }
        find.query = query
        find.replacement = replacement
        find.options = options
        let (text, count) = find.replacingAll(in: d.buffer.text)
        guard count > 0 else { return 0 }
        d.restore(text: text)
        search(selectingCurrent: false)
        return count
    }
}
