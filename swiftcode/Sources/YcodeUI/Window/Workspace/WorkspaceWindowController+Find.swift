import AppKit
import YcodeIDECore
import YcodeLanguage

extension WorkspaceWindowController {
    func installFindHooks() {
        navigator.findBuffers = { [weak self] in self?.unsavedFindBuffers() ?? [:] }
        navigator.findOpenFiles = { [weak self] in self?.openFindFiles() ?? [] }
        navigator.findSemantic = { [weak self] q in await SemanticFind.run(q, service: self?.session.language?.client) }
        navigator.findReplaceIO = findReplaceIO
        navigator.findPerformReplace = { [weak self] plan in self?.performWorkspaceReplace(plan) ?? plan.apply(.disk) }
        navigator.onOpenFindMatch = { [weak self] path, m in self?.openFindMatch(path, m) }
    }

    func findEditor(for path: String) -> SourceEditorController? {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return allEditors.first { $0.fileURL?.standardizedFileURL.path == p }
    }

    func unsavedFindBuffers() -> [String: String] {
        var out: [String: String] = [:]
        for e in allEditors where e.isDirty {
            guard let url = e.fileURL else { continue }
            out[url.path] = e.text
            out[url.standardizedFileURL.path] = e.text
        }
        return out
    }

    func openFindFiles() -> [String] {
        var seen = Set<String>()
        return allEditors.compactMap { $0.fileURL?.path }.filter { seen.insert($0).inserted }
    }

    var findReplaceIO: ReplaceIO {
        ReplaceIO(read: { [weak self] path in
            MainActor.assumeIsolated {
                if let e = self?.findEditor(for: path) { return e.text }
                return try? String(contentsOfFile: path, encoding: .utf8)
            }
        }, write: { [weak self] path, text in
            MainActor.assumeIsolated {
                guard let self else { return false }
                if let e = self.findEditor(for: path) { return e.replaceText(with: text, actionName: "Replace") }
                guard (try? text.write(toFile: path, atomically: true, encoding: .utf8)) != nil else { return false }
                self.session.language?.fileChangedOnDisk(URL(fileURLWithPath: path))
                return true
            }
        })
    }

    func performWorkspaceReplace(_ plan: ReplacePlan) -> ReplaceTransaction {
        let um = window?.undoManager
        um?.beginUndoGrouping()
        let t = plan.apply(findReplaceIO)
        var disk = t
        disk.changes = t.changes.filter { findEditor(for: $0.path) == nil }
        if !disk.changes.isEmpty { registerDiskReplace(disk, toOriginal: true) }
        um?.setActionName(t.title)
        um?.endUndoGrouping()
        return t
    }

    private func registerDiskReplace(_ t: ReplaceTransaction, toOriginal: Bool) {
        window?.undoManager?.registerUndo(withTarget: self) { wc in
            MainActor.assumeIsolated {
                _ = ReplaceHistory.restore(t, wc.findReplaceIO, toOriginal: toOriginal)
                wc.registerDiskReplace(t, toOriginal: !toOriginal)
                wc.navigator.rerunAfterReplace()
            }
        }
    }

    func openFindMatch(_ path: String, _ m: WorkspaceSearch.Match) {
        openFromNavigator(path: path, line: m.line)
        if editor.fileURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path { editor.selectFindMatch(m.range) }
    }

    func showFindNavigator() {
        navigatorItem.isCollapsed = false
        navigator.select(3)
    }

    var selectedSourceText: String? {
        guard editor.fileURL != nil else { return nil }
        let sel = editor.textView.selectedRange()
        return sel.length > 0 ? (editor.text as NSString).substring(with: sel) : nil
    }

    @objc public func findAndReplaceInWorkspace(_ sender: Any?) {
        showFindNavigator()
        navigator.setFindOptions(mode: .replace)
        if let q = selectedSourceText { navigator.find(q) }
        window?.makeFirstResponder(navigator.findField)
    }

    @objc public func findNextInWorkspace(_ sender: Any?) { navigator.stepFindResult(forward: true) }
    @objc public func findPreviousInWorkspace(_ sender: Any?) { navigator.stepFindResult(forward: false) }

    @objc public func findSelectedTextInWorkspace(_ sender: Any?) { findSelection(match: .containing) }
    @objc public func findSelectedWordsInWorkspace(_ sender: Any?) { findSelection(match: .matchingWord) }

    func findSelection(match: FindQuery.Match) {
        guard let q = selectedSourceText else { NSSound.beep(); return }
        showFindNavigator()
        navigator.setFindOptions(kind: .text, match: match.rawValue)
        navigator.noteRecentSearch(q)
        navigator.find(q)
    }

    @objc public func findAncestorTypes(_ sender: Any?) { Task { await findTypes(.ancestorTypes) } }
    @objc public func findDescendentTypes(_ sender: Any?) { Task { await findTypes(.descendentTypes) } }
    @objc public func findConformingTypes(_ sender: Any?) { Task { await findTypes(.conformingTypes) } }

    @discardableResult
    public func findTypes(_ kind: FindQuery.Kind) async -> SemanticFind.Result? {
        guard let (url, p) = caretLocation else { NSSound.beep(); return nil }
        try? editor.save()
        let seed = SemanticFind.Seed(url: url, position: p, name: symbolName(at: editor.textView.selectedRange().location))
        let r = await SemanticFind.run(kind, at: seed, service: session.language?.client)
        showFindNavigator()
        navigator.showSemanticResult(r)
        return r
    }

    func validateFindMenuItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(findNextInWorkspace(_:)), #selector(findPreviousInWorkspace(_:)): return navigator.findModel.matchCount > 0
        case #selector(findSelectedTextInWorkspace(_:)), #selector(findSelectedWordsInWorkspace(_:)): return selectedSourceText != nil
        case #selector(findAncestorTypes(_:)), #selector(findDescendentTypes(_:)), #selector(findConformingTypes(_:)):
            return editor.fileURL != nil && editor.auxiliary == nil && session.language != nil
        default: return nil
        }
    }
}
