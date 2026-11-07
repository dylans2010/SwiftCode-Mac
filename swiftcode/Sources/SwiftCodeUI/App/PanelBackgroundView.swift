import AppKit

@MainActor
public final class PanelBackgroundView: NSView {

    public static func paints(in window: NSWindow?) -> Bool {
        guard #available(macOS 26, *), let window else { return true }
        return window.styleMask.contains(.titled)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard Self.paints(in: window) else { return }
        NSColor.windowBackgroundColor.setFill()
        bounds.intersection(dirtyRect).fill()
    }
}
