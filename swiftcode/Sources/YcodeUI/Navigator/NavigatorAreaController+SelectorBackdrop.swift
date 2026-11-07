import AppKit
import YcodeIDECore

extension NavigatorAreaController {
    func installSelectorBackdrop(in root: NSView) {
        let backdrop = selectorBackdrop
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(backdrop, positioned: .below, relativeTo: selectorGlass)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: selectorGlass.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: selectorGlass.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: selectorGlass.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: selectorGlass.trailingAnchor),
        ])
        backdrop.sources = { [weak self] in self.map { [$0.scrollView] } ?? [] }
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        selectorBackdropObserver.value = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip,
                                                                               queue: .main) { [weak backdrop] _ in
            MainActor.assumeIsolated { backdrop?.needsDisplay = true }
        }
    }
}

final class ObserverBox {
    var value: NSObjectProtocol?
    deinit { if let value { NotificationCenter.default.removeObserver(value) } }
}

final class SelectorBackdropView: NSView {
    var sources: () -> [NSView] = { [] }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var shape: NSBezierPath {
        let r = bounds.height / 2
        return NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let background = NSColor.textBackgroundColor
        background.setFill()
        bounds.fill()
        if let image = StructureBlur.image(of: bounds, in: self, sources: sources(), background: background) {
            StructureBlur.draw(image, for: bounds, in: self, share: CGFloat(BarBlur.selectorShare))
        }
        NSColor.labelColor.withAlphaComponent(CGFloat(BarBlur.selectorFill)).setFill()
        bounds.fill(using: .sourceOver)
        NSGraphicsContext.restoreGraphicsState()
    }
}
