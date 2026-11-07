import Foundation
import Observation
import SwiftCodeEditorKit
import SwiftCodeIDECore
import SwiftCodeLanguage

public struct QuickHelpPopover: Equatable, Identifiable, Sendable {
    public var id: Int
    public var path: String
    public var offset: Int
    public var document: QuickHelpDocument
    public var text: String
}

public struct RenameRequest: Equatable, Sendable {
    public var path: String
    public var position: Position
    public var range: NSRange
    public var oldName: String
}

@MainActor
@Observable
public final class ShellLanguageFeatures {
    public enum InspectorTab: Int, CaseIterable, Sendable { case file = 0, history = 1, quickHelp = 2 }

    public var inspectorTab: InspectorTab = .file
    public internal(set) var popover: QuickHelpPopover?
    public internal(set) var inspectorHelp: QuickHelpDocument?
    public internal(set) var rename: RenameRequest?
    public internal(set) var renamePreview: RenamePreview?
    public internal(set) var isRenaming = false
    public internal(set) var highlights: [NSRange] = []
    public internal(set) var notice: String?
    @ObservationIgnored var popoverCount = 0
    @ObservationIgnored var noticeTask: Task<Void, Never>?
    @ObservationIgnored var inspectorTask: Task<Void, Never>?
    @ObservationIgnored public internal(set) var diskBackups: [String: String] = [:]
    public internal(set) var caretSymbol: SymbolScanner.Symbol?
    public internal(set) var documentSymbols: [SymbolScanner.Symbol] = []
    @ObservationIgnored var symbolsRevision: (path: String, revision: Int)?
    @ObservationIgnored var symbolTask: Task<Void, Never>?
    @ObservationIgnored public var openExternally: (URL) -> Void = { _ in }

    public init() {}
}

extension WorkspaceShellModel {

    func lspPosition(_ offset: Int, in d: EditorDocument) -> Position {
        let doc = d.buffer.document
        let o = min(max(0, offset), d.buffer.length)
        let line = doc.line(containing: o)
        return Position(line: line, character: o - doc.lineStart(line))
    }

    func offset(of p: Position, in d: EditorDocument) -> Int {
        let doc = d.buffer.document
        guard p.line < doc.lineCount else { return d.buffer.length }
        let r = doc.lineRange(max(0, p.line))
        return min(r.lowerBound + max(0, p.character), r.upperBound)
    }

    func languageTarget(at offset: Int? = nil) -> (url: URL, position: Position, document: EditorDocument)? {
        guard let d = editor, let language = session.language, d.readOnlyReason == nil else { return nil }
        let url = URL(fileURLWithPath: d.path)
        languageUpdates.removeValue(forKey: d.path)?.cancel()
        language.change(url, text: d.buffer.text)
        return (url, lspPosition(offset ?? d.buffer.selection.range.lowerBound, in: d), d)
    }

    func isLanguageCommandEnabled(_ c: ShellCommand) -> Bool {
        guard let d = editor, d.readOnlyReason == nil, session.language != nil else { return false }
        return c != .renameSymbol || !d.buffer.isReadOnly
    }

    func performLanguage(_ c: ShellCommand) {
        switch c {
        case .jumpToDefinition: Task { await jumpToDefinition() }
        case .jumpToOriginalSource: Task { await jumpToOriginalSource() }
        case .showQuickHelp: Task { await showQuickHelp() }
        case .renameSymbol: Task { await beginRename() }
        case .findSelectedSymbol: Task { await findSelectedSymbolInWorkspace() }
        case .showCallHierarchy: Task { await findCallHierarchy() }
        case .showFileInspector: showInspector(.file)
        case .showQuickHelpInspector: showInspector(.quickHelp)
        default: break
        }
    }

    public func showInspector(_ tab: ShellLanguageFeatures.InspectorTab) {
        isInspectorShown = true
        languageFeatures.inspectorTab = tab
        if tab == .quickHelp { refreshQuickHelpInspector() }
    }

    func noteLanguage(_ message: String) {
        let f = languageFeatures
        f.notice = message
        f.noticeTask?.cancel()
        f.noticeTask = Task { [weak f] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            f?.notice = nil
        }
    }

    @discardableResult
    public func jumpToDefinition(at offset: Int? = nil) async -> Bool {
        guard let t = languageTarget(at: offset) else { return false }
        dismissQuickHelp()
        let session = session
        guard let loc = await withLanguageTimeout(nil, { await session.definition(t.url, at: t.position) }) else {
            noteLanguage("No definition found")
            return false
        }
        reveal(loc)
        return true
    }

    @discardableResult
    public func jumpToOriginalSource() async -> Bool {
        guard let t = languageTarget() else { return false }
        let session = session
        guard let loc = await withLanguageTimeout(nil, { await session.declarationOrDefinition(t.url, at: t.position) }) else {
            noteLanguage("No declaration found")
            return false
        }
        reveal(loc)
        return true
    }

