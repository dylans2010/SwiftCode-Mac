import AppKit

@MainActor
enum GlassBars {
    static var enabled: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
    static let height: CGFloat = 30
    static let topOffset: CGFloat = -1

    static func capsule(cornerRadius: CGFloat = height / 2) -> NSView {
        if #available(macOS 26, *) {
            let g = NSGlassEffectView()
            g.cornerRadius = cornerRadius
            g.style = .regular
            return g
        }
        return NSView()
    }

    static func style(_ b: NSButton, primary: Bool = false) {
        if #available(macOS 26, *) {
            b.bezelStyle = .glass
            b.borderShape = .capsule
            b.tintProminence = primary ? .primary : .none
        } else {
            b.bezelStyle = .push
        }
    }
}

@MainActor
enum TabGlyphTint {
    static func color(selected: Bool) -> NSColor {
        guard GlassBars.enabled else { return selected ? .controlAccentColor : .secondaryLabelColor }
        return NSColor.labelColor.withAlphaComponent(selected ? 0.39 : 0.35)
    }

    static func navigatorColor(selected: Bool) -> NSColor {
        guard GlassBars.enabled else { return color(selected: selected) }
        return .labelColor
    }
}

final class SelectionPillView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        layer?.cornerRadius = bounds.height / 2
        layer?.cornerCurve = .continuous
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    func follow(_ target: NSView?, size: NSSize) {
        guard let target, !target.isHidden, let sup = superview, target.superview != nil else { isHidden = true; return }
        let r = sup.convert(target.bounds, from: target)
        frame = NSRect(x: (r.midX - size.width / 2).rounded(), y: (r.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        isHidden = false
        needsDisplay = true
    }
}
