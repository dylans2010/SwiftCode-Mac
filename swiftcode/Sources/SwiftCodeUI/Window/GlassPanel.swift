import AppKit

@available(macOS 26, *)
@MainActor
final class GlassPanel: NSPanel {
    let controller: NSViewController
    var onClose: (() -> Void)?
    private var closing = false

    init(content controller: NSViewController, cornerRadius: CGFloat) {
        self.controller = controller
        let size = controller.view.frame.size
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.cornerRadius = cornerRadius
        glass.contentView = controller.view
        contentView = glass
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        close()
    }

    override func close() {
        guard !closing else { return }
        closing = true
        parent?.removeChildWindow(self)
        super.close()
        onClose?()
    }

    func show(over window: NSWindow) {
        let f = window.frame
        setFrameOrigin(NSPoint(x: (f.midX - frame.width / 2).rounded(),
                               y: (f.maxY - f.height * 0.18 - frame.height).rounded()))
        window.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }
}
