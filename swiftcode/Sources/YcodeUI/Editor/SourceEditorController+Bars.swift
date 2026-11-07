import AppKit

extension SourceEditorController {
    func contentMovedUnderBars() {
        bandBackdrop.needsDisplay = true
        onContentMovedUnderBars?()
    }
}
