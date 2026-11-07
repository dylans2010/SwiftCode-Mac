import AppKit
import YcodeIDECore

extension WorkspaceWindowController {
    var shownDocumentURL: URL? { editor.fileURL ?? editor.auxiliaryFile ?? imageViewerBox.pending?.url }

    @discardableResult
    public func handleOpenRequest(_ url: URL) -> Bool {
        let key = OpenRequestKey.path(url)
        if let shown = shownDocumentURL, OpenRequestKey.path(shown) == key { return false }
        open(path: session.model.root.projectPath(forOpening: url) ?? url.path, line: nil)
        return true
    }
}
