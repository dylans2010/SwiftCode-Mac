import AppKit
import YcodeIDECore
import YcodeLanguage

extension WorkspaceWindowController {
    @objc public func showEditorOnly(_ sender: Any?) {
        if canvasAuto.modeOn || canvas != nil { setCanvasMode(false) }
        if editorArea.tab.assistant != nil { toggleAssistant(nil) }
        if editor.isShowingComparison { editor.hideComparison() }
        editor.hideInlineComparison()
        updateToolbarState()
    }

    @objc public func showInlineIssues(_ sender: Any?) { for e in editorArea.allEditors { e.showsInlineIssues = true } }
    @objc public func hideInlineIssues(_ sender: Any?) { for e in editorArea.allEditors { e.showsInlineIssues = false } }

    @objc public func toggleWrapLines(_ sender: Any?) { Preferences.shared.wrapLines.toggle() }
    @objc public func toggleInvisibles(_ sender: Any?) { Preferences.shared.showInvisibles.toggle() }
    @objc public func toggleCodeCoverage(_ sender: Any?) {
        Preferences.shared.showCodeCoverage.toggle()
        refreshCodeCoverage()
    }

    func refreshCodeCoverage() {
        let counts = Preferences.shared.showCodeCoverage ? editor.fileURL.flatMap { session.coverageLineCounts(file: $0.path) } : nil
        editor.setCoverage(WorkspaceSession.coverageMarks(counts), shown: Preferences.shared.showCodeCoverage)
    }

    @objc public func toggleAuthors(_ sender: Any?) { editor.showsAuthors.toggle() }

    @objc public func showLastChangeForLine(_ sender: Any?) {
        guard let url = editor.fileURL else { return }
        let line = editor.currentLine, text = editor.isDirty ? editor.text : nil
        Task {
            if await !sourceControl.showLastChange(path: url.path, line: line, contents: text) { NSSound.beep() }
        }
    }

    @objc public func toggleScopeGuides(_ sender: Any?) {
        let p = Preferences.shared
        p.scopeGuides = p.scopeGuides == .none ? .lines : .none
    }

    @discardableResult
    @objc public func performRefactorItem(_ sender: Any?) -> Bool {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? Int) ?? -1
        guard let i = RefactorCatalog.actionIndex(forItem: tag, in: cachedCodeActions) else { NSSound.beep(); return false }
        let a = cachedCodeActions[i]
        Task { await perform(a) }
        return true
    }

    func validateEditorMenuItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(performRefactorItem(_:)):
            return RefactorCatalog.actionIndex(forItem: item.tag, in: cachedCodeActions) != nil
        case #selector(toggleCanvas(_:)): item.state = canvasAuto.modeOn ? .on : .off
        case #selector(toggleAssistant(_:)): item.state = editorArea.tab.assistant != nil ? .on : .off
        case #selector(toggleComparison(_:)): item.state = editor.isShowingComparison || editor.isShowingInlineComparison ? .on : .off
        case NSSelectorFromString("toggleMinimap:"): item.state = editor.showsMinimap ? .on : .off
        case #selector(toggleWrapLines(_:)): item.state = Preferences.shared.wrapLines ? .on : .off
        case #selector(toggleInvisibles(_:)): item.state = Preferences.shared.showInvisibles ? .on : .off
        case #selector(toggleCodeCoverage(_:)): item.state = Preferences.shared.showCodeCoverage ? .on : .off
        case #selector(toggleAuthors(_:)):
            item.state = editor.showsAuthors ? .on : .off
            return hasSourceFile && sourceControl.snapshot.repository != nil
        case #selector(showLastChangeForLine(_:)): return hasSourceFile && sourceControl.snapshot.repository != nil
        case #selector(toggleScopeGuides(_:)): item.state = Preferences.shared.scopeGuides != .none ? .on : .off
        case NSSelectorFromString("toggleLineNumbers:"): item.state = editor.showsLineNumbers ? .on : .off
        case #selector(showInlineComparison(_:)): item.state = editor.comparisonStyle == .inline ? .on : .off
        case #selector(showSideBySideComparison(_:)): item.state = editor.comparisonStyle == .sideBySide ? .on : .off
        case #selector(showInlineIssues(_:)): return !editor.showsInlineIssues
        case #selector(hideInlineIssues(_:)): return editor.showsInlineIssues
        default: return validateEditorCommandItem(item)
        }
        return true
    }
}