    public func reveal(_ loc: Location) {
        let path = loc.url.standardizedFileURL.path
        open(path, line: loc.start.line + 1)
        guard let d = editor, d.path == path else { return }
        let a = offset(of: loc.start, in: d)
        var b = offset(of: loc.end, in: d)
        if b <= a { b = identifierEnd(d.buffer, from: a) }
        d.buffer.setSelection(b > a ? EditorSelection(anchor: a, head: b) : EditorSelection(caret: a))
        refreshQuickHelpInspector()
    }

    @discardableResult
    public func showQuickHelp(at offset: Int? = nil) async -> QuickHelpDocument? {
        guard let t = languageTarget(at: offset) else { return nil }
        let session = session
        guard let hover = await withLanguageTimeout(nil, { await session.hover(t.url, at: t.position) }) else {
            dismissQuickHelp()
            noteLanguage("No Quick Help")
            return nil
        }
        let file = await withLanguageTimeout(nil, { await session.definition(t.url, at: t.position) })?.url.standardizedFileURL.path
        let doc = QuickHelpDocument(hover: hover, file: file)
        let f = languageFeatures
        f.popoverCount += 1
        let start = t.document.buffer.identifierStart(before: offset ?? t.document.buffer.caret)
        f.popover = QuickHelpPopover(id: f.popoverCount, path: t.document.path, offset: start, document: doc, text: QuickHelpFormatter.plain(hover))
        f.inspectorHelp = doc
        return doc
    }

    public func openDocumentation(for name: String) {
        var c = URLComponents(string: "https://developer.apple.com/search/")
        c?.queryItems = [URLQueryItem(name: "q", value: name)]
        if let u = c?.url { languageFeatures.openExternally(u) }
    }

    public func openQuickHelpFile(_ path: String) {
        dismissQuickHelp()
        open(path)
    }

    public func dismissQuickHelp() {
        if languageFeatures.popover != nil { languageFeatures.popover = nil }
    }

    public func caretMoved() {
        dismissQuickHelp()
        scheduleCaretSymbolUpdate()
        guard isInspectorShown, languageFeatures.inspectorTab == .quickHelp else { return }
        refreshQuickHelpInspector(after: 0.35)
    }

