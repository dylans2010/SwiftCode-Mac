import AppKit
import YcodeIDECore

extension WorkspaceWindowController {
    func extendEditorUnderToolbar(column: NSView, centerColumn: NSView) {
        let v = editorArea.view
        guard GlassBars.enabled else {
            v.topAnchor.constraint(equalTo: column.topAnchor).isActive = true
            return
        }
        v.topAnchor.constraint(equalTo: centerColumn.topAnchor).isActive = true
        _ = column
        (centerColumn as? CenterColumnView)?.onLayout = { [weak self] col in self?.followToolbarBand(col.safeAreaInsets.top) }
    }

    private func followToolbarBand(_ top: CGFloat) {
        let v = editorArea.view
        var a = v.superview
        while let x = a, !(x is CenterColumnView) {
            if x.clipsToBounds { x.clipsToBounds = false }
            a = x.superview
        }
        var insets = v.additionalSafeAreaInsets
        guard abs(insets.top - top) > 0.25 else { return }
        insets.top = top
        v.additionalSafeAreaInsets = insets
    }

    public var editorOverhang: CGFloat {
        guard isWindowLoaded, let content = window?.contentView else { return 0 }
        let editor = editorArea.view.convert(editorArea.view.bounds, to: content)
        let split = centerSplit.view.convert(centerSplit.view.bounds, to: content)
        return content.isFlipped ? split.minY - editor.minY : editor.maxY - split.maxY
    }
}

final class CenterColumnView: NSView {
    var onLayout: ((NSView) -> Void)?
    override func layout() {
        super.layout()
        onLayout?(self)
    }
}
