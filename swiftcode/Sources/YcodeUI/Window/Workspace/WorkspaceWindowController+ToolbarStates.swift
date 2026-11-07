import AppKit
import YcodeIDECore

extension WorkspaceWindowController {
    static var togglePillColor: NSColor { .quaternaryLabelColor }

    func styleToolbarToggles() {
        for c in [toolbarControls.leftPanes, toolbarControls.editorModes] {
            c.selectedSegmentBezelColor = Self.togglePillColor
        }
    }

    func updateToolbarAvailability() {
        for item in window?.toolbar?.items ?? [] {
            guard let c = item.view as? NSSegmentedControl, c.segmentCount >= 2 else { continue }
            switch item.itemIdentifier {
            case Self.runID:
                c.setEnabled(true, forSegment: 0)
                c.setEnabled(session.isBusy, forSegment: 1)
            case Self.historyID:
                c.setEnabled(editor.history.canGoBack, forSegment: 0)
                c.setEnabled(editor.history.canGoForward, forSegment: 1)
            default: break
            }
        }
    }
}