    func scheduleCaretSymbolUpdate() {
        let f = languageFeatures
        f.symbolTask?.cancel()
        f.symbolTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.updateCaretSymbol()
        }
    }

    public func updateCaretSymbol() {
        let f = languageFeatures
        guard let d = editor else {
            if f.caretSymbol != nil { f.caretSymbol = nil }
            if !f.documentSymbols.isEmpty { f.documentSymbols = [] }
            f.symbolsRevision = nil
            return
        }
        let b = d.buffer
        if f.symbolsRevision?.path != d.path || f.symbolsRevision?.revision != b.textRevision {
            let lang = SourceTokenizer.Language(fileName: (d.path as NSString).lastPathComponent)
            let symbols = SymbolScanner.symbols(in: b.text, language: lang)
            if symbols != f.documentSymbols { f.documentSymbols = symbols }
            f.symbolsRevision = (d.path, b.textRevision)
        }
        let at = DocumentSymbols.enclosing(f.documentSymbols, line: b.caretLine + 1, text: b.text as NSString, index: LineIndex(b.text))
        if at != f.caretSymbol { f.caretSymbol = at }
    }

    public func openSymbol(_ s: SymbolScanner.Symbol) {
        guard let path = document?.path else { return }
        open(path, line: s.line)
        updateCaretSymbol()
    }

    public func refreshQuickHelpInspector(after delay: Double = 0) {
        let f = languageFeatures
        f.inspectorTask?.cancel()
        f.inspectorTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
            guard !Task.isCancelled, let self, let t = self.languageTarget() else { return }
            let session = self.session
            let hover = await withLanguageTimeout(nil, { await session.hover(t.url, at: t.position) })
            guard !Task.isCancelled else { return }
            guard let hover else { f.inspectorHelp = nil; return }
            let file = await withLanguageTimeout(nil, { await session.definition(t.url, at: t.position) })?.url.standardizedFileURL.path
            guard !Task.isCancelled else { return }
            f.inspectorHelp = QuickHelpDocument(hover: hover, file: file)
        }
    }

    public func quickHelpInspectorSettled() async { await languageFeatures.inspectorTask?.value }

    @discardableResult
    public func beginRename() async -> Bool {
        guard let t = languageTarget(), !t.document.buffer.isReadOnly else { return false }
        dismissQuickHelp()
        let session = session
        guard let r = await withLanguageTimeout(nil, { await session.prepareRename(t.url, at: t.position) }) else {
            noteLanguage("Can't rename this symbol")
            return false
        }
        let d = t.document
        let a = offset(of: r.start, in: d), b = offset(of: r.end, in: d)
        let name = r.placeholder ?? d.buffer.string(a..<max(a, b))
        let highlights = await withLanguageTimeout([], { await session.documentHighlights(t.url, at: t.position) })
        let f = languageFeatures
        f.highlights = highlights.map { h in
            let s = offset(of: h.start, in: d), e = offset(of: h.end, in: d)
            return NSRange(location: s, length: max(0, e - s))
        }
        if f.highlights.isEmpty { f.highlights = [NSRange(location: a, length: max(0, b - a))] }
        f.renamePreview = nil
        f.rename = RenameRequest(path: d.path, position: t.position, range: NSRange(location: a, length: max(0, b - a)), oldName: name)
        return true
    }

    @discardableResult
    public func commitRename(to newName: String) async -> WorkspaceEdit? {
        let f = languageFeatures
        guard let r = f.rename else { return nil }
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != r.oldName else {
            cancelRename()
            return nil
        }
        f.isRenaming = true
        defer { f.isRenaming = false }
        if let d = openDocuments[r.path], let language = session.language {
            languageUpdates.removeValue(forKey: r.path)?.cancel()
            language.change(URL(fileURLWithPath: r.path), text: d.buffer.text)
        }
        let session = session
        guard let edit = await withLanguageTimeout(nil, { await session.rename(URL(fileURLWithPath: r.path), at: r.position, to: name) }) else {
            noteLanguage("Rename failed")
            cancelRename()
            return nil
        }
        if edit.files.count > 1 {
            f.renamePreview = RenamePreview(edit: edit, oldName: r.oldName, newName: name) { [weak self] url in self?.currentText(of: url.standardizedFileURL.path) }
        } else {
            applyWorkspaceEdit(edit)
            cancelRename()
        }
        return edit
    }

    @discardableResult
    public func applyRenamePreview() -> [String] {
        guard let p = languageFeatures.renamePreview else { return [] }
        let changed = applyWorkspaceEdit(p.edit)
        cancelRename()
        return changed
    }

    public func cancelRename() {
        let f = languageFeatures
        f.rename = nil
        f.renamePreview = nil
        f.highlights = []
        focusEditor()
    }

    public func currentText(of path: String) -> String? {
        openDocuments[path]?.buffer.text ?? (try? String(contentsOfFile: path, encoding: .utf8))
    }

    @discardableResult
    public func applyWorkspaceEdit(_ edit: WorkspaceEdit) -> [String] {
        var changed: [String] = []
        for url in edit.files {
            let edits = edit.changes[url] ?? []
            guard !edits.isEmpty else { continue }
            let path = url.standardizedFileURL.path
            if let d = openDocuments[path] {
                guard !d.buffer.isReadOnly else { continue }
                let ranges = TextEditApplication.ranges(edits, in: d.buffer.text)
                d.buffer.replaceAll(ranges.map { ($0.range, $0.newText) })
                syncEdited(d)
            } else {
                guard let old = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                languageFeatures.diskBackups[path] = old
                do {
                    try TextEditApplication.apply(edits, to: old).write(toFile: path, atomically: true, encoding: .utf8)
                } catch {
                    continue
                }
                session.language?.fileChangedOnDisk(URL(fileURLWithPath: path))
            }
            changed.append(path)
        }
        return changed
    }

    @discardableResult
    public func findSelectedSymbolInWorkspace() async -> Int {
        guard let t = languageTarget() else { return 0 }
        let session = session
        let refs = await withLanguageTimeout([], timeout: 15, { await session.references(t.url, at: t.position) })
        let b = t.document.buffer
        let caret = b.caret
        let name = b.string(b.identifierStart(before: caret)..<identifierEnd(b, from: caret))
        guard !refs.isEmpty else {
            noteLanguage("No references found")
            return 0
        }
        let results = SymbolResults.fileResults(refs) { [weak self] in self?.currentText(of: $0) }
        let count = results.reduce(0) { $0 + $1.matches.count }
        showFindResults(query: name, title: SymbolResults.referencesTitle(name, count: count), results)
        return count
    }

    @discardableResult
    public func findCallHierarchy() async -> Int {
        guard let t = languageTarget() else { return 0 }
        let session = session
        guard let tree = await withLanguageTimeout(nil, timeout: 15, { await session.callerTree(t.url, at: t.position) }) else {
            noteLanguage("Not a callable symbol")
            return 0
        }
        let b = t.document.buffer
        var name = b.string(b.identifierStart(before: b.caret)..<identifierEnd(b, from: b.caret))
        if name.isEmpty { name = tree.name }
        showFindResults(query: name, title: SymbolResults.callersTitle(name), [])
        callHierarchy.onOpen = { [weak self] path, line in self?.open(path, line: line) }
        callHierarchy.show(tree)
        return tree.callerCount
    }

    private func identifierEnd(_ b: EditorBuffer, from offset: Int) -> Int {
        let u = b.document.units
        var e = offset
        while e < u.count, let s = Unicode.Scalar(u[e]), CharacterSet.alphanumerics.contains(s) || s == "_" { e += 1 }
        return e
    }
}

@MainActor
func withLanguageTimeout<T: Sendable>(_ fallback: T, timeout: Double = 5, _ work: @escaping @MainActor () async -> T) async -> T {
    await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
        let once = LanguageResumeOnce(cont)
        Task { @MainActor in once.resume(await work()) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
            once.resume(fallback)
        }
    }
}

@MainActor
private final class LanguageResumeOnce<T: Sendable> {
    private var cont: CheckedContinuation<T, Never>?
    init(_ c: CheckedContinuation<T, Never>) { cont = c }
    func resume(_ v: T) {
        cont?.resume(returning: v)
        cont = nil
    }
}
