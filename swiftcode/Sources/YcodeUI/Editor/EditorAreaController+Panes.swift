import AppKit

extension EditorAreaController {
    public func updatePaneChrome() {
        guard isViewLoaded else { return }
        let t = tab
        let split = t.editors.count > 1
        let panes = t.editors.filter { $0 !== t.assistant }.count
        for (i, e) in t.editors.enumerated() {
            e.jumpBar.isActivePane = !split || i == t.focused
            let closable = panes > 1 && t.assistant !== e
            e.jumpBar.showsPaneCloseButton = closable
            if closable { e.jumpBar.onClose = { [weak self, weak e] in if let e { self?.closePane(e) } } }
        }
    }

    public func closePane(_ e: SourceEditorController) {
        focus(e)
        closeFocusedEditor()
    }
}
